require 'koholint/items'
require 'koholint/skills/goto'

module Koholint
  module Skills
    # Walks onto a thing's cell; a pickup is read from the item bytes before and after, never assumed from the walk.
    class Touch
      class Run < Goto::Run
        def initialize(type:, **rest)
          super(**rest)
          @type = type
        end

        def result(state = @last)
          before = Touch.items(@start)
          after = Touch.items(state)
          super.merge(target_type: @type, items_before: before, items_after: after, picked_up: before != after).compact
        end
      end

      def self.items(state) = { held: Items.held(state).uniq.sort, rupees: state.rupees.to_i }

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
