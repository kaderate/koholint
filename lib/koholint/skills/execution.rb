require 'koholint/geometry'

module Koholint
  module Skills
    class Execution
      HARD_CAP = 400
      CENTRING_FRAMES = 16
      DIRECTIONS = %i[up right down left].freeze

      attr_reader :frames, :stopped_by
      attr_writer :triggers

      def initialize(skill:, params:, state:)
        @skill = skill
        @params = params
        @start = state
        @last = state
        @frames = 0
        @stopped_by = nil
        @centring = nil
        @blocked_at = nil
        @triggers = nil
        @last_input = nil
        @trigger_input = nil
      end

      def next_input(state)
        @last = state
        @trigger_input = @last_input if state.dialog_open? && !@start.dialog_open? && @trigger_input.nil?
        return nil if @stopped_by

        buttons = if @frames >= hard_cap then finish(:frame_cap)
                  elsif @centring then centre(state)
                  else input_for(state)
                  end
        @frames += 1 if buttons
        @last_input = buttons if buttons
        buttons
      end

      def abort(reason)
        @frames -= 1
        @stopped_by = reason
      end

      def result(state = @last)
        aligned, offset = alignment(state)
        { skill: @skill, params: @params, frames: @frames, from: place(@start), to: place(state),
          moved_cells: moved_cells(state), room_changed: room(@start) != room(state), hp_delta: state.hp.to_i - @start.hp.to_i,
          dialog_before: @start.dialog_open?, dialog_after: state.dialog_open?, stopped_by: @stopped_by,
          aligned:, offset:, blocked_at: @blocked_at, trigger_input: trigger_input }
      end

      private

      def trigger_input
        return nil unless @stopped_by == :dialogue && !@start.dialog_open?

        directions = Array(@trigger_input) & DIRECTIONS
        directions.empty? ? nil : directions
      end

      def forbidden_at(state)
        return [] unless @triggers && state.cell

        @triggers.forbidden([state.room_id, state.map_id], state.cell)
      end

      def finish(reason)
        @blocked_at = blocked_at_for(@last) if reason == :blocked
        return centre_after(reason) if centres? && %i[done blocked].include?(reason)

        @stopped_by = reason
        nil
      end

      def centres? = false

      def hard_cap = HARD_CAP

      def blocked_direction = nil

      def blocked_at_for(state)
        row, col = state.cell
        return nil unless row && blocked_direction

        { row:, col:, direction: blocked_direction }
      end

      def centre_after(reason)
        @centring = { reason:, frames: 0 }
        centre(@last)
      end

      def centre(state)
        reason = @centring[:reason]
        event = if room(state) != room(@start) then :room_change
                elsif state.hp.to_i < @start.hp.to_i then :damage
                elsif state.dialog_open? && !@start.dialog_open? then :dialogue
                end
        buttons = toward_centre(state, avoid: (blocked_direction if reason == :blocked)) unless event || @centring[:frames] >= CENTRING_FRAMES
        @centring[:frames] += 1 if buttons
        return buttons if buttons

        @centring = nil
        @stopped_by = event || reason
        nil
      end

      def toward_centre(state, avoid:)
        return nil unless state.cell

        dx, dy = Geometry.offset(state.x, state.y, state.cell)
        wanted = []
        wanted << (dx.positive? ? :left : :right) if dx.abs > Geometry::ALIGN_TOLERANCE
        wanted << (dy.positive? ? :up : :down) if dy.abs > Geometry::ALIGN_TOLERANCE
        blocked = forbidden_at(state)
        direction = wanted.find { |d| d != avoid && !blocked.include?(d) }
        [direction] if direction
      end

      def alignment(state)
        cell = state.cell
        return [false, { dx: nil, dy: nil }] unless cell

        dx, dy = Geometry.offset(state.x, state.y, cell)
        [Geometry.aligned?(state.x, state.y, cell), { dx:, dy: }]
      end

      def room(state) = [state.room_id, state.map_id]

      def moved_cells(state)
        from = @start.cell
        to = state.cell
        return from.zip(to).sum { |a, b| (a - b).abs } if from && to
        return 0 unless @start.x && @start.y && state.x && state.y

        ((@start.x - state.x).abs + (@start.y - state.y).abs + 8) / 16
      end

      def place(state)
        row, col = state.cell
        { room: state.room_id, map: state.map_id, x: state.x, y: state.y, row:, col: }
      end
    end
  end
end
