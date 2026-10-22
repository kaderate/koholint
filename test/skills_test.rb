require_relative 'test_helper'
require 'koholint/ledger'
require 'koholint/triggers'
require 'support/emulator_cache'
require 'koholint/decision'
require 'koholint/vision/grid_builder'
require 'koholint/calibration/walk_probe'
require 'koholint/game_state'
require 'koholint/skills/registry'
require 'koholint/perception'

class SkillsTest < Minitest::Test
  def registry = @registry ||= Koholint::Skills::Registry.default

  def state(x: 88, y: 80, hp: 24, room_id: 1, dialog_state: 0, frame: 0)
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
    assert_equal %w[walk press advance_dialogue wait goto step talk_to explore], registry.names
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

  def test_non_hash_params_are_rejected_for_every_skill
    [5, 'up', nil, [1], 1.5, true].each do |bad|
      registry.names.each do |name|
        assert_raises(ArgumentError, "#{name} with #{bad.inspect}") { registry.validate(name, bad) }
        assert_raises(ArgumentError, "#{name} with #{bad.inspect}") { registry.start(name, state, bad) }
      end
    end
  end

  def test_ill_typed_param_values_are_rejected
    [{ direction: 5, cells: 1 }, { direction: [:up], cells: 1 }, { direction: :up, cells: 'two' }, { direction: :up, cells: [1] }].each do |bad|
      assert_raises(ArgumentError, bad.inspect) { registry.validate('walk', bad) }
    end
    [{ button: 5, frames: 3 }, { button: :a, frames: '3' }, { button: {}, frames: 3 }].each { |bad| assert_raises(ArgumentError, bad.inspect) { registry.validate('press', bad) } }
    [{ frames: 'x' }, { frames: [5] }, { frames: nil }].each { |bad| assert_raises(ArgumentError, bad.inspect) { registry.validate('wait', bad) } }
    assert_raises(ArgumentError) { registry.validate('advance_dialogue', { x: 1 }) }
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
    execution = registry.start('walk', state(y: 80), { direction: :up, cells: 1 })
    states = (0..40).map { |i| state(y: 80 - i) }
    inputs = drive(execution, states)
    result = execution.result(states[inputs.size])
    assert_equal :done, result[:stopped_by]
    assert_equal 1, result[:moved_cells]
    assert_equal({ row: 4, col: 5 }, result[:from].slice(:row, :col))
    assert_equal({ row: 3, col: 5 }, result[:to].slice(:row, :col))
    assert_equal 12, inputs.size
    assert_equal 3, inputs.last(3).count([:up])
    assert_equal 9, result[:frames] - 3
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

  def test_advance_dialogue_runs_one_cycle_while_open
    open = state(dialog_state: 129)
    execution = registry.start('advance_dialogue', open, {})
    inputs = drive(execution, Array.new(60) { state(dialog_state: 135) })
    assert_equal [[:a]] * 3 + [[]] * 27, inputs
    result = execution.result(open)
    assert_equal :done, result[:stopped_by]
    assert_equal 30, result[:frames]
    assert result[:dialog_before]
    assert result[:dialog_after]
  end

  def test_advance_dialogue_stops_the_frame_it_closes
    open = state(dialog_state: 129)
    execution = registry.start('advance_dialogue', open, {})
    assert_equal 5, drive(execution, Array.new(5) { open } + [state(dialog_state: 0)] * 5).size
    result = execution.result(state)
    assert_equal :done, result[:stopped_by]
    assert_equal 5, result[:frames]
    refute result[:dialog_after]
  end

  def test_walk_counts_net_cells
    execution = registry.start('walk', state(y: 80), { direction: :up, cells: 2 })
    ys = [80, 79, 78, 64, 48, 47]
    inputs = drive(execution, ys.map { |y| state(y:) })
    assert_equal 4, inputs.size
    result = execution.result(state(y: 48))
    assert_equal :done, result[:stopped_by]
    assert_equal 2, result[:moved_cells]
  end

  def test_moved_cells_off_the_grid_uses_the_pixel_distance
    execution = registry.start('walk', state(y: 3), { direction: :up, cells: 1 })
    assert_nil Koholint::GameState.cell_at(80, 3)
    assert_equal 1, execution.result(state(y: 19))[:moved_cells]
    assert_equal 0, execution.result(state(y: 10))[:moved_cells]
  end

  def test_walk_bounce_across_a_boundary_is_not_progress
    execution = registry.start('walk', state(y: 72), { direction: :up, cells: 2 })
    ys = [72, 71, 72, 71, 72, 71, 72] + [71] * 10 + [68] * 20
    inputs = drive(execution, ys.map { |y| state(y:) })
    result = execution.result(state(y: 68))
    assert_equal :blocked, result[:stopped_by]
    assert_operator inputs.size, :<, ys.size
    assert_operator result[:moved_cells], :<=, 1
  end

  def test_walk_blocked_at_y39_centres_up_and_ends_aligned
    execution = registry.start('walk', state(y: 80), { direction: :up, cells: 5 })
    states = (80).downto(39).map { |y| state(y:) } + [state(y: 39)] * 10 + (38).downto(30).map { |y| state(y:) }
    inputs = drive(execution, states)
    result = execution.result(state(y: 35))
    assert_equal :blocked, result[:stopped_by]
    assert_equal({ row: 1, col: 5, direction: :up }, result[:blocked_at])
    assert_equal [[:up]], inputs.uniq
    assert_operator inputs.size - (42 + 8), :<=, 7
    assert_equal inputs.size, result[:frames]
    assert result[:aligned]
  end

  def test_blocked_walk_reports_the_cell_and_direction
    execution = registry.start('walk', state, { direction: :right, cells: 2 })
    drive(execution, Array.new(40) { state })
    result = execution.result(state)
    assert_equal :blocked, result[:stopped_by]
    assert_equal({ row: 4, col: 5, direction: :right }, result[:blocked_at])
    assert result[:aligned]
  end

  def test_blocked_at_survives_a_dialogue_opening_during_centring
    execution = registry.start('walk', state(y: 39), { direction: :left, cells: 1 })
    inputs = drive(execution, Array.new(9) { state(y: 39) } + [state(y: 39, dialog_state: 129)])
    result = execution.result(state(y: 39, dialog_state: 129))
    assert_equal :dialogue, result[:stopped_by]
    assert_equal({ row: 1, col: 5, direction: :left }, result[:blocked_at])
    assert_equal [[:left]] * 8 + [[:up]], inputs
  end

  def test_centring_does_not_press_the_blocked_direction_again
    execution = registry.start('walk', state(y: 39), { direction: :up, cells: 1 })
    inputs = drive(execution, Array.new(40) { state(y: 39) })
    assert_equal [[:up]] * 8, inputs
    assert_equal :blocked, execution.result(state(y: 39))[:stopped_by]
  end

  def test_centring_is_skipped_on_dialogue_and_blocked_at_is_nil_otherwise
    execution = registry.start('walk', state(y: 72), { direction: :up, cells: 3 })
    event = state(y: 71, dialog_state: 129)
    drive(execution, [state, event])
    result = execution.result(event)
    assert_equal :dialogue, result[:stopped_by]
    assert_equal 1, result[:frames]
    assert_nil result[:blocked_at]
  end

  def doorway(**over) = state(x: 88, y: 121, **over)

  def test_execution_records_the_input_that_opened_a_dialogue_by_itself
    execution = registry.start('walk', doorway, { direction: :right, cells: 1 })
    open = doorway(dialog_state: 129)
    inputs = drive(execution, [doorway] + [doorway(x: 89)] * 3 + [open])
    assert_equal [[:right]] * 4, inputs
    result = execution.result(open)
    assert_equal :dialogue, result[:stopped_by]
    assert_equal [:right], result[:trigger_input]
  end

  def test_trigger_input_is_the_centring_press_and_nil_for_a_and_for_other_stops
    execution = registry.start('walk', doorway(y: 128), { direction: :up, cells: 1 })
    drive(execution, [doorway(y: 128)] * 20)
    assert_nil execution.result(doorway(y: 128))[:trigger_input]
    pressing = registry.start('press', doorway, { button: :a, frames: 3 })
    open = doorway(dialog_state: 129)
    drive(pressing, [doorway, doorway, open])
    assert_nil pressing.result(open)[:trigger_input]
    advance = registry.start('advance_dialogue', open, {})
    drive(advance, [open] * 3)
    assert_nil advance.result(open)[:trigger_input]
    centring = registry.start('walk', doorway, { direction: :up, cells: 1 })
    drive(centring, [doorway] + [doorway] * 8 + [open])
    assert_equal [:down], centring.result(open)[:trigger_input]
  end

  def test_centring_never_presses_a_forbidden_direction
    triggers = Koholint::Triggers.new
    cell = doorway.cell
    triggers.record(place: [1, 0], cell:, skill: 'walk', direction: 'down', input: :down)
    free = registry.start('walk', doorway, { direction: :right, cells: 1 })
    assert_includes drive(free, [doorway] * 12 + [doorway(x: 100)] * 3).flatten, :down
    execution = registry.start('walk', doorway, { direction: :right, cells: 1 }, { triggers: })
    inputs = drive(execution, [doorway] * 30)
    refute_includes inputs.flatten, :down
    result = execution.result(doorway)
    refute result[:aligned]
    assert_equal 7, result[:offset][:dy].abs
  end

  def test_centring_stops_after_sixteen_frames_when_never_aligned
    execution = registry.start('walk', state(y: 39), { direction: :left, cells: 1 })
    inputs = drive(execution, Array.new(60) { state(y: 39) })
    result = execution.result(state(y: 39))
    assert_equal 8 + 16, inputs.size
    assert_equal :blocked, result[:stopped_by]
    refute result[:aligned]
  end

  def test_centring_aborts_on_budget
    execution = registry.start('walk', state(y: 39), { direction: :left, cells: 1 })
    9.times { execution.next_input(state(y: 39)) }
    assert_equal [:up], execution.next_input(state(y: 39))
    execution.abort(:budget)
    result = execution.result(state(y: 39))
    assert_equal :budget, result[:stopped_by]
    assert_equal 9, result[:frames]
  end

  def test_press_and_wait_report_alignment_without_centring
    execution = registry.start('wait', state(y: 39), { frames: 2 })
    assert_equal [[], []], drive(execution, Array.new(5) { state(y: 39) })
    result = execution.result(state(y: 39))
    assert_equal({ dx: 0, dy: 7 }, result[:offset])
    refute result[:aligned]
    assert_nil result[:blocked_at]
  end

  def test_step_right_is_done_after_the_pixels_and_does_not_centre
    execution = registry.start('step', state(x: 88), { direction: :right, pixels: 8 })
    inputs = drive(execution, (88..100).map { |x| state(x:) })
    assert_equal Array.new(8) { [:right] }, inputs
    result = execution.result(state(x: 96))
    assert_equal :done, result[:stopped_by]
    assert_equal 8, result[:moved_px]
    assert_equal 8, result[:frames]
  end

  def test_step_blocked_after_eight_still_frames
    execution = registry.start('step', state, { direction: :up, pixels: 5 })
    assert_equal Array.new(8) { [:up] }, drive(execution, Array.new(12) { state })
    result = execution.result(state)
    assert_equal :blocked, result[:stopped_by]
    assert_equal 0, result[:moved_px]
    assert_nil result[:blocked_at]
  end

  def test_step_stops_on_dialogue
    execution = registry.start('step', state, { direction: :left, pixels: 3 })
    assert_equal [[:left]], drive(execution, [state, state(dialog_state: 1)])
    assert_equal :dialogue, execution.stopped_by
  end

  def test_step_stops_on_frame_cap
    execution = registry.start('step', state, { direction: :left, pixels: 16 })
    drive(execution, Array.new(200) { |i| state(x: 88 - (i / 7)) })
    assert_equal :frame_cap, execution.stopped_by
  end

  def test_step_params_range_errors
    [{ direction: :up, pixels: 0 }, { direction: :up, pixels: 17 }, { direction: :north, pixels: 3 }, { direction: :up }].each do |bad|
      assert_raises(ArgumentError, bad.inspect) { registry.validate('step', bad) }
    end
    assert_equal({ direction: :up, pixels: 5 }, registry.validate('step', { 'direction' => 'up', 'pixels' => 5 }))
  end

  def test_rom_step_up_moves_the_pixels
    skip_without_rom!
    emulator = fresh(EmulatorCache.interactive)
    start = Koholint::Perception.read(emulator)
    result, = run_skill(emulator, 'step', { direction: :up, pixels: 5 })
    final = Koholint::Perception.read(emulator)
    assert_in_delta 5, start.y - final.y, 1
    assert_in_delta 5, result[:moved_px], 1
  end

  def test_rom_walk_up_three_ends_aligned_and_a_left_walk_is_not_blocked
    skip_without_rom!
    emulator = fresh(EmulatorCache.interactive)
    execution = registry.start('walk', Koholint::Perception.read(emulator), { direction: :up, cells: 3 })
    before_centring = nil
    while (buttons = execution.next_input(Koholint::Perception.read(emulator)))
      before_centring ||= Koholint::Perception.read(emulator) if execution.instance_variable_get(:@centring)
      emulator.step(buttons)
    end
    final = Koholint::Perception.read(emulator)
    assert_operator (before_centring.y - 32).abs, :>, Koholint::Geometry::ALIGN_TOLERANCE
    result = execution.result(final)
    assert result[:aligned], result.inspect
    assert_operator result[:offset][:dy].abs, :<=, Koholint::Geometry::ALIGN_TOLERANCE
    result, = run_skill(emulator, 'walk', { direction: :left, cells: 3 })
    refute_equal :blocked, result[:stopped_by], result.inspect
  end


  def test_hard_cap
    execution = Koholint::Skills::Wait::Run.new(skill: 'wait', params: {}, state:, duration: 1000)
    assert_equal 400, drive(execution, Array.new(500) { state }).size
  end

  class OpenGrid
    def initialize(walls: []) = @walls = walls
    def static_sprite(_row, _col) = nil
    def passable(row, col, _direction) = @walls.include?([row, col]) ? :no : :yes
  end

  def simulate(execution, start, walls: [], limit: 600)
    x, y = start
    hp = 24
    inputs = []
    limit.times do
      current = state(x:, y:)
      buttons = execution.next_input(current)
      break unless buttons

      inputs << buttons
      dx, dy = { up: [0, -1], down: [0, 1], left: [-1, 0], right: [1, 0] }.fetch(buttons.first, [0, 0])
      nx = x + dx
      ny = y + dy
      cell = Koholint::Geometry.cell_for(nx + (7 * dx), ny + (7 * dy))
      next if cell && walls.include?(cell)

      x = nx
      y = ny
    end
    [execution.result(state(x:, y:, hp:)), inputs]
  end

  def goto(row, col, start: [88, 80], grid: OpenGrid.new, ledger: nil, triggers: nil, **walls)
    execution = registry.start('goto', state(x: start[0], y: start[1]), { row:, col: }, { grid:, ledger:, triggers: }.compact)
    simulate(execution, start, **walls)
  end

  def test_goto_three_cells_ends_done_and_aligned
    result, inputs = goto(4, 8)
    assert_equal :done, result[:stopped_by]
    assert_equal 3, result[:path_length]
    assert_equal 3, result[:steps_done]
    assert result[:aligned]
    assert_equal [4, 8], [result[:to][:row], result[:to][:col]]
    assert_equal result[:frames], inputs.size
  end

  def test_goto_exposes_the_edges_it_crossed
    result, = goto(4, 8)
    assert_equal [[4, 5, :right], [4, 6, :right], [4, 7, :right]], result[:crossed]
  end

  def test_goto_blocked_after_one_step_crosses_one_edge
    result, = goto(4, 8, walls: [[4, 7]])
    assert_equal [[4, 5, :right]], result[:crossed]
  end

  def test_goto_turns_after_centring
    result, = goto(2, 6, start: [88, 80])
    assert_equal :done, result[:stopped_by]
    assert result[:aligned]
    assert_equal [2, 6], [result[:to][:row], result[:to][:col]]
  end

  def test_goto_blocked_segment_reports_blocked_at
    result, = goto(4, 8, grid: OpenGrid.new, walls: [[4, 7]])
    assert_equal :blocked, result[:stopped_by]
    assert_equal({ row: 4, col: 6, direction: :right }, result[:blocked_at])
    assert_operator result[:steps_done], :<, result[:path_length]
  end

  def test_goto_unreachable_target_is_no_path_after_one_frame
    wall = (0..7).map { |row| [row, 7] }
    result, inputs = goto(4, 8, grid: OpenGrid.new(walls: wall))
    assert_equal :no_path, result[:stopped_by]
    assert_equal 1, result[:frames]
    assert_equal [[]], inputs
    assert_equal 0, result[:path_length]
  end

  def test_goto_no_path_carries_a_cause
    result, = goto(4, 8, grid: OpenGrid.new(walls: [[4, 8]]))
    assert_equal 'target believed blocked', result[:cause]
    result, = goto(4, 8, grid: OpenGrid.new(walls: (0..7).map { |row| [row, 7] }))
    assert_equal 'no route over known cells', result[:cause]
    ledger = Koholint::Ledger.new
    place = [state.room_id, state.map_id]
    2.times { ledger.record(place:, blocked_at: { row: 4, col: 5, direction: :right }) }
    result, = goto(4, 6, ledger:, grid: OpenGrid.new(walls: [[3, 5], [5, 5], [3, 6], [5, 6], [4, 4]]))
    assert_equal 'no route: doubtful edges (4,5) right', result[:cause]
  end

  def test_goto_no_path_cause_names_forbidden_trigger_edges
    triggers = Koholint::Triggers.new
    triggers.record(place: [state.room_id, state.map_id], cell: [4, 5], skill: 'walk', input: :right)
    result, = goto(4, 6, triggers:, grid: OpenGrid.new(walls: [[3, 5], [5, 5], [3, 6], [5, 6], [4, 4]]))
    assert_equal :no_path, result[:stopped_by]
    assert_equal 'no route: edges where the game opens a dialogue by itself: (4,5) right; walk or step there explicitly if passing is the goal', result[:cause]
  end

  def test_goto_without_a_grid_is_no_path
    execution = registry.start('goto', state, { row: 4, col: 8 })
    result, inputs = simulate(execution, [88, 80])
    assert_equal :no_path, result[:stopped_by]
    assert_equal 'no grid', result[:cause]
    assert_equal 1, inputs.size
  end

  def test_goto_to_the_current_cell_spends_a_frame_and_is_done
    result, = goto(4, 5)
    assert_equal :done, result[:stopped_by]
    assert_operator result[:frames], :>=, 1
    assert_equal 0, result[:path_length]
  end

  def test_goto_stops_on_room_change_and_damage
    execution = registry.start('goto', state, { row: 4, col: 9 }, { grid: OpenGrid.new })
    execution.next_input(state)
    execution.next_input(state(room_id: 2))
    assert_equal :room_change, execution.result.fetch(:stopped_by)
    execution = registry.start('goto', state, { row: 4, col: 9 }, { grid: OpenGrid.new })
    execution.next_input(state)
    execution.next_input(state(hp: 20))
    assert_equal :damage, execution.result.fetch(:stopped_by)
  end

  def test_goto_params_are_validated
    [{ row: 8, col: 0 }, { row: 0, col: 10 }, { row: -1, col: 0 }, { row: 'a', col: 0 }, { row: 1 }, { row: 1, col: 1, x: 1 }].each do |bad|
      assert_raises(ArgumentError, bad.inspect) { registry.start('goto', state, bad, { grid: OpenGrid.new }) }
    end
  end

  class DirectProber
    def run(emulator, **options) = Koholint::Calibration::WalkProbe.run(emulator, **options)
  end

  class SilentTrace
    def emit(*, **) = nil
  end

  def interactive_grid(emulator)
    builder = Koholint::Vision::GridBuilder.new(trace: SilentTrace.new, prober: DirectProber.new)
    state = Koholint::Perception.read(emulator)
    5.times.map { builder.observe(emulator, state) }.last
  end

  def test_rom_goto_across_the_starting_house_ends_aligned_on_the_target
    skip_without_rom!
    grid = interactive_grid(EmulatorCache.interactive)
    [[1, 4], [1, 6], [1, 2]].each do |row, col|
      refute grid.static_sprite(row, col)
      emulator = fresh(EmulatorCache.interactive)
      execution = registry.start('goto', Koholint::Perception.read(emulator), { row:, col: }, { grid: })
      while (buttons = execution.next_input(Koholint::Perception.read(emulator)))
        emulator.step(buttons)
      end
      result = execution.result(Koholint::Perception.read(emulator))
      assert_equal :done, result[:stopped_by], [row, col].inspect
      assert result[:aligned]
      assert_equal [row, col], result.fetch(:to).values_at(:row, :col)
      assert_operator result[:frames], :<=, 400
    end
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
    assert_equal %w[skill params justification confidence plan], schema[:required]
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

  def test_rom_walk_right_in_the_doorway_avoids_a_forbidden_down
    skip_without_rom!
    emulator = fresh(EmulatorCache.interactive)
    [[:down, 3], [:down, 3], [:right, 1]].each { |direction, cells| run_skill(emulator, 'walk', { direction:, cells: }) }
    result, = run_skill(emulator, 'walk', { direction: :down, cells: 2 })
    skip 'setup did not provoke the trigger from the interactive snapshot' unless result[:stopped_by] == :dialogue && result[:trigger_input]

    30.times do
      state = Koholint::Perception.read(emulator)
      break unless state.dialog_open?

      run_skill(emulator, 'advance_dialogue', {})
    end
    state = Koholint::Perception.read(emulator)
    skip 'dialogue did not close' if state.dialog_open?

    triggers = Koholint::Triggers.new
    triggers.record(place: [state.room_id, state.map_id], cell: state.cell, skill: 'walk', direction: 'down', input: :down)
    execution = registry.start('walk', state, { direction: :right, cells: 1 }, { triggers: })
    journal = []
    while (buttons = execution.next_input(Koholint::Perception.read(emulator)))
      emulator.step(buttons)
      journal << buttons
    end
    final = execution.result(Koholint::Perception.read(emulator))
    refute_includes journal.flatten, :down
    refute_equal :dialogue, final[:stopped_by]
  end

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

  def test_rom_advance_dialogue_runs_one_cycle_or_closes
    skip_without_rom!
    emulator = fresh(EmulatorCache.at(700))
    emulator.step until Koholint::Perception.read(emulator).dialog_open? || emulator.frame > 1200
    assert Koholint::Perception.read(emulator).dialog_open?
    result, journal = run_skill(emulator, 'advance_dialogue', {})
    assert_equal result[:frames], journal.size
    assert(result[:frames] == 30 || (result[:frames] < 30 && !result[:dialog_after]))
  end
end
