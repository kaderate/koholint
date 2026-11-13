module Koholint
  module Policies
    class Delegated
      module Outcomes
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
