require_relative 'test_helper'
require 'koholint/game_state'
require 'koholint/skills/registry'

class AttackTest < Minitest::Test
  class FakeGrid
    def static_sprite(*) = nil
    def passable(*) = :yes
  end

  VECTORS = { up: [0, -1], down: [0, 1], left: [-1, 0], right: [1, 0] }.freeze

  def registry = @registry ||= Koholint::Skills::Registry.default

  def state(x:, y:, hp: 24, sword: 1)
    Koholint::GameState.new(frame: 0, room_id: 1, map_id: 0, x:, y:, hp:, item_a: sword, item_b: 4, dialog_state: 0, game_mode: 0x0B, game_submode: 7, milestone: :sword)
  end

  def enemy(row, col, health: 1, slot: 3, type: 9, contact: 9)
    x, y = Koholint::Geometry.center_of(row, col)
    { slot:, type:, x:, y:, status: 5, health:, cell: [row, col], kind: :enemy, contact: }
  end

  # Link moves 1 px per direction frame; an A press lands a hit when he faces the enemy within 24 px along and 8 px across.
  def fight(target, enemies, from: [4, 2], sword: 1, immune: false, knockback: 0, hurt_at: nil, cap: nil, limit: 1000)
    x, y = Koholint::Geometry.center_of(*from)
    hp = 24
    reader = -> { enemies.map { |e| e.merge(cell: Koholint::Geometry.cell_for(e[:x], e[:y])) } }
    execution = registry.start('attack', state(x:, y:, sword:), { row: target[0], col: target[1] }, { grid: FakeGrid.new, entities: reader })
    execution.__getobj__.define_singleton_method(:hard_cap) { cap } if cap
    facing = nil
    inputs = []
    limit.times do
      hp = 20 if hurt_at && inputs.size >= hurt_at
      buttons = execution.next_input(state(x:, y:, sword:, hp:)) or break
      inputs << buttons
      direction = (buttons & VECTORS.keys).first
      if direction
        facing = direction
        x += VECTORS[direction][0]
        y += VECTORS[direction][1]
      end
      next unless buttons.include?(:a) && !immune

      enemies.each do |e|
        dx = e[:x] - x
        dy = e[:y] - y
        along, cross = %i[left right].include?(facing) ? [dx * VECTORS[facing][0], dy] : [dy * VECTORS[facing][1], dx]
        next unless along.between?(8, 24) && cross.abs <= 8 && e[:status] == 5 && inputs.size - e.fetch(:hit, -99) > 10

        e[:hit] = inputs.size
        e[:health] -= 1
        e[:status] = 1 if e[:health].zero?
        e[:x] += VECTORS[facing][0] * knockback if e[:status] == 5
        e[:y] += VECTORS[facing][1] * knockback if e[:status] == 5
      end
    end
    [execution.result(state(x:, y:, sword:, hp:)), inputs]
  end

  def test_attack_is_a_registry_skill_that_the_shield_wraps
    assert_includes registry.names, 'attack'
    assert_includes Koholint::Skills::Shielded::MOVING, 'attack'
  end

  def test_walks_next_to_the_enemy_faces_it_and_kills_it_with_one_strike
    result, inputs = fight([4, 6], [enemy(4, 6)])
    assert_equal :done, result[:stopped_by]
    assert_equal({ row: 4, col: 5 }, result[:standing_cell])
    assert_equal [true, 1, 1], result.values_at(:killed, :strikes, :hits)
    assert_includes inputs, [:a]
  end

  def test_strikes_again_until_a_two_hit_enemy_dies
    result, = fight([4, 6], [enemy(4, 6, health: 2, type: 198)])
    assert_equal [:done, true, 2, 2], result.values_at(:stopped_by, :killed, :strikes, :hits)
  end

  def test_gives_up_after_the_strike_cap_when_no_hit_lands
    result, = fight([4, 6], [enemy(4, 6)], immune: true)
    assert_equal [:no_kill, false, Koholint::Skills::Attack::MAX_STRIKES, 0], result.values_at(:stopped_by, :killed, :strikes, :hits)
  end

  def test_walks_up_again_when_a_strike_knocks_the_enemy_more_than_two_cells_away
    result, = fight([4, 6], [enemy(4, 6, health: 2, type: 198)], knockback: 40)
    assert_equal [:done, true, 2, 1], result.values_at(:stopped_by, :killed, :hits, :approaches)
  end

  def test_stops_with_target_gone_when_a_strike_knocks_the_enemy_off_the_grid
    result, = fight([4, 6], [enemy(4, 6, health: 2, type: 198)], knockback: 200)
    assert_equal [:target_gone, false, 1], result.values_at(:stopped_by, :killed, :hits)
  end

  def test_stops_when_link_is_hurt
    result, = fight([4, 6], [enemy(4, 6)], hurt_at: 10, immune: true)
    assert_equal [:damage, false], result.values_at(:stopped_by, :killed)
  end

  def test_stops_at_its_frame_cap
    result, inputs = fight([4, 6], [enemy(4, 6)], immune: true, cap: 50)
    assert_equal :frame_cap, result[:stopped_by]
    assert_equal 50, inputs.size
  end

  def test_refuses_without_the_sword_on_a_button
    result, inputs = fight([4, 6], [enemy(4, 6)], sword: 0)
    assert_equal :refused, result[:stopped_by]
    assert_match(/sword/, result[:cause])
    assert_empty inputs
  end

  def test_stops_with_no_target_when_no_enemy_is_at_or_next_to_the_cell
    result, = fight([1, 1], [enemy(4, 6)])
    assert_equal :no_target, result[:stopped_by]
  end

  def test_strikes_an_unidentified_thing_the_way_it_strikes_an_enemy
    unknown = enemy(4, 6, health: 2, type: 11).merge(kind: :unknown).except(:contact)
    result, = fight([4, 6], [unknown])
    assert_equal [:done, true, 2], result.values_at(:stopped_by, :killed, :hits)
    assert_equal 11, result[:target][:type]
  end

  def test_prefers_an_enemy_over_an_unidentified_thing_and_never_targets_a_person
    unknown = enemy(4, 6, slot: 1, type: 12).merge(kind: :unknown)
    result, = fight([4, 6], [unknown, enemy(4, 6, slot: 2)])
    assert_equal 2, result[:target][:slot]
    person, = fight([4, 6], [enemy(4, 6, type: 62).merge(kind: :npc)])
    assert_equal :no_target, person[:stopped_by]
  end

  def test_strikes_a_creature_but_never_a_thing_of_another_kind
    creature, = fight([4, 6], [enemy(4, 6, type: 45).merge(kind: :creature)])
    assert_equal [:done, true], creature.values_at(:stopped_by, :killed)
    object, = fight([4, 6], [enemy(4, 6, type: 99).merge(kind: :object)])
    assert_equal :no_target, object[:stopped_by]
  end

  def test_backs_off_when_closer_than_the_enemy_contact_before_striking
    near = enemy(4, 6)
    near[:x] -= 6
    result, inputs = fight([4, 6], [near], from: [4, 5])
    assert result[:killed]
    first_a = inputs.index([:a])
    assert(inputs.first(first_a).any? { |buttons| buttons.include?(:left) })
  end

  def test_prefers_a_standing_cell_outside_another_enemy_s_reach
    other = enemy(2, 6, slot: 4)
    result, = fight([4, 6], [enemy(4, 6), other], from: [3, 2])
    refute_equal({ row: 3, col: 6 }, result[:standing_cell])
  end
end
