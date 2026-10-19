require_relative 'test_helper'
require 'support/emulator_cache'
require 'koholint/decision'
require 'koholint/game_state'
require 'koholint/skills/registry'
require 'koholint/perception'

class SkillsTest < Minitest::Test
  def registry = @registry ||= Koholint::Skills::Registry.default

  def state(x: 80, y: 72, hp: 24, room_id: 1, dialog_state: 0, frame: 0)
    Koholint::GameState.new(frame:, room_id:, map_id: 0, x:, y:, hp:, dialog_state:, game_mode: 0x0B, game_submode: 7, milestone: :none)
  end

  def drive(execution, states)
    inputs = []
    states.each do |s|
      buttons = execution.next_input(s)
      break unless buttons

      inputs << buttons
    end
    inputs
  end

  def test_registry_names_and_unknown_skill
    assert_equal %w[walk press advance_dialogue wait], registry.names
    assert_raises(ArgumentError) { registry.fetch('fly') }
    assert_raises(ArgumentError) { registry.start('fly', state, {}) }
  end

  def test_out_of_range_params_raise
    assert_raises(ArgumentError) { registry.start('walk', state, { direction: :up, cells: 6 }) }
    assert_raises(ArgumentError) { registry.start('walk', state, { direction: :north, cells: 1 }) }
    assert_raises(ArgumentError) { registry.start('press', state, { button: :up, frames: 3 }) }
    assert_raises(ArgumentError) { registry.start('press', state, { button: :a, frames: 61 }) }
    assert_raises(ArgumentError) { registry.start('wait', state, { frames: 0 }) }
    assert_raises(ArgumentError) { registry.start('wait', state, { frames: 121 }) }
    assert_raises(ArgumentError) { registry.start('wait', state, { frames: 5, extra: 1 }) }
  end

  def test_string_keys_and_values_are_accepted
    assert_equal({ direction: :up, cells: 2 }, registry.validate('walk', { 'direction' => 'up', 'cells' => 2 }))
  end

  def test_wait_consumes_exactly_its_frames
    execution = registry.start('wait', state, { frames: 4 })
    assert_equal [[], [], [], []], drive(execution, Array.new(10) { state })
    assert_equal 4, execution.result(state)[:frames]
    assert_equal :done, execution.result(state)[:stopped_by]
  end

  def test_press_holds_then_idles
    execution = registry.start('press', state, { button: :a, frames: 3 })
    inputs = drive(execution, Array.new(30) { state })
    assert_equal [[:a]] * 3 + [[]] * 10, inputs
  end

  def test_walk_done_when_cell_changes
    execution = registry.start('walk', state(y: 72), { direction: :up, cells: 1 })
    states = (0..40).map { |i| state(y: 72 - i) }
    inputs = drive(execution, states)
    result = execution.result(states[inputs.size])
    assert_equal :done, result[:stopped_by]
    assert_equal 1, result[:moved_cells]
    assert_equal({ row: 4, col: 5 }, result[:from].slice(:row, :col))
    assert_equal({ row: 3, col: 5 }, result[:to].slice(:row, :col))
    assert_equal inputs.size, result[:frames]
  end

  def test_walk_blocked_after_eight_still_frames
    execution = registry.start('walk', state, { direction: :right, cells: 2 })
    inputs = drive(execution, Array.new(40) { state })
    assert_equal 8, inputs.size
    assert_equal :blocked, execution.result(state)[:stopped_by]
    assert_equal 0, execution.result(state)[:moved_cells]
  end

  def test_walk_frame_cap_when_creeping
    execution = registry.start('walk', state, { direction: :up, cells: 1 })
    inputs = drive(execution, (0..200).map { |i| state(y: 72 + ((i / 7) % 2)) })
    assert_equal 90, inputs.size
    assert_equal :frame_cap, execution.result(state)[:stopped_by]
  end

  def test_walk_stops_on_dialogue_room_change_and_damage
    {
      dialogue: state(y: 71, dialog_state: 129),
      room_change: state(y: 71, room_id: 2),
      damage: state(y: 71, hp: 16)
    }.each do |reason, event|
      execution = registry.start('walk', state, { direction: :up, cells: 3 })
      drive(execution, [state, event])
      result = execution.result(event)
      assert_equal reason, result[:stopped_by]
      assert_equal 1, result[:frames]
    end
  end

  def test_advance_dialogue_cycle_and_stop_on_change
    open = state(dialog_state: 129)
    execution = registry.start('advance_dialogue', open, {})
    inputs = drive(execution, Array.new(31) { state(dialog_state: 130) })
    assert_equal [[:a]] * 3 + [[]] * 27, inputs
    assert_equal 30, inputs.size
    result = execution.result(state)
    assert_equal :done, result[:stopped_by]
    assert result[:dialog_before]
    refute result[:dialog_after]
  end

  def test_advance_dialogue_stops_when_closed
    open = state(dialog_state: 129)
    execution = registry.start('advance_dialogue', open, {})
    assert_equal 5, drive(execution, Array.new(5) { open } + [state(dialog_state: 0)]).size
  end

  def test_advance_dialogue_capped_at_ninety
    open = state(dialog_state: 129)
    execution = registry.start('advance_dialogue', open, {})
    assert_equal 90, drive(execution, Array.new(200) { open }).size
    assert_equal :frame_cap, execution.result(open)[:stopped_by]
  end

  def test_hard_cap
    execution = Koholint::Skills::Wait::Run.new(skill: 'wait', params: {}, state:, duration: 1000)
    assert_equal 400, drive(execution, Array.new(500) { state }).size
  end

  def test_choose_skill_validate_and_schema
    point = Koholint::DecisionPoint.choose_skill(registry)
    assert_equal :choose_skill, point.name
    assert_nil point.options
    choice = { skill: 'walk', params: { direction: 'up', cells: 2 } }
    assert_equal choice, point.validate(choice)
    assert_raises(Koholint::DecisionPoint::Invalid) { point.validate({ skill: 'fly', params: {} }) }
    assert_raises(Koholint::DecisionPoint::Invalid) { point.validate({ skill: 'wait', params: { frames: 999 } }) }
    assert_raises(Koholint::DecisionPoint::Invalid) { point.validate({ skill: 'wait' }) }
    schema = point.json_schema
    assert_equal registry.names, schema[:properties][:skill][:enum]
    assert_equal registry.names, schema[:properties][:params][:anyOf].map { |s| s[:title] }
    assert_equal %w[skill params justification confidence], schema[:required]
    assert JSON.parse(JSON.generate(schema))
  end

  def run_skill(emulator, name, params)
    execution = registry.start(name, Koholint::Perception.read(emulator), params)
    journal = []
    while (buttons = execution.next_input(Koholint::Perception.read(emulator)))
      emulator.step(buttons)
      journal << buttons
    end
    [execution.result(Koholint::Perception.read(emulator)), journal]
  end

  def fresh(emulator) = Koholint::Emulator.restore(emulator.dump)

  def test_rom_walk_up_one_cell
    skip_without_rom!
    result, = run_skill(fresh(EmulatorCache.interactive), 'walk', { direction: :up, cells: 1 })
    assert_equal 1, result[:moved_cells]
    assert_equal :done, result[:stopped_by]
    assert_equal result[:from][:row] - 1, result[:to][:row]
  end

  def test_rom_walk_right_is_blocked
    skip_without_rom!
    result, = run_skill(fresh(EmulatorCache.interactive), 'walk', { direction: :right, cells: 1 })
    assert_equal :blocked, result[:stopped_by]
    assert_equal 0, result[:moved_cells]
  end

  def test_rom_wait_and_press_frame_counts
    skip_without_rom!
    emulator = fresh(EmulatorCache.interactive)
    start = emulator.frame
    result, journal = run_skill(emulator, 'wait', { frames: 30 })
    assert_equal 30, journal.size
    assert_equal start + 30, emulator.frame
    assert_equal 30, result[:frames]
    _, journal = run_skill(emulator, 'press', { button: :a, frames: 3 })
    assert_equal 13, journal.size
  end

  def test_rom_advance_dialogue_progresses
    skip_without_rom!
    emulator = fresh(EmulatorCache.at(700))
    emulator.step until Koholint::Perception.read(emulator).dialog_open? || emulator.frame > 1200
    before = Koholint::Perception.read(emulator).dialog_state
    result, = run_skill(emulator, 'advance_dialogue', {})
    assert(!result[:dialog_after] || Koholint::Perception.read(emulator).dialog_state != before)
  end
end
