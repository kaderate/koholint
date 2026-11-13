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
require 'koholint/navigation/planner'
require 'koholint/revisit'
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
      HEMMED_ATTEMPTS = 4
      LOCK_BUFFER = 8
      LOCK_SKILLS = %w[walk step goto talk_to explore].freeze
      PATH_SKILLS = %w[goto talk_to explore attack].freeze
      LOCKED_WAIT = { skill: 'wait', params: { frames: 30 } }.freeze
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
      FALL_MOTION = 6
      EXPLORE = { skill: 'explore', params: {} }.freeze
      AUTO_OBJECTIVE = { title: 'Explore the nearest untried exits (picked by the harness)', predicate: { kind: 'new_place' } }.freeze

      def initialize(client:, registry:, objectives:, manual: '', on_step: nil, on_activity: nil, ledger: nil, triggers: nil, talk_log: nil, leads: nil, explore_log: nil, revisit: nil,
                     budget: nil, autopilot: nil, cards: {}, loop_watch: nil)
        @cards = cards.dup
        @loop_watch = loop_watch || LoopWatch.new
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
        offer_learned(context[:room_objects]) if @composites.any? && context[:room_objects]
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

      STAND_SKILLS = %w[guard wait].freeze
      STAND_MARGIN = 32

      def keep_moving(result, state)
        choice = result[:choice]
        return result unless choice.is_a?(Hash) && STAND_SKILLS.include?(choice[:skill].to_s) && state.phase == :playing && !state.dialog_open?
        return result unless Navigation::Threat.within?(Navigation::Threat.of(entities_now), state.x, state.y, margin: STAND_MARGIN)

        result.merge(choice: EXPLORE, justification: "harness: no standing next to a hostile creature (replaces the model's #{choice[:skill]}): #{result[:justification]}", autopilot: false)
      end

      def continue_dialogue(result, state)
        return result unless @flushing && state.dialog_open?

        @auto = true
        result.merge(choice: ADVANCE, justification: "harness: the dialogue goes on after #{@pages_read} pages read, keep advancing (replaces the model's choice): #{result[:justification]}")
      end

      def failure_text(error)
        return error.message if error.is_a?(Failure)

        where = error.backtrace&.first&.sub(%r{\A.*/(?=lib/koholint/)}, '')
        "#{error.class}: #{error.message}#{" at #{where}" if where}"
      end

      def after_action(choice:, outcome:, state:, frame:)
        return unless choice.key?(:skill)

        @autopilot&.acted(skill: choice[:skill], outcome:) unless @revisit_acting
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

      # A learned capability is offered only while its object is on screen.
      def offer_learned(room_objects)
        grid = room_objects.call
        cells = @composites.to_h { |skill| [skill, grid.each_with_index.flat_map { |row, r| row.each_index.select { |c| row[c] == skill.entry['target']['object'] }.map { |c| [r, c] } }] }
        present = cells.select { |_, at| at.any? }
        @learned = present.map { |skill, at| "- #{skill.name} (row, col, direction): #{Capabilities.describe(skill.entry)}. Object #{skill.entry['target']['object']} here at #{at.map { |r, c| "(#{r},#{c})" }.join(', ')}; give the free cell next to it where Link stands and the direction facing it." }
        names = @registry.names - SCREEN_ONLY - (@composites - present.keys).map(&:name)
        @skill_point = DecisionPoint.choose_skill(subset(@registry, names)) unless @skill_point.registry.names == (names & @registry.names)
      end

      private

      def screen(state) = state.phase(booted: true).then { |phase| phase if SCREEN_SKILLS.key?(phase) }

      def subset(registry, names) = Skills::Registry.new((names & registry.names).map { |name| registry.fetch(name) })

      def screen_settling?(state)
        mode = state.mode
        settling = mode && !mode.ready.empty? && !mode.ready?(state)
        @screen_since = settling ? @screen_since || state.frame : nil
        settling && state.frame - @screen_since < SCREEN_WAIT_LIMIT_FRAMES
      end

      def screen_wait(state)
        @locked_wait = true
        { choice: SCREEN_WAIT, justification: "#{state.mode.name}: waiting for the screen to settle", confidence: 1.0, agent: 'delegated',
          latency_ms: 0, cost_usd: 0.0, fallback: false, prompt: nil, image: nil }
      end

      def game_over_continue(state)
        option, text = state.mode.choices.first
        unless @over
          @notes << { kind: 'death', detail: "game over: #{text}" }
          @deaths[[state.room_id, state.map_id]] += 1
        end
        @over = @died = @locked_wait = true
        { choice: { skill: 'choose_option', params: { option: } }, justification: "game over: #{text} (picked by the harness)", confidence: 1.0,
          agent: 'delegated', latency_ms: 0, cost_usd: 0.0, fallback: false, prompt: nil, image: nil }
      end

      def note_damage(state)
        hp = state.hp.to_i
        if @last_hp && hp < @last_hp && !state.loading?
          @hurt_at = state.frame
          @hp_lost += @last_hp - hp
          @notes << { kind: 'damage', detail: "hp #{@last_hp} -> #{hp}" }
        end
        @last_hp = hp
      end

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

      def note_talk_source(choice, outcome)
        return unless LOCK_SKILLS.include?(choice[:skill])

        talked = choice[:skill] == 'talk_to' && outcome[:talked] == true
        entity = outcome[:entity].is_a?(Hash) ? outcome[:entity][:type] || outcome[:entity]['type'] : nil
        @talk_source = talked ? choice[:params].transform_keys(&:to_sym).slice(:row, :col).merge(entity ? { entity: } : {}) : nil
      end

      def note_stuck(outcome, state)
        return if state.link_motion_state.to_i == FALL_MOTION

        place = [state.room_id, state.map_id]
        @stuck = { place:, cells: Set.new, count: 0 } unless @stuck && @stuck[:place] == place
        cells = %i[from to].filter_map { |key| Ledger.pick(outcome, key) }.select { |at| Ledger.place_of(at) == place }
                           .map { |at| [Ledger.pick(at, :row), Ledger.pick(at, :col)] }
        fresh = cells.count { |cell| @stuck[:cells].add?(cell) }.positive?
        if fresh
          @stuck[:count] = 0
          @stuck[:hint] = false
        elsif STUCK_STOPS.include?(outcome[:stopped_by].to_s) && (@stuck[:count] += 1) >= STUCK_AT
          @stuck[:count] = 0
          @stuck[:hint] = true
          @stuck[:times] = @stuck[:times].to_i + 1
          @notes << { kind: 'stuck', detail: "#{STUCK_AT} results in #{place.join('-')} without a new cell (#{@stuck[:times]} times here)" }
        end
      end

      def note_loop(state, frame)
        return unless state.game_mode == PLAY_MODE

        @loop_watch.observe(place: [state.room_id, state.map_id], frame:)
        @notes.concat(@loop_watch.notes)
        @loop_watch.notes.clear
      end

      def objective_place
        objective = @objectives.current or return
        predicate = objective[:predicate]
        predicate[:kind].to_s == 'reach_place' ? predicate[:place] : objective.dig(:target, :place)
      end

      def route_line(state)
        goal = objective_place
        here = [state.room_id, state.map_id]
        return if goal.nil? || goal == here

        exit = ->(via) { via.is_a?(Array) ? "door above (#{via[0] + 1},#{via[1]})" : via.to_s }
        avoid = @skipped && @skipped[:place] == here ? @skipped[:vias] : []
        skipped = avoid.empty? ? '' : " (the last explore found no way from Link to the #{avoid.map(&exit).join(', ')} exit here)"
        hops = @explore_log.path(here, goal:, avoid:)
        return "Known route to #{goal.join('-')}: none over the exits taken so far#{skipped}." unless hops

        steps = hops.map { |hop| "#{exit.(hop[:via])} to #{hop[:to].join('-')}" }
        "Known route to #{goal.join('-')} over exits taken before (#{hops.size} screens; explore with no direction follows it)#{skipped}: #{steps.join(', ')}"
      end

      def aim_explore(choice, state, context)
        return unless choice[:skill].to_s == 'explore' && choice[:params].to_h.empty?

        place = objective_place
        aim = follow_choice(state)&.dig(:aim) || ({ place: } if place && place != [state.room_id, state.map_id])
        context[:aim] = aim if aim
      end

      def alerts(state)
        place = [state.room_id, state.map_id]
        lines = []
        if (loop = @loop_watch.hint)
          lines << "LOOP: #{loop[:place].join('-')} was entered #{LoopWatch::ENTRIES} times in #{loop[:span]} frames without reaching a new place " \
                   "(#{loop[:places].join(', ')}). Going back and forth between known screens is not progress: " \
                   "#{objective_place ? 'follow the known route to the objective place, or choose another objective' : 'choose an objective that leads to an untried exit or a new place'}."
        end
        if @deaths[place].positive?
          lines << "DIED HERE #{@deaths[place]} time(s): the planner already routes around the contact zones of the creatures on screen; " \
                   'keep clear of them or push them away with the shield, and do not cross holes.'
        end
        if @stuck&.dig(:hint) && @stuck[:place] == place
          lines << "STUCK: #{STUCK_AT} results in a row here found no frontier, no path or were blocked, without reaching a new cell. The grid may be wrong: " \
                   'try the cells marked doubtful, step onto stairs or narrow gaps from the cell centre, and read the grid against the screen image.'
        end
        lines
      end

      def note_no_path(choice, outcome, frame)
        return unless PATH_SKILLS.include?(choice[:skill]) && outcome[:stopped_by].to_s == 'no_path' && @objectives.current

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

      def feed_ledger(choice, outcome, state, frame, objective: true)
        from = outcome[:from].is_a?(Hash) ? outcome[:from] : {}
        place = from[:room] && from[:map] ? [from[:room], from[:map]] : [state.room_id, state.map_id]
        Ledger.edges_of(outcome).each { |edge| @ledger.record(place:, blocked_at: edge) }
        blocked_at = outcome[:blocked_at]
        if blocked_at && objective
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
        clearing = Triggers.clearing(skill: choice[:skill], params: choice[:params], result: outcome)
        @triggers.clear(**clearing) if clearing
        return unless Triggers.scripted?(skill: choice[:skill], params: choice[:params], result: outcome)

        cell = Triggers.cell_of(outcome)
        @triggers.record(place: place_of(outcome, :to, state), cell:, skill: choice[:skill], direction: Triggers.direction_of(choice[:skill], choice[:params]),
                          input: outcome[:trigger_input]&.first)
        cell && @triggers.count(place_of(outcome, :to, state), cell)
      end

      def feed_talk_log(choice, outcome, state)
        return unless choice[:skill] == 'talk_to' && TalkLog.attempt?(outcome)

        params = choice[:params]
        @talk_log.record(place: place_of(outcome, :from, state), row: params[:row] || params['row'], col: params[:col] || params['col'], talked: outcome[:talked] == true,
                         standing: TalkLog.standing_of(outcome), entity: TalkLog.entity_of(outcome))
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
        elsif PATH_SKILLS.include?(choice[:skill])
          Array(outcome[:crossed]).each { |row, col, direction| @ledger.entered(place:, cell: [row, col], direction:) }
        end
      end

      def note_lock(choice, outcome, state)
        pos = [state.x, state.y]
        @locks.clear if state.dialog_open? || (@locks.any? && @locks.last[:pos] != pos)
        skill = choice[:skill]
        if LOCK_SKILLS.include?(skill)
          stopped = outcome[:stopped_by].to_s
          if stopped == 'blocked' && outcome[:moved_cells].to_i.zero? && outcome[:moved_px].to_i.zero?
            params = choice[:params] || {}
            direction = PATH_SKILLS.include?(skill) ? nil : (params[:direction] || params['direction']).to_s
            @locks << { direction:, pos: }
            @locks.shift while @locks.size > LOCK_BUFFER
          elsif stopped != 'no_path'
            @locks.clear
          end
        end
        latch_hemmed(state)
      end

      def latch_hemmed(state)
        return if @hemmed && @hemmed[:waits] < HEMMED_WAIT_LIMIT && hemmed?(state)
        return if state.dialog_open? || @locks.size < HEMMED_ATTEMPTS || @locks.filter_map { |l| l[:direction] }.uniq.size < HEMMED_DIRECTIONS

        @hemmed = { pos: @locks.first[:pos], place: [state.room_id, state.map_id], waits: 0, attempts: @locks.count { |l| l[:direction] } }
      end

      def hemmed?(state) = !!@hemmed && !state.dialog_open? && [state.x, state.y] == @hemmed[:pos] && [state.room_id, state.map_id] == @hemmed[:place]

      def release_hemmed(state)
        return unless @hemmed && !state.loading?

        clear_hemmed unless hemmed?(state)
      end

      def clear_hemmed
        @hemmed = nil
        @locks.clear
      end

      def automatic_advance(decision_point, state, context)
        return unless decision_point.name == :choose_skill && state.phase == :dialogue && !@agent_driven

        if @sequence && sequence_full?(state)
          @flushes = @flushes.to_i + 1
          @flushing = @flushes == 1
          @agent_driven = true unless @flushing
          @objectives.touch(frame: state.frame)
          return
        end
        rgb = context[:dialogue_rgb]&.call or return
        unless @sequence
          @sequence = { pages: [], rows: [], start: state.frame, place: [state.room_id, state.map_id], source: @talk_source }
          @objectives.touch(frame: state.frame)
        end
        @sequence[:last] = state.frame
        @sequence[:waited] = false
        @sequence[:pages] << rgb
        @sequence[:rows] << Vision::DialogueShot.text_rows(rgb)
        @auto = true
        announce(:acting, "automatic dialogue advance, page #{@page + 1}", state, skill: ADVANCE[:skill], page: @page + 1)
        { choice: ADVANCE, justification: 'automatic dialogue advance', confidence: 1.0, agent: 'delegated', latency_ms: 0, cost_usd: 0.0,
          fallback: false, prompt: nil, image: nil }
      end

      def sequence_full?(state)
        @sequence[:pages].size >= DIALOGUE_PAGE_LIMIT || state.frame - @sequence[:start] >= DIALOGUE_FRAME_LIMIT
      end

      def track_locked(state)
        if WAIT_PHASES.include?(state.phase)
          unless @locked_since
            @locked_since = state.frame
            @objectives.touch(frame: state.frame)
          end
        elsif @locked_since && !state.loading?
          @settle_until = state.frame + SETTLE_FRAMES if state.phase == :playing && locked_frames(state) >= SETTLE_FRAMES
          @locked_since = nil
          @objectives.touch(frame: state.frame)
        end
      end

      def locked_frames(state) = @locked_since ? state.frame - @locked_since : 0

      def locked_waiting?(state)
        track_locked(state)
        return false unless WAIT_PHASES.include?(state.phase)
        return true if locked_frames(state) < LOCKED_WAIT_LIMIT_FRAMES

        unless @lock_capped == @locked_since
          @lock_capped = @locked_since
          @notes << { kind: 'lock_cap', detail: "#{state.mode&.name || state.phase} held Link for #{locked_frames(state)} frames: the model decides from now on" }
        end
        false
      end

      def locked_wait
        @locked_wait = true
        { choice: LOCKED_WAIT, justification: 'locked: waiting for Link to be free', confidence: 1.0, agent: 'delegated', latency_ms: 0, cost_usd: 0.0,
          fallback: false, prompt: nil, image: nil }
      end

      # The sword scene of 242/0 released Link for 3 frames between two locks, so a long lock is trusted over only after a short wait.
      def settling?(state) = !!@settle_until && state.phase == :playing && state.frame < @settle_until

      def settle_wait(state)
        @locked_wait = true
        frames = @settle_until - state.frame
        { choice: { skill: 'wait', params: { frames: } }, justification: "locked: Link was just released, waiting #{frames} frames in case the scene goes on",
          confidence: 1.0, agent: 'delegated', latency_ms: 0, cost_usd: 0.0, fallback: false, prompt: nil, image: nil }
      end

      def hemmed_wait
        @waiting = true
        @hemmed[:waits] += 1
        @locks.clear if @hemmed[:waits] >= HEMMED_WAIT_LIMIT
        { choice: HEMMED_WAIT, justification: 'deterministic hemmed-in wait: blocked in several directions without movement at the same position',
          confidence: 1.0, agent: 'delegated', latency_ms: 0, cost_usd: 0.0, fallback: false, prompt: nil, image: nil }
      end

      def ask(decision_point, state, context)
        entities_now
        @candidates = decision_point.name == :choose_objective ? build_candidates(state, context) : []
        @prompt = Agents::Context.build(state:, grid: grid_for(state, context), objective: @objectives.current, history: @objectives.history, entities: @entities,
                                       attempts: @objectives.attempts_for_prompt, manual: @manual, last_results: @last_results, ledger: @ledger, refusals: @refusals, plan: @plan,
                                       triggers: @triggers, talk_log: @talk_log, signs: objects_now, locked: (@hemmed[:attempts] if @hemmed && hemmed?(state)),
                                       locked_frames: (locked_frames(state) if WAIT_PHASES.include?(state.phase)), goal: goal_line, leads: @leads.all, stamp: stamp(state),
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

      def remember_text(transcription, state)
        pages = [transcription].flatten(1).compact.map { |page| page[:text] }
        return if pages.empty?

        text = Dialogues.text(pages)
        @objectives.note_text(text)
        source = @images || @reading ? @read_at[:source] : @talk_source
        place = @images || @reading ? @read_at[:place] : [state.room_id, state.map_id]
        conversation = @read_at[:conversation] if @images || @reading
        first = [transcription].flatten(1).compact.first
        @talk_log.store_pages(conversation, pages) if conversation && @images
        @talk_log.remember(place:, cell: [source[:row], source[:col]], text:, stamp: stamp(state), entity: source[:entity], conversation:, speaker: first[:speaker]) if source
        @revisit.read if @images || @reading
      end

      def stamp(state) = Dialogues.stamp(milestone: state.milestone, items: Dialogues.items(state.inventory, state.item_a, state.item_b), leads: Dialogues.leads_count(@leads.all))

      def notes_for(output, transcription, state)
        goal = @leads.change_goal(output['goal'], frame: state.frame, objectives: @objectives.finished)
        notes = goal ? { goal: } : {}
        here = [state.room_id, state.map_id]
        name = @leads.name_place(here, output['place_name']) if output['place_name'].is_a?(String) && state.phase(booted: true) != :loading
        notes[:place_name] = { place: here, name: } if name
        return notes unless output.key?('leads')

        pages = [transcription].flatten(1).compact
        place = @read_at && @images ? @read_at[:place] : [state.room_id, state.map_id]
        source = @images ? @read_at[:source] : @talk_source
        texts = pages.map { |page| page[:text] }
        leads, rejected = @leads.absorb(output['leads'], transcription: [texts.join(' '), Dialogues.text(texts)], place:, source:)
        notes.merge(leads:, leads_rejected: rejected)
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
        @speaker = speaker_of(output)
        return { transcription: sequence_pages(text) }.reject { |_, v| v.empty? } if @images
        return {} unless state.phase == :dialogue && !clean(text).empty?

        { transcription: { text: clean(text), page: @page } }
      end

      def sequence_pages(text)
        paragraphs = text.split(/\n[^\S\n]*\n/).map { |chunk| clean(chunk, cap: nil) }.reject(&:empty?)
        chunks = paragraphs.flat_map { |paragraph| paragraph.scan(/.{1,#{TRANSCRIPTION_LIMIT}}/m) }
        chunks.first(DIALOGUE_PAGE_LIMIT).each_with_index.map { |t, i| page_entry(t, i + 1, speaker: @speaker) }
      end

      def page_entry(text, page, speaker: nil, cached: nil)
        { text:, page:, frame: @read_at[:start], place: @read_at[:place], conversation: @read_at[:conversation], speaker:, cached: }.compact
      end

      def speaker_of(output)
        name = output['speaker']
        name = name.is_a?(String) ? clean(name.tr("\n", ' '), cap: SPEAKER_LIMIT) : ''
        name.empty? ? nil : name
      end

      def cached_reading(decision_point, state)
        return unless decision_point.name == :choose_skill && @sequence && state.phase != :dialogue && !state.dialog_open?

        conversation = Vision::DialogueShot.signature(@sequence[:rows])
        pages = conversation && @talk_log.pages_for(conversation)
        return unless pages

        @read_at = @sequence.slice(:start, :place, :source).merge(conversation:)
        speaker = @talk_log.speaker_for(conversation)
        @page = @sequence[:pages].size
        @sequence = nil
        @objectives.touch(frame: state.frame)
        entries = pages.each_with_index.map { |text, i| page_entry(text, i + 1, speaker:, cached: true) }
        @reading = { transcription: entries }
        remember_text(entries, state)
        @reading
      end

      def entities_now
        @entities = @entities_reader ? Array(@entities_reader.call) : []
      end

      def objects_now = @objects_reader ? Array(@objects_reader.call) : []

      def autopilot_choice(decision_point, state, context)
        return unless @autopilot && decision_point.name == :choose_skill && !@sequence && !@reading && !hemmed?(state)

        follow = follow_choice(state)
        result = @autopilot.next_choice(state:, objective: @objectives.current, follow: follow&.dig(:choice)) or return
        context[:aim] = follow[:aim] if follow&.dig(:aim)
        @autopilot_acting = true
        result
      end

      def follow_choice(state)
        target = @objectives.current&.dig(:target) or return
        here = target[:place] == [state.room_id, state.map_id]
        case target[:kind]
        when 'exit' then { choice: { skill: 'explore', params: { direction: target[:direction] } } } if here
        when 'door' then { choice: EXPLORE, aim: { door: target[:cell] } } if here
        when 'person', 'sign', 'examine'
          return (@objectives.current.dig(:predicate, :kind).to_s == 'reach_place' ? { choice: EXPLORE, aim: { place: target[:place] } } : nil) unless here

          cell = target[:kind] == 'person' ? entities_now.find { |entity| entity[:type] == target[:type] && entity[:cell] }&.dig(:cell) : target[:cell]
          { choice: { skill: 'talk_to', params: { row: cell[0], col: cell[1] } } } if cell
        when 'place', 'lead', 'shelter' then { choice: EXPLORE, aim: { place: target[:place] } } unless here
        end
      end

      # A detected loop drops the current objective and explores toward the nearest place with untried work, once per detection.
      def loop_break(decision_point, state, context)
        hint = @loop_watch.hint
        return if hint.nil? || hint.equal?(@loop_broken) || @sequence || !%i[choose_skill choose_objective].include?(decision_point.name)

        place = [state.room_id, state.map_id]
        route = @explore_log.route(place)
        return unless route || @explore_log.untried?(place)

        @loop_broken = hint
        @objectives.abandon(frame: state.frame, reason: 'loop')
        @objectives.start(frame: state.frame, **AUTO_OBJECTIVE, autopilot: true)
        @autopilot&.adopt(@objectives.current)
        context[:aim] = { place: route[:goal] } if route
        choice = decision_point.name == :choose_objective ? AUTO_OBJECTIVE.dup : EXPLORE
        { choice:, justification: "loop in #{hint[:places].join(', ')}: explore #{route ? "toward #{route[:goal].join('-')}" : 'here'}, the nearest place with untried work",
          confidence: 1.0, agent: 'delegated', latency_ms: 0, cost_usd: 0.0, fallback: false, autopilot: true, prompt: nil, image: nil }
      end

      def auto_objective(decision_point, state)
        return unless @autopilot && decision_point.name == :choose_objective
        return if @autopilot.objective_hold(state:, last: @objectives.history.last)

        place = [state.room_id, state.map_id]
        return unless @explore_log.untried?(place) || @explore_log.route(place)

        @objectives.start(frame: state.frame, **AUTO_OBJECTIVE, autopilot: true)
        @autopilot.adopt(@objectives.current)
        { choice: AUTO_OBJECTIVE.dup, justification: 'autopilot: the last explore chain reached a place and achieved its objective; keep exploring', confidence: 1.0,
          agent: 'delegated', latency_ms: 0, cost_usd: 0.0, fallback: false, autopilot: true, prompt: nil, image: nil }
      end

      def revisit_low? = @budget ? @budget.nearly_exhausted?(frames: Revisit::CYCLE_FRAMES, share: REVISIT_BUDGET_SHARE) : false

      # Untried exits or clearable objects left in a surveyed place come before talking to people again.
      def revisit_danger?(state)
        place = [state.room_id, state.map_id]
        hemmed?(state) || (@explore_log.surveyed?(place) && @explore_log.untried?(place))
      end

      def revisit_candidate(state)
        return unless @entities_reader

        @revisit.candidate(state:, entities: entities_now, signs: objects_now, stamp: stamp(state), budget_low: revisit_low?, danger: revisit_danger?(state))
      end

      def revisit_choice(decision_point, state)
        return unless decision_point.name == :choose_skill && !@sequence

        action = @revisit.next_action(state:, entities: entities_now, signs: objects_now, stamp: stamp(state), budget_low: revisit_low?, danger: revisit_danger?(state))
        return unless action

        @revisit_acting = true
        npc = action[:npc]
        what = npc ? "revisit npc: entity type #{npc[:type]} at (#{npc[:cell][0]},#{npc[:cell][1]})" : "engage sign at (#{action[:sign][:cell][0]},#{action[:sign][:cell][1]})"
        { choice: action.slice(:skill, :params), justification: "#{what}, round #{action[:round]}",
          confidence: 1.0, agent: 'delegated', latency_ms: 0, cost_usd: 0.0, fallback: false, prompt: nil, image: nil }
      end

      def override_for_revisit(result, decision_point, state)
        revisit = revisit_choice(decision_point, state) or return result

        result.merge(choice: revisit[:choice], justification: "#{revisit[:justification]} (replaces the model's choice #{result[:choice][:skill]})")
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
        text += Agents::Context.explore_note(outcome) if outcome[:skill].to_s == 'explore'
        standing = outcome[:standing_cell]
        text += ", standing_cell (#{standing[:row]},#{standing[:col]})" if standing.is_a?(Hash)
        text
      end
    end
  end
end
