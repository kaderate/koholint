require 'koholint/perception'

module Koholint
  class Revisit
    ROUND_CAP = 6
    CYCLE_FRAMES = 1800
    FAILURE_CAP = 2
    VISIT_STAMPS = 3
    DANGER_PIXELS = 48
    VISIT_ENGAGEMENTS = 4
    VISIT_FRAMES = 900
    SIGN_ROUNDS = 2
    PHASES = %i[playing].freeze

    attr_reader :open

    def initialize(talk_log:, visit_engagements: VISIT_ENGAGEMENTS, visit_frames: VISIT_FRAMES)
      @talk_log = talk_log
      @visit_engagements = visit_engagements
      @visit_frames = visit_frames
      @sign_rounds = Hash.new(0)
      @npcs = Hash.new { |hash, key| hash[key] = { rounds: 0, slots: [] } }
      @failures = Hash.new(0)
      @visit = nil
      @visits = 0
      @open = nil
      @notes = []
    end

    def candidate(state:, entities:, stamp:, signs: [], budget_low: false, danger: false)
      return if budget_low || danger || !PHASES.include?(state.phase(booted: true)) || hurt?(state) || threatened?(state, entities)

      place = [state.room_id, state.map_id]
      visit = visit_for(place)
      cap(visit, stamp, state) if over_frames?(visit, stamp, state.frame)
      return if blocked?(visit, stamp, state.frame)

      people = entities.select { |entity| npc?(entity) }
      pending = people.select { |entity| pending?(place, entity, stamp, people, visit) }
      unread = signs.select { |sign| sign?(sign) && unread?(place, sign, visit) }
      return if pending.empty? && unread.empty?
      return spent(visit, state) if spent?(visit, state.frame)

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

      visit[:cycles][stamp] ||= state.frame
      visit[:started] ||= state.frame
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

    def spent?(visit, frame) = visit[:engaged] >= @visit_engagements || (visit[:started] && frame - visit[:started] >= @visit_frames)

    def spent(visit, state)
      return if visit[:spent]

      visit[:spent] = true
      @notes << { kind: 'revisit', detail: { place: visit[:place], round: 0, outcome: 'visit_cap', engagements: visit[:engaged],
                                             frames: visit[:started] ? state.frame - visit[:started] : 0 } }
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
