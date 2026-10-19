require 'koholint/agents/context'
require 'koholint/agents/prompts'
require 'koholint/decision'
require 'koholint/ledger'
require 'koholint/navigation/planner'
require 'koholint/talk_log'
require 'koholint/triggers'
require 'koholint/vision/beliefs'
require 'koholint/vision/capabilities'
require 'koholint/vision/dialogue_shot'
require 'koholint/vision/grid'

module Koholint
  module Policies
    class Delegated
      RESULT_LIMIT = 6
      TRANSCRIPTION_LIMIT = 500
      PLAN_LIMIT = DecisionPoint::PLAN_MAX
      DIALOGUE_PAGE_LIMIT = 40
      DIALOGUE_FRAME_LIMIT = 1800
      SHEET_PAGES = 8
      REFUSAL_LIMIT = 3
      STALE_SEQUENCE_FRAMES = 600
      Failure = Class.new(StandardError)
      Refusal = Class.new(Failure)
      REOPEN_WAIT = { skill: 'wait', params: { frames: 10 } }.freeze
      FALLBACK_CHOICE = { skill: 'wait', params: { frames: 30 } }.freeze
      HEMMED_WAIT = { skill: 'wait', params: { frames: 120 } }.freeze
      ADVANCE = { skill: 'advance_dialogue', params: {} }.freeze
      HEMMED_DIRECTIONS = 4
      HEMMED_WAIT_LIMIT = 1800 / HEMMED_WAIT[:params][:frames]

      def initialize(client:, registry:, objectives:, manual: '', on_step: nil, on_activity: nil, ledger: nil, triggers: nil, talk_log: nil)
        @ledger = hook_doubt(ledger || Ledger.new)
        @triggers = triggers || Triggers.new
        @talk_log = talk_log || TalkLog.new
        @refusals = []
        @plan = nil
        @frame = 0
        @client = client
        @registry = registry
        @objectives = objectives
        @manual = manual.to_s
        @on_step = on_step
        @on_activity = on_activity
        @last_results = []
        @walks = []
        @hemmed = nil
        @page = 0
        @sequence = nil
        @agent_driven = false
        @skill_point = DecisionPoint.choose_skill(registry)
      end

      def decision_point_for(_state) = @objectives.current ? @skill_point : DecisionPoint.choose_objective

      def observe(state, frame:)
        unless state.loading?
          @ledger.reset_unless([state.room_id, state.map_id])
          @triggers.reset_unless([state.room_id, state.map_id])
        end
        release_hemmed(state)
        track { @objectives.update(state, frame:) }
      end

      def cancel = (@client.cancel if @client.respond_to?(:cancel))

      def decide(decision_point, state, context)
        @prompt = @image = @images = nil
        context[:ledger] = @ledger
        remember_grid(state, context)
        drop_stale_sequence(state)
        automatic = automatic_advance(decision_point, state, context)
        return automatic if automatic

        reopen = reopen_wait(decision_point, state)
        return reopen if reopen

        if decision_point.name == :choose_skill && !@sequence && hemmed?(state)
          return hemmed_wait if @hemmed[:waits] < HEMMED_WAIT_LIMIT

          clear_hemmed
        end

        reply = ask(decision_point, state, context)
        raise Failure, reply.error if reply.error

        choice = decision_point.validate(reply.output).slice(*decision_point.output_schema)
        start_objective(choice, state, context) if decision_point.name == :choose_objective
        plan = remember_plan(reply.output)
        answer(choice, reply, reply.output).merge(plan ? { plan: } : {}).merge(transcription_for(reply.output, state, decision_point))
      rescue NameError, TypeError
        raise
      rescue StandardError => e
        note_refusal(e, choice) if e.is_a?(Refusal)
        { choice: FALLBACK_CHOICE, justification: e.is_a?(Failure) ? e.message : "#{e.class}: #{e.message}", confidence: 0.0, agent: 'claude', latency_ms: 0,
          cost_usd: cost_of(reply), fallback: true, decision_point: @skill_point, prompt: @prompt, image: @image, images: @images,
          **(e.is_a?(Refusal) ? { refused: true } : {}) }
      end

      def after_action(choice:, outcome:, state:, frame:)
        return unless choice.key?(:skill)

        @frame = frame
        @page += 1 if choice[:skill] == 'advance_dialogue'
        unless state.phase == :dialogue
          @page = 0
          @agent_driven = false
        end
        if @auto
          @auto = false
          return track { @objectives.update(state, frame:) }
        end
        @last_results << outcome
        @last_results.shift while @last_results.size > RESULT_LIMIT
        note_walk(choice, outcome, state)
        feed_ledger(choice, outcome, state, frame)
        opened = feed_triggers(choice, outcome, state)
        feed_talk_log(choice, outcome, state)
        note_no_path(choice, outcome, frame)
        unless @waiting
          @objectives.record_attempt(skill: choice[:skill], params: choice[:params], result_summary: summary(outcome, opened))
        end
        @waiting = false
        track { @objectives.update(state, frame:) }
      end

      private

      def hook_doubt(ledger)
        ledger.on_doubt ||= method(:doubt)
        ledger
      end

      def doubt(place:, cell:, direction:, count:)
        return unless believed_free?(cell, direction)

        trace = @objectives.trace if @objectives.respond_to?(:trace)
        trace&.emit(:grid_contradiction, frame: @frame, place:, row: cell[0], col: cell[1], direction: direction.to_s, believed: 'yes',
                                         observed: "blocked x#{count}")
      end

      def believed_free?(cell, direction)
        drow, dcol = Vision::GridBuilder::STEPS.fetch(direction.to_sym)
        row = cell[0] + drow
        col = cell[1] + dcol
        @last_grid && row.between?(0, Vision::Grid::ROWS - 1) && col.between?(0, Vision::Grid::COLS - 1) &&
          @last_grid.passable(row, col, direction.to_sym) == :yes
      end

      def note_no_path(choice, outcome, frame)
        return unless %w[goto talk_to].include?(choice[:skill]) && outcome[:stopped_by].to_s == 'no_path' && @objectives.current

        track { @objectives.note_no_path(frame:) }
      end

      def note_refusal(error, choice)
        choice = {} unless choice.is_a?(Hash)
        @refusals << { reason: error.message, title: choice[:title], predicate: choice[:predicate] }
        @refusals.shift while @refusals.size > REFUSAL_LIMIT
      end

      def remember_grid(state, context)
        place = [state.room_id, state.map_id]
        @last_grid = nil unless @last_place == place
        @last_place = place
        @last_grid = context[:grid] if context[:grid]
        context[:grid] ||= @last_grid
      end

      def drop_stale_sequence(state)
        return unless @sequence

        stale = state.phase != :dialogue && state.frame - @sequence[:last] > STALE_SEQUENCE_FRAMES
        @sequence = nil if stale || @sequence[:place] != [state.room_id, state.map_id]
      end

      def reopen_wait(decision_point, state)
        return unless decision_point.name == :choose_skill && @sequence && state.phase != :dialogue && !@sequence[:waited]

        @sequence[:waited] = true
        @waiting = true
        @objectives.touch(frame: state.frame)
        { choice: REOPEN_WAIT, justification: 'automatic dialogue advance: waiting for the dialogue to reopen', confidence: 1.0, agent: 'delegated',
          latency_ms: 0, cost_usd: 0.0, fallback: false, prompt: nil, image: nil }
      end

      def track
        before = @objectives.history.size
        yield
        return unless @objectives.history.size > before

        @plan = nil
        @on_step&.call
      end

      def start_objective(choice, state, context)
        predicate = Objectives.normalize(choice[:predicate])
        place = [state.room_id, state.map_id]
        if predicate[:kind].to_s == 'leave_place' && predicate[:place] != place
          raise Refusal, "leave_place must name the current place #{place.inspect}, not #{predicate[:place].inspect}"
        end
        raise Refusal, 'predicate is already true in the current state' if satisfied?(predicate, state, place)
        if trivial?(predicate, state, place, context)
          raise Refusal, 'reach_cell target is already reachable over cells observed free; choose a goal that needs exploration'
        end
        raise Refusal, 'dialogue_closed needs an open dialogue' if predicate[:kind].to_s == 'dialogue_closed' && !state.dialog_open?

        clear_hemmed
        @refusals.clear
        @objectives.start(frame: state.frame, title: choice[:title], predicate: choice[:predicate])
      end

      def satisfied?(predicate, state, place)
        case predicate[:kind].to_s
        when 'reach_place' then predicate[:place] == place
        when 'reach_cell' then predicate[:place] == place && state.cell == [predicate[:row], predicate[:col]]
        else false
        end
      end

      def trivial?(predicate, state, place, context)
        return false unless predicate[:kind].to_s == 'reach_cell' && predicate[:place] == place

        grid = context[:grid]
        return false unless grid && state.cell

        Navigation::Planner.new(grid:, ledger: @ledger, place:).path(from: state.cell, to: [predicate[:row], predicate[:col]], mode: :free_only) != nil
      end

      def feed_ledger(choice, outcome, state, frame)
        from = outcome[:from].is_a?(Hash) ? outcome[:from] : {}
        place = from[:room] && from[:map] ? [from[:room], from[:map]] : [state.room_id, state.map_id]
        blocked_at = outcome[:blocked_at]
        if blocked_at
          @ledger.record(place:, blocked_at:)
          track { @objectives.note_blocked(blocked_at:, target: @objectives.current&.dig(:predicate), frame:) } if @objectives.current
        end
        note_entered(choice, outcome, place)
        @ledger.reset_unless([state.room_id, state.map_id]) unless state.loading?
      end

      def place_of(outcome, key, state)
        from = outcome[key].is_a?(Hash) ? outcome[key] : {}
        from[:room] && from[:map] ? [from[:room], from[:map]] : [state.room_id, state.map_id]
      end

      def feed_triggers(choice, outcome, state)
        return unless Triggers.scripted?(skill: choice[:skill], params: choice[:params], result: outcome)

        cell = Triggers.cell_of(outcome)
        @triggers.record(place: place_of(outcome, :to, state), cell:, skill: choice[:skill], direction: Triggers.direction_of(choice[:skill], choice[:params]))
        cell && @triggers.count(place_of(outcome, :to, state), cell)
      end

      def feed_talk_log(choice, outcome, state)
        return unless choice[:skill] == 'talk_to'

        params = choice[:params]
        @talk_log.record(place: place_of(outcome, :from, state), row: params[:row] || params['row'], col: params[:col] || params['col'], talked: outcome[:talked] == true)
      end

      def note_entered(choice, outcome, place)
        from = outcome[:from]
        to = outcome[:to]
        return unless from.is_a?(Hash) && to.is_a?(Hash) && from[:row] && to[:row] && [from[:row], from[:col]] != [to[:row], to[:col]]
        return unless [from[:room], from[:map]] == [to[:room], to[:map]]

        if choice[:skill] == 'walk'
          direction = (choice[:params][:direction] || choice[:params]['direction'])&.to_sym
          delta = Navigation::Planner::DELTAS[direction] or return
          cell = [from[:row], from[:col]]
          outcome[:moved_cells].to_i.times do
            @ledger.entered(place:, cell:, direction:)
            cell = [cell[0] + delta[0], cell[1] + delta[1]]
          end
        elsif %w[goto talk_to].include?(choice[:skill])
          Array(outcome[:crossed]).each { |row, col, direction| @ledger.entered(place:, cell: [row, col], direction:) }
        end
      end

      def note_walk(choice, outcome, state)
        @walks << (choice[:skill] == 'walk' ? { direction: choice[:params][:direction] || choice[:params]['direction'], stopped_by: outcome[:stopped_by].to_s,
                                                 moved: outcome[:moved_cells].to_i, pos: [state.x, state.y] } : nil)
        @walks.shift while @walks.size > HEMMED_DIRECTIONS
        latch_hemmed(state)
      end

      def latch_hemmed(state)
        return if state.dialog_open? || @walks.size < HEMMED_DIRECTIONS || @walks.any?(&:nil?)
        return unless @walks.map { |w| w[:direction].to_s }.uniq.size == HEMMED_DIRECTIONS
        return unless @walks.all? { |w| w[:stopped_by] == 'blocked' && w[:moved].zero? && w[:pos] == @walks.first[:pos] }

        @hemmed = { pos: @walks.first[:pos], place: [state.room_id, state.map_id], waits: 0 }
      end

      def hemmed?(state) = !!@hemmed && !state.dialog_open? && [state.x, state.y] == @hemmed[:pos] && [state.room_id, state.map_id] == @hemmed[:place]

      def release_hemmed(state)
        return unless @hemmed && !state.loading?

        clear_hemmed unless hemmed?(state)
      end

      def clear_hemmed
        @hemmed = nil
        @walks.clear
      end

      def automatic_advance(decision_point, state, context)
        return unless decision_point.name == :choose_skill && state.phase == :dialogue && !@agent_driven

        if @sequence && sequence_full?(state)
          @agent_driven = true
          @objectives.touch(frame: state.frame)
          return
        end
        rgb = context[:dialogue_rgb]&.call or return
        unless @sequence
          @sequence = { pages: [], start: state.frame, place: [state.room_id, state.map_id] }
          @objectives.touch(frame: state.frame)
        end
        @sequence[:last] = state.frame
        @sequence[:waited] = false
        @sequence[:pages] << rgb
        @auto = true
        announce(:acting, "automatic dialogue advance, page #{@page + 1}", state, skill: ADVANCE[:skill], page: @page + 1)
        { choice: ADVANCE, justification: 'automatic dialogue advance', confidence: 1.0, agent: 'delegated', latency_ms: 0, cost_usd: 0.0,
          fallback: false, prompt: nil, image: nil }
      end

      def sequence_full?(state)
        @sequence[:pages].size >= DIALOGUE_PAGE_LIMIT || state.frame - @sequence[:start] >= DIALOGUE_FRAME_LIMIT
      end

      def hemmed_wait
        @waiting = true
        @hemmed[:waits] += 1
        { choice: HEMMED_WAIT, justification: 'deterministic hemmed-in wait: four directions blocked without movement at the same position',
          confidence: 1.0, agent: 'delegated', latency_ms: 0, cost_usd: 0.0, fallback: false, prompt: nil, image: nil }
      end

      def ask(decision_point, state, context)
        @prompt = Agents::Context.build(state:, grid: grid_for(state, context), objective: @objectives.current, history: @objectives.history,
                                       attempts: @objectives.attempts_for_prompt, manual: @manual, last_results: @last_results, ledger: @ledger, refusals: @refusals, plan: @plan,
                                       triggers: @triggers, talk_log: @talk_log)
        if decision_point.name == :choose_skill && @sequence
          @pages_read = @sequence[:pages].size
          @images = Vision::DialogueShot.sheets(@sequence[:pages], per_sheet: SHEET_PAGES)
          @read_at = @sequence.slice(:start, :place)
          @sequence = nil
          @page = @pages_read
          @objectives.touch(frame: state.frame)
          @prompt += "\nDialogue pages attached: #{@pages_read} pages. Transcribe them in transcription, one paragraph per page separated by a blank line."
        elsif state.phase == :dialogue && decision_point.name == :choose_skill
          @image = context[:dialogue_shot]&.call
        end
        announce_call(decision_point, state)
        pictures = @images ? { images: @images } : { image: @image }
        @client.call(system: Agents::Prompts.system_for(decision_point, sheets: !@images.nil?), prompt: @prompt, schema: decision_point.json_schema, **pictures)
      end

      def announce_call(decision_point, state)
        count = @images ? @images.size : (@image ? 1 : 0)
        model = @client.model if @client.respond_to?(:model)
        if @images
          announce(:reading_dialogue, "reading #{@pages_read} dialogue pages", state, decision_point: decision_point.name.to_s, model:, images: count, pages: @pages_read)
        else
          announce(:deciding, 'asking the agent', state, decision_point: decision_point.name.to_s, model:, images: count)
        end
      end

      def announce(kind, label, state, **detail) = @on_activity&.call(kind:, label:, frame: state.frame, detail: detail.compact)

      def remember_plan(output)
        text = output['plan']
        plan = text.is_a?(String) ? clean(text.tr("\n", ' '), cap: PLAN_LIMIT) : ''
        return if plan.empty?

        @plan = plan
      end

      def clean(text, cap: TRANSCRIPTION_LIMIT) = text.gsub(/[^\P{Cntrl}\n]/, '').strip.then { |t| cap ? t[0, cap] : t }

      def transcription_for(output, state, decision_point)
        text = output['transcription']
        return {} unless decision_point.name == :choose_skill && text.is_a?(String)
        return { transcription: sequence_pages(text) }.reject { |_, v| v.empty? } if @images
        return {} unless state.phase == :dialogue && !clean(text).empty?

        { transcription: { text: clean(text), page: @page } }
      end

      def sequence_pages(text)
        paragraphs = text.split(/\n[^\S\n]*\n/).map { |chunk| clean(chunk, cap: nil) }.reject(&:empty?)
        chunks = paragraphs.flat_map { |paragraph| paragraph.scan(/.{1,#{TRANSCRIPTION_LIMIT}}/m) }
        chunks.first(DIALOGUE_PAGE_LIMIT).each_with_index.map { |t, i| { text: t, page: i + 1, frame: @read_at[:start], place: @read_at[:place] } }
      end

      def grid_for(_state, _context)
        @last_grid || Vision::Grid.new(cells: Array.new(Vision::Grid::ROWS) { Array.new(Vision::Grid::COLS) }, static_sprites: [],
                                       beliefs: Vision::Beliefs.new, capabilities: Vision::Capabilities.new)
      end

      def answer(choice, reply, output)
        { choice:, justification: output['justification'].to_s, confidence: output['confidence']&.to_f, agent: 'claude',
          latency_ms: reply.latency_ms.to_i, cost_usd: reply.cost_usd.to_f, prompt: @prompt, image: @image, images: @images }
      end

      def cost_of(reply) = reply.respond_to?(:cost_usd) ? reply.cost_usd.to_f : 0.0

      def summary(outcome, opened = nil)
        text = "stopped_by #{outcome[:stopped_by]}, moved #{outcome[:moved_cells]} cells, room_changed #{outcome[:room_changed]}, hp_delta #{outcome[:hp_delta]}"
        blocked = outcome[:blocked_at]
        text += ", blocked_at (#{blocked[:row]},#{blocked[:col]}) #{blocked[:direction]}" if blocked.is_a?(Hash)
        text += ", cause #{outcome[:cause]}" if outcome[:cause]
        text += ", talked #{outcome[:talked]}" unless outcome[:talked].nil?
        text += ", dialogue opened by itself x#{opened}" if opened
        standing = outcome[:standing_cell]
        text += ", standing_cell (#{standing[:row]},#{standing[:col]})" if standing.is_a?(Hash)
        text
      end
    end
  end
end
