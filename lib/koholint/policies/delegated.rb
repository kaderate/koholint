require 'koholint/agents/context'
require 'koholint/agents/prompts'
require 'koholint/autopilot'
require 'koholint/capabilities'
require 'koholint/candidates'
require 'koholint/decision'
require 'koholint/dialogues'
require 'koholint/entities'
require 'koholint/explore_log'
require 'koholint/leads'
require 'koholint/ledger'
require 'koholint/loop_watch'
require 'koholint/zero_watch'
require 'koholint/navigation/planner'
require 'koholint/revisit'
require 'koholint/talk_log'
require 'koholint/triggers'
require 'koholint/vision/beliefs'
require 'koholint/vision/capabilities'
require 'koholint/vision/dialogue_shot'
require 'koholint/vision/grid'
require 'koholint/policies/delegated/dialogue'
require 'koholint/policies/delegated/guidance'
require 'koholint/policies/delegated/outcomes'
require 'koholint/policies/delegated/waits'

module Koholint
  module Policies
    class Delegated
      include Dialogue
      include Guidance
      include Outcomes
      include Waits

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
      HEMMED_ATTEMPTS = 4
      LOCK_BUFFER = 8
      LOCK_SKILLS = %w[walk step goto talk_to explore].freeze
      PATH_SKILLS = %w[goto talk_to explore attack].freeze
      LOCKED_WAIT = { skill: 'wait', params: { frames: 30, until_free: true } }.freeze
      LOCKED_WAIT_LIMIT_FRAMES = 900
      SETTLE_FRAMES = 30
      HEMMED_WAIT_LIMIT = 1800 / HEMMED_WAIT[:params][:frames]
      SCREEN_SKILLS = { menu: %w[menu_move menu_assign close_menu press wait], map: %w[close_map press wait], save: %w[choose_option press wait],
                        game_over: %w[choose_option press wait], unknown: %w[press wait] }.freeze
      SCREEN_ONLY = %w[close_menu close_map menu_move menu_assign choose_option].freeze
      SCREEN_WAIT = { skill: 'wait', params: { frames: 5 } }.freeze
      SCREEN_WAIT_LIMIT_FRAMES = 300
      WAIT_PHASES = %i[locked cutscene].freeze
      SPEAKER_LIMIT = Trace::SPEAKER_MAX
      REVISIT_BUDGET_SHARE = 0.05
      STUCK_STOPS = %w[no_frontier no_path blocked stalled].freeze
      STUCK_AT = 6
      ZERO_WAIT = { skill: 'wait', params: { frames: 120 } }.freeze
      FALL_MOTION = 6
      EXPLORE = { skill: 'explore', params: {} }.freeze
      AUTO_OBJECTIVE = { title: 'Explore the nearest untried exits (picked by the harness)', predicate: { kind: 'new_place' } }.freeze

      def initialize(client:, registry:, objectives:, manual: '', on_step: nil, on_activity: nil, ledger: nil, triggers: nil, talk_log: nil, leads: nil, explore_log: nil, revisit: nil,
                     budget: nil, autopilot: nil, cards: {}, loop_watch: nil, zero_watch: nil)
        @cards = cards.dup
        @loop_watch = loop_watch || LoopWatch.new
        @zero_watch = zero_watch || ZeroWatch.new
        @candidates = []
        @budget = budget
        @autopilot = autopilot
        @explore_log = explore_log || ExploreLog.new
        @leads = leads || Leads.new
        @ledger = hook_doubt(ledger || Ledger.new)
        @triggers = triggers || Triggers.new
        @talk_log = talk_log || TalkLog.new
        @revisit = revisit || Revisit.new(talk_log: @talk_log)
        @entities = []
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
        @locks = []
        @hemmed = nil
        @page = 0
        @sequence = nil
        @agent_driven = false
        @locked_since = nil
        @skill_point = DecisionPoint.choose_skill(subset(registry, registry.names - SCREEN_ONLY))
        @composites = registry.names.map { |name| registry.fetch(name) }.grep(Skills::Composite)
        @learned = []
        @notes = []
        @hp_lost = 0
        @deaths = Hash.new(0)
        @screen_points = SCREEN_SKILLS.transform_values { |names| DecisionPoint.choose_skill(subset(registry, names)) }
      end

      def prepare(context)
        @entities_reader = context[:entities] if context[:entities]
        @objects_reader = context[:objects] if context[:objects]
        offer_learned(context[:room_objects], context[:held]) if @composites.any? && context[:room_objects]
      end

      def decision_point_for(state)
        return @screen_points.fetch(screen(state)) if screen(state)
        return @skill_point if locked_waiting?(state) || settling?(state)
        return @skill_point if revisit_candidate(state) || (state.phase == :dialogue && !@agent_driven)

        @objectives.current ? @skill_point : DecisionPoint.choose_objective
      end

      def observe(state, frame:)
        unless state.loading?
          @ledger.reset_unless([state.room_id, state.map_id])
          @triggers.reset_unless([state.room_id, state.map_id])
        end
        @screen_since = nil unless screen(state)
        release_hemmed(state)
        track_locked(state)
        @over = false unless screen(state) == :game_over
        note_damage(state)
        note_loop(state, frame)
        @revisit.observe(state)
        track { @objectives.update(state, frame:) }
      end

      def cancel = (@client.cancel if @client.respond_to?(:cancel))

      def decide(decision_point, state, context)
        @asked = false
        result = decide_with(decision_point, state, context)
        @autopilot&.model_called(state:, objective: @objectives.current, news: !Array(result[:leads]).empty? || !result[:goal].nil?) if @asked
        notes = @revisit.notes + @notes
        @notes = []
        notes.empty? ? result : result.merge(notables: notes)
      end

      def decide_with(decision_point, state, context)
        @prompt = @image = @images = @reading = nil
        @revisit_acting = false
        @autopilot_acting = false
        @flushing = false
        prepare(context)
        context[:ledger] = @ledger
        context[:triggers] = @triggers
        context[:talk_log] = @talk_log
        context[:explore_log] = @explore_log
        remember_grid(state, context)
        drop_stale_sequence(state)
        if screen(state)
          return screen_wait(state) if screen_settling?(state)
          return game_over_continue(state) if screen(state) == :game_over
        else
          automatic = automatic_advance(decision_point, state, context)
          return automatic if automatic

          reopen = reopen_wait(decision_point, state)
          return reopen if reopen

          @reading = cached_reading(decision_point, state)
          return locked_wait.merge(@reading || {}) if locked_waiting?(state)
          return settle_wait(state).merge(@reading || {}) if settling?(state)

          revisit = revisit_choice(decision_point, state)
          return revisit.merge(@reading || {}) if revisit

          if decision_point.name == :choose_skill && !@sequence && hemmed?(state)
            return hemmed_wait if @hemmed[:waits] < HEMMED_WAIT_LIMIT

            @locks.clear
          end

          broken = loop_break(decision_point, state, context)
          return broken if broken

          capped = zero_cap(decision_point, state, context)
          return capped if capped

          autopilot = autopilot_choice(decision_point, state, context)
          return autopilot if autopilot

          auto = auto_objective(decision_point, state)
          return auto if auto
        end

        reply = ask(decision_point, state, context)
        raise Failure, reply.error if reply.error

        output = decision_point.name == :choose_objective ? resolve_candidate(reply.output) : reply.output
        choice = decision_point.validate(output).slice(*decision_point.output_schema)
        aim_explore(choice, state, context) if decision_point.name == :choose_skill
        start_objective(choice, state, context, reply.output['because']) if decision_point.name == :choose_objective
        plan = remember_plan(reply.output)
        transcription = @reading || transcription_for(reply.output, state, decision_point)
        remember_text(transcription[:transcription], state) unless @reading
        notes = notes_for(reply.output, transcription[:transcription], state)
        result = answer(choice, reply, reply.output).merge(plan ? { plan: } : {}).merge(transcription).merge(notes)
        continue_dialogue(keep_moving(@images ? override_for_revisit(result, decision_point, state) : result, state), state)
      rescue NameError, TypeError
        raise
      rescue StandardError => e
        note_refusal(e, choice) if e.is_a?(Refusal)
        engine = !@asked && !e.is_a?(Failure) && !e.is_a?(Refusal)
        { choice: FALLBACK_CHOICE, justification: failure_text(e), confidence: 0.0, agent: engine ? 'engine' : 'claude', latency_ms: 0,
          cost_usd: cost_of(reply), fallback: true, decision_point: @skill_point, prompt: @prompt, image: @image, images: @images,
          **(e.is_a?(Refusal) ? { refused: true } : {}), **(engine ? { engine_error: true } : {}) }
      end

      def failure_text(error)
        return error.message if error.is_a?(Failure)

        where = error.backtrace&.first&.sub(%r{\A.*/(?=lib/koholint/)}, '')
        "#{error.class}: #{error.message}#{" at #{where}" if where}"
      end

      def after_action(choice:, outcome:, state:, frame:)
        return unless choice.key?(:skill)

        @autopilot&.acted(skill: choice[:skill], outcome:) unless @revisit_acting
        @zero_watch.note(place: Ledger.place_of(outcome[:from]) || [state.room_id, state.map_id], skill: choice[:skill], stop: outcome[:stopped_by], frames: outcome[:frames])
        @frame = frame
        @page += 1 if choice[:skill] == 'advance_dialogue'
        unless state.phase == :dialogue
          @page = 0
          @agent_driven = false
        end
        @flushes = 0 if state.phase == :playing
        if @auto || @locked_wait
          @auto = @locked_wait = false
          return track { @objectives.update(state, frame:) }
        end
        revisiting = @revisit_acting && choice[:skill] == 'talk_to'
        @revisit.talked(outcome) if revisiting
        @revisit_acting = false
        autopiloted = @autopilot_acting
        @autopilot_acting = false
        @last_results << (autopiloted ? outcome.merge(autopilot: true) : outcome)
        @last_results.shift while @last_results.size > RESULT_LIMIT
        note_lock(choice, outcome, state)
        note_talk_source(choice, outcome)
        feed_ledger(choice, outcome, state, frame, objective: !revisiting)
        opened = feed_triggers(choice, outcome, state)
        feed_talk_log(choice, outcome, state)
        @explore_log.note(outcome)
        @explore_log.absorb(outcome) if choice[:skill] == 'explore'
        @skipped = { place: Ledger.place_of(outcome[:from]), vias: Array(outcome[:unreachable]) } if choice[:skill] == 'explore'
        note_no_path(choice, outcome, frame) unless revisiting
        note_stuck(outcome, state)
        unless @waiting || revisiting
          @objectives.record_attempt(skill: choice[:skill], params: choice[:params], result_summary: "#{'(autopilot) ' if autopiloted}#{summary(outcome, opened)}")
        end
        @waiting = false
        track { @objectives.update(state, frame:) }
      end

      def offered_candidates = Candidates.offered(@candidates, @candidate)

      # A learned capability is offered only while its item is held and its object is on screen.
      def offer_learned(room_objects, held)
        grid = room_objects.call
        cells = @composites.select { |skill| skill.usable?(held) }.to_h { |skill| [skill, grid.each_with_index.flat_map { |row, r| row.each_index.select { |c| row[c] == skill.entry['target']['object'] }.map { |c| [r, c] } }] }
        present = cells.select { |_, at| at.any? }
        @learned = present.map { |skill, at| "- #{skill.name} (row, col, direction): #{Capabilities.describe(skill.entry)}. Object #{skill.entry['target']['object']} here at #{at.map { |r, c| "(#{r},#{c})" }.join(', ')}; give the free cell next to it where Link stands and the direction facing it." }
        names = @registry.names - SCREEN_ONLY - (@composites - present.keys).map(&:name)
        @skill_point = DecisionPoint.choose_skill(subset(@registry, names)) unless @skill_point.registry.names == (names & @registry.names)
      end

      private

      def screen(state) = state.phase(booted: true).then { |phase| phase if SCREEN_SKILLS.key?(phase) }

      def subset(registry, names) = Skills::Registry.new((names & registry.names).map { |name| registry.fetch(name) })

      def remember_grid(state, context)
        place = [state.room_id, state.map_id]
        @last_grid = nil unless @last_place == place
        @last_place = place
        @last_grid = context[:grid] if context[:grid]
        context[:grid] ||= @last_grid
      end

      def track
        before = @objectives.history.size
        yield
        return unless @objectives.history.size > before

        @plan = nil
        @on_step&.call
      end

      def start_objective(choice, state, context, because = nil)
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
        because = nil unless @leads.known?(because)
        picked = @candidate
        @objectives.start(frame: state.frame, title: choice[:title], predicate: choice[:predicate], because:, candidate: picked&.dig(:id), target: picked&.dig(:target))
      end

      def resolve_candidate(output)
        @candidate = nil
        id = output['candidate']
        return output unless id.is_a?(String) && !id.strip.empty?

        found = Candidates.find(@candidates, id)
        raise Refusal, "unknown candidate #{id.strip}: pick an id from the candidate list, or give title and predicate without a candidate" unless found

        @candidate = found
        title = output['title'].is_a?(String) && !output['title'].strip.empty? ? output['title'] : found[:title]
        output.merge('title' => title, 'predicate' => found[:predicate].transform_keys(&:to_s))
      end

      def build_candidates(state, context)
        place = [state.room_id, state.map_id]
        signs = objects_now
        if state.phase(booted: true) == :playing
          @cards[place] = { people: @entities.select { |entity| entity[:kind].to_s == 'npc' && entity[:cell] }.map { |entity| entity.slice(:type, :cell) },
                            signs: signs.select { |object| object[:kind].to_s == 'sign' }.map { |object| object.slice(:cell) } }
        end
        @candidates = Candidates.build(place:, grid: context[:grid], explore_log: @explore_log, talk_log: @talk_log, leads: @leads, cards: @cards,
                                       entities: @entities, signs:, stamp: stamp(state), link: state.cell, low_health: false)
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

      def ask(decision_point, state, context)
        entities_now
        @objectives.history.each { |done| @leads.note_objective(done) }
        @candidates = decision_point.name == :choose_objective ? build_candidates(state, context) : []
        @prompt = Agents::Context.build(state:, grid: grid_for(state, context), objective: @objectives.current, history: @objectives.history, entities: @entities,
                                       attempts: @objectives.attempts_for_prompt, manual: @manual, last_results: @last_results, ledger: @ledger, refusals: @refusals, plan: @plan,
                                       triggers: @triggers, talk_log: @talk_log, signs: objects_now, locked: (@hemmed[:attempts] if @hemmed && hemmed?(state)),
                                       locked_frames: (locked_frames(state) if WAIT_PHASES.include?(state.phase)), goal: goal_line, leads: @leads.with_status, stamp: stamp(state),
                                       place_name: @leads.name_of([state.room_id, state.map_id]), candidates: (Candidates.lines(@candidates) if decision_point.name == :choose_objective),
                                       learned: (@learned if decision_point.name == :choose_skill),
                                       resolve: @leads.method(:place_for), hp_lost: @hp_lost, died: @died, alerts: alerts(state), route: route_line(state))
        @hp_lost = 0
        @died = false
        if @reading
          text = Dialogues.text(@reading[:transcription].map { |entry| entry[:text] })
          @prompt += "\nThe dialogue that just closed repeated a text already read (not sent again): #{clean(text.tr("\n", ' '), cap: TRANSCRIPTION_LIMIT)}"
        elsif decision_point.name == :choose_skill && @sequence
          @pages_read = @sequence[:pages].size
          @images = Vision::DialogueShot.sheets(@sequence[:pages], per_sheet: SHEET_PAGES)
          @read_at = @sequence.slice(:start, :place, :source).merge(conversation: (Vision::DialogueShot.signature(@sequence[:rows]) unless state.dialog_open?))
          @sequence = nil
          @page = @pages_read
          @objectives.touch(frame: state.frame)
          @prompt += "\nDialogue pages attached: #{@pages_read} pages. Transcribe them in transcription, one paragraph per page separated by a blank line."
          @prompt += "\nThe harness is talking to the people here again until they repeat themselves: your skill choice is replaced by the next talk." if revisit_candidate(state)
        elsif state.phase == :dialogue && decision_point.name == :choose_skill
          @image = context[:dialogue_shot]&.call
        end
        announce_call(decision_point, state)
        @asked = true
        pictures = @images ? { images: @images } : { image: @image }
        @client.call(system: Agents::Prompts.system_for(decision_point, sheets: !@images.nil?), prompt: @prompt, schema: decision_point.json_schema, **pictures)
      end

      def goal_line
        return unless @leads.goal
        return @leads.goal unless @leads.goal_frame && @leads.goal_objectives

        ago = @objectives.finished - @leads.goal_objectives
        "#{@leads.goal} (set at frame #{@leads.goal_frame}, #{ago} #{ago == 1 ? 'objective' : 'objectives'} ago)"
      end

      def stamp(state) = Dialogues.stamp(milestone: state.milestone, items: Dialogues.items(state.inventory, state.item_a, state.item_b), leads: Dialogues.leads_count(@leads.all))

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

      def entities_now
        @entities = @entities_reader ? Array(@entities_reader.call) : []
      end

      def objects_now = @objects_reader ? Array(@objects_reader.call) : []

      def grid_for(_state, _context)
        @last_grid || Vision::Grid.new(cells: Array.new(Vision::Grid::ROWS) { Array.new(Vision::Grid::COLS) }, static_sprites: [],
                                       beliefs: Vision::Beliefs.new, capabilities: Vision::Capabilities.new)
      end

      def answer(choice, reply, output)
        { choice:, justification: output['justification'].to_s, confidence: output['confidence']&.to_f, agent: 'claude',
          latency_ms: reply.latency_ms.to_i, cost_usd: reply.cost_usd.to_f, prompt: @prompt, image: @image, images: @images }
      end

      def cost_of(reply) = reply.respond_to?(:cost_usd) ? reply.cost_usd.to_f : 0.0

    end
  end
end
