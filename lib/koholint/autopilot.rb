require 'koholint/navigation/threat'
require 'koholint/perception'

module Koholint
  class Autopilot
    CHAIN_LIMIT = 6
    CHAIN_FRAMES = 2400
    BENIGN = %w[new_place known_place budget untried_object].freeze
    ARRIVED = %w[new_place known_place].freeze
    RETURNS = 3
    EXPLORING = %w[new_place leave_place new_text].freeze
    CHOICE = { skill: 'explore', params: {} }.freeze
    FIGHT_LIMIT = 8
    FIGHT_FRAMES = 900
    FIGHT_REACH = 2
    FIGHT_FLOOR = 16
    FIGHT_DROP = 8
    FIGHT_AFTER = { 'attack' => %w[done target_gone], 'explore' => %w[danger] }.freeze
    DISENGAGE_LIMIT = 3
    STEP = { up: [0, -1], down: [0, 1], left: [-1, 0], right: [1, 0] }.freeze

    attr_reader :chain, :chain_limit, :chain_frames

    def initialize(chain_limit: CHAIN_LIMIT, chain_frames: CHAIN_FRAMES)
      @chain_limit = chain_limit
      @chain_frames = chain_frames
      @chain = 0
      @since = @stop = nil
      @acted = false
      @returns = Hash.new(0)
      @fight = 0
      @struck = { place: nil, types: [] }
    end

    def model_called(state:, objective:, news: false)
      @chain = 0
      @since = state.frame
      @hp = state.health
      @objective = objective&.dig(:id)
      @news = news
      @stop = nil
      @acted = false
      @returns = Hash.new(0)
      @fight = 0
      @fight_stop = false
      @disengaged = 0
      @walled = []
    end

    def adopt(objective) = @objective = objective&.dig(:id)

    def acted(skill:, outcome:)
      @acted = true
      @fight_stop = outcome.is_a?(Hash) && FIGHT_AFTER.fetch(skill.to_s, []).include?(outcome[:stopped_by].to_s) unless skill.to_s == 'wait'
      note_struck(skill, outcome) if outcome.is_a?(Hash)
      @walled |= [outcome[:params][:direction].to_s] if skill.to_s == 'walk' && outcome.is_a?(Hash) && outcome[:params].is_a?(Hash) && walled?(outcome)
      @stop = skill.to_s == 'explore' && outcome.is_a?(Hash) ? outcome[:stopped_by].to_s : nil
      to = outcome[:to] if @stop == 'known_place'
      @returns[[to[:room], to[:map]]] += 1 if to.is_a?(Hash) && @returns
    end

    def hold_reason(state:, objective:, follow: nil, danger: false)
      return 'no model call yet' unless @since

      target = objective&.dig(:target)
      first = follow && target && !@acted
      return "last stop #{@stop || 'not an explore'}" unless first || BENIGN.include?(@stop)
      return 'target followed' if target && @acted && follow && follow[:skill] != 'explore'

      common = common_hold(state, news: !target)
      return common if common
      return 'objective changed' unless objective && objective[:id] == @objective

      kind = objective.dig(:predicate, :kind).to_s
      return "objective #{kind}" unless EXPLORING.include?(kind) || target
      return 'no way to follow the target' if target && !follow

      cap_hold(state)
    end

    def next_choice(state:, objective:, follow: nil, danger: false)
      return if hold_reason(state:, objective:, follow:, danger:)

      @chain += 1 unless @stop == 'known_place'
      @stop = nil
      what = follow ? "follow the objective target with #{follow[:skill]}" : 'explore again'
      { choice: follow || CHOICE, justification: "autopilot: #{what} (#{@chain}/#{@chain_limit})", confidence: 1.0, agent: 'delegated',
        latency_ms: 0, cost_usd: 0.0, fallback: false, autopilot: true, prompt: nil, image: nil }
    end

    # After an attack that killed or lost its target, or an explore stopped short of an enemy's touch, strike the nearest other enemy (or a type struck here before) without a call.
    def fight_choice(state:, entities:)
      return unless @since && @fight_stop && state.phase == :playing && state.cell
      return if state.health < FIGHT_FLOOR || state.health < @hp - FIGHT_DROP
      return if @fight >= FIGHT_LIMIT || state.frame - @since >= FIGHT_FRAMES

      here = @struck[:place] == [state.room_id, state.map_id]
      struck = here ? @struck[:types] : []
      row, col = state.cell
      target = Array(entities).select { |entity| entity[:cell] && !(here && entity[:slot] == @struck[:slot]) }
                              .select { |entity| entity[:kind].to_s == 'enemy' || (entity[:kind].to_s == 'unknown' && struck.include?(entity[:type])) }
                              .select { |entity| [(entity[:cell][0] - row).abs, (entity[:cell][1] - col).abs].max <= FIGHT_REACH }
                              .min_by { |entity| [(entity[:cell][0] - row).abs + (entity[:cell][1] - col).abs, entity[:slot]] } or return
      @fight += 1
      @fight_stop = false
      { choice: { skill: 'attack', params: { row: target[:cell][0], col: target[:cell][1] } },
        justification: "autopilot: keep fighting, type #{target[:type]} at (#{target[:cell].join(',')}) (#{@fight}/#{FIGHT_LIMIT})", confidence: 1.0,
        agent: 'delegated', latency_ms: 0, cost_usd: 0.0, fallback: false, autopilot: true, prompt: nil, image: nil }
    end

    # At one heart or less with an enemy within a cell of its touch, step away from every such enemy before the model decides.
    def disengage_choice(state:, entities:, grid: nil)
      return unless @since && state.phase == :playing && state.x && state.cell && state.health <= Perception::HP_PER_HEART && @disengaged < DISENGAGE_LIMIT

      near = Navigation::Threat.of(Array(entities)).select { |threat| Navigation::Threat.distance(threat, state.x, state.y) <= threat[:reach] + Geometry::CELL }
      return if near.empty?

      holes = grid.respond_to?(:hole_margin) ? grid.hole_margin + Geometry::ROWS.times.to_a.product(Geometry::COLS.times.to_a).select { |cell| grid.hole?(*cell) } : []
      direction = STEP.reject { |name, (dx, dy)| Array(@walled).include?(name.to_s) || holes.include?([state.cell[0] + dy, state.cell[1] + dx]) || near.any? { |threat| ((threat[:x] - state.x) * dx) + ((threat[:y] - state.y) * dy) > 0 } }
                      .max_by { |_, (dx, dy)| near.map { |threat| Navigation::Threat.distance(threat, state.x + (dx * Geometry::CELL), state.y + (dy * Geometry::CELL)) }.min }
                      &.first or return
      @disengaged += 1
      { choice: { skill: 'walk', params: { direction: direction.to_s, cells: 1 } },
        justification: "autopilot: disengage at #{state.health} hp, step #{direction} away from #{near.map { |threat| threat[:type] }.join(', ')} (#{@disengaged}/#{DISENGAGE_LIMIT})",
        confidence: 1.0, agent: 'delegated', latency_ms: 0, cost_usd: 0.0, fallback: false, autopilot: true, prompt: nil, image: nil }
    end

    def objective_hold(state:, last:)
      return 'no model call yet' unless @since
      return "last stop #{@stop || 'not an explore'}" unless ARRIVED.include?(@stop)
      return 'last objective not achieved by the chain' unless last && last[:outcome].to_s == 'achieved' && last[:id] == @objective

      common_hold(state) || cap_hold(state)
    end

    private

    def common_hold(state, news: true)
      return 'new lead or goal' if news && @news
      return 'explore loop' if @returns.values.max.to_i >= RETURNS
      return "phase #{state.phase}" unless state.phase == :playing
      return 'hp dropped' if state.health < @hp
      return 'low health' if state.health <= Perception::HP_PER_HEART

      nil
    end

    # The types struck count for the visit only: leaving the place forgets them, as a resume (which starts with none) would.
    def note_struck(skill, outcome)
      from = outcome[:from]
      target = outcome[:target]
      if skill.to_s == 'attack' && target.is_a?(Hash) && from.is_a?(Hash)
        here = [from[:room], from[:map]]
        @struck = { place: here, types: [] } unless @struck[:place] == here
        @struck[:types] |= [target[:type]]
        @struck[:slot] = target[:slot]
      end
      to = outcome[:to]
      @struck = { place: nil, types: [] } if to.is_a?(Hash) && @struck[:place] && [to[:room], to[:map]] != @struck[:place]
    end

    def walled?(outcome) = outcome[:stopped_by].to_s == 'blocked' || (outcome[:stopped_by].to_s == 'danger' && outcome[:frames].to_i.zero?)

    def cap_hold(state)
      return 'chain cap' if @chain >= @chain_limit
      return 'frame cap' if state.frame - @since >= @chain_frames

      nil
    end
  end
end
