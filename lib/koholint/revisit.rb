require 'koholint/perception'

module Koholint
  class Revisit
    ROUND_CAP = 6
    CYCLE_FRAMES = 1800
    FAILURE_CAP = 2
    VISIT_STAMPS = 3
    DANGER_PIXELS = 48
    VISIT_FRAMES = 2700
    SIGN_ROUNDS = 2
    PHASES = %i[playing].freeze

    attr_reader :open

    def initialize(talk_log:, visit_frames: VISIT_FRAMES)
      @talk_log = talk_log
      @visit_frames = visit_frames
      @clock = 0
      @seen = nil
      @sign_rounds = Hash.new(0)
      @npcs = Hash.new { |hash, key| hash[key] = { rounds: 0, slots: [] } }
      @failures = Hash.new(0)
      @visit = nil
      @visits = 0
      @open = nil
      @notes = []
    end

    def observe(state)
      frame = state.frame.to_i
      @clock += frame - @seen[0] if @seen && @seen[1] == :playing && frame > @seen[0]
      @seen = [frame, state.phase(booted: true)]
    end

    def candidate(state:, entities:, stamp:, signs: [], budget_low: false, danger: false)
      observe(state)
      return if budget_low || danger || !PHASES.include?(state.phase(booted: true)) || hurt?(state) || threatened?(state, entities)

      place = [state.room_id, state.map_id]
      visit = visit_for(place)
      cap(visit, stamp) if over_frames?(visit, stamp)
      return if blocked?(visit, stamp)

      people = entities.select { |entity| npc?(entity) }
      pending = people.select { |entity| pending?(place, entity, stamp, people, visit) }
      unread = signs.select { |sign| sign?(sign) && unread?(place, sign, visit) }
      return if pending.empty? && unread.empty?
      return spent(visit) if spent?(visit)

      current = unread.find { |sign| [:sign, sign[:cell]] == visit[:current] }
      return current if current

      tried = @npcs[[place, visit[:current], stamp]][:slots] if visit[:current]
      same = pending.select { |entity| entity[:type] == visit[:current] }
      (same.reject { |entity| tried.include?(entity[:slot]) }.first || same.first) ||
        (pending + unread).min_by { |target| [distance(state, target), target[:slot] || -1, target[:cell]] }
    end

    def next_action(state:, entities:, stamp:, signs: [], budget_low: false, danger: false)
      close(:no_text) if @open
      place = [state.room_id, state.map_id]
      visit = visit_for(place)
      target = candidate(state:, entities:, stamp:, signs:, budget_low:, danger:) or return

      visit[:cycles][stamp] ||= @clock
      visit[:started] ||= @clock
      visit[:engaged] += 1
      return engage_sign(place, visit, target, stamp) if sign?(target)

      visit[:current] = target[:type]
      entry = @npcs[[place, target[:type], stamp]]
      entry[:rounds] += 1
      entry[:slots] |= [target[:slot]]
      @open = { place:, type: target[:type], cell: target[:cell], round: entry[:rounds], stamp:, visit: visit[:id] }
      { skill: 'talk_to', params: { row: target[:cell][0], col: target[:cell][1] }, npc: @open.slice(:place, :type, :cell), round: entry[:rounds] }
    end

    def talked(outcome)
      return unless @open
      return if outcome[:talked] == true || outcome['talked'] == true

      key = [@open[:visit], @open[:sign] ? [:sign, @open[:cell]] : @open[:type]]
      @failures[key] += 1
      close(@failures[key] >= FAILURE_CAP ? :unreachable : :no_dialogue)
    end

    def read
      return unless @open
      return close(@talk_log.sign_read?(place: @open[:place], cell: @open[:cell]) ? :read : :no_text) if @open[:sign]

      close(@talk_log.last_status(place: @open[:place], entity: @open[:type]))
    end

    def notes
      out = @notes
      @notes = []
      out
    end

    private

    def npc?(entity) = entity[:kind].to_s == 'npc' && entity[:verified] == true && entity[:cell]

    def sign?(object) = object[:kind].to_s == 'sign' && object[:verified] == true && object[:cell]

    def unread?(place, sign, visit)
      @sign_rounds[[place, sign[:cell]]] < SIGN_ROUNDS && @failures[[visit[:id], [:sign, sign[:cell]]]] < FAILURE_CAP &&
        !@talk_log.sign_read?(place:, cell: sign[:cell])
    end

    def engage_sign(place, visit, sign, stamp)
      visit[:current] = [:sign, sign[:cell]]
      round = @sign_rounds[[place, sign[:cell]]] += 1
      @open = { place:, sign: true, cell: sign[:cell], round:, stamp:, visit: visit[:id] }
      { skill: 'talk_to', params: { row: sign[:cell][0], col: sign[:cell][1] }, sign: { place:, cell: sign[:cell] }, round: }
    end

    def spent?(visit) = visit[:started] && @clock - visit[:started] >= @visit_frames

    def spent(visit)
      return if visit[:spent]

      visit[:spent] = true
      @notes << { kind: 'revisit', detail: { place: visit[:place], round: 0, outcome: 'visit_cap', engagements: visit[:engaged], frames: @clock - visit[:started] } }
      nil
    end

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
      @visit = { place:, id: @visits, cycles: {}, capped: [], current: nil, engaged: 0, started: nil, spent: false }
    end

    def blocked?(visit, stamp)
      visit[:capped].include?(stamp) || over_frames?(visit, stamp) || (!visit[:cycles].key?(stamp) && visit[:cycles].size >= VISIT_STAMPS)
    end

    def over_frames?(visit, stamp) = visit[:cycles].key?(stamp) && @clock - visit[:cycles][stamp] >= CYCLE_FRAMES

    def pending?(place, entity, stamp, people, visit)
      entry = @npcs[[place, entity[:type], stamp]]
      return false if entry[:rounds] >= ROUND_CAP || @failures[[visit[:id], entity[:type]]] >= FAILURE_CAP
      return true unless @talk_log.status(place:, entity: entity[:type], stamp:) == :exhausted

      people.count { |other| other[:type] == entity[:type] } > 1 && !entry[:slots].include?(entity[:slot])
    end

    def cap(visit, stamp)
      return if visit[:capped].include?(stamp)

      visit[:capped] << stamp
      @notes << { kind: 'revisit', detail: { npc: { place: visit[:place], type: visit[:current] }, round: 0, outcome: 'cycle_frame_cap',
                                             frames: @clock - visit[:cycles][stamp] } }
    end

    def close(outcome)
      who = @open[:sign] ? { sign: @open.slice(:place, :cell) } : { npc: @open.slice(:place, :type, :cell) }
      @notes << { kind: 'revisit', detail: { **who, round: @open[:round], outcome: outcome.to_s } }
      @open = nil
    end

    def distance(state, entity)
      from = state.cell
      from ? (from[0] - entity[:cell][0]).abs + (from[1] - entity[:cell][1]).abs : 0
    end
  end
end
