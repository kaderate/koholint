module Koholint
  module Policies
    class Delegated
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
          hint = @loop_watch.pending_hint
          return if hint.nil? || @sequence || !%i[choose_skill choose_objective].include?(decision_point.name)

          place = [state.room_id, state.map_id]
          route = @explore_log.route(place)
          return unless route || @explore_log.untried?(place)

          @loop_watch.act!
          @objectives.abandon(frame: state.frame, reason: 'loop')
          @objectives.start(frame: state.frame, **AUTO_OBJECTIVE, autopilot: true)
          @autopilot&.adopt(@objectives.current)
          context[:aim] = { place: route[:goal] } if route
          choice = decision_point.name == :choose_objective ? AUTO_OBJECTIVE.dup : EXPLORE
          { choice:, justification: "#{LoopWatch::BREAK} #{hint[:places].join(', ')}: explore #{route ? "toward #{route[:goal].join('-')}" : 'here'}, the nearest place with untried work",
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
      end
    end
  end
end
