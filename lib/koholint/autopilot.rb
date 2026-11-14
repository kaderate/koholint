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
    FIGHT_ON = %w[done target_gone].freeze

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
      @attack_stop = nil
    end

    def adopt(objective) = @objective = objective&.dig(:id)

    def acted(skill:, outcome:)
      @acted = true
      @attack_stop = skill.to_s == 'attack' && outcome.is_a?(Hash) ? outcome[:stopped_by].to_s : nil unless skill.to_s == 'wait'
      note_struck(skill, outcome) if outcome.is_a?(Hash)
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

    # After an attack that killed or lost its target, strike the nearest other enemy (or a type struck here before) without a call.
    def fight_choice(state:, entities:)
      return unless @since && FIGHT_ON.include?(@attack_stop) && state.phase == :playing && state.cell
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
      @attack_stop = nil
      { choice: { skill: 'attack', params: { row: target[:cell][0], col: target[:cell][1] } },
        justification: "autopilot: keep fighting, type #{target[:type]} at (#{target[:cell].join(',')}) (#{@fight}/#{FIGHT_LIMIT})", confidence: 1.0,
        agent: 'delegated', latency_ms: 0, cost_usd: 0.0, fallback: false, autopilot: true, prompt: nil, image: nil }
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

    def cap_hold(state)
      return 'chain cap' if @chain >= @chain_limit
      return 'frame cap' if state.frame - @since >= @chain_frames

      nil
    end
  end
end
