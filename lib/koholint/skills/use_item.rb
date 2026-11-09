require 'koholint/items'
require 'koholint/skills/execution'
require 'koholint/skills/screens'

module Koholint
  module Skills
    # Puts an item on a button through the START menu when it is not on one, then holds that button.
    class ItemRun < Execution
      SETTLE_FRAMES = 60
      # Measured: A and B do nothing for 16 frames after close_menu returns (runs 20261020-085011-8330, 20261101-141755-eca1).
      AFTER_MENU_FRAMES = 16
      IDLE_FRAMES = 10

      def initialize(item:, button:, hold:, **rest)
        super(**rest)
        @query = item
        @wanted = button
        @hold = hold
        @steps = nil
        @held = 0
        @raised = 0
        @equipped = false
      end

      def result(state = @last)
        super.merge(item: @id, item_name: @id && Items.name(@id), button: @button, equipped: @equipped, raised_frames: @raised,
                    item_a: state.item_a, item_b: state.item_b, **(@cause ? { cause: @cause } : {}))
      end

      private

      def hard_cap = 900

      def input_for(state)
        return begin_with(state) if @steps.nil?
        return menu(state) unless @steps.empty?

        use(state)
      end

      def begin_with(state)
        return finish(:wrong_mode) unless state.phase(booted: true) == :playing

        @id = Items.find(@query)
        return refuse("#{@query} is not held") unless @id && Items.held(state).include?(@id)

        @button = Items.button_of(state, @id)
        @steps = @button ? [] : equip_steps(state)
        input_for(state)
      end

      def equip_steps(state)
        @button = @wanted || :b
        @equipped = true
        [[Screens.open_menu, {}], [Screens::MenuMove.new, { slot: Items.slot_of(state, @id) }], [Screens::MenuAssign.new, { button: @button }],
         [Screens.close_menu, {}]]
      end

      def menu(state)
        @sub ||= @steps.first.then { |skill, params| skill.start(state, params) }
        buttons = @sub.next_input(state)
        return buttons if buttons
        return finish_with(@sub.stopped_by, "#{@steps.first.first.name} stopped by #{@sub.stopped_by}") unless @sub.stopped_by == :done

        @steps.shift
        @sub = nil
        @menu_closed = @frames if @steps.empty?
        input_for(state)
      end

      def use(state)
        unless @pressing
          return [] if @menu_closed && @frames - @menu_closed < AFTER_MENU_FRAMES
          return [] if state.phase(booted: true) != :playing && @frames - @menu_closed.to_i < SETTLE_FRAMES
          return finish_with(:wrong_mode, "phase #{state.phase(booted: true)} after the menu") unless state.phase(booted: true) == :playing
          return refuse("#{Items.name(@id)} is no longer on #{@button}") unless Items.button_of(state, @id) == @button

          @pressing = @frames
          @base = state
        end
        @raised += 1 if @held.positive? && state.shield_raised.to_i.positive?
        return finish(:dialogue) if state.dialog_open? && !@base.dialog_open?
        return finish(:room_change) if room(state) != room(@base)
        if @held < @hold
          @held += 1
          return [@button]
        end

        @frames - @pressing >= @hold + IDLE_FRAMES ? finish(:done) : []
      end

      def refuse(cause) = finish_with(:refused, cause)

      def finish_with(reason, cause)
        @cause = cause
        finish(reason)
      end
    end

    class UseItem
      MAX_FRAMES = 60
      HOLD = 8

      def name = 'use_item'

      def params_schema
        { type: 'object', title: name,
          properties: { item: { type: 'string', minLength: 1, maxLength: 40 }, button: { type: 'string', enum: %w[a b] },
                        frames: { type: 'integer', minimum: 1, maximum: MAX_FRAMES } },
          required: %w[item], additionalProperties: false }
      end

      def normalize(params)
        params = Skills.symbolize(params, %i[item button frames])
        item = params[:item]
        raise ArgumentError, 'use_item: item must be an item name or id' unless (item.is_a?(String) && !item.strip.empty?) || item.is_a?(Integer)
        raise ArgumentError, 'use_item: button must be a or b' if params.key?(:button) && !%w[a b].include?(params[:button].to_s)
        frames = params.fetch(:frames, HOLD)
        raise ArgumentError, "use_item: frames must be 1..#{MAX_FRAMES}" unless frames.is_a?(Integer) && frames.between?(1, MAX_FRAMES)

        { item:, frames:, **(params.key?(:button) ? { button: params[:button].to_s } : {}) }
      end

      def start(state, params, _context = {})
        params = normalize(params)
        ItemRun.new(skill: name, params:, state:, item: params[:item], button: params[:button]&.to_sym, hold: params[:frames])
      end
    end

    class Guard
      MAX_FRAMES = 120

      def name = 'guard'

      def params_schema
        { type: 'object', title: name,
          properties: { frames: { type: 'integer', minimum: 1, maximum: MAX_FRAMES } },
          required: %w[frames], additionalProperties: false }
      end

      def normalize(params)
        params = Skills.symbolize(params, %i[frames])
        frames = params[:frames]
        raise ArgumentError, "guard: frames must be 1..#{MAX_FRAMES}" unless frames.is_a?(Integer) && frames.between?(1, MAX_FRAMES)

        { frames: }
      end

      def start(state, params, _context = {})
        params = normalize(params)
        ItemRun.new(skill: name, params:, state:, item: Items::SHIELD, button: nil, hold: params[:frames])
      end
    end
  end
end
