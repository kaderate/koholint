require_relative 'test_helper'
require 'support/emulator_cache'
require 'koholint/game_state'
require 'koholint/perception'
require 'koholint/skills/registry'

class UseItemTest < Minitest::Test
  SHIELD_RUN = File.expand_path('../runs/20261020-085011-8330', __dir__)
  OUTDOORS_FRAME = 3908

  def registry = @registry ||= Koholint::Skills::Registry.default

  def state(**fields)
    Koholint::GameState.new(frame: 0, room_id: 1, map_id: 0, x: 88, y: 80, hp: 24, milestone: :shield, game_mode: 0x0B, game_submode: 7,
                            dialog_state: 0, inventory_cursor: 0, menu_option: 0, item_a: 0, item_b: 0, inventory: Array.new(10, 0),
                            shield_raised: 0, **fields)
  end

  # A model of the START menu and the shield: A/B in the menu swap the slot under the cursor with that button.
  class Game
    attr_reader :state

    def initialize(state)
      @state = state
      @previous = []
    end

    def feed(buttons)
      edge = buttons - @previous
      @previous = buttons
      s = @state.dup
      s.inventory = s.inventory.dup
      edge.each { |button| press(s, button) }
      s.shield_raised = s.game_mode == 11 && [[:a, s.item_a], [:b, s.item_b]].any? { |button, id| id == 4 && buttons.include?(button) } ? 1 : 0
      s.frame += 1
      @state = s
    end

    def press(s, button)
      case [s.game_mode, button]
      in [11, :start] then s.game_mode, s.game_submode = 12, 8
      in [12, :start] then s.game_mode, s.game_submode = 11, 7
      in [12, :right | :left | :down | :up] then s.inventory_cursor = (s.inventory_cursor + { right: 1, left: -1, down: 2, up: -2 }[button]) % 10
      in [12, :a] then s.item_a, s.inventory[s.inventory_cursor] = s.inventory[s.inventory_cursor], s.item_a
      in [12, :b] then s.item_b, s.inventory[s.inventory_cursor] = s.inventory[s.inventory_cursor], s.item_b
      else nil
      end
    end
  end

  def drive(name, params, start)
    game = Game.new(start)
    execution = registry.start(name, start, params)
    inputs = []
    while (buttons = execution.next_input(game.state))
      inputs << buttons
      game.feed(buttons)
    end
    [execution.result(game.state), game.state, inputs]
  end

  def test_use_item_presses_the_button_the_item_is_on
    result, after, inputs = drive('use_item', { item: 'shield' }, state(item_b: 4))
    assert_equal :done, result[:stopped_by]
    assert_equal :b, result[:button]
    refute result[:equipped]
    assert_equal 8, inputs.count([:b])
    assert_equal 11, after.game_mode
  end

  def test_use_item_assigns_an_item_from_its_slot_first
    start = state(item_b: 2, inventory: [0, 0, 0, 4, 0, 0, 0, 0, 0, 0])
    result, after, = drive('use_item', { item: 4, button: 'a' }, start)
    assert_equal :done, result[:stopped_by]
    assert result[:equipped]
    assert_equal [4, 2], [after.item_a, after.item_b]
    assert_equal 0, after.inventory[3]
    assert_equal :playing, after.phase(booted: true)
  end

  def test_use_item_refuses_an_item_not_held_and_screens
    result, = drive('use_item', { item: 'bombs' }, state(item_b: 4))
    assert_equal :refused, result[:stopped_by]
    assert_match(/not held/, result[:cause])
    assert_equal :wrong_mode, drive('use_item', { item: 'shield' }, state(item_b: 4, dialog_state: 2)).first[:stopped_by]
    assert_raises(ArgumentError) { registry.validate('use_item', { item: '' }) }
    assert_raises(ArgumentError) { registry.validate('use_item', { item: 'shield', button: 'start' }) }
  end

  def test_guard_holds_the_shield_and_counts_the_raised_frames
    result, _, inputs = drive('guard', { frames: 20 }, state(item_a: 4))
    assert_equal :done, result[:stopped_by]
    assert_equal 20, result[:raised_frames]
    assert_equal 20, inputs.count(%i[a])
    assert_raises(ArgumentError) { registry.validate('guard', { frames: 5, direction: 'left' }) }
    start = state(inventory: [4] + Array.new(9, 0))
    result, after, = drive('guard', { frames: 5 }, start)
    assert_equal [:done, true, 5, 4], [result[:stopped_by], result[:equipped], result[:raised_frames], after.item_b]
    assert_equal :refused, drive('guard', { frames: 5 }, state).first[:stopped_by]
  end

  def run_skill(emulator, name, params)
    execution = registry.start(name, Koholint::Perception.read(emulator), params)
    while (buttons = execution.next_input(Koholint::Perception.read(emulator)))
      emulator.step(buttons)
    end
    execution.result(Koholint::Perception.read(emulator))
  end

  def test_guard_and_use_item_on_the_rom
    skip_without_rom!
    skip 'shield run journal not available' unless File.file?(File.join(SHIELD_RUN, 'inputs.log'))
    emulator = Koholint::Emulator.restore(EmulatorCache.replayed(SHIELD_RUN, OUTDOORS_FRAME).dump)
    assert_equal 4, Koholint::Perception.read(emulator).item_b
    result = run_skill(emulator, 'guard', { frames: 30 })
    assert_equal [:done, 30, false], [result[:stopped_by], result[:raised_frames], result[:equipped]]
    assert_equal 0, Koholint::Perception.read(emulator).shield_raised
    result = run_skill(emulator, 'use_item', { item: 'shield', button: 'a' })
    assert_equal [:done, :b], [result[:stopped_by], result[:button]]
    run_skill(emulator, 'open_menu', {})
    run_skill(emulator, 'menu_assign', { button: 'b' })
    run_skill(emulator, 'close_menu', {})
    moved = Koholint::Perception.read(emulator)
    assert_equal [0, 4], [moved.item_b, moved.inventory[moved.inventory_cursor]]
    result = run_skill(emulator, 'guard', { frames: 30 })
    assert_equal [:done, true, :b], [result[:stopped_by], result[:equipped], result[:button]]
    assert_equal 30, result[:raised_frames]
    assert_equal 4, Koholint::Perception.read(emulator).item_b
  end
end
