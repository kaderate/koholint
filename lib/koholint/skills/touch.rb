require 'koholint/items'
require 'koholint/skills/goto'

module Koholint
  module Skills
    # Walks to a reachable cell next to a still thing and holds the direction into it, the way a push holds, one side after another,
    # since the thing's own sprite covers its cell. A pickup is a change of the item bytes between arrival at a side and the game
    # settling, so nothing the walk met on the way counts. A scene or a text that opens first ends the touch unsettled: the harness reads it.
    class Touch
      SETTLE_STILL = 8
      SETTLE_FRAMES = 60
      HOLD_STILL = 40
      HOLD_FRAMES = 60

      class Run < Goto::Run
        def initialize(type:, thing:, **rest)
          @type = type
          @thing = thing
          @sides = []
          @hold = nil
          super(**rest)
          @arrival = nil
          @holding = nil
          @landing = nil
        end

        def next_input(state)
          return land(state) if @landing
          return hold(state) if @holding

          buttons = super
          return buttons unless buttons.nil? && @stopped_by == :done

          @stopped_by = nil
          @arrival = { frame: state.frame, items: Touch.items(state) }
          @holding = { still: 0, last: nil, frames: 0 }
          hold(state)
        end

        def result(state = @last)
          merged = super.merge(target_type: @type, thing: { row: @thing[0], col: @thing[1] }, sides: @sides.map(&:to_s), items_after: Touch.items(state),
                               settled: @landing&.dig(:still).to_i >= SETTLE_STILL)
          return merged unless @arrival

          merged.merge(arrival_frame: @arrival[:frame], items_before: @arrival[:items], **(merged[:settled] ? { picked_up: @arrival[:items] != merged[:items_after] } : {}))
        end

        private

        def initial_plan = next_side(@start.cell)

        # The nearest cell next to the thing that a path reaches, among the sides not held yet; holding from it faces the thing.
        def next_side(from)
          return nil unless from && @planner

          options = Geometry::DIRECTIONS.filter_map do |direction|
            next if @sides.include?(direction)

            cell = Geometry.step(@thing, Geometry::OPPOSITE.fetch(direction)) or next
            path = @planner.path(from:, to: cell, cross_margin: cross_margin?) or next
            [path, cell, direction]
          end
          path, cell, direction = options.min_by { |path, _, direction| [path.size, Geometry::DIRECTIONS.index(direction)] }
          @cause = path ? nil : 'no cell next to the thing is reachable'
          return nil unless path

          @target = cell
          @hold = direction
          @initial_length ||= path.size - 1
          path
        end

        def hold(state)
          @last = state
          return nil if @stopped_by
          return end_touch(:frame_cap) if @frames >= hard_cap
          return end_touch(:room_change) if state.place != @start.place
          return end_touch(:scene) if state.scene?
          return end_touch(:dialogue) if state.dialog_open?
          return end_touch(:damage) if state.health < @start.health
          return begin_landing(state) if Touch.items(state) != @arrival[:items]

          position = [state.x, state.y]
          @holding[:still] = position == @holding[:last] ? @holding[:still] + 1 : 0
          @holding[:last] = position
          @holding[:frames] += 1
          return next_hold(state) if @holding[:still] >= HOLD_STILL || @holding[:frames] >= HOLD_FRAMES

          @frames += 1
          [@hold]
        end

        def next_hold(state)
          @sides << @hold
          @holding = nil
          path = next_side(state.cell) or return end_touch(:no_contact)

          restart(state, path)
          next_input(state)
        end

        def begin_landing(state)
          @holding = nil
          @landing = { still: 0, frames: 0 }
          land(state)
        end

        def land(state)
          @last = state
          return nil if @stopped_by
          return end_touch(:scene) if state.scene?
          return end_touch(:dialogue) if state.dialog_open?

          @landing[:still] = Touch.settled?(state) ? @landing[:still] + 1 : 0
          @landing[:frames] += 1
          return end_touch(:done) if @landing[:still] >= SETTLE_STILL || @landing[:frames] >= SETTLE_FRAMES

          @frames += 1
          []
        end

        def end_touch(reason)
          @sides << @hold if @holding && @hold && !@sides.include?(@hold)
          @stopped_by = reason
          nil
        end
      end

      def self.items(state) = { held: Items.held(state).uniq.sort, rupees: state.rupees.to_i }

      def self.settled?(state) = !state.dialog_open? && state.link_frozen.to_i.zero? && state.controllable?

      def name = 'touch'

      def params_schema
        { type: 'object', title: name,
          properties: { row: { type: 'integer', minimum: 0, maximum: Geometry::ROWS - 1 },
                        col: { type: 'integer', minimum: 0, maximum: Geometry::COLS - 1 },
                        type: { type: 'integer', minimum: 0, maximum: 255 } },
          required: %w[row col type], additionalProperties: false }
      end

      def normalize(params)
        params = Skills.symbolize(params, %i[row col type])
        raise ArgumentError, "touch: row must be 0..#{Geometry::ROWS - 1}" unless params[:row].is_a?(Integer) && params[:row].between?(0, Geometry::ROWS - 1)
        raise ArgumentError, "touch: col must be 0..#{Geometry::COLS - 1}" unless params[:col].is_a?(Integer) && params[:col].between?(0, Geometry::COLS - 1)
        raise ArgumentError, 'touch: type must be 0..255' unless params[:type].is_a?(Integer) && params[:type].between?(0, 255)

        { row: params[:row], col: params[:col], type: params[:type] }
      end

      def start(state, params, context = {})
        params = normalize(params)
        thing = [params[:row], params[:col]]
        Run.new(skill: name, params:, state:, target: thing, thing:, type: params[:type], context:)
      end
    end
  end
end
