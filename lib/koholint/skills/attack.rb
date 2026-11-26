require 'koholint/entities'
require 'koholint/items'
require 'koholint/navigation/threat'
require 'koholint/skills/goto'

module Koholint
  module Skills
    # Walks next to an enemy, lines up with it inside the sword's measured reach and strikes until it dies.
    class Attack
      REACH = Geometry.fact(:sword_reach).transform_keys(&:to_sym).freeze
      STRIKE_FRAMES = 3
      RECOVER_FRAMES = 24
      MAX_STRIKES = 6
      LINEUP_FRAMES = 60
      APPROACHES = 3
      HARD_CAP = 900
      FAR = 2 * Geometry::CELL
      CONTACT_SLACK = 2
      BACKOFF_STILL = 4

      class Run < Goto::Run
        def initialize(cell:, context:, **rest)
          @entities = context[:entities]
          @max_strikes = MAX_STRIKES
          @enemy = enemy_near(cell)
          @phase = :walk
          @strikes = 0
          @hits = 0
          @killed = false
          @swing = nil
          @lineup = 0
          @approaches = 0
          @axis = nil
          @backoff = 0
          @grid = context[:grid]
          super(target: nil, context:, **rest)
        end

        def next_input(state)
          buttons = super
          return buttons unless buttons.nil? && @phase == :walk && @stopped_by == :done

          @stopped_by = nil
          @phase = :strike
          super
        end

        def result(state = @last)
          super.merge(target: @enemy&.slice(:slot, :type, :cell), standing_cell: @target && { row: @target[0], col: @target[1] },
                      strikes: @strikes, hits: @hits, killed: @killed, approaches: @approaches, **(@refusal ? { cause: @refusal } : {}))
        end

        private

        def centres? = @phase == :walk

        def hard_cap = HARD_CAP

        # An unidentified thing the agent names is a target too: new places bring types no census has seen yet. The nearest to the
        # named cell wins, an enemy only on a tie, so a known enemy a cell away never replaces the thing on the cell itself.
        def enemy_near(cell)
          targets = Array(@entities&.call).select { |entity| entity[:cell] && (entity[:kind].to_s == 'enemy' || Entities.creature?(entity)) }
          targets.select { |entity| (entity[:cell][0] - cell[0]).abs <= 1 && (entity[:cell][1] - cell[1]).abs <= 1 }
                 .min_by { |entity| [(entity[:cell][0] - cell[0]).abs + (entity[:cell][1] - cell[1]).abs, entity[:kind].to_s == 'enemy' ? 0 : 1, entity[:slot]] }
                 &.slice(:slot, :type, :x, :y, :cell, :status, :health, :contact)
        end

        def danger_of(context)
          return nil unless context[:entities] && @enemy

          @danger = -> { Entities.danger_cells(Array(context[:entities].call).reject { |entity| entity[:slot] == @enemy[:slot] }) + [@enemy[:cell]] }
        end

        def initial_plan = approach(@start.cell)

        def approach(from)
          return nil unless @enemy && from && @planner
          return beside(from) if (from[0] - @enemy[:cell][0]).abs + (from[1] - @enemy[:cell][1]).abs <= 1
          return beside(from) if from == @start.cell && [(@enemy[:x] - @start.x.to_i).abs, (@enemy[:y] - @start.y.to_i).abs].max <= FAR

          zones = Array(@danger&.call)
          options = Geometry::DELTAS.values.filter_map do |dr, dc|
            cell = [@enemy[:cell][0] + dr, @enemy[:cell][1] + dc]
            next unless Geometry.in_grid?(cell)

            path = @planner.path(from:, to: cell)
            [[zones.include?(cell) ? 1 : 0, path.size], cell, path] if path
          end
          _, @target, path = options.min_by(&:first)
          @initial_length = path ? path.size - 1 : 0
          @cause = 'no reachable cell next to the enemy' unless path
          path
        end

        # Already on or next to the enemy's cell: strike from here, since a cluster that hems Link in leaves no other cell to reach.
        def beside(from)
          @target = from
          @initial_length = 0
          [from]
        end

        def input_for(state)
          if @frames.zero?
            @button = Items.button_of(state, Items::SWORD)
            return refuse('the sword is on neither A nor B') unless @button
            return idle(:no_target) unless @enemy
          end
          @phase = :strike if @phase == :walk && @frames.positive? && (turn_to(Array(@entities.call), state) || in_reach?(state))
          @rushed ||= closing?(state)
          return super if @phase == :walk
          return finish(:room_change) if state.place != @start.place

          strike(state)
        end

        def strike(state)
          all = Array(@entities.call)
          now = all.find { |entity| entity.values_at(:slot, :type) == @enemy.values_at(:slot, :type) }
          @hits += 1 if now && now[:health].to_i < @enemy[:health].to_i
          return finish(:target_gone) unless now&.dig(:cell)
          return killed unless now[:status] == @enemy[:status]

          @enemy = @enemy.merge(now.slice(:x, :y, :cell, :health))
          return finish(:damage) if state.health < @start.health
          return swing if @swing
          return finish(:no_kill) if @strikes >= @max_strikes
          turn_to(all, state)
          return reapproach(state) if far?(state) && @approaches < APPROACHES

          lineup(state)
        end

        def killed
          @killed = true
          finish(:done)
        end

        def lineup(state)
          dx = @enemy[:x] - state.x.to_i
          dy = @enemy[:y] - state.y.to_i
          horizontal = @axis ? @axis == :horizontal : dx.abs >= dy.abs
          facing = horizontal ? (dx.positive? ? :right : :left) : (dy.positive? ? :down : :up)
          along = horizontal ? dx.abs : dy.abs
          cross = horizontal ? dy : dx
          move = if cross.abs > REACH[:cross] then horizontal ? (cross.positive? ? :down : :up) : (cross.positive? ? :right : :left)
                 elsif along > REACH[:along] then facing
                 elsif along < closest && !@rushed then Geometry::OPPOSITE.fetch(facing)
                 elsif @facing != facing then along > closest || @rushed ? facing : Geometry::OPPOSITE.fetch(facing)
                 end
          return begin_swing unless move
          return finish(:hole) if hole_ahead?(state, move)
          return finish(:out_of_reach) if (@lineup += 1) > LINEUP_FRAMES

          note_backoff(state, along < closest && move == Geometry::OPPOSITE.fetch(facing), horizontal)
          @facing = move
          [move]
        end

        # Backing off into a wall leaves Link in contact: line up on the other axis instead.
        def note_backoff(state, backing, horizontal)
          position = [state.x, state.y]
          @backoff = backing && position == @backoff_at ? @backoff + 1 : 0
          @backoff_at = position
          return if @backoff < BACKOFF_STILL

          @axis = horizontal ? :vertical : :horizontal
          @backoff = 0
        end

        # Lining up moves Link a few pixels at a time with no plan, so it checks the cell his next pixels enter.
        def hole_ahead?(state, move)
          dx, dy = Geometry::DELTAS.fetch(move).reverse
          ahead = Geometry.cell_for(state.x.to_i + (dx * Geometry::CELL / 2), state.y.to_i + (dy * Geometry::CELL / 2))
          ahead && @grid.respond_to?(:hole?) && @grid.hole?(*ahead)
        end

        # An enemy that comes closer to Link than the target is the one to strike: it touches first.
        def turn_to(all, state)
          return unless @enemy

          current = all.find { |entity| entity.values_at(:slot, :type) == @enemy.values_at(:slot, :type) }
          @enemy = @enemy.merge(current.slice(:x, :y, :cell)) if current
          distance = ->(entity) { [(entity[:x] - state.x.to_i).abs, (entity[:y] - state.y.to_i).abs].max }
          nearer = all.select { |entity| entity[:kind].to_s == 'enemy' && entity[:cell] && entity[:status] == @enemy[:status] && entity[:slot] != @enemy[:slot] && distance.(entity) < distance.(@enemy) }
                      .min_by { |entity| [distance.(entity), entity[:slot]] } or return
          return if distance.(nearer) > FAR

          @enemy = nearer.slice(:slot, :type, :x, :y, :cell, :status, :health, :contact)
          @gap = @rushed = nil
          @lineup = 0
          @axis = nil
          true
        end

        def in_reach?(state)
          return false unless @enemy

          dx = (@enemy[:x] - state.x.to_i).abs
          dy = (@enemy[:y] - state.y.to_i).abs
          [dx, dy].max <= REACH[:along] && [dx, dy].min <= REACH[:cross]
        end

        def gap(state) = [(@enemy[:x] - state.x.to_i).abs, (@enemy[:y] - state.y.to_i).abs].max

        # Backing off from an enemy that walks at Link never opens the gap, so he turns and strikes instead.
        def closing?(state)
          return false unless @enemy

          was = @gap
          @gap = gap(state)
          !!was && @gap < was
        end

        def far?(state) = [(@enemy[:x] - state.x.to_i).abs, (@enemy[:y] - state.y.to_i).abs].max > FAR

        # A struck enemy is knocked back and may walk off: walk next to it again rather than chase it pixel by pixel.
        def reapproach(state)
          @approaches += 1
          path = approach(state.cell) or return finish(:no_path)

          restart(state, path)
          @phase = :walk
          @lineup = 0
          @axis = nil
          input_for(state)
        end

        def closest = (@enemy[:contact] || Navigation::Threat::DEFAULT_REACH) + CONTACT_SLACK

        def begin_swing
          @lineup = 0
          @swing = 0
          @strikes += 1
          swing
        end

        def swing
          @swing += 1
          return [@button] if @swing <= STRIKE_FRAMES
          return [] if @swing <= STRIKE_FRAMES + RECOVER_FRAMES

          @swing = nil
          []
        end

        def refuse(cause)
          @refusal = cause
          finish(:refused)
        end
      end

      def name = 'attack'

      def params_schema
        { type: 'object', title: name,
          properties: { row: { type: 'integer', minimum: 0, maximum: Geometry::ROWS - 1 },
                        col: { type: 'integer', minimum: 0, maximum: Geometry::COLS - 1 } },
          required: %w[row col], additionalProperties: false }
      end

      def normalize(params)
        params = Skills.symbolize(params, %i[row col])
        raise ArgumentError, "attack: row must be 0..#{Geometry::ROWS - 1}" unless params[:row].is_a?(Integer) && params[:row].between?(0, Geometry::ROWS - 1)
        raise ArgumentError, "attack: col must be 0..#{Geometry::COLS - 1}" unless params[:col].is_a?(Integer) && params[:col].between?(0, Geometry::COLS - 1)

        { row: params[:row], col: params[:col] }
      end

      def start(state, params, context = {})
        params = normalize(params)
        Run.new(skill: name, params:, state:, cell: [params[:row], params[:col]], context:)
      end
    end
  end
end
