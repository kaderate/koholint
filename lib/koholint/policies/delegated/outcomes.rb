require 'koholint/policies/base'

module Koholint
  module Policies
    class Delegated < Base
      module Outcomes
        FLOOR_SHARE = 0.1

        private

        def note_damage(state)
          hp = state.health
          if @last_hp && hp < @last_hp && !state.loading?
            @hurt_at = state.frame
            @hp_lost += @last_hp - hp
            @notes << { kind: 'damage', detail: "hp #{@last_hp} -> #{hp}" }
          end
          @last_hp = hp
        end

        def note_hurt(outcome, state)
          hit = -outcome[:hp_delta].to_i
          return unless hit.positive? && state.x

          entity = Hurts.in_contact(state, entities_now) or return
          detail = { type: entity[:type], hit:, place: state.place, cell: entity[:cell] }
          @hurts.add(type: entity[:type], hit:, place: state.place, frame: state.frame)
          @notes << { kind: 'hurt', detail: }
        end

        def note_talk_source(choice, outcome)
          return unless LOCK_SKILLS.include?(choice[:skill])

          talked = choice[:skill] == 'talk_to' && outcome[:talked] == true
          entity = outcome[:entity].is_a?(Hash) ? outcome[:entity][:type] || outcome[:entity]['type'] : nil
          @talk_source = talked ? choice[:params].transform_keys(&:to_sym).slice(:row, :col).merge(entity ? { entity: } : {}) : nil
        end

        def note_stuck(outcome, state)
          return if state.falling?

          place = state.place
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

          @loop_watch.observe(place: state.place, frame:)
          @notes.concat(@loop_watch.notes)
          @loop_watch.notes.clear
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

        def feed_ledger(choice, outcome, state, frame, objective: true)
          place = place_of(outcome, :from, state)
          Ledger.edges_of(outcome).each { |edge| @ledger.record(place:, blocked_at: edge) }
          blocked_at = outcome[:blocked_at]
          if blocked_at && objective
            track { @objectives.note_blocked(blocked_at:, target: @objectives.current&.dig(:predicate), frame:) } if @objectives.current
          end
          note_entered(choice, outcome, place)
          @ledger.reset_unless(state.place) unless state.loading?
        end

        def place_of(outcome, key, state)
          (Ledger.place_of(outcome[key]) if outcome[key].is_a?(Hash)) || state.place
        end

        def feed_triggers(choice, outcome, state)
          clearing = Triggers.clearing(skill: choice[:skill], params: choice[:params], result: outcome)
          @triggers.clear(**clearing) if clearing
          @contact = nil
          return unless Triggers.scripted?(skill: choice[:skill], params: choice[:params], result: outcome)

          cell = Triggers.cell_of(outcome)
          note_contact(place_of(outcome, :to, state), cell, outcome[:trigger_input]&.first)
          @triggers.record(place: place_of(outcome, :to, state), cell:, skill: choice[:skill], direction: Triggers.direction_of(choice[:skill], choice[:params]),
                            input: outcome[:trigger_input]&.first)
          cell && @triggers.count(place_of(outcome, :to, state), cell)
        end

        # The thing in the cell Link pressed toward when the game opened a text: a catalogued npc on it, else its object, unless Link has
        # stood on that object here (floor). The room object table holds an id in every cell.
        def note_contact(place, cell, input)
          target = Geometry.step(cell, input.to_sym) if cell && input
          return unless target

          row, col = target

          person = entities_now.find { |entity| entity[:cell] == [row, col] && entity[:kind].to_s == 'npc' }
          objects = @room_objects_reader&.call
          object = objects&.dig(row, col)
          thing = person ? { entity: person[:type] } : ({ object: } if object && !floor?(objects, object, place, cell))
          @contact = { row:, col:, **thing } if thing
        end

        # Ground is an id Link has stood on here, or one that fills a large share of the room (a ground kind not walked yet).
        def floor?(objects, object, place, cell)
          return true if (@explore_log.walked(place) | [cell]).any? { |r, c| objects.dig(r, c) == object }

          objects.flatten.count(object) >= objects.flatten.size * FLOOR_SHARE
        end

        def feed_talk_log(choice, outcome, state)
          item = choice[:skill] == 'use_item' && TalkLog.given(outcome)
          @talk_log.give(place: place_of(outcome, :from, state), item:) if item
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
            delta = Geometry::DELTAS[direction] or return
            cell = [from[:row], from[:col]]
            outcome[:moved_cells].to_i.times do
              @ledger.entered(place:, cell:, direction:)
              cell = [cell[0] + delta[0], cell[1] + delta[1]]
            end
          elsif PATH_SKILLS.include?(choice[:skill])
            Array(outcome[:crossed]).each { |row, col, direction| @ledger.entered(place:, cell: [row, col], direction:) }
          end
        end

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
end
