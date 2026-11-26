require 'digest'
require 'koholint/policies/base'

module Koholint
  module Policies
    class Delegated < Base
      module Guidance
        STAND_SKILLS = %w[guard wait].freeze
        STAND_MARGIN = 32

        def keep_moving(result, state)
          choice = result[:choice]
          return result unless choice.is_a?(Hash) && STAND_SKILLS.include?(choice[:skill].to_s) && state.phase == :playing && !state.dialog_open?
          return result unless Navigation::Threat.within?(Navigation::Threat.of(entities_now), state.x, state.y, margin: STAND_MARGIN)

          result.merge(choice: EXPLORE, justification: "harness: no standing next to a hostile creature (replaces the model's #{choice[:skill]}): #{result[:justification]}", autopilot: false)
        end

        private

        def objective_place
          objective = @objectives.current or return
          predicate = objective[:predicate]
          predicate[:kind].to_s == 'reach_place' ? predicate[:place] : objective.dig(:target, :place)
        end

        def route_line(state)
          danger = @explore_log.dangerous.map { |place| "#{place.join('-')} (#{@healers.hits[place]} hp)" }
          warned = danger.empty? ? nil : "Places where one measured hit would take Link's #{state.health} hp, which the harness never walks into: #{danger.join(', ')}."
          known = known_route(state)
          [known, warned].compact.join("\n").then { |line| line unless line.empty? }
        end

        def known_route(state)
          goal = objective_place
          here = state.place
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
          aim = follow_choice(state)&.dig(:aim) || ({ place: } if place && place != state.place)
          context[:aim] = aim if aim
        end

        def alerts(state, objective: false)
          place = state.place
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
          lines.concat(fresh_puzzles(place).map { |puzzle| puzzle_line(puzzle) })
          lines.concat(puzzle_texts(place, objective:))
        end

        TEXTS_BUDGET = 2000
        TEXT_PREFIX = 'TEXT READ HERE (quoted in full while a puzzle here is open): '

        # While a puzzle here is open, what was read here is quoted whole (a lead keeps one sentence, and a low one is never shown again),
        # newest first within a character budget, at every objective decision and at the first decision of each visit.
        # The texts of a puzzle place offered as a candidate travel with the offer, in the same budget.
        def puzzle_texts(place, objective: false)
          @texts_shown ||= Set.new
          here = puzzle_open?(place) && (@texts_shown.add?([place, @explore_log.visits(place)]) || objective) ? [[place, TEXT_PREFIX]] : []
          away = @candidates.filter_map { |candidate| candidate[:target][:place] if candidate[:id].start_with?('puzzle-') && candidate[:target][:place] != place }
                            .map { |where| [where, "TEXT READ IN #{where.join('-')} (beside the candidate puzzle-#{where.join('-')}): "] }
          left = TEXTS_BUDGET
          (here + away).flat_map { |where, prefix| @leads.texts_at(where).reverse.map { |text| [prefix, text.gsub(/\s+/, ' ').strip] } }.filter_map do |prefix, text|
            next if left <= 0

            shown = text.size > left ? "#{text[0, left]}... (cut)" : text
            left -= text.size
            "#{prefix}« #{shown} »"
          end
        end

        def puzzle_open?(place) = @explore_log.puzzles(place).any? && !@explore_log.bench_concluded?(place)

        MODEL_HOLD_FRAMES = 1800

        # Entering a place with an open puzzle and texts read there ends a harness objective so the model chooses the next one with those
        # texts in front of it, once per context and set of texts read there: no new text, no new paid ask. An objective of the model's own
        # is left alone.
        def note_puzzle_entry(state)
          place = state.place
          @puzzle_ask = nil unless @puzzle_ask&.dig(:place) == place
          return unless state.phase(booted: true) == :playing && puzzle_open?(place)
          return if @objectives.current && !@objectives.current[:autopilot]

          texts = @leads.texts_at(place)
          return if texts.empty?

          entry = { place:, texts: Digest::SHA256.hexdigest(texts.map { |text| Dialogues.key(text) }.sort.join("\n"))[0, 16] }
          return unless @explore_log.enter_puzzle(place, Exits.context(state), entry[:texts])

          @objectives.abandon(frame: state.frame, reason: 'puzzle') if @objectives.current
          @puzzle_ask = entry
        end

        # A loop break replaces a harness objective at once, and one the model wrote only after MODEL_HOLD_FRAMES.
        def model_hold?(state)
          current = @objectives.current
          current && !current[:autopilot] && state.frame - current[:started_frame] < MODEL_HOLD_FRAMES
        end

        # Each puzzle is stated once per visit of its place, not in every prompt.
        def fresh_puzzles(place)
          @puzzles_shown ||= Set.new
          @explore_log.puzzles(place).last(PUZZLE_LINES).select { |puzzle| @puzzles_shown.add?([puzzle[:id], @explore_log.visits(place)]) }
        end

        PUZZLE_LINES = 2

        def puzzle_line(puzzle)
          way = puzzle[:way].is_a?(Array) ? "the door above (#{puzzle[:way][0] + 1},#{puzzle[:way][1]})" : "the #{puzzle[:way]} side"
          observed = puzzle[:observed]
          landing = observed[:landing] ? " (landing row #{observed[:landing][0]}, col #{observed[:landing][1]})" : ''
          led = "led to #{observed[:to].join('-')}#{landing}"
          frames = puzzle[:frames]
          seen = frames.empty? ? '' : ", #{frames.size} #{frames.size == 1 ? 'time' : 'times'} since frame #{frames.first}"
          expected = puzzle[:expected][:to].join('-')
          fact = case puzzle[:kind]
                 when 'unexpected_arrival' then "leaving #{puzzle[:place].join('-')} by #{way} #{led}, not to #{expected}, the screen next to it on the map#{seen}."
                 when 'refuted' then "the way back from #{puzzle[:place].join('-')} by #{way} was assumed to lead to #{expected}; it #{led}#{seen}."
                 else "leaving #{puzzle[:place].join('-')} by #{way} led to #{expected} before, and #{led}#{seen}."
                 end
          bench = @explore_log.bench_of(puzzle[:place])
          return "PUZZLE (observed, not explained): #{fact}" unless bench

          reached = bench['ways'].select { |_, to| to.is_a?(Array) }.map do |way, to|
            status = @explore_log.bench_status(puzzle[:place], Exits.way_key(way.match?(/\A\d+-\d+\z/) ? way.split('-').map(&:to_i) : way))
            "#{way} to #{to.join('-')}#{status == 'observed' ? ' (one lineage)' : ''}"
          end
          unreached = bench['ways'].reject { |_, to| to.is_a?(Array) }.keys
          outcome = case bench['status']
                    when 'leads_on' then "leads on to #{bench['new_places'].map { |to| to.join('-') }.join(', ')}"
                    when 'incomplete' then "ways not reached: #{unreached.join(', ')}, so it concludes nothing yet"
                    else 'every way was reached and none leads to a place not seen yet, so the outcome depends on something else'
                    end
          "PUZZLE (observed, measured by the exit bench with Link's current items): #{fact} Bench: #{reached.join(', ')}; #{outcome}."
        end

        def autopilot_choice(decision_point, state, context)
          return unless @autopilot && decision_point.name == :choose_skill && !@sequence && !@reading && !hemmed?(state)

          disengage = @autopilot.disengage_choice(state:, entities: entities_now, grid: context[:grid])
          return disengage.tap { @autopilot_acting = true } if disengage

          heart = @autopilot.heart_choice(state:, entities: entities_now, grid: context[:grid])
          return heart.merge(decision_point: @touch_point).tap { @autopilot_acting = true } if heart

          fight = @autopilot.fight_choice(state:, entities: entities_now, objects: objects_now)
          return fight.tap { @autopilot_acting = true } if fight

          door = @autopilot.door_choice(state:, doors: objects_now.select { |object| object[:kind].to_s == 'door' }.map { |object| object[:cell] })
          return door.tap { @autopilot_acting = true } if door

          touch = @autopilot.touch_choice(state:, objective: @objectives.current, entities: entities_now)
          return touch.merge(decision_point: @touch_point).tap { @autopilot_acting = true } if touch

          place = state.place
          # A place that has hurt Link is no place to try unknown things: the model may still choose to.
          trial = @autopilot.try_choice(state:, objective: @objectives.current, entities: entities_now, tried: ->(type) { @explore_log.met?(place, type) }) unless @healers.hits.key?(place)
          return trial.tap { @autopilot_acting = true } if trial

          follow = follow_choice(state)
          aim = follow&.dig(:aim, :place)
          # An objective's way through a place whose measured hit would take Link's health is walked only if a safe way exists; else the model chooses.
          if aim && @explore_log.path(state.place, goal: aim)&.any? { |hop| @explore_log.dangerous.include?(hop[:to]) }
            return unless @explore_log.path(state.place, goal: aim, ban: true)

            context[:ban] = true
          end
          result = @autopilot.next_choice(state:, objective: @objectives.current, follow: follow&.dig(:choice)) or return
          context[:aim] = follow[:aim] if follow&.dig(:aim)
          @autopilot_acting = true
          result[:choice][:skill] == 'touch' ? result.merge(decision_point: @touch_point) : result
        end

        def follow_choice(state)
          target = @objectives.current&.dig(:target) or return
          here = target[:place] == state.place
          case target[:kind]
          when 'exit' then { choice: { skill: 'explore', params: { direction: target[:direction] } } } if here
          when 'door' then { choice: EXPLORE, aim: { door: target[:cell] } } if here
          when 'person', 'sign', 'chest', 'examine'
            return ({ choice: EXPLORE, aim: { place: target[:place] } } if target[:remote] || @objectives.current.dig(:predicate, :kind).to_s == 'reach_place') unless here

            cell = target[:kind] == 'person' ? entities_now.find { |entity| entity[:type] == target[:type] && entity[:cell] }&.dig(:cell) : target[:cell]
            return unless cell
            if target[:try] && @objectives.talked_to?
              return { choice: { skill: 'use_item', params: { item: Items.name(target[:item]) } } } if target[:item]

              return { choice: { skill: 'touch', params: { row: cell[0], col: cell[1], type: target[:type] } } }
            end

            { choice: { skill: 'talk_to', params: { row: cell[0], col: cell[1] } } }
          when 'place', 'lead' then { choice: EXPLORE, aim: { place: target[:place] } } unless here
          end
        end

        # A detected loop drops the current objective, once per detection, and explores toward the nearest place with untried work outside the loop,
        # or, when no place has any, goes to the reachable place entered least outside the loop.
        def loop_break(decision_point, state, context)
          hint = @loop_watch.pending_hint
          return if hint.nil? || @sequence || !%i[choose_skill choose_objective].include?(decision_point.name) || @puzzle_ask || model_hold?(state)

          place = state.place
          looped = hint[:places].map { |at| at.split('-').map(&:to_i) }
          route = @explore_log.route(place, skip: looped)
          unless route || @explore_log.untried?(place)
            away = @explore_log.least_visited(place, avoid: looped) or return
          end

          @loop_watch.act!
          note_dropped(@objectives.current)
          @objectives.abandon(frame: state.frame, reason: 'loop')
          objective = away ? { title: "Leave the loop for #{away[:goal].join('-')}, the reachable place entered least", predicate: { kind: 'reach_place', place: away[:goal] } } : AUTO_OBJECTIVE
          @objectives.start(frame: state.frame, **objective, target: ({ kind: 'place', place: away[:goal] } if away), autopilot: true)
          @autopilot&.adopt(@objectives.current)
          goal = (route || away)&.dig(:goal)
          context.merge!(aim: { place: goal }, ban: true) if goal && !route&.dig(:lifted)
          choice = decision_point.name == :choose_objective ? objective.dup : EXPLORE
          what = if away then "no place has untried work: explore toward #{goal.join('-')}, the reachable place entered least"
                 else "explore #{route ? "toward #{goal.join('-')}" : 'here'}, the nearest place with untried work outside the loop"
                 end
          DecisionPoint.harness_choice(choice, "#{LoopWatch::BREAK} #{hint[:places].join(', ')}: #{what}", autopilot: true)
        end

        # A delivery the loop break dropped is a lead the loop says nothing about, so it is taken up again once the loop is cut, REOFFERS times at most.
        def note_dropped(objective, any: false)
          return unless objective && (any || DROPPED.any? { |prefix| objective[:candidate].to_s.start_with?(prefix) })

          @dropped = objective.slice(:title, :predicate, :candidate, :target)
        end

        # Taken up once per drop, and only while the menu still offers it: a delivery that fired retires its candidate.
        def dropped_objective(decision_point, state, context)
          return unless @dropped && decision_point.name == :choose_objective && !@loop_watch.pending_hint

          objective = @dropped
          @dropped = nil
          key = objective[:candidate] || objective[:title]
          return if @reoffers[key] >= REOFFERS
          # A lead's claim is model-written, so a lead dropped by a heal goes back to the menu, never to a harness-alone take.
          return if objective[:candidate].to_s.start_with?('lead-')
          return if objective[:candidate] && build_candidates(state, context).none? { |candidate| candidate[:id] == objective[:candidate] }

          @reoffers[key] += 1
          @objectives.start(frame: state.frame, **objective, autopilot: true)
          @autopilot&.adopt(@objectives.current)
          DecisionPoint.harness_choice(objective.slice(:title, :predicate), "the loop is cut: #{key}, set aside, is taken up again (#{@reoffers[key]}/#{REOFFERS})", autopilot: true)
        end

        # Survival before anything else, at every decision: at or below the largest hit measured on the lineage (the next one may kill), by a way through no place
        # where enemies were seen, or at one heart on a way to the objective through such a place, Link goes to the nearest place a talk healed him; the objective
        # is taken up again afterwards.
        # A place card with one person or unknown thing names who to talk to there.
        def heal_detour(decision_point, state, context)
          return unless %i[choose_skill choose_objective].include?(decision_point.name) && !@sequence && state.max_hp.to_i > state.health

          current = @objectives.current
          return if current&.dig(:heal) || @healers.detours >= HEAL_DETOURS

          goal = current&.dig(:predicate, :place)
          hops = goal && @explore_log.path(state.place, goal:)
          crossing = state.health <= Perception::HP_PER_HEART && hops&.any? { |hop| Array(@cards.dig(hop[:to], :enemies)).any? }
          return unless crossing || (@healers.hit && state.health <= @healers.hit)

          ways = @healers.places.filter_map { |at| [at, at == state.place ? [] : @explore_log.path(state.place, goal: at, ban: true)] }.select(&:last)
          ways = ways.reject { |_, path| path.any? { |hop| Array(@cards.dig(hop[:to], :enemies)).any? } } unless crossing
          place, = ways.min_by { |_, path| path.size }
          return unless place

          @healers.detoured
          note_dropped(current, any: true)
          @objectives.abandon(frame: state.frame, reason: 'heal') if current
          who = Array(@cards.dig(place, :people)) + Array(@cards.dig(place, :unknown))
          target = (who.size == 1 ? { kind: 'person', place:, type: who.first[:type], cell: who.first[:cell] } : { kind: 'place', place: }).merge(heal_below: state.health)
          @objectives.start(frame: state.frame, title: "Heal in #{place.join('-')}, where a talk healed Link before", predicate: { kind: 'reach_place', place: }, target:, autopilot: true)
          @objectives.current[:heal] = true
          @autopilot&.adopt(@objectives.current)
          context[:aim] = { place: } unless place == state.place
          why = crossing ? "the way to #{goal.join('-')} crosses enemies" : "the largest hit measured is #{@healers.hit} hp"
          choice = decision_point.name == :choose_objective ? @objectives.current.slice(:title, :predicate) : EXPLORE
          DecisionPoint.harness_choice(choice, "#{state.health} hp and #{why}: heal in #{place.join('-')} first (#{@healers.detours}/#{HEAL_DETOURS})", autopilot: true)
        end

        def zero_cap(decision_point, state, context)
          place = state.place
          return unless decision_point.name == :choose_skill && !@sequence && @zero_watch.due?(place)

          skill, stop, count, mark = @zero_watch.streak.values_at(:skill, :stop, :count, :mark)
          detail = mark == ZeroWatch::MARK ? "zero-frame: #{skill} #{stop} #{count} times in a row" : "no cell walked: #{skill} #{stop} #{count} times on this visit"
          @notes << { kind: 'stuck', detail: "#{detail} in #{place.join('-')}" }
          route = @explore_log.route(place) if @zero_watch.explore?
          away = @explore_log.least_visited(place) if @zero_watch.explore? && !route
          goal = (route || away)&.dig(:goal)
          context.merge!(aim: { place: goal }, ban: true) if goal && !route&.dig(:lifted)
          spot = [place, state.cell]
          low = !goal && state.health <= Perception::HP_PER_HEART
          @deadlock = nil unless low && @deadlock&.dig(:spot) == spot
          zone = !goal && state.cell ? Entities.danger_cells(entities_now) : []
          pressed = ([state.cell] + Geometry::DELTAS.values.map { |dr, dc| [state.cell[0] + dr, state.cell[1] + dc] }).intersect?(zone) if zone.any?
          retreat = @retreated&.dig(:spot) != spot && (pressed || (low && @deadlock && @deadlock[:waits] >= DEADLOCK_WAITS))
          # With the dangerous places the only ways left, or the way back leading into one, the model chooses once per spot, its context listing them;
          # after that the bounded wait answers, and never a retreat into one.
          if @explore_log.dangerous.any? && (retreat ? @explore_log.dangerous.include?(@explore_log.ways(place)[@explore_log.entered(place)]) : !goal)
            unless @handed_back == spot
              @handed_back = spot
              return
            end
            retreat = false
          end
          return guarded(state, context) if retreat && retreats(state) >= RETREAT_CAP
          @retreated = { spot:, hp: state.health } if retreat
          side = Array(@explore_log.entered(place)).flatten.join('-')
          @retreats << [place, side, state.frame] if retreat
          context[:retreat] = true if retreat
          @deadlock = { spot:, waits: (@deadlock&.dig(:waits) || 0) + 1 } if low && !retreat
          choice = goal || retreat ? EXPLORE : ZERO_WAIT
          @zero_watch.capping(choice[:skill])
          what = if route then "explore toward #{goal.join('-')}, the nearest place with untried work"
                 elsif away then "no place has untried work: explore toward #{goal.join('-')}, the reachable place entered least"
                 elsif pressed then 'no way out with a hostile in touch: leave by the side Link came in'
                 elsif retreat then "no way out at one heart after #{DEADLOCK_WAITS} waits: leave by the side Link came in"
                 else "wait #{ZERO_WAIT[:params][:frames]} frames before asking again"
                 end
          what = "#{what} (retreat by the #{side} side)" if retreat
          DecisionPoint.harness_choice(choice, "#{skill} ended #{stop} #{mark} #{count} times here: #{what}", autopilot: true)
        end

        def retreats(state)
          came = Array(@explore_log.entered(state.place)).flatten.join('-')
          @retreats.count { |place, side, frame| place == state.place && side == came && state.frame - frame < RETREAT_WINDOW }
        end

        # Sent back by the same side of the same place RETREAT_CAP times within RETREAT_WINDOW frames, the way is guarded: the objective is set
        # aside (taken up again later) and explore heads for work elsewhere instead of coming back to retreat again.
        def guarded(state, context)
          place = state.place
          @notes << { kind: 'stuck', detail: "guarded: sent back by the #{@explore_log.entered(place)} side of #{place.join('-')} #{RETREAT_CAP} times in #{RETREAT_WINDOW} frames" }
          note_dropped(@objectives.current, any: true)
          @objectives.abandon(frame: state.frame, reason: 'guarded')
          @objectives.start(frame: state.frame, **AUTO_OBJECTIVE, autopilot: true)
          @autopilot&.adopt(@objectives.current)
          route = @explore_log.route(place, skip: [place])
          context.merge!(aim: { place: route[:goal] }, ban: true) if route && !route[:lifted]
          DecisionPoint.harness_choice(EXPLORE, "#{place.join('-')} is guarded (#{RETREAT_CAP} retreats in #{RETREAT_WINDOW} frames): explore #{route ? "toward #{route[:goal].join('-')}" : 'elsewhere'}", autopilot: true)
        end

        # A person whose recorded text names an item Link holds, by the words of its pickup text, is tried with it: talk while holding it,
        # then use it; tried again only once Link read a new text from them or a route to them appeared.
        def item_objective(decision_point, state)
          return unless decision_point.name == :choose_objective && !@puzzle_ask

          hops = @explore_log.hops(state.place)
          held = Items.held_ids(state)
          @item_names.each do |item, words|
            next unless held.include?(item)

            seen = ->(where, who) { [@talk_log.talks_with(where, who).size, where == state.place || hops.key?(where)] }
            place, type, cell = @talk_log.mentioning(words).find do |where, who, _|
              seen.(where, who)[1] && !@talk_log.talked_holding?(where, who, item) && @item_tries[[item, where, who]] != seen.(where, who)
            end
            next unless place

            @item_tries[[item, place, type]] = seen.(place, type)
            who = @talk_log.name_of(place, type) || "person (type #{type})"
            objective = { title: "Bring the #{words.join(' ')} to #{who}"[0, 80], predicate: { kind: 'reach_place', place: },
                          target: { kind: 'person', place:, type:, cell:, try: true, item:, name: words.join(' '), seen: seen.(place, type) } }
            @objectives.start(frame: state.frame, **objective, autopilot: true)
            @autopilot&.adopt(@objectives.current)
            return DecisionPoint.harness_choice(objective.slice(:title, :predicate), "autopilot: #{who} in #{place.join('-')} named the #{words.join(' ')} Link holds; talk with it held, then use it", autopilot: true)
          end
          nil
        end

        # A reachable souvenir naming a held item by its pickup text is taken up like a lineage text, once; a drop is re-offered by the rules above.
        def souvenir_objective(decision_point, state, context)
          return unless decision_point.name == :choose_objective && !@puzzle_ask && @souvenirs.any?

          taken = @souvenirs_taken | @objectives.history.map { |done| done[:candidate] } | [@objectives.current&.dig(:candidate)]
          souvenir = build_candidates(state, context).find do |candidate|
            target = candidate[:target]
            candidate[:id].start_with?('souvenir-') && !taken.include?(candidate[:id]) &&
              Array(Items.pickup_text_names[target[:item]]).any? { |words| words.join(' ') == target[:name] }
          end or return

          @objectives.start(frame: state.frame, title: souvenir[:title], predicate: souvenir[:predicate], candidate: souvenir[:id], target: souvenir[:target], autopilot: true)
          @autopilot&.adopt(@objectives.current)
          DecisionPoint.harness_choice(souvenir.slice(:title, :predicate), "autopilot: #{souvenir[:id]} names the #{souvenir[:target][:name]} Link holds; talk with it held, then use it", autopilot: true)
        end

        def auto_objective(decision_point, state)
          return unless @autopilot && decision_point.name == :choose_objective && !@puzzle_ask
          return if @autopilot.objective_hold(state:, last: @objectives.history.last)

          place = state.place
          return unless @explore_log.work?(place) || @explore_log.route(place)
          return if unmet_person?(state, place)

          @objectives.start(frame: state.frame, **AUTO_OBJECTIVE, autopilot: true)
          @autopilot.adopt(@objectives.current)
          DecisionPoint.harness_choice(AUTO_OBJECTIVE.dup, 'autopilot: the last explore chain reached a place and achieved its objective; keep exploring', autopilot: true)
        end

        # A person here never tried is offered first at the model's objective choice, which keeping on exploring would skip.
        def unmet_person?(state, place)
          entities_now.any? do |entity|
            entity[:kind].to_s == 'npc' && entity[:cell] && @talk_log.attempts(place, [[:entity, entity[:type]]]).zero? &&
              @talk_log.status(place:, entity: entity[:type], stamp: stamp(state)) == :never
          end
        end

        def revisit_low? = @budget ? @budget.nearly_exhausted?(frames: Revisit::CYCLE_FRAMES, share: REVISIT_BUDGET_SHARE) : false

        # Untried exits or clearable objects left in a surveyed place come before talking to people again.
        def revisit_danger?(state)
          place = state.place
          hemmed?(state) || (@explore_log.surveyed?(place) && @explore_log.untried?(place))
        end

        def revisit_candidate(state)
          return unless @entities_reader

          @revisit.candidate(state:, entities: entities_now, signs: objects_for(state), stamp: stamp(state), budget_low: revisit_low?, danger: revisit_danger?(state))
        end

        def revisit_choice(decision_point, state)
          return unless decision_point.name == :choose_skill && !@sequence

          action = @revisit.next_action(state:, entities: entities_now, signs: objects_for(state), stamp: stamp(state), budget_low: revisit_low?, danger: revisit_danger?(state))
          return unless action

          @revisit_acting = true
          npc = action[:npc]
          what = npc ? "revisit npc: entity type #{npc[:type]} at (#{npc[:cell][0]},#{npc[:cell][1]})" : "#{action[:sign][:chest] ? 'open chest' : 'engage sign'} at (#{action[:sign][:cell][0]},#{action[:sign][:cell][1]})"
          DecisionPoint.harness_choice(action.slice(:skill, :params), "#{what}, round #{action[:round]}")
        end

        def override_for_revisit(result, decision_point, state)
          revisit = revisit_choice(decision_point, state) or return result

          result.merge(choice: revisit[:choice], justification: "#{revisit[:justification]} (replaces the model's choice #{result[:choice][:skill]})")
        end
      end
    end
  end
end
