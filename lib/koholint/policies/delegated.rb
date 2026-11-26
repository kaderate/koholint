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
require 'koholint/policies/base'
require 'koholint/policies/memory'
require 'koholint/policies/delegated/dialogue'
require 'koholint/policies/delegated/guidance'
require 'koholint/policies/delegated/outcomes'
require 'koholint/policies/delegated/waits'

module Koholint
  module Policies
    class Delegated < Base
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
      HEMMED_PROBES = Geometry::DIRECTIONS.map(&:to_s).freeze
      HEMMED_PROBE_PIXELS = 2
      SCREEN_SKILLS = { menu: %w[menu_move menu_assign close_menu press wait], map: %w[close_map press wait], save: %w[choose_option press wait],
                        game_over: %w[choose_option press wait], unknown: %w[press wait] }.freeze
      SCREEN_ONLY = %w[close_menu close_map menu_move menu_assign choose_option].freeze
      AUTOPILOT_ONLY = %w[touch].freeze
      SCREEN_WAIT = { skill: 'wait', params: { frames: 5 } }.freeze
      SCREEN_WAIT_LIMIT_FRAMES = 300
      SPEAKER_LIMIT = Trace::SPEAKER_MAX
      REVISIT_BUDGET_SHARE = 0.05
      STUCK_STOPS = %w[no_frontier no_path blocked stalled].freeze
      STUCK_AT = 6
      ZERO_WAIT = { skill: 'wait', params: { frames: 120 } }.freeze
      DEADLOCK_WAITS = 3
      DROPPED = %w[need- souvenir-].freeze
      REOFFERS = 2
      HEAL_DETOURS = 2
      RETREAT_CAP = 2
      RETREAT_WINDOW = 3000
      EXPLORE = { skill: 'explore', params: {} }.freeze
      AUTO_OBJECTIVE = { title: 'Explore the nearest untried exits (picked by the harness)', predicate: { kind: 'new_place' } }.freeze

      def initialize(client:, registry:, objectives:, memory: Memory.new, manual: '', on_step: nil, on_activity: nil, revisit: nil, budget: nil, autopilot: nil, exits: nil, souvenirs: [])
        @exits = exits
        @souvenirs = souvenirs
        @cards = memory.cards.dup
        @healers = memory.healers
        @retreats = memory.retreats.dup
        @reoffers = Hash.new(0).merge(memory.reoffers)
        @souvenirs_taken = memory.souvenirs_taken.dup
        @loop_watch = memory.loop_watch
        @zero_watch = memory.zero_watch
        @candidates = []
        @budget = budget
        @autopilot = autopilot
        @explore_log = memory.explore_log
        @leads = memory.leads
        @ledger = memory.ledger
        @triggers = memory.triggers
        @talk_log = memory.talk_log
        @item_names = memory.item_names.dup
        @pending_gains = []
        @item_tries = memory.item_tries.dup
        @stalled = memory.stalled.dup
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
        @skill_point = DecisionPoint.choose_skill(subset(registry, registry.names - SCREEN_ONLY - AUTOPILOT_ONLY))
        @touch_point = DecisionPoint.choose_skill(subset(registry, AUTOPILOT_ONLY))
        @composites = registry.names.map { |name| registry.fetch(name) }.grep(Skills::Composite)
        @learned = []
        @notes = []
        @hp_lost = 0
        @deaths = Hash.new(0)
        @chest_failures = Set.new
        @screen_points = SCREEN_SKILLS.transform_values { |names| DecisionPoint.choose_skill(subset(registry, names)) }
      end

      def prepare(context)
        @entities_reader = context[:entities] if context[:entities]
        @objects_reader = context[:objects] if context[:objects]
        @room_objects_reader = context[:room_objects] if context[:room_objects]
        offer_learned(context[:room_objects], context[:held]) if @composites.any? && context[:room_objects]
      end

      def note_card(card)
        @explore_log.card(card[:place], Array(card[:unknown]))
        before = @cards[card[:place]] || {}
        @cards[card[:place]] = before.merge(unknown: PlaceCard.stillness(before[:unknown], card[:unknown]), held: @held)
      end

      def decision_point_for(state)
        return @screen_points.fetch(screen(state)) if screen(state)
        return @skill_point if locked_waiting?(state) || settling?(state)
        return @skill_point if revisit_candidate(state) || (state.phase == :dialogue && !@agent_driven)

        @objectives.current ? @skill_point : DecisionPoint.choose_objective
      end

      def observe(state, frame:)
        unless state.loading?
          @ledger.reset_unless(state.place)
          @triggers.reset_unless(state.place)
        end
        @screen_since = nil unless screen(state)
        note_gains(state)
        @retreated = nil if @retreated && (@retreated[:spot][0] != state.place || state.health > @retreated[:hp])
        @retreated[:hp] = [@retreated[:hp], state.health].min if @retreated
        @healers.saw(place: state.place, health: state.health) unless state.loading?
        @healers.heard(state.place) if state.dialog_open?
        @held = Dialogues.items(state.inventory, state.item_a, state.item_b)
        release_hemmed(state)
        track_locked(state)
        @over = false unless screen(state) == :game_over
        note_damage(state)
        note_loop(state, frame)
        @revisit.observe(state)
        note_open_chest(state)
        track { @objectives.update(state, frame:) }
        note_puzzle_entry(state)
      end

      def cancel = (@client.cancel if @client.respond_to?(:cancel))

      def decide(decision_point, state, context)
        @asked = false
        @leads.note_held(Items.held_ids(state))
        @explore_log.in_context(Exits.context(state))
        @explore_log.dangerous = @healers.dangerous(state.health) if state.health
        context[:fragile] = true if @healers.hit && state.health && state.health <= @healers.hit
        @zero_watch.in_context(Exits.context(state))
        @explore_log.use_bench(Exits.for_context(@exits, Exits.context(state))) if @exits
        @puzzles_offered = []
        entry = @puzzle_ask if decision_point.name == :choose_objective
        result = decide_with(decision_point, state, context)
        @puzzle_ask = nil if entry
        result = result.merge(puzzles_offered: @puzzles_offered) unless @puzzles_offered.empty?
        result = result.merge(puzzle_entry: entry) if entry
        news = !Array(result[:leads]).empty? || !result[:goal].nil?
        @autopilot&.model_called(state:, objective: @objectives.current, news:) if @asked
        @zero_watch.news! if news
        notes = @revisit.notes + @notes
        @notes = []
        puzzles = @explore_log.new_puzzles(place: state.place, cell: state.cell)
        result = result.merge(puzzles:) unless puzzles.empty?
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
        context[:fight] = ->(now) { @autopilot.fight_target(state: now, entities: entities_now, objects: objects_now) } if @autopilot
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

          detour = heal_detour(decision_point, state, context)
          return detour if detour

          broken = loop_break(decision_point, state, context)
          return broken if broken

          capped = zero_cap(decision_point, state, context)
          return capped if capped

          autopilot = autopilot_choice(decision_point, state, context)
          return autopilot if autopilot

          dropped = dropped_objective(decision_point, state, context)
          return dropped if dropped

          remembered = souvenir_objective(decision_point, state, context)
          return remembered if remembered

          wanted = item_objective(decision_point, state)
          return wanted if wanted

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
        @healers.moved if outcome[:moved_cells].to_i.positive?
        @objectives.abandon(frame:, reason: 'unreachable') if choice[:skill] == 'explore' && outcome[:held_back] && @objectives.current
        @zero_watch.note(place: Ledger.place_of(outcome[:from]) || state.place, skill: choice[:skill], stop: outcome[:stopped_by], frames: outcome[:frames],
                         cells: outcome[:cells_walked], to: Ledger.place_of(outcome[:to]))
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
        note_chest_attempt(choice, outcome, state)
        note_try(choice, outcome, state)
        feed_ledger(choice, outcome, state, frame, objective: !revisiting)
        opened = feed_triggers(choice, outcome, state)
        feed_talk_log(choice, outcome, state)
        @explore_log.note(outcome, frame:)
        @explore_log.absorb(outcome, frame:) if choice[:skill] == 'explore'
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
        names = @registry.names - SCREEN_ONLY - AUTOPILOT_ONLY - (@composites - present.keys).map(&:name)
        @skill_point = DecisionPoint.choose_skill(subset(@registry, names)) unless @skill_point.registry.names == (names & @registry.names)
      end

      private

      def screen(state) = state.phase(booted: true).then { |phase| phase if SCREEN_SKILLS.key?(phase) }

      def subset(registry, names) = Skills::Registry.new((names & registry.names).map { |name| registry.fetch(name) })

      def remember_grid(state, context)
        place = state.place
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
        place = state.place
        if predicate[:kind].to_s == 'leave_place' && predicate[:place] != place
          raise Refusal, "leave_place must name the current place #{place.inspect}, not #{predicate[:place].inspect}"
        end
        raise Refusal, 'predicate is already true in the current state' if satisfied?(predicate, state, place) && !@candidate&.dig(:target, :try)
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
        place = state.place
        signs = objects_for(state)
        if state.phase(booted: true) == :playing
          @cards[place] = (@cards[place] || {}).merge(people: @entities.select { |entity| entity[:kind].to_s == 'npc' && entity[:cell] }.map { |entity| entity.slice(:type, :cell) },
                                                      enemies: @entities.select { |entity| entity[:kind].to_s == 'enemy' && entity[:cell] }.map { |entity| entity.slice(:type, :cell) },
                                                      signs: signs.select { |object| object[:kind].to_s == 'sign' }.map { |object| object.slice(:cell) },
                                                      chests: signs.select { |object| object[:reachable] }.map { |object| object[:cell] })
        end
        @candidates = Candidates.build(place:, grid: context[:grid], explore_log: @explore_log, talk_log: @talk_log, leads: @leads, cards: @cards,
                                       entities: @entities, signs:, stamp: stamp(state), link: state.cell, souvenirs: @souvenirs,
                                       item_names: @item_names)
        # A candidate no known route reaches is not offered again after its objective stalled, until a route to it appears.
        stalled = @stalled | @objectives.history.filter_map { |done| done[:candidate] if done[:reason] == 'stall' }
        hops = @explore_log.hops(place)
        @candidates.reject! { |candidate| stalled.include?(candidate[:id]) && (where = candidate.dig(:target, :place)) && where != place && !hops.key?(where) }
        @candidates.each { |candidate| offer_puzzle(candidate[:target][:place]) if candidate[:id].start_with?('puzzle-') }
        @candidates
      end

      def offer_puzzle(place)
        @explore_log.offer_puzzle(place)
        (@puzzles_offered ||= []) << place
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
                                       triggers: @triggers, talk_log: @talk_log, signs: objects_for(state), locked: (@hemmed[:attempts] if @hemmed && hemmed?(state)),
                                       locked_frames: (locked_frames(state) if Modes::HELD.include?(state.phase)), goal: goal_line, leads: @leads.with_status, stamp: stamp(state),
                                       place_name: @leads.name_of(state.place), candidates: (Candidates.lines(@candidates) if decision_point.name == :choose_objective),
                                       learned: (@learned if decision_point.name == :choose_skill),
                                       resolve: @leads.method(:place_for), hp_lost: @hp_lost, died: @died, alerts: alerts(state, objective: decision_point.name == :choose_objective), route: route_line(state))
        @hp_lost = 0
        @died = false
        if @reading
          text = Dialogues.text(@reading[:transcription].map { |entry| entry[:text] })
          @prompt += "\nThe dialogue that just closed repeated a text already read (not sent again): #{clean(text.tr("\n", ' '), cap: TRANSCRIPTION_LIMIT)}"
        elsif decision_point.name == :choose_skill && @sequence
          @pages_read = @sequence[:pages].size
          @images = Vision::DialogueShot.sheets(@sequence[:pages], per_sheet: SHEET_PAGES)
          @read_at = @sequence.slice(:start, :place, :source, :contact).merge(conversation: (Vision::DialogueShot.signature(@sequence[:rows]) unless state.dialog_open?))
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

      # Closed chests carry whether a route on the current grid reaches the cell below them, from where they open; a chest whose
      # opening failed on this visit of the place is no longer reachable work until the next visit.
      def objects_for(state)
        place = state.place
        grid = @last_grid if @last_place == place
        objects_now.map do |object|
          next object unless object[:kind].to_s == 'chest' && !object[:open]

          below = [object[:cell][0] + 1, object[:cell][1]]
          failed = @chest_failures.include?([place, object[:cell], @explore_log.visits(place)])
          object.merge(reachable: !failed && (state.cell == below || (!grid.nil? && !state.cell.nil? &&
            !Navigation::Planner.new(grid:, ledger: @ledger, place:, triggers: @triggers).path(from: state.cell, to: below).nil?)))
        end
      end

      def chest_open?(cell) = objects_now.any? { |object| object[:kind].to_s == 'chest' && object[:open] && object[:cell] == cell }

      def note_open_chest(state)
        target = @objectives.current&.dig(:target)
        return unless target && target[:kind].to_s == 'chest' && target[:place] == state.place && chest_open?(target[:cell])

        @objectives.note_chest_open(place: target[:place], cell: target[:cell])
      end

      # Any talk_to aimed at a chest takes it off the away list; one that drew no response leaves it closed for this visit.
      # An item newly held takes its name from its pickup text, the first text transcribed at its place after the gain shows as held
      # (the rule of Items.pickup_names).
      def note_gains(state)
        held = Dialogues.items(state.inventory, state.item_a, state.item_b)
        @pending_gains += (held - @held).map { |item| { item:, place: state.place, frame: state.frame } } if @held
        @pending_gains.reject! do |gain|
          read = @last_read if @last_read && @last_read[:place] == gain[:place] && @last_read[:frame] > gain[:frame]
          words = Items.name_words(read&.dig(:text))
          @item_names[gain[:item]] ||= words if words.any?
          read || state.frame - gain[:frame] > Items::PICKUP_FRAMES
        end
      end

      # Only a talk that reached the thing, or a touch that held against it, tries it.
      def note_try(choice, outcome, state)
        skill = choice[:skill].to_s
        return unless %w[talk_to touch use_item].include?(skill)

        answered = outcome[:talked] == true || outcome[:dialog_after] == true
        reached = case skill
                  when 'touch' then outcome.key?(:arrival_frame)
                  when 'use_item' then outcome[:item] && !%w[refused wrong_mode].include?(outcome[:stopped_by].to_s)
                  else answered || TalkLog.attempt?(outcome)
                  end
        @objectives.note_try(place: state.place, type: outcome[:target_type], skill:, answered:, item: outcome[:item]) if reached
      end

      def note_chest_attempt(choice, outcome, state)
        return unless choice[:skill] == 'talk_to'

        place = state.place
        cell = [Ledger.pick(choice[:params], :row), Ledger.pick(choice[:params], :col)]
        chest = objects_now.find { |object| object[:kind].to_s == 'chest' && object[:cell] == cell } or return
        @cards[place][:chests] -= [cell] if @cards.dig(place, :chests)
        @chest_failures << [place, cell, @explore_log.visits(place)] unless chest[:open] || outcome[:talked] == true
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

    end
  end
end
