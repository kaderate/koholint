module Koholint
  module Skills
    class Execution
      HARD_CAP = 400

      attr_reader :frames, :stopped_by

      def initialize(skill:, params:, state:)
        @skill = skill
        @params = params
        @start = state
        @last = state
        @frames = 0
        @stopped_by = nil
      end

      def next_input(state)
        @last = state
        return nil if @stopped_by

        buttons = @frames >= HARD_CAP ? finish(:frame_cap) : input_for(state)
        @frames += 1 if buttons
        buttons
      end

      def abort(reason)
        @frames -= 1
        @stopped_by = reason
      end

      def result(state = @last)
        { skill: @skill, params: @params, frames: @frames, from: place(@start), to: place(state),
          moved_cells: moved_cells(state), room_changed: room(@start) != room(state), hp_delta: state.hp.to_i - @start.hp.to_i,
          dialog_before: @start.dialog_open?, dialog_after: state.dialog_open?, stopped_by: @stopped_by }
      end

      private

      def finish(reason)
        @stopped_by = reason
        nil
      end

      def room(state) = [state.room_id, state.map_id]

      def cell(state) = [(state.y.to_i - 8) / 16, state.x.to_i / 16]

      def moved_cells(state) = cell(@start).zip(cell(state)).sum { |a, b| (a - b).abs }

      def place(state)
        row, col = cell(state)
        { room: state.room_id, map: state.map_id, x: state.x, y: state.y, row:, col: }
      end
    end
  end
end
