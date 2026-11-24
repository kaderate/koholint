require 'koholint/items'
require 'koholint/skills/goto'

module Koholint
  module Skills
    # Walks onto a thing's cell; a pickup is a change of the item bytes between arrival on the cell and the game settling there,
    # so nothing the walk met on the way counts. A scene or a text that opens first ends the touch unsettled: the harness reads it.
    class Touch
      SETTLE_STILL = 8
      SETTLE_FRAMES = 60

      class Run < Goto::Run
        def initialize(type:, **rest)
          super(**rest)
          @type = type
          @arrival = nil
          @landing = nil
        end

        def next_input(state)
          @arrival ||= { frame: state.frame, items: Touch.items(state) } if state.cell == @target && !@stopped_by
          return land(state) if @landing

          buttons = super
          return buttons unless buttons.nil? && @stopped_by == :done && @arrival

          @stopped_by = nil
          @landing = { still: 0, frames: 0 }
          land(state)
        end

        def result(state = @last)
          merged = super.merge(target_type: @type, items_after: Touch.items(state), settled: @landing&.dig(:still).to_i >= SETTLE_STILL)
          return merged unless @arrival

          merged.merge(arrival_frame: @arrival[:frame], items_before: @arrival[:items], **(merged[:settled] ? { picked_up: @arrival[:items] != merged[:items_after] } : {}))
        end

        private

        def land(state)
          @last = state
          return nil if @stopped_by
          return finish_landing(:scene) if state.scene?
          return finish_landing(:dialogue) if state.dialog_open?

          @landing[:still] = Touch.settled?(state) ? @landing[:still] + 1 : 0
          @landing[:frames] += 1
          return finish_landing(:done) if @landing[:still] >= SETTLE_STILL || @landing[:frames] >= SETTLE_FRAMES

          @frames += 1
          []
        end

        def finish_landing(reason)
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
        Run.new(skill: name, params:, state:, target: [params[:row], params[:col]], type: params[:type], context:)
      end
    end
  end
end
