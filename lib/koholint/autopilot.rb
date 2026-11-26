require 'set'
require 'koholint/decision'
require 'koholint/entities'
require 'koholint/navigation/threat'
require 'koholint/perception'

module Koholint
  class Autopilot
    CHAIN_LIMIT = 6
    CHAIN_FRAMES = 2400
    BENIGN = %w[new_place known_place budget untried_object tried pushed enemy].freeze
    ARRIVED = %w[new_place known_place].freeze
    TALKED = 'talked'.freeze
    FOUGHT = 'fought'.freeze
    HARMLESS = %w[done target_gone hole out_of_reach].freeze
    TALK_ENDS = %w[done no_response].freeze
    DOOR_STEP = { skill: 'walk', params: { direction: 'up', cells: 2 } }.freeze
    RETURNS = 3
    EXPLORING = %w[new_place leave_place new_text].freeze
    CHOICE = { skill: 'explore', params: {} }.freeze
    FIGHT_LIMIT = 8
    REFIGHTS = 2
    TRY_LIMIT = 6
    NOTHING = %w[no_response no_path frame_cap blocked target_free].freeze
    FIGHT_FRAMES = 900
    FIGHT_REACH = 2
    FIGHT_FLOOR = 16
    FIGHT_DROP = 8
    FIGHT_ON = %w[done target_gone].freeze
    FIGHT_SIGHT = 2 * Geometry::CELL
    MISSED = %w[blocked no_path out_of_reach no_kill hole].freeze
    DISENGAGE_LIMIT = 3
    HEART_LIMIT = 2
    HEART_ENDS = %w[done target_gone].freeze
    STEP = { up: [0, -1], down: [0, 1], left: [-1, 0], right: [1, 0] }.freeze
    PROBE_SKILLS = %w[explore goto walk attack].freeze
    PROBE_STOPS = %w[enemy blocked no_path no_frontier out_of_reach].freeze
    PROBE_LIMIT = 6

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
      @missed = { place: nil, slots: [], far: Hash.new(0) }
      @walled = { spot: nil, directions: [] }
      @untried = []
      @trying = false
      @aimed = Set.new
      @tries = 0
      @try_place = nil
      @trial = nil
      @touchable = []
      @probes = 0
      @probed = { place: nil, slots: [] }
      @held = nil
      @hostile = Set.new
      @seen_health = nil
      @offspring = { place: nil }
    end

    def model_called(state:, objective:, news: false)
      @chain = 0
      @since = state.frame
      @hp = state.health
      @objective = objective&.dig(:id)
      @news = news
      @stop = nil
      @acted = false
      @last_skill = nil
      @returns = Hash.new(0)
      @fight = 0
      @attack_stop = nil
      @disengaged = 0
      @untried = []
      @tries = 0
      @goto_done = false
    end

    def adopt(objective) = @objective = objective&.dig(:id)

    def acted(skill:, outcome:)
      @acted = true
      @last_skill = skill.to_s unless %w[wait advance_dialogue].include?(skill.to_s)
      @attack_stop = skill.to_s == 'attack' && outcome.is_a?(Hash) && !@sighted ? outcome[:stopped_by].to_s : nil unless skill.to_s == 'wait'
      @sighted = false unless skill.to_s == 'wait'
      note_hurt(outcome) if skill.to_s == 'attack' && outcome.is_a?(Hash) && outcome[:stopped_by].to_s == 'damage' && outcome[:from].is_a?(Hash)
      note_missed(outcome) if skill.to_s == 'attack' && outcome.is_a?(Hash)
      note_struck(skill, outcome) if outcome.is_a?(Hash)
      note_probe(skill, outcome) if outcome.is_a?(Hash)
      note_walled(outcome) if skill.to_s == 'walk' && outcome.is_a?(Hash) && outcome[:params].is_a?(Hash) && walled?(outcome)
      explored = skill.to_s == 'explore' && outcome.is_a?(Hash)
      @stop = stop_after(skill.to_s, outcome.is_a?(Hash) ? outcome[:stopped_by].to_s : nil) unless @heart_touch && skill.to_s == 'touch' && outcome.is_a?(Hash) && HEART_ENDS.include?(outcome[:stopped_by].to_s)
      @heart_touch = false
      trial = @trying && @trial
      @trial = nil
      if trial && skill.to_s == 'talk_to' && outcome.is_a?(Hash) && NOTHING.include?(outcome[:stopped_by].to_s)
        @touchable << trial.merge(type: trial[:type] || outcome[:target_type])
      end
      @trying = false
      @untried = Array(outcome[:untried_objects]).map { |cell| [cell[:row], cell[:col]] } if explored
      @goto_done = skill.to_s == 'goto' ? outcome.is_a?(Hash) && outcome[:stopped_by].to_s == 'done' : skill.to_s == 'wait' && @goto_done
      to = outcome[:to] if @stop == 'known_place'
      @returns[[to[:room], to[:map]]] += 1 if to.is_a?(Hash) && @returns
    end

    def hold_reason(state:, objective:, follow: nil, danger: false, caps: true)
      return 'no model call yet' unless @since

      target = objective&.dig(:target)
      # A heal objective is survival first: no stop and no hp loss hands it back to the model.
      heal = target&.dig(:heal_below)
      fresh = follow && follow[:skill] != 'explore' && follow[:skill] != @last_skill
      first = follow && target && (!@acted || fresh)
      return "last stop #{@stop || 'not an explore'}" unless heal || first || BENIGN.include?(@stop) || @stop == TALKED || (@stop == FOUGHT && target)
      return 'target followed' if target && @acted && follow && follow[:skill] != 'explore' && !fresh

      common = common_hold(state, news: !target || @stop == TALKED, health: !heal && (!fresh || @stop == FOUGHT))
      return common if common
      return 'objective changed' unless objective && objective[:id] == @objective

      kind = objective.dig(:predicate, :kind).to_s
      return "objective #{kind}" unless EXPLORING.include?(kind) || target
      return 'no way to follow the target' if target && !follow && !ARRIVED.include?(@stop) && @stop != TALKED

      cap_hold(state) if caps
    end

    # A thing on screen never tried is tried once with talk_to before exploring on, nearest first: the sprites the last explore offered where no catalogued enemy stands,
    # and uncatalogued entities of a type never aimed at here. Tries cost no call, so TRY_LIMIT per visit bounds them, not the chain caps.
    def try_choice(state:, objective:, entities:, tried:)
      return unless state.cell && !objective&.dig(:target) && !hold_reason(state:, objective:, caps: false)

      here = state.place
      visit(here)
      return if @tries >= TRY_LIMIT

      struck = @struck[:place] == here ? @struck[:types] : []
      enemies = Array(entities).select { |entity| entity[:kind].to_s == 'enemy' }.map { |entity| entity[:cell] }
      things = (@untried - enemies).map { |cell| [cell, nil] } +
               Array(entities).select { |entity| entity[:kind].to_s == 'unknown' && entity[:cell] && !struck.include?(entity[:type]) && !tried.(entity[:type]) && !@aimed.include?([here, entity[:type]]) }
                              .map { |entity| [entity[:cell], entity[:type]] }
      row, col = state.cell
      nearest = things.min_by { |(r, c), _| [(r - row).abs + (c - col).abs, r, c] } or return
      cell, type = nearest
      @untried.delete(cell)
      @aimed << [here, type] if type
      @trial = { place: here, type:, cell: [cell[0], cell[1]] }
      @trying = true
      @tries += 1
      what = type ? "entity type #{type}" : 'object'
      DecisionPoint.harness_choice({ skill: 'talk_to', params: { row: cell[0], col: cell[1] } }, "autopilot: try the never-tried #{what} at (#{cell.join(',')})", autopilot: true)
    end

    # A still uncatalogued entity whose try gave nothing is walked onto once per visit, nearest first: touch reads the item bytes to tell a pickup.
    # Still means it is still in the cell the try aimed at and not catalogued as moving; tries and touches share TRY_LIMIT.
    def touch_choice(state:, objective:, entities:)
      return unless state.cell && !objective&.dig(:target) && !hold_reason(state:, objective:, caps: false)

      here = state.place
      visit(here)
      return if @tries >= TRY_LIMIT

      struck = @struck[:place] == here ? @struck[:types] : []
      row, col = state.cell
      still = @touchable.reject { |trial| trial[:type].nil? || struck.include?(trial[:type]) }.filter_map do |trial|
        entity = Array(entities).find { |each| each[:kind].to_s == 'unknown' && each[:type] == trial[:type] && each[:cell] == trial[:cell] && each[:moves] != true }
        [trial, entity[:cell]] if entity
      end
      trial, cell = still.min_by { |_, (r, c)| [(r - row).abs + (c - col).abs, r, c] } || (return nil)
      @touchable.delete(trial)
      @trying = true
      @tries += 1
      DecisionPoint.harness_choice({ skill: 'touch', params: { row: cell[0], col: cell[1], type: trial[:type] } },
                                   "autopilot: walk onto the still entity type #{trial[:type]} at (#{cell.join(',')}), whose try gave nothing", autopilot: true)
    end

    def next_choice(state:, objective:, follow: nil, danger: false)
      return if hold_reason(state:, objective:, follow:, danger:)

      @chain += 1 unless @stop == 'known_place'
      @stop = nil
      what = follow ? "follow the objective target with #{follow[:skill]}" : 'explore again'
      DecisionPoint.harness_choice(follow || CHOICE, "autopilot: #{what} (#{@chain}/#{@chain_limit})", autopilot: true)
    end

    # After an attack that killed or lost its target, strike the nearest other enemy (or a type struck here before) without a call.
    def fight_choice(state:, entities:, objects: [], safe: true)
      sighted = fight_target(state:, entities:, objects:, safe:)
      if sighted
        @fight += 1
        @attack_stop = nil
        @sighted = true
        return DecisionPoint.harness_choice({ skill: 'attack', params: { row: sighted[:cell][0], col: sighted[:cell][1] } },
                                            "autopilot: fight type #{sighted[:type]} at (#{sighted[:cell].join(',')}), #{sighted[:sword_hits] ? "a #{sighted[:sword_hits]}-strike kill" : 'not identified, taken for an enemy'} (#{@fight}/#{FIGHT_LIMIT})", autopilot: true)
      end
      return unless @since && FIGHT_ON.include?(@attack_stop) && state.phase == :playing && state.cell
      return if state.health < FIGHT_FLOOR || state.health < @hp - FIGHT_DROP
      return if @fight >= FIGHT_LIMIT || state.frame - @since >= FIGHT_FRAMES

      here = @struck[:place] == state.place
      struck = here ? @struck[:types] : []
      row, col = state.cell
      target = Array(entities).select { |entity| entity[:cell] && !(here && entity[:slot] == @struck[:slot]) }
                              .select { |entity| entity[:kind].to_s == 'enemy' || (entity[:kind].to_s == 'unknown' && struck.include?(entity[:type])) }
                              .select { |entity| [(entity[:cell][0] - row).abs, (entity[:cell][1] - col).abs].max <= FIGHT_REACH }
                              .min_by { |entity| [(entity[:cell][0] - row).abs + (entity[:cell][1] - col).abs, entity[:slot]] } or return
      @fight += 1
      @attack_stop = nil
      DecisionPoint.harness_choice({ skill: 'attack', params: { row: target[:cell][0], col: target[:cell][1] } }, "autopilot: keep fighting, type #{target[:type]} at (#{target[:cell].join(',')}) (#{@fight}/#{FIGHT_LIMIT})", autopilot: true)
    end

    # Crumbling floor gives way under a Link who stands to strike, so no fight starts with his footprint on it.
    def fight_target(state:, entities:, objects: [], safe: true)
      return unless @since && state.phase == :playing && state.cell && state.x

      @fight_hurt = nil if @fight_hurt && @fight_hurt[:place] != state.place
      return if state.health <= Perception::HP_PER_HEART || @fight >= FIGHT_LIMIT
      return if @fight_hurt && (@fight_hurt[:count] > 1 || !state.max_hp || state.health * 2 <= state.max_hp)
      return if Array(objects).any? { |object| object[:kind].to_s == 'crumbling' && Geometry.footprint_cells(state.x, state.y).include?(object[:cell]) }

      here = @missed[:place] == state.place
      missed = here ? @missed[:slots] : []
      missed += [@struck[:slot]] if @struck[:place] == state.place
      distance = ->(entity) { [(entity[:x] - state.x).abs, (entity[:y] - state.y).abs].max }
      far = ->(entity) { here && @missed[:far].key?(entity[:slot]) && distance.(entity) > Geometry::CELL }
      offspring = offspring_slots(state, entities)
      strikable = ->(entity) { entity[:kind].to_s == 'enemy' ? entity[:sword_hits] == 1 || (entity[:sword_hits] == 2 && entity[:sword_verified]) : safe && offspring.include?(entity[:slot]) }
      Array(entities).select { |entity| strikable.(entity) && (!@fight_hurt || entity[:sword_verified]) && entity[:cell] && entity[:x] && !missed.include?(entity[:slot]) && !far.(entity) }
                     .select { |entity| distance.(entity) <= FIGHT_SIGHT }
                     .min_by { |entity| [distance.(entity), entity[:slot]] }
    end

    # Health lost with a creature catalogued as moving within a cell of Link is the evidence that its type may hurt, for the session.
    def note_contact(state:, entities:)
      lost = @seen_health && state.health && state.health < @seen_health
      @seen_health = state.health
      return unless lost && state.cell

      row, col = state.cell
      @hostile |= Array(entities).select { |entity| Entities.creature?(entity) && entity[:moves] == true && entity[:cell] }
                                 .select { |entity| [(entity[:cell][0] - row).abs, (entity[:cell][1] - col).abs].max <= 1 }.map { |entity| entity[:type] }
    end

    # A creature not identified whose type hurt Link with it in touch, standing in touch when a walk or a strike stopped short, gets one sword strike
    # (the attack's strikes capped at 1 through the context): once per slot per visit and PROBE_LIMIT times per session, never at one heart, where the
    # measured hit says no (safe) or with a person on screen.
    def probe_choice(state:, entities:, safe:)
      return unless safe && @since && @held && state.phase == :playing && state.cell && state.health > Perception::HP_PER_HEART && @probes < PROBE_LIMIT
      return if Array(entities).any? { |entity| entity[:kind].to_s == 'npc' }

      @probed = { place: state.place, slots: [] } unless @probed[:place] == state.place
      row, col = state.cell
      target = Array(entities).select { |entity| Entities.creature?(entity) && @hostile.include?(entity[:type]) && entity[:cell] && !@probed[:slots].include?(entity[:slot]) }
                              .select { |entity| [(entity[:cell][0] - row).abs, (entity[:cell][1] - col).abs].max <= 1 }
                              .min_by { |entity| [(entity[:cell][0] - row).abs + (entity[:cell][1] - col).abs, entity[:slot]] } or return
      stop = @held
      @held = nil
      @probes += 1
      @probed[:slots] << target[:slot]
      DecisionPoint.harness_choice({ skill: 'attack', params: { row: target[:cell][0], col: target[:cell][1] } },
                                   "autopilot: strike the unidentified type #{target[:type]} at (#{target[:cell].join(',')}) once, in touch after a #{stop} stop (probe #{@probes}/#{PROBE_LIMIT})", autopilot: true).merge(strikes: 1)
    end

    # At one heart or less with an enemy within a cell of its touch, step away from every such enemy before the model decides.
    def disengage_choice(state:, entities:, grid: nil)
      return unless @since && state.phase == :playing && state.x && state.cell && state.health <= Perception::HP_PER_HEART && @disengaged < DISENGAGE_LIMIT

      near = Navigation::Threat.of(Array(entities)).select { |threat| Navigation::Threat.distance(threat, state.x, state.y) <= threat[:reach] + Geometry::CELL }
      return if near.empty?

      holes = grid.respond_to?(:hole_margin) ? grid.hole_margin + Geometry::ROWS.times.to_a.product(Geometry::COLS.times.to_a).select { |cell| grid.hole?(*cell) } : []
      zone = Navigation::Threat.zone(Navigation::Threat.of(Array(entities)) - near, margin: Entities::DANGER_MARGIN)
      beside = zone.flat_map { |row, col| [[row, col], [row - 1, col], [row + 1, col], [row, col - 1], [row, col + 1]] }
      farther = ->(dx, dy) { near.all? { |threat| Navigation::Threat.distance(threat, state.x + (dx * Geometry::CELL), state.y + (dy * Geometry::CELL)) > Navigation::Threat.distance(threat, state.x, state.y) } }
      walled = @walled[:spot] == [*state.place, *state.cell] ? @walled[:directions] : []
      wall = lambda do |name|
        ahead = Geometry.step(state.cell, name)
        walled.include?(name.to_s) || (ahead && grid.respond_to?(:passable) && grid.passable(*ahead, name) == :no)
      end
      direction = STEP.reject { |name, (dx, dy)| wall.(name) || (holes + beside).include?([state.cell[0] + dy, state.cell[1] + dx]) || !farther.(dx, dy) }
                      .max_by { |_, (dx, dy)| near.map { |threat| Navigation::Threat.distance(threat, state.x + (dx * Geometry::CELL), state.y + (dy * Geometry::CELL)) }.min }
                      &.first or return
      @disengaged += 1
      DecisionPoint.harness_choice({ skill: 'walk', params: { direction: direction.to_s, cells: 1 } }, "autopilot: disengage at #{state.health} hp, step #{direction} away from #{near.map { |threat| threat[:type] }.join(', ')} (#{@disengaged}/#{DISENGAGE_LIMIT})", autopilot: true)
    end

    # Below full health, the nearest heart on screen outside every contact zone is walked to before any fight; the walk routes around the zones.
    # A heart counts only when visible, a still sprite on known floor, since one hidden under a pot or a bush has no sprite; touch walks beside it, never across a contact zone, and holds into it.
    # Each slot is aimed at once per visit and HEART_LIMIT bounds a visit, so a heart goto cannot reach is not chased.
    def heart_choice(state:, entities:, grid: nil)
      @hearts = { place: state.place, slots: [] } unless @hearts&.dig(:place) == state.place
      return unless @since && state.phase == :playing && state.cell && state.max_hp && state.health < state.max_hp

      return if @hearts[:slots].size >= HEART_LIMIT

      danger = Entities.danger_cells(Array(entities), margin: Entities::DANGER_MARGIN + (state.health <= Perception::HP_PER_HEART ? Geometry::CELL : 0))
      row, col = state.cell
      heart = Array(entities).select { |entity| entity[:heals] && entity[:cell] && grid&.static_sprite(*entity[:cell]) && grid.floor?(*entity[:cell]) && !danger.include?(entity[:cell]) && !@hearts[:slots].include?(entity[:slot]) }
                             .min_by { |entity| [(entity[:cell][0] - row).abs + (entity[:cell][1] - col).abs, entity[:slot]] } or return
      @hearts[:slots] << heart[:slot]
      @heart_touch = true
      DecisionPoint.harness_choice({ skill: 'touch', params: { row: heart[:cell][0], col: heart[:cell][1], type: heart[:type], safe: true, slot: heart[:slot] } },
                                   "autopilot: pick up the heart at (#{heart[:cell].join(',')}) at #{state.health}/#{state.max_hp} hp (#{@hearts[:slots].size}/#{HEART_LIMIT})", autopilot: true)
    end

    # After a goto that ended on the cell right below a door, step through the door without a call.
    def door_choice(state:, doors:)
      return unless @since && @goto_done && state.cell && !common_hold(state)

      row, col = state.cell
      return unless Array(doors).include?([row - 1, col])

      @goto_done = false
      DecisionPoint.harness_choice(DOOR_STEP, "autopilot: step up through the door at (#{row - 1},#{col}) the goto ended below", autopilot: true)
    end

    def objective_hold(state:, last:)
      return 'no model call yet' unless @since
      return "last stop #{@stop || 'not an explore'}" unless ARRIVED.include?(@stop)
      return 'last objective not achieved by the chain' unless last && last[:outcome].to_s == 'achieved' && last[:id] == @objective

      common_hold(state) || cap_hold(state)
    end

    private

    def visit(here)
      return if @try_place == here

      @tries = 0
      @touchable = []
      @try_place = here
    end

    # health: false for a step at the target itself (its talk or touch), which only the harness can make once the model handed it the target.
    def common_hold(state, news: true, health: true)
      return 'new lead or goal' if news && @news
      return 'explore loop' if @returns.values.max.to_i >= RETURNS
      return "phase #{state.phase}" unless state.phase == :playing
      return 'hp dropped' if health && state.health < @hp
      return 'low health' if health && state.health <= Perception::HP_PER_HEART

      nil
    end

    # An enemy an attack could not reach or strike is not fought on sight again in that place, save one only out of reach, once in touch.
    def note_missed(outcome)
      from = outcome[:from]
      return unless from.is_a?(Hash) && outcome[:target].is_a?(Hash) && MISSED.include?(outcome[:stopped_by].to_s)

      here = [from[:room], from[:map]]
      slot = outcome[:target][:slot]
      @missed = { place: here, slots: [], far: Hash.new(0) } unless @missed[:place] == here
      @missed[:far][slot] += 1 if outcome[:stopped_by].to_s == 'out_of_reach'
      @missed[:slots] |= [slot] if outcome[:stopped_by].to_s != 'out_of_reach' || @missed[:far][slot] > REFIGHTS
    end

    # Above half health a first damage in a place leaves fights with verified enemies on; a second one, or half health, ends them for the visit.
    def note_hurt(outcome)
      here = [outcome[:from][:room], outcome[:from][:map]]
      @fight_hurt = { place: here, count: @fight_hurt&.dig(:place) == here ? @fight_hurt[:count] + 1 : 1 }
    end

    # The types struck count for the visit only: leaving the place forgets them, as a resume (which starts with none) would.
    def note_struck(skill, outcome)
      from = outcome[:from]
      target = outcome[:target]
      if skill.to_s == 'attack' && target.is_a?(Hash) && from.is_a?(Hash)
        here = [from[:room], from[:map]]
        @struck = { place: here, types: [] } unless @struck[:place] == here
        @struck[:types] |= [target[:type]]
        @struck[:slot] = target[:slot] unless MISSED.include?(outcome[:stopped_by].to_s) || outcome[:stopped_by].to_s == 'damage'
      end
      to = outcome[:to]
      @struck = { place: nil, types: [] } if to.is_a?(Hash) && @struck[:place] && [to[:room], to[:map]] != @struck[:place]
    end

    # A walk or strike that stopped short arms the probe until the next skill. A hit that left an enemy's slot to something else marks that spot:
    # what appears there is fought as an enemy until struck once.
    def note_probe(skill, outcome)
      skill = skill.to_s
      stop = outcome[:stopped_by].to_s
      return if %w[wait advance_dialogue].include?(skill)

      @held = PROBE_SKILLS.include?(skill) && PROBE_STOPS.include?(stop) ? stop : nil
      from = outcome[:from]
      to = outcome[:to]
      target = outcome[:target]
      @offspring = { place: nil } if to.is_a?(Hash) && [to[:room], to[:map]] != @offspring[:place]
      return unless skill == 'attack' && target.is_a?(Hash) && from.is_a?(Hash)

      enemy = Entities.catalogue.dig(target[:type], :kind).to_s == 'enemy'
      @offspring[:slots] -= [target[:slot]] if @offspring[:slots]
      @offspring = { place: [from[:room], from[:map]], slot: target[:slot], type: target[:type], cell: target[:cell] } if stop == 'target_gone' && enemy
    end

    # Taken once, at the first look after the hit: creatures catalogued as moving in the struck slot under another type or on the cell where it stood.
    def offspring_slots(state, entities)
      return [] unless @offspring[:place] == state.place

      unless @offspring[:slots]
        @offspring[:slots] = Array(entities).select { |entity| Entities.creature?(entity) && entity[:moves] == true && entity[:type] != @offspring[:type] && (entity[:slot] == @offspring[:slot] || entity[:cell] == @offspring[:cell]) }
                                            .map { |entity| entity[:slot] }
      end
      @offspring[:slots]
    end

    # A try stays benign whatever it met, through the dialogue it opened; only a talk the model chose ends as talked.
    def stop_after(skill, stop)
      return stop if skill == 'explore'
      return 'tried' if @trying || (%w[advance_dialogue wait].include?(skill) && @stop == 'tried')
      return TALKED if (skill == 'talk_to' && TALK_ENDS.include?(stop)) || (%w[advance_dialogue wait].include?(skill) && @stop == TALKED)
      # A fight that did not hurt Link leaves an objective's target to follow; only damage hands the choice back.
      return FOUGHT if (skill == 'attack' && HARMLESS.include?(stop)) || (%w[advance_dialogue wait].include?(skill) && @stop == FOUGHT)

      nil
    end

    # A walk blocked from a cell stays blocked from it, across model calls, until Link stands somewhere else.
    def note_walled(outcome)
      from = outcome[:from]
      return unless from.is_a?(Hash)

      at = outcome[:blocked_at].is_a?(Hash) ? outcome[:blocked_at] : from
      spot = [from[:room], from[:map], at[:row], at[:col]]
      @walled = { spot:, directions: [] } unless @walled[:spot] == spot
      @walled[:directions] |= [outcome[:params][:direction].to_s]
    end

    def walled?(outcome) = outcome[:stopped_by].to_s == 'blocked'

    def cap_hold(state)
      return 'chain cap' if @chain >= @chain_limit
      return 'frame cap' if state.frame - @since >= @chain_frames

      nil
    end
  end
end
