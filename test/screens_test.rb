require_relative 'test_helper'
require 'support/emulator_cache'
require 'koholint/game_state'
require 'koholint/perception'
require 'koholint/skills/registry'

class ScreensTest < Minitest::Test
  SHIELD_RUN = File.expand_path('../runs/20261020-085011-8330', __dir__)
  OUTDOORS_FRAME = 3908

  def registry = @registry ||= Koholint::Skills::Registry.default

  def state(**fields)
    Koholint::GameState.new(frame: 0, room_id: 1, map_id: 0, x: 88, y: 80, hp: 24, milestone: :none, game_mode: 0x0B, game_submode: 7,
                            dialog_state: 0, inventory_cursor: 0, menu_option: 0, item_a: 0, item_b: 4, **fields)
  end

  # A tiny screen model: a cursor moves on the press edge of a direction, A/B/START act on their press edge.
  class Screen
    attr_reader :state

    def initialize(state, columns: 2, count: 10)
      @state = state
      @columns = columns
      @count = count
      @previous = []
    end

    def feed(buttons)
      edge = buttons - @previous
      @previous = buttons
      edge.each { |button| press(button) }
      @state = @state.dup.tap { |s| s.frame += 1 }
    end

    def press(button)
      s = @state.dup
      case [s.game_mode, button]
      in [11, :start] then s.game_mode, s.game_submode = 12, 8
      in [11, :select] then s.game_mode, s.game_submode = 7, 5
      in [12, :start] | [7, :b] then s.game_mode, s.game_submode = 11, 7
      in [12, :right | :left | :down | :up] then s.inventory_cursor = (s.inventory_cursor + { right: 1, left: -1, down: @columns, up: -@columns }[button]) % @count
      in [12, :a] then s.item_a = 9
      in [6, :down] then s.menu_option = (s.menu_option + 1) % 2
      in [6, :up] then s.menu_option = (s.menu_option - 1) % 2
      in [6, :a] then s.game_mode, s.game_submode = s.menu_option.zero? ? [11, 2] : [0, 0]
      else nil
      end
      @state = s
    end
  end

  def drive(name, params, start)
    screen = Screen.new(start)
    execution = registry.start(name, start, params)
    while (buttons = execution.next_input(screen.state))
      screen.feed(buttons)
    end
    [execution.result(screen.state), screen.state]
  end

  def test_open_and_close_the_menu
    result, opened = drive('open_menu', {}, state)
    assert_equal :done, result[:stopped_by]
    assert_equal 'inventory', result[:mode]
    result, closed = drive('close_menu', {}, opened)
    assert_equal :done, result[:stopped_by]
    assert_equal :playing, closed.phase(booted: true)
  end

  def test_open_and_close_the_map
    result, opened = drive('open_map', {}, state)
    assert_equal :done, result[:stopped_by]
    assert_equal 'map', result[:mode]
    assert_equal :done, drive('close_map', {}, opened).first[:stopped_by]
  end

  def test_screen_skills_stop_with_wrong_mode_elsewhere
    dialogue = state(dialog_state: 3)
    assert_equal :wrong_mode, drive('open_menu', {}, dialogue).first[:stopped_by]
    assert_equal :wrong_mode, drive('close_menu', {}, state).first[:stopped_by]
    assert_equal :wrong_mode, drive('close_map', {}, state).first[:stopped_by]
    assert_equal :wrong_mode, drive('menu_move', { slot: 3 }, state).first[:stopped_by]
    assert_equal :wrong_mode, drive('menu_assign', { button: 'a' }, state(game_mode: 12, game_submode: 3)).first[:stopped_by]
    assert_equal :wrong_mode, drive('choose_option', { option: 1 }, state(game_mode: 12, game_submode: 8)).first[:stopped_by]
    assert_equal 0, drive('open_menu', {}, dialogue).first[:frames]
  end

  def test_menu_move_reaches_any_slot_by_the_shortest_way
    menu = state(game_mode: 12, game_submode: 8)
    (0..9).each do |slot|
      result, reached = drive('menu_move', { slot: }, menu)
      assert_equal :done, result[:stopped_by], slot
      assert_equal slot, reached.inventory_cursor
    end
    assert_operator drive('menu_move', { slot: 9 }, menu).first[:frames], :<, 20
  end

  def test_menu_move_reports_a_cursor_that_does_not_move
    stuck = Class.new(Screen) { def press(_button) = nil }
    menu = state(game_mode: 12, game_submode: 8)
    screen = stuck.new(menu)
    execution = registry.start('menu_move', menu, { slot: 4 })
    while (buttons = execution.next_input(screen.state))
      screen.feed(buttons)
    end
    assert_equal :no_response, execution.stopped_by
  end

  def test_menu_assign_reports_the_swap
    result, = drive('menu_assign', { button: 'a' }, state(game_mode: 12, game_submode: 8))
    assert_equal :done, result[:stopped_by]
    assert_equal 9, result[:item_a]
  end

  def test_choose_option_moves_the_arrow_confirms_and_releases_a_once_the_screen_left
    start = state(game_mode: 6, game_submode: 5, menu_option: 1)
    screen = Screen.new(start)
    execution = registry.start('choose_option', start, { option: 0 })
    inputs = []
    while (buttons = execution.next_input(screen.state))
      inputs << buttons
      screen.feed(buttons)
    end
    assert_equal :done, execution.stopped_by
    assert_equal [11, 2], [screen.state.game_mode, screen.state.game_submode]
    assert_equal 1, inputs.count { |buttons| buttons.include?(:a) }
    assert_equal :wrong_mode, drive('choose_option', { option: 2 }, state(game_mode: 6, game_submode: 5)).first[:stopped_by]
  end

  def test_choose_option_refuses_an_option_that_quits_to_the_title
    result, after = drive('choose_option', { option: 1 }, state(game_mode: 6, game_submode: 5))
    assert_equal :refused, result[:stopped_by]
    assert_equal 0, result[:frames]
    assert_equal 6, after.game_mode
    over = state(link_motion_state: 7, game_over_stage: 4)
    assert_equal :refused, drive('choose_option', { option: 1 }, over).first[:stopped_by]
    assert_equal 2, registry.fetch('choose_option').params_schema.dig(:properties, :option, :maximum)
  end

  def run_skill(emulator, name, params)
    execution = registry.start(name, Koholint::Perception.read(emulator), params)
    while (buttons = execution.next_input(Koholint::Perception.read(emulator)))
      emulator.step(buttons)
    end
    execution.result(Koholint::Perception.read(emulator))
  end

  def test_menu_and_map_on_the_rom
    skip_without_rom!
    skip 'shield run journal not available' unless File.file?(File.join(SHIELD_RUN, 'inputs.log'))
    emulator = Koholint::Emulator.restore(EmulatorCache.replayed(SHIELD_RUN, OUTDOORS_FRAME).dump)
    assert_equal :done, run_skill(emulator, 'open_menu', {})[:stopped_by]
    assert_equal :menu, Koholint::Perception.read(emulator).phase(booted: true)
    assert_equal :done, run_skill(emulator, 'menu_move', { slot: 3 })[:stopped_by]
    assert_equal 3, Koholint::Perception.read(emulator).inventory_cursor
    assert_equal :done, run_skill(emulator, 'close_menu', {})[:stopped_by]
    assert_equal :playing, Koholint::Perception.read(emulator).phase(booted: true)
    assert_equal :done, run_skill(emulator, 'open_map', {})[:stopped_by]
    assert_equal :map, Koholint::Perception.read(emulator).phase(booted: true)
    assert_equal :done, run_skill(emulator, 'close_map', {})[:stopped_by]
    assert_equal :playing, Koholint::Perception.read(emulator).phase(booted: true)
  end
end
