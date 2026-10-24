module Koholint
  class Revisit
    ROUND_CAP = 6
    CYCLE_FRAMES = 1800
    FAILURE_CAP = 2
    PHASES = %i[playing].freeze

    attr_reader :open

    def initialize(talk_log:)
      @talk_log = talk_log
      @npcs = Hash.new { |hash, key| hash[key] = { rounds: 0, failures: 0 } }
      @cycle = nil
      @capped = {}
      @open = nil
      @notes = []
    end

    def candidate(state:, entities:, stamp:, budget_low: false)
      return if budget_low || !PHASES.include?(state.phase(booted: true))

      place = [state.room_id, state.map_id]
      return if @capped[[place, stamp]]

      pending = entities.select { |entity| entity[:kind].to_s == 'npc' && entity[:cell] && pending?(place, entity[:type], stamp) }
      return if pending.empty?

      current = @cycle && @cycle[:place] == place && @cycle[:stamp] == stamp ? @cycle[:npc] : nil
      pending.find { |entity| entity[:type] == current } || pending.min_by { |entity| [distance(state.cell, entity[:cell]), entity[:slot]] }
    end

    def next_action(state:, entities:, stamp:, budget_low: false)
      close(:no_text) if @open
      place = [state.room_id, state.map_id]
      @cycle = nil if @cycle && (@cycle[:place] != place || @cycle[:stamp] != stamp)
      npc = candidate(state:, entities:, stamp:, budget_low:)
      return @cycle = nil unless npc
      return cap(place, stamp, state) if @cycle && state.frame - @cycle[:started] >= CYCLE_FRAMES

      @cycle ||= { place:, stamp:, started: state.frame }
      @cycle[:npc] = npc[:type]
      entry = @npcs[[place, npc[:type], stamp]]
      entry[:rounds] += 1
      @open = { place:, type: npc[:type], cell: npc[:cell], round: entry[:rounds], stamp: }
      { skill: 'talk_to', params: { row: npc[:cell][0], col: npc[:cell][1] }, npc: @open.slice(:place, :type, :cell), round: entry[:rounds] }
    end

    def talked(outcome)
      return unless @open
      return if outcome[:talked] == true || outcome['talked'] == true

      entry = @npcs[[@open[:place], @open[:type], @open[:stamp]]]
      entry[:failures] += 1
      close(entry[:failures] >= FAILURE_CAP ? :unreachable : :no_dialogue)
    end

    def read
      return unless @open

      close(@talk_log.last_status(place: @open[:place], entity: @open[:type]))
    end

    def notes
      out = @notes
      @notes = []
      out
    end

    private

    def pending?(place, type, stamp)
      entry = @npcs[[place, type, stamp]]
      entry[:rounds] < ROUND_CAP && entry[:failures] < FAILURE_CAP && @talk_log.status(place:, entity: type, stamp:) != :exhausted
    end

    def cap(place, stamp, state)
      @capped[[place, stamp]] = true
      @notes << { kind: 'revisit', detail: { npc: { place:, type: @cycle[:npc] }, round: 0, outcome: 'cycle_frame_cap', frames: state.frame - @cycle[:started] } }
      @cycle = nil
    end

    def close(outcome)
      @notes << { kind: 'revisit', detail: { npc: @open.slice(:place, :type, :cell), round: @open[:round], outcome: outcome.to_s } }
      @open = nil
    end

    def distance(from, to) = from ? (from[0] - to[0]).abs + (from[1] - to[1]).abs : 0
  end
end
