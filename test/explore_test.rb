require_relative 'test_helper'
require 'support/emulator_cache'
require 'koholint/calibration/walk_probe'
require 'koholint/explore_log'
require 'koholint/game_state'
require 'koholint/ledger'
require 'koholint/perception'
require 'koholint/skills/registry'
require 'koholint/talk_log'
require 'koholint/vision/grid_builder'

class ExploreTest < Minitest::Test
  DELTA = { up: [0, -1], down: [0, 1], left: [-1, 0], right: [1, 0] }.freeze
  CLOSED = ['##########', *Array.new(6) { '#........#' }, '##########'].freeze
  PLACE = [1, 0].freeze

  class MapGrid
    def initialize(rows) = @rows = rows
    def static_sprite(row, col) = @rows[row][col] == 'o' ? 'sprite' : nil
    def passable(row, col, _direction) = { '.' => :yes, '#' => :no, 'o' => :no }.fetch(@rows[row][col], :unknown)
  end

  def registry = @registry ||= Koholint::Skills::Registry.default

  def state(x: 88, y: 80, room_id: 1, hp: 24, dialog_state: 0)
    Koholint::GameState.new(frame: 0, room_id:, map_id: 0, x:, y:, hp:, dialog_state:, game_mode: 0x0B, game_submode: 7, milestone: :none)
  end

  def with(rows, *edits)
    rows = rows.map(&:dup)
    edits.each_slice(2) { |(row, col), char| rows[row][col] = char }
    rows
  end

  def explore(rows, truth: rows, exits: [], harm: [], start: [88, 80], params: {}, limit: 1000, **context)
    walls = truth.each_with_index.flat_map { |line, row| line.chars.each_index.select { |col| '#o'.include?(line[col]) }.map { |col| [row, col] } }
    execution = registry.start('explore', state(x: start[0], y: start[1]), params, { grid: MapGrid.new(rows), **context })
    x, y = start
    room_id = 1
    hp = 24
    inputs = []
    limit.times do
      hp = 20 if harm.include?(Koholint::Geometry.cell_for(x, y))
      buttons = execution.next_input(state(x:, y:, room_id:, hp:)) or break
      inputs << buttons
      dx, dy = DELTA.fetch(buttons.first, [0, 0])
      next if dx.zero? && dy.zero?

      ahead = Koholint::Geometry.cell_for(x + dx + (7 * dx), y + dy + (7 * dy))
      room_id = 2 if ahead.nil? && exits.include?([Koholint::Geometry.cell_for(x, y), buttons.first])
      next if ahead.nil? || walls.include?(ahead)

      x += dx
      y += dy
    end
    [execution.result(state(x:, y:, room_id:, hp:)), inputs]
  end

  def test_walks_to_the_nearest_frontier_and_steps_into_the_unknown
    result, inputs = explore(with(CLOSED, [4, 7], '?'))
    assert_equal :no_frontier, result[:stopped_by]
    assert_includes result[:crossed], [4, 6, :right]
    assert_equal [4, 7], result[:to].values_at(:row, :col)
    assert_equal({ kind: :frontier, row: 4, col: 6, direction: :right }, result[:target])
    assert_equal [], result[:tried_exits]
    assert_equal result[:frames], inputs.size
    refute result[:place_changed]
  end

  def test_a_blocked_step_into_the_unknown_is_a_blocked_edge_and_the_next_frontier_is_tried
    rows = with(CLOSED, [4, 7], '?', [1, 5], '?')
    result, = explore(rows, truth: with(CLOSED, [4, 7], '#'))
    assert_equal :no_frontier, result[:stopped_by]
    assert_includes result[:blocked_edges], { row: 4, col: 6, direction: :right }
    assert_equal [1, 5], result[:to].values_at(:row, :col)
    assert_equal [{ row: 4, col: 6, direction: :right }], result[:blocked_edges]
    assert_nil result[:blocked_at]
  end

  def test_leaves_through_an_exit_and_stops_on_the_new_place
    rows = with(CLOSED, [7, 5], '.')
    result, = explore(rows, exits: [[[7, 5], :down]])
    assert_equal :new_place, result[:stopped_by]
    assert result[:place_changed]
    assert_equal [{ row: 7, col: 5, direction: :down, outcome: :left }], result[:exits]
    log = Koholint::ExploreLog.new
    log.absorb(result)
    assert log.tried?(PLACE, [7, 5], :down)
    result, = explore(rows, exits: [[[7, 5], :down]], explore_log: log)
    assert_equal :no_frontier, result[:stopped_by]
    assert_equal [{ row: 7, col: 5, direction: :down }], result[:tried_exits]
  end

  def test_an_exit_blocked_twice_is_tried
    rows = with(CLOSED, [7, 5], '.')
    log = Koholint::ExploreLog.new
    2.times do
      result, = explore(rows, explore_log: log)
      assert_equal :no_frontier, result[:stopped_by]
      assert_equal [{ row: 7, col: 5, direction: :down, outcome: :blocked }], result[:exits]
      log.absorb(result)
    end
    result, inputs = explore(rows, explore_log: log)
    assert_equal :no_frontier, result[:stopped_by]
    assert_equal [[]], inputs
    assert_equal [{ row: 7, col: 5, direction: :down }], result[:tried_exits]
  end

  def test_direction_hint_prefers_that_side_and_nearest_without_it
    rows = with(CLOSED, [4, 7], '?', [1, 5], '?')
    result, = explore(rows, limit: 3)
    assert_equal({ kind: :frontier, row: 4, col: 6, direction: :right }, result[:target])
    result, = explore(rows, params: { direction: 'up' }, limit: 3)
    assert_equal({ kind: :frontier, row: 2, col: 5, direction: :up }, result[:target])
    assert_equal({ direction: :up }, result[:params])
  end

  def test_a_closed_known_place_is_no_frontier_after_one_idle_frame
    result, inputs = explore(CLOSED)
    assert_equal :no_frontier, result[:stopped_by]
    assert_equal [[]], inputs
    assert_equal 1, result[:frames]
    assert_equal 0, result[:cells_walked]
  end

  def test_stops_once_near_an_object_never_talked_to
    rows = with(CLOSED, [1, 8], 'o', [2, 8], '?')
    result, = explore(rows, truth: with(rows, [2, 8], '.'))
    assert_equal :untried_object, result[:stopped_by]
    assert_equal [{ row: 1, col: 8 }], result[:untried_objects]
    assert_includes result[:offered], { row: 1, col: 8 }
    log = Koholint::ExploreLog.new
    log.absorb(result)
    result, = explore(rows, truth: with(rows, [2, 8], '.'), explore_log: log)
    assert_equal :no_frontier, result[:stopped_by]
  end

  def test_objects_already_talked_to_or_near_at_the_start_do_not_stop
    rows = with(CLOSED, [1, 8], 'o', [2, 8], '?')
    talk_log = Koholint::TalkLog.new
    talk_log.record(place: PLACE, row: 1, col: 8, talked: true)
    result, = explore(rows, truth: with(rows, [2, 8], '.'), talk_log:)
    assert_equal :no_frontier, result[:stopped_by]
    near = with(CLOSED, [3, 5], 'o', [6, 5], '?')
    result, = explore(near, truth: with(near, [6, 5], '.'))
    assert_equal :no_frontier, result[:stopped_by]
    assert_equal [{ row: 3, col: 5 }], result[:offered]
  end

  def test_blocked_after_three_attempts_without_progress
    rows = with(CLOSED, [1, 1], '?', [1, 8], '?', [6, 1], '?', [6, 8], '?')
    truth = with(CLOSED, [3, 5], '#', [5, 5], '#', [4, 4], '#', [4, 6], '#')
    result, = explore(rows, truth:)
    assert_equal :blocked, result[:stopped_by]
    assert_equal 3, result[:legs]
    refute_nil result[:blocked_at]
    assert_equal 3, result[:blocked_edges].size
    assert_match(/\Agoto leg to \(\d,\d\) stopped blocked\z/, result[:cause])
  end

  def test_a_failed_leg_reports_its_real_cause
    rows = with(CLOSED, [1, 1], '?', [1, 8], '?', [6, 1], '?', [6, 8], '?')
    execution = registry.start('explore', state, {}, { grid: MapGrid.new(rows) })
    stub = Struct.new(:stopped) do
      def next_input(_state) = nil
      def result(_state) = { stopped_by: stopped, crossed: [], blocked_at: nil, cause: ('no route over known cells' if stopped == :no_path) }
    end
    frames = 0
    until execution.stopped_by || frames > 20
      leg = execution.instance_variable_get(:@leg)
      execution.instance_variable_set(:@leg, stub.new(frames.even? ? :no_path : :frame_cap)) if leg && !leg.is_a?(stub)
      execution.next_input(state)
      frames += 1
    end
    result = execution.result
    assert_equal :blocked, result[:stopped_by]
    assert_match(/\Agoto leg to \(\d,\d\) stopped (no_path: no route over known cells|frame_cap)\z/, result[:cause])
  end

  def test_damage_walls_the_frontier_so_the_next_call_avoids_it
    rows = with(CLOSED, [4, 7], '?', [1, 5], '?')
    log = Koholint::ExploreLog.new
    result, = explore(rows, harm: [[4, 7]], explore_log: log)
    assert_equal :damage, result[:stopped_by]
    assert_equal [{ row: 4, col: 7 }], result[:walls]
    assert_includes result[:blocked_edges], { row: 4, col: 6, direction: :right }
    log.absorb(result)
    result, = explore(rows, harm: [[4, 7]], explore_log: log)
    refute_equal :damage, result[:stopped_by]
    refute_includes result[:crossed], [4, 6, :right]
    assert_equal [1, 5], result[:to].values_at(:row, :col)
  end

  def test_an_open_dialogue_at_the_start_stops_after_one_idle_frame
    open = state(dialog_state: 1)
    execution = registry.start('explore', open, {}, { grid: MapGrid.new(with(CLOSED, [4, 7], '?')) })
    assert_equal [], execution.next_input(open)
    assert_nil execution.next_input(open)
    assert_equal :dialogue, execution.result[:stopped_by]
    assert_equal 1, execution.result[:frames]
  end

  def test_doubtful_edges_are_avoided
    rows = with(CLOSED, [4, 7], '?', [1, 5], '?')
    ledger = Koholint::Ledger.new
    2.times { ledger.record(place: PLACE, blocked_at: { row: 4, col: 6, direction: :right }) }
    result, = explore(rows, ledger:, limit: 3)
    assert_equal({ kind: :frontier, row: 2, col: 5, direction: :up }, result[:target])
  end

  def test_budget_caps_a_call
    open = Array.new(8) { '.' * 10 }
    rows = Array.new(8) { '?' * 10 }
    rows[4] = '?????.????'
    result, inputs = explore(rows, truth: open)
    assert_equal :budget, result[:stopped_by]
    assert_equal 600, inputs.size
    assert_operator result[:cells_walked], :>, 5
  end

  def test_stops_on_dialogue_and_damage
    execution = registry.start('explore', state, {}, { grid: MapGrid.new(with(CLOSED, [4, 7], '?')) })
    execution.next_input(state)
    execution.next_input(state(dialog_state: 1))
    assert_equal :dialogue, execution.result[:stopped_by]
    execution = registry.start('explore', state, {}, { grid: MapGrid.new(with(CLOSED, [4, 7], '?')) })
    execution.next_input(state)
    execution.next_input(state(hp: 20))
    assert_equal :damage, execution.result[:stopped_by]
  end

  def test_without_a_grid_is_no_frontier_with_a_cause
    result = registry.start('explore', state, {}).tap { |e| 2.times { e.next_input(state) } }.result
    assert_equal :no_frontier, result[:stopped_by]
    assert_equal 'no grid', result[:cause]
  end

  def test_is_deterministic
    rows = with(CLOSED, [1, 1], '?', [6, 8], '?', [2, 4], '?')
    assert_equal explore(rows), explore(rows)
  end

  def test_params_are_validated
    assert_equal({}, registry.validate('explore', {}))
    assert_equal({ direction: :left }, registry.validate('explore', { 'direction' => 'left' }))
    [{ direction: 'north' }, { direction: 3 }, { cells: 1 }].each do |bad|
      assert_raises(ArgumentError, bad.inspect) { registry.validate('explore', bad) }
    end
  end

  def test_explore_log_is_rebuilt_from_action_events
    events = [{ 'type' => 'action', 'skill' => 'explore',
                'result' => { 'from' => { 'room' => 1, 'map' => 0 }, 'exits' => [{ 'row' => 7, 'col' => 5, 'direction' => 'down', 'outcome' => 'left' }],
                              'offered' => [{ 'row' => 1, 'col' => 8 }] } }]
    log = Koholint::ExploreLog.from_events(events)
    assert log.tried?(PLACE, [7, 5], :down)
    assert log.offered?(PLACE, [1, 8])
    refute log.offered?([2, 0], [1, 8])
  end

  class SilentTrace
    def emit(*, **) = nil
  end

  def test_rom_explore_in_the_starting_house_moves_and_stops_with_a_reason
    skip_without_rom!
    emulator = Koholint::Emulator.restore(EmulatorCache.interactive.dump)
    builder = Koholint::Vision::GridBuilder.new(trace: SilentTrace.new, prober: Koholint::Calibration::WalkProbe)
    start = Koholint::Perception.read(emulator)
    grid = 5.times.map { builder.observe(emulator, Koholint::Perception.read(emulator)) }.last
    execution = registry.start('explore', Koholint::Perception.read(emulator), {}, { grid: })
    while (buttons = execution.next_input(Koholint::Perception.read(emulator)))
      emulator.step(buttons)
    end
    result = execution.result(Koholint::Perception.read(emulator))
    assert_includes %i[new_place no_frontier untried_object blocked budget dialogue locked], result[:stopped_by]
    assert_operator result[:frames], :<=, 600
    assert_operator result[:cells_walked], :>, 0, result.inspect
    refute_equal start.cell, Koholint::Perception.read(emulator).cell unless result[:place_changed]
  end
end
