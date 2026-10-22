require 'koholint/modes'
require 'koholint/skills/execution'

module Koholint
  module Skills
    module Screens
      HOLD = 8
      TAP = 3
      RELEASE = 2
      RESPONSE_FRAMES = 30
      # The game ignores START and SELECT for about 12 frames after returning to play, so an unanswered press is repeated.
      PLAY_PHASES = %i[playing locked dialogue].freeze

      def self.mode_name(state) = Modes.for(state)&.name

      def self.settled_in?(state, name) = mode_name(state) == name && Modes.ready?(state)

      class Run < Execution
        def result(state = @last) = super.merge(mode: Screens.mode_name(state), item_a: state.item_a, item_b: state.item_b)

        private

        def hard_cap = 600

        def input_for(state)
          if @frames.zero?
            return finish(:wrong_mode) unless allowed?(state)
          end
          screen_input(state)
        end
      end

      class Toggle
        attr_reader :name

        def initialize(name:, from:, to:, button:, limit:)
          @name = name
          @from = from
          @to = to
          @button = button
          @limit = limit
        end

        class Run < Screens::Run
          def initialize(from:, to:, button:, limit:, **rest)
            super(**rest)
            @from = from
            @to = to
            @button = button
            @limit = limit
          end

          private

          def allowed?(state) = @from == :play ? state.phase(booted: true) == :playing : Screens.settled_in?(state, @from)

          def arrived?(state) = @to == :play ? PLAY_PHASES.include?(state.phase(booted: true)) : Screens.settled_in?(state, @to)

          def screen_input(state)
            @pressed ||= 0
            return [@button] if @frames - @pressed < HOLD
            return finish(:done) if arrived?(state)
            return finish(:no_response) if @frames >= HOLD + @limit
            return [] unless Screens.mode_name(state) == Screens.mode_name(@start) && @frames - @pressed >= HOLD + RESPONSE_FRAMES

            @pressed = @frames
            [@button]
          end
        end

        def params_schema = { type: 'object', title: name, properties: {}, additionalProperties: false }

        def normalize(params)
          Skills.symbolize(params, [])
          {}
        end

        def start(state, params, _context = {})
          Run.new(skill: name, params: normalize(params), state:, from: @from, to: @to, button: @button, limit: @limit)
        end
      end

      def self.open_menu = Toggle.new(name: 'open_menu', from: :play, to: 'inventory', button: :start, limit: 150)

      def self.close_menu = Toggle.new(name: 'close_menu', from: 'inventory', to: :play, button: :start, limit: 150)

      def self.open_map = Toggle.new(name: 'open_map', from: :play, to: 'map', button: :select, limit: 200)

      def self.close_map = Toggle.new(name: 'close_map', from: 'map', to: :play, button: :b, limit: 200)

      class Cursor < Screens::Run
        STEPS = 12

        def initialize(target:, **rest)
          super(**rest)
          @target = target
          @hold = 0
          @idle = 0
          @before = nil
          @steps = 0
        end

        private

        def mode(state) = Modes.for(state)

        def cursor_of(state) = state[mode(state).cursor.fetch('field').to_sym].to_i

        def count(state) = mode(state).cursor.fetch('count')

        def move(state, cursor)
          return [@direction] if (@hold -= 1).positive?

          @idle += 1
          if @before
            @before = nil if cursor != @before && @idle >= RELEASE
            return finish(:no_response) if @before && @idle >= RESPONSE_FRAMES
            return [] if @before || @idle < RELEASE
          end
          return yield if cursor == @target
          return finish(:no_response) if (@steps += 1) > STEPS

          @direction = direction(state, cursor)
          @before = cursor
          @hold = press
          @idle = 0
          [@direction]
        end

        def press = HOLD
      end

      class MenuMove
        def name = 'menu_move'

        class Run < Cursor
          private

          def press = TAP

          def allowed?(state) = Screens.settled_in?(state, 'inventory') && @target < count(state)

          def screen_input(state) = move(state, cursor_of(state)) { finish(:done) }

          def direction(state, cursor)
            size = count(state)
            columns = mode(state).cursor.fetch('columns')
            steps = { right: 1, left: -1, down: columns, up: -columns }
            seen = { cursor => nil }
            queue = [cursor]
            until queue.empty?
              at = queue.shift
              steps.each do |dir, delta|
                to = (at + delta) % size
                next if seen.key?(to)

                seen[to] = seen[at] || dir
                return seen[to] if to == @target

                queue << to
              end
            end
          end
        end

        def params_schema
          { type: 'object', title: name, properties: { slot: { type: 'integer', minimum: 0, maximum: 9 } }, required: %w[slot],
            additionalProperties: false }
        end

        def normalize(params)
          params = Skills.symbolize(params, %i[slot])
          raise ArgumentError, 'menu_move: slot must be 0..9' unless params[:slot].is_a?(Integer) && params[:slot].between?(0, 9)

          { slot: params[:slot] }
        end

        def start(state, params, _context = {})
          params = normalize(params)
          Run.new(skill: name, params:, state:, target: params[:slot])
        end
      end

      class MenuAssign
        BUTTONS = %i[a b].freeze

        def name = 'menu_assign'

        class Run < Screens::Run
          def initialize(button:, **rest)
            super(**rest)
            @button = button
          end

          private

          def allowed?(state) = Screens.settled_in?(state, 'inventory')

          def screen_input(state)
            return [@button] if @frames < HOLD
            return finish(:done) if [state.item_a, state.item_b] != [@start.item_a, @start.item_b]
            return finish(:no_response) if @frames >= HOLD + RESPONSE_FRAMES

            []
          end
        end

        def params_schema
          { type: 'object', title: name, properties: { button: { type: 'string', enum: BUTTONS.map(&:to_s) } }, required: %w[button],
            additionalProperties: false }
        end

        def normalize(params)
          params = Skills.symbolize(params, %i[button])
          button = params[:button].respond_to?(:to_sym) ? params[:button].to_sym : nil
          raise ArgumentError, 'menu_assign: button must be a or b' unless BUTTONS.include?(button)

          { button: }
        end

        def start(state, params, _context = {})
          params = normalize(params)
          Run.new(skill: name, params:, state:, button: params[:button])
        end
      end

      class ChooseOption
        LIMIT = 300

        def name = 'choose_option'

        class Run < Cursor
          private

          def allowed?(state)
            current = mode(state)
            @screen = current&.name
            current&.cursor&.fetch('field') == 'menu_option' && Modes.ready?(state) && @target < count(state)
          end

          def screen_input(state)
            return confirm(state) if @confirming

            move(state, cursor_of(state)) do
              @confirming = @frames
              [:a]
            end
          end

          def confirm(state)
            elapsed = @frames - @confirming
            return [:a] if elapsed < HOLD
            return finish(:done) if Screens.mode_name(state) != @screen
            return finish(:no_response) if elapsed >= HOLD + LIMIT

            []
          end

          def direction(state, cursor) = (@target - cursor) % count(state) <= count(state) / 2 ? :down : :up
        end

        def params_schema
          { type: 'object', title: name, properties: { option: { type: 'integer', minimum: 0, maximum: 2 } }, required: %w[option],
            additionalProperties: false }
        end

        def normalize(params)
          params = Skills.symbolize(params, %i[option])
          raise ArgumentError, 'choose_option: option must be 0..2' unless params[:option].is_a?(Integer) && params[:option].between?(0, 2)

          { option: params[:option] }
        end

        def start(state, params, _context = {})
          params = normalize(params)
          Run.new(skill: name, params:, state:, target: params[:option])
        end
      end
    end
  end
end
