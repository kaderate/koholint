module Koholint
  class Autopilot
    CHAIN_LIMIT = 6
    CHAIN_FRAMES = 2400
    BENIGN = %w[new_place budget].freeze
    EXPLORING = %w[new_place leave_place new_text].freeze
    CHOICE = { skill: 'explore', params: {} }.freeze

    attr_reader :chain, :chain_limit, :chain_frames

    def initialize(chain_limit: CHAIN_LIMIT, chain_frames: CHAIN_FRAMES)
      @chain_limit = chain_limit
      @chain_frames = chain_frames
      @chain = 0
      @since = @stop = nil
    end

    def model_called(state:, objective:, news: false)
      @chain = 0
      @since = state.frame
      @hp = state.hp.to_i
      @objective = objective&.dig(:id)
      @news = news
      @stop = nil
    end

    def acted(skill:, outcome:)
      @stop = skill.to_s == 'explore' && outcome.is_a?(Hash) ? outcome[:stopped_by].to_s : nil
    end

    def hold_reason(state:, objective:)
      return 'no model call yet' unless @since
      return "last stop #{@stop || 'not an explore'}" unless BENIGN.include?(@stop)
      return 'new lead or goal' if @news
      return "phase #{state.phase}" unless state.phase == :playing
      return 'hp dropped' if state.hp.to_i < @hp
      return 'objective changed' unless objective && objective[:id] == @objective

      kind = objective.dig(:predicate, :kind).to_s
      return "objective #{kind}" unless EXPLORING.include?(kind)
      return 'chain cap' if @chain >= @chain_limit
      return 'frame cap' if state.frame - @since >= @chain_frames

      nil
    end

    def next_choice(state:, objective:)
      return if hold_reason(state:, objective:)

      @chain += 1
      @stop = nil
      { choice: CHOICE, justification: "autopilot: explore again (#{@chain}/#{@chain_limit})", confidence: 1.0, agent: 'delegated',
        latency_ms: 0, cost_usd: 0.0, fallback: false, autopilot: true, prompt: nil, image: nil }
    end
  end
end
