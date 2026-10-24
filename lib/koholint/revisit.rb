require 'koholint/perception'

module Koholint
  class Revisit
    ROUND_CAP = 6
    CYCLE_FRAMES = 1800
    FAILURE_CAP = 2
    VISIT_STAMPS = 3
    DANGER_PIXELS = 48
    PHASES = %i[playing].freeze

    attr_reader :open

    def initialize(talk_log:)
      @talk_log = talk_log
      @npcs = Hash.new { |hash, key| hash[key] = { rounds: 0, slots: [] } }
      @failures = Hash.new(0)
      @visit = nil
      @visits = 0
      @open = nil
      @notes = []
    end

    def candidate(state:, entities:, stamp:, budget_low: false, danger: false)
      return if budget_low || danger || !PHASES.include?(state.phase(booted: true)) || hurt?(state) || threatened?(state, entities)

      place = [state.room_id, state.map_id]
      visit = visit_for(place)
      cap(visit, stamp, state) if over_frames?(visit, stamp, state.frame)
      return if blocked?(visit, stamp, state.frame)

      people = entities.select { |entity| npc?(entity) }
      pending = people.select { |entity| pending?(place, entity, stamp, people, visit) }
      return if pending.empty?

      tried = @npcs[[place, visit[:current], stamp]][:slots] if visit[:current]
      same = pending.select { |entity| entity[:type] == visit[:current] }
      (same.reject { |entity| tried.include?(entity[:slot]) }.first || same.first) ||
        pending.min_by { |entity| [distance(state, entity), entity[:slot]] }
    end

    def next_action(state:, entities:, stamp:, budget_low: false, danger: false)
      close(:no_text) if @open
      place = [state.room_id, state.map_id]
      visit = visit_for(place)
      npc = candidate(state:, entities:, stamp:, budget_low:, danger:) or return

      visit[:cycles][stamp] ||= state.frame
      visit[:current] = npc[:type]
      entry = @npcs[[place, npc[:type], stamp]]
      entry[:rounds] += 1
      entry[:slots] |= [npc[:slot]]
      @open = { place:, type: npc[:type], cell: npc[:cell], round: entry[:rounds], stamp:, visit: visit[:id] }
      { skill: 'talk_to', params: { row: npc[:cell][0], col: npc[:cell][1] }, npc: @open.slice(:place, :type, :cell), round: entry[:rounds] }
    end

    def talked(outcome)
      return unless @open
      return if outcome[:talked] == true || outcome['talked'] == true

      key = [@open[:visit], @open[:type]]
      @failures[key] += 1
      close(@failures[key] >= FAILURE_CAP ? :unreachable : :no_dialogue)
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

    def npc?(entity) = entity[:kind].to_s == 'npc' && entity[:verified] == true && entity[:cell]

    def hurt?(state) = state.hp && state.max_hp && state.hp < state.max_hp - Perception::HP_PER_HEART

    def threatened?(state, entities)
      entities.any? do |entity|
        risky = entity[:kind].to_s == 'enemy' || (entity[:kind].to_s == 'unknown' && entity[:moves] != false)
        risky && (entity[:x] - state.x.to_i).abs <= DANGER_PIXELS && (entity[:y] - state.y.to_i).abs <= DANGER_PIXELS
      end
    end

    def visit_for(place)
      return @visit if @visit && @visit[:place] == place

      @visits += 1
      @visit = { place:, id: @visits, cycles: {}, capped: [], current: nil }
    end

    def blocked?(visit, stamp, frame)
      visit[:capped].include?(stamp) || over_frames?(visit, stamp, frame) || (!visit[:cycles].key?(stamp) && visit[:cycles].size >= VISIT_STAMPS)
    end

    def over_frames?(visit, stamp, frame) = visit[:cycles].key?(stamp) && frame - visit[:cycles][stamp] >= CYCLE_FRAMES

    def pending?(place, entity, stamp, people, visit)
      entry = @npcs[[place, entity[:type], stamp]]
      return false if entry[:rounds] >= ROUND_CAP || @failures[[visit[:id], entity[:type]]] >= FAILURE_CAP
      return true unless @talk_log.status(place:, entity: entity[:type], stamp:) == :exhausted

      people.count { |other| other[:type] == entity[:type] } > 1 && !entry[:slots].include?(entity[:slot])
    end

    def cap(visit, stamp, state)
      return if visit[:capped].include?(stamp)

      visit[:capped] << stamp
      @notes << { kind: 'revisit', detail: { npc: { place: visit[:place], type: visit[:current] }, round: 0, outcome: 'cycle_frame_cap',
                                             frames: state.frame - visit[:cycles][stamp] } }
    end

    def close(outcome)
      @notes << { kind: 'revisit', detail: { npc: @open.slice(:place, :type, :cell), round: @open[:round], outcome: outcome.to_s } }
      @open = nil
    end

    def distance(state, entity)
      from = state.cell
      from ? (from[0] - entity[:cell][0]).abs + (from[1] - entity[:cell][1]).abs : 0
    end
  end
end
