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

  def explore(rows, truth: rows, exits: [], harm: [], rocks: [], callouts: [], start: [88, 80], params: {}, limit: 1000, **context)
    walls = truth.each_with_index.flat_map { |line, row| line.chars.each_index.select { |col| '#o'.include?(line[col]) }.map { |col| [row, col] } }
    execution = registry.start('explore', state(x: start[0], y: start[1]), params, { grid: MapGrid.new(rows), **context })
    x, y = start
    room_id = 1
    hp = 24
    dialog_state = 0
    inputs = []
    limit.times do
      hp = 20 if harm.include?(Koholint::Geometry.cell_for(x, y))
      buttons = execution.next_input(state(x:, y:, room_id:, hp:, dialog_state:)) or break
      inputs << buttons
      dx, dy = DELTA.fetch(buttons.first, [0, 0])
      next if dx.zero? && dy.zero?

      ahead = Koholint::Geometry.cell_for(x + dx + (7 * dx), y + dy + (7 * dy))
      room_id = 2 if ahead.nil? && exits.include?([Koholint::Geometry.cell_for(x, y), buttons.first])
      row, col = Koholint::Geometry.cell_for(x, y)
      ox, oy = Koholint::Geometry.offset(x + dx, y + dy, [row, col])
      pushed = rocks.include?([row + dy, col + dx]) && ((dx * ox) > 4 || (dy * oy) > 6)
      dialog_state = 1 if pushed
      next if ahead.nil? || walls.include?(ahead) || pushed

      x += dx
      y += dy
      dialog_state = 1 if callouts.include?(Koholint::Geometry.cell_for(x, y))
    end
    [execution.result(state(x:, y:, room_id:, hp:, dialog_state:)), inputs]
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
    assert_equal [{ row: 7, col: 5, direction: :down, outcome: :left, to: [2, 0] }], result[:exits]
    log = Koholint::ExploreLog.new
    log.absorb(result)
    assert log.tried?(PLACE, [7, 5], :down)
    result, = explore(rows, exits: [[[7, 5], :down]], explore_log: log)
    assert_equal [:known_place, { goal: [2, 0], next: [2, 0] }], result.values_at(:stopped_by, :route)
    log.absorb({ from: { room: 2, map: 0 }, survey: { sides: {}, doors: [] } })
    result, = explore(rows, exits: [[[7, 5], :down]], explore_log: log)
    assert_equal :no_frontier, result[:stopped_by]
    assert_equal [{ row: 7, col: 5, direction: :down }], result[:tried_exits]
  end

  def test_a_side_left_once_is_not_offered_again_from_another_cell
    rows = with(CLOSED, [7, 4], '.', [7, 5], '.')
    log = Koholint::ExploreLog.new
    result, = explore(rows, exits: [[[7, 5], :down]], explore_log: log)
    assert_equal :new_place, result[:stopped_by]
    log.absorb(result)
    log.absorb({ from: { room: 2, map: 0 }, survey: { sides: {}, doors: [] } })
    result, inputs = explore(rows, exits: [[[7, 4], :down]], explore_log: log)
    assert_equal :no_frontier, result[:stopped_by], result.inspect
    assert_equal [[]], inputs
  end

  def test_a_return_to_a_known_place_is_known_place_not_new_place
    rows = with(CLOSED, [7, 5], '.')
    log = Koholint::ExploreLog.new
    log.note({ from: { room: 2, map: 0 } })
    result, = explore(rows, exits: [[[7, 5], :down]], explore_log: log)
    assert_equal :known_place, result[:stopped_by]
  end

  def test_a_place_without_untried_exits_heads_for_the_nearest_place_that_has_some
    rows = with(CLOSED, [7, 5], '.', [0, 5], '.', [4, 7], '?')
    log = Koholint::ExploreLog.new
    log.absorb({ from: { room: 1, map: 0 }, exits: [{ row: 7, col: 5, direction: :down, outcome: :left, to: [2, 0] }, { row: 0, col: 5, direction: :up, outcome: :left, to: [3, 0] }],
                 survey: { sides: { down: [{ row: 7, col: 5 }], up: [{ row: 0, col: 5 }] }, doors: [] } })
    log.absorb({ from: { room: 2, map: 0 }, exits: [{ row: 0, col: 5, direction: :up, outcome: :left, to: [1, 0] }],
                 survey: { sides: { up: [{ row: 0, col: 5 }] }, doors: [] } })
    log.absorb({ from: { room: 3, map: 0 }, exits: [{ row: 7, col: 5, direction: :down, outcome: :left, to: [1, 0] }],
                 survey: { sides: { down: [{ row: 7, col: 5 }], left: [{ row: 3, col: 0 }] }, doors: [] } })
    refute log.untried?([2, 0])
    assert log.untried?([3, 0])
    result, = explore(rows, exits: [[[0, 5], :up]], explore_log: log)
    assert_equal :known_place, result[:stopped_by], result.inspect
    assert_equal({ goal: [3, 0], next: [3, 0] }, result[:route])
    assert_equal({ kind: :exit, row: 0, col: 5, direction: :up }, result[:target])
  end

  # Place 3 is explored (bushes at (3,1) and (4,1), Link walked (3,2), (4,2) and (4,1)), then a capability clears a bush in 160/0.
  def inferring_log(clears: [{ 'target' => { 'row' => 3, 'col' => 8 }, 'effect' => true }], explored_after: false)
    walls = Array.new(8) { Array.new(10, 'wall') }
    bushes = walls.map(&:dup).tap { |grid| grid[3][1] = grid[4][1] = 'bush' }
    explore = ->(frame) { { 'type' => 'action', 'frame' => frame, 'skill' => 'explore', 'result' => { 'from' => { 'room' => 3, 'map' => 0 }, 'crossed' => [[3, 2, 'down'], [4, 2, 'left']],
                                                                                                    'exits' => [{ 'row' => 7, 'col' => 5, 'direction' => 'down', 'outcome' => 'left', 'to' => [1, 0] }],
                                                                                                    'survey' => { 'sides' => { 'down' => [{ 'row' => 7, 'col' => 5 }] }, 'doors' => [], 'pending' => false } } } }
    events = [{ 'type' => 'screen', 'place' => [3, 0], 'grid' => bushes }, explore.(1),
              { 'type' => 'action', 'frame' => 2, 'skill' => 'explore', 'result' => { 'from' => { 'room' => 1, 'map' => 0 }, 'survey' => { 'sides' => { 'up' => [{ 'row' => 0, 'col' => 5 }] }, 'doors' => [] },
                                                                                      'exits' => [{ 'row' => 0, 'col' => 5, 'direction' => 'up', 'outcome' => 'left', 'to' => [3, 0] }] } },
              { 'type' => 'screen', 'place' => [160, 0], 'grid' => walls.map(&:dup).tap { |grid| grid[3][8] = grid[2][4] = 'bush' } },
              { 'type' => 'action', 'frame' => 3, 'skill' => 'goto', 'result' => { 'from' => { 'room' => 160, 'map' => 0 }, 'clears' => clears } }]
    events << explore.(4) if explored_after
    Koholint::ExploreLog.from_events(events)
  end

  def test_a_tile_a_capability_cleared_makes_a_place_explored_before_untried_with_its_source
    log = inferring_log
    assert_equal [{ cell: [3, 1], look: 'bush', source: { place: [160, 0], cell: [3, 8] }, wins: 1, losses: 0 }], log.inferred_clearable([3, 0]),
                 'the tile is read from the screen events; the walked bush at (4,1) is no object'
    assert log.untried?([3, 0])
    rows = with(CLOSED, [0, 5], '.', [7, 5], '.')
    result, = explore(rows, exits: [[[0, 5], :up]], explore_log: log)
    assert_equal({ goal: [3, 0], next: [3, 0], clearable: log.inferred_clearable([3, 0]) }, result[:route])
    log.absorb({ from: { room: 3, map: 0 }, clears: [{ target: { row: 3, col: 1 }, effect: false }] })
    assert_empty log.inferred_clearable([3, 0]), 'a failed clear or a visit with the capability ends the hypothesis'
    refute log.untried?([3, 0])
  end

  def test_a_place_explored_after_a_clear_infers_nothing
    log = inferring_log(explored_after: true)
    assert_empty log.inferred_clearable([3, 0])
    refute log.untried?([3, 0])
  end

  def test_a_tile_that_failed_as_often_as_it_cleared_infers_nothing
    failed = { 'target' => { 'row' => 2, 'col' => 4 }, 'effect' => false }
    assert_empty inferring_log(clears: [{ 'target' => { 'row' => 3, 'col' => 8 }, 'effect' => true }, failed]).inferred_clearable([3, 0])
    looks = [{ 'target' => { 'row' => 3, 'col' => 8 }, 'effect' => true, 'look' => 'bush' }, { 'target' => { 'row' => 2, 'col' => 4 }, 'effect' => true, 'look' => 'bush' }, failed]
    assert_equal [2, 1], inferring_log(clears: looks).inferred_clearable([3, 0]).first.values_at(:wins, :losses)
  end

  def test_untried_exits_that_cannot_be_reached_yet_send_explore_to_the_frontier_before_another_place
    rows = with(CLOSED, [0, 5], '.', [1, 5], '#', [1, 4], '#', [1, 6], '#', [2, 5], '?', [7, 5], '.')
    log = Koholint::ExploreLog.new
    log.absorb({ from: { room: 1, map: 0 }, exits: [{ row: 7, col: 5, direction: :down, outcome: :left, to: [2, 0] }] })
    result, = explore(rows, truth: with(rows, [2, 5], '#'), explore_log: log, limit: 200)
    assert_includes result[:walls], { row: 2, col: 5 }, result.inspect
    assert_equal({ goal: [2, 0], next: [2, 0] }, result[:route])
    assert_equal false, result[:survey][:pending]
  end

  def test_an_untried_door_is_entered_by_walking_up_into_it
    rows = with(CLOSED, [3, 5], '#')
    door = [{ object: 226, cell: [3, 5], kind: :door, verified: true }]
    execution = registry.start('explore', state(x: 40, y: 96), {}, { grid: MapGrid.new(rows), objects: -> { door } })
    x, y = 40, 96
    room_id = 1
    submode = 7
    inputs = []
    300.times do
      current = Koholint::GameState.new(frame: 0, room_id:, map_id: room_id == 1 ? 0 : 16, x:, y:, hp: 24, dialog_state: 0, game_mode: 0x0B, game_submode: submode, milestone: :none)
      buttons = execution.next_input(current) or break
      inputs << buttons
      dx, dy = DELTA.fetch(buttons.first, [0, 0])
      cell = Koholint::Geometry.cell_for(x + dx + (7 * dx), y + dy + (7 * dy))
      submode = 2 if cell == [3, 5] && room_id == 1
      room_id = 5 if submode == 2 && inputs.count([]) > 10
      next if submode != 7 || cell.nil? || (rows[cell[0]][cell[1]] == '#' && cell != [3, 5])

      x += dx
      y += dy
    end
    assert_equal :new_place, execution.result[:stopped_by]
    result = execution.result(Koholint::GameState.new(frame: 0, room_id:, map_id: 16, x:, y:, hp: 24, dialog_state: 0, game_mode: 0x0B, game_submode: 7, milestone: :none))
    assert_equal({ sides: {}, doors: [{ row: 3, col: 5 }], pending: false }, result[:survey])
    assert_equal :door, result[:target][:kind], result.inspect
    assert_equal [4, 5, :up], result[:target].values_at(:row, :col, :direction)
    assert_includes inputs, []
  end

  def test_a_step_up_from_a_door_cell_is_not_a_frontier_and_a_room_change_inside_the_screen_is_a_door
    rows = with(CLOSED, [3, 5], '?')
    door = [{ object: 226, cell: [4, 5], kind: :door, verified: true }]
    result, = explore(rows, objects: -> { door }, explore_log: Koholint::ExploreLog.new, limit: 50)
    refute_equal({ kind: :frontier, row: 4, col: 5, direction: :up }, result[:target])
    execution = registry.start('explore', state, {}, { grid: MapGrid.new(with(CLOSED, [3, 5], '.')), objects: -> { door } })
    execution.next_input(state)
    3.times { execution.next_input(state(y: 79)) }
    execution.next_input(state(y: 70, room_id: 9))
    assert_equal [{ row: 5, col: 5, direction: :up, outcome: :left, to: [9, 0], kind: :door }], execution.result[:exits]
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

  def test_an_aim_direction_acts_as_the_hint_and_an_aimed_door_comes_first
    rows = with(CLOSED, [4, 7], '?', [1, 5], '?')
    result, = explore(rows, aim: { direction: :up }, limit: 3)
    assert_equal({ kind: :frontier, row: 2, col: 5, direction: :up }, result[:target])
    door = [{ object: 226, cell: [2, 2], kind: :door, verified: true }, { object: 226, cell: [5, 6], kind: :door, verified: true }]
    result, = explore(CLOSED, objects: -> { door }, limit: 2)
    assert_equal [6, 6], result[:target].values_at(:row, :col)
    result, = explore(CLOSED, objects: -> { door }, aim: { door: [2, 2] }, limit: 2)
    assert_equal [:door, 3, 2], result[:target].values_at(:kind, :row, :col)
  end

  def test_a_loop_break_route_skips_the_loops_places_so_two_places_cannot_alternate
    log = Koholint::ExploreLog.new
    log.absorb({ from: { room: 97, map: 0 }, survey: { sides: { left: [{ row: 3, col: 0 }] }, doors: [] },
                 exits: [{ row: 3, col: 9, direction: :right, outcome: :left, to: [98, 0] }, { row: 0, col: 4, direction: :up, outcome: :left, to: [81, 0] }] })
    log.absorb({ from: { room: 98, map: 0 }, survey: { sides: { down: [{ row: 7, col: 2 }] }, doors: [] }, exits: [{ row: 3, col: 0, direction: :left, outcome: :left, to: [97, 0] }] })
    log.absorb({ from: { room: 81, map: 0 }, survey: { sides: { up: [{ row: 0, col: 4 }] }, doors: [] }, exits: [{ row: 7, col: 4, direction: :down, outcome: :left, to: [97, 0] }] })
    assert_equal [[98, 0], [97, 0]], [log.route([97, 0])[:goal], log.route([98, 0])[:goal]], 'each place aims at the other'
    looped = [[97, 0], [98, 0]]
    assert_equal [[81, 0], [81, 0]], [log.route([97, 0], skip: looped)[:goal], log.route([98, 0], skip: looped)[:goal]]
    assert_equal({ goal: [81, 0], next: [97, 0], via: :left }, log.route([98, 0], skip: looped), 'a skipped place is still crossed')
  end

  def test_a_walk_and_an_explore_through_the_same_unrecognised_door_record_the_same_edge
    walk = { 'type' => 'action', 'frame' => 3, 'skill' => 'walk', 'result' => { 'skill' => 'walk', 'from' => { 'room' => 98, 'map' => 0, 'row' => 3, 'col' => 7 }, 'to' => { 'room' => 189, 'map' => 10, 'row' => 7, 'col' => 5 },
                                                                         'exit' => { 'row' => 3, 'col' => 7, 'direction' => 'up', 'walk_in' => true } } }
    explore = { 'type' => 'action', 'frame' => 4, 'skill' => 'explore', 'result' => { 'from' => { 'room' => 98, 'map' => 0, 'row' => 3, 'col' => 7 },
                                                                                  'exits' => [{ 'row' => 4, 'col' => 7, 'direction' => 'up', 'outcome' => 'left', 'to' => [189, 10], 'kind' => 'door' }] } }
    by_walk = Koholint::ExploreLog.from_events([walk])
    by_explore = Koholint::ExploreLog.from_events([explore])
    assert [by_walk, by_explore].all? { |log| log.door_edge?([98, 0], [3, 7]) }, 'the cell Link stood on when the door took him, as in run ab63-new-3'
    refute by_walk.door_edge?([98, 0], [2, 7])
  end

  def test_a_door_walked_through_that_is_no_door_object_is_no_frontier
    rows = with(CLOSED, [1, 5], '?')
    result, = explore(rows, limit: 3)
    assert_equal({ kind: :frontier, row: 2, col: 5, direction: :up }, result[:target])
    log = Koholint::ExploreLog.new
    log.absorb({ from: { room: 1, map: 0 }, exits: [{ row: 3, col: 5, direction: :up, outcome: :left, to: [189, 10], kind: :door }] })
    result, = explore(rows, explore_log: log, limit: 3)
    refute_equal({ kind: :frontier, row: 2, col: 5, direction: :up }, result[:target])
  end

  def test_a_route_goes_through_a_door_walked_before_that_is_no_door_object
    rows = with(CLOSED, [1, 5], '?')
    log = Koholint::ExploreLog.new
    log.absorb({ from: { room: 1, map: 0 }, survey: { sides: {}, doors: [] }, exits: [{ row: 3, col: 5, direction: :up, outcome: :left, to: [189, 10], kind: :door }] })
    result, = explore(rows, explore_log: log, limit: 3)
    assert_equal({ goal: [189, 10], next: [189, 10] }, result[:route])
    assert_equal({ kind: :door, row: 3, col: 5, direction: :up }, result[:target])
  end

  def test_least_visited_is_the_reachable_place_entered_least_nearest_first_outside_the_loop
    log = Koholint::ExploreLog.new
    log.absorb({ from: { room: 1, map: 0 }, exits: [{ row: 0, col: 5, direction: :up, outcome: :left, to: [2, 0] }, { row: 7, col: 5, direction: :down, outcome: :left, to: [4, 0] }] })
    log.absorb({ from: { room: 2, map: 0 }, exits: [{ row: 0, col: 5, direction: :up, outcome: :left, to: [3, 0] }] })
    log.absorb({ from: { room: 3, map: 0 }, exits: [{ row: 0, col: 5, direction: :up, outcome: :left, to: [5, 0] }] })
    [[1, 2], [2, 1], [1, 4], [4, 1], [1, 2], [2, 1]].each { |from, to| log.note({ from: { room: from, map: 0 }, to: { room: to, map: 0 } }) }
    assert_equal({ goal: [3, 0], next: [2, 0], via: :up }, log.least_visited([1, 0]), 'nearest among the least entered')
    assert_equal [5, 0], log.least_visited([1, 0], avoid: [[3, 0]])[:goal]
    assert_equal [4, 0], log.least_visited([1, 0], avoid: [[3, 0], [5, 0]])[:goal]
    assert_nil log.least_visited([1, 0], avoid: [[2, 0], [3, 0], [4, 0], [5, 0]])
  end

  def test_an_aimed_place_is_routed_to_before_local_untried_exits
    rows = with(CLOSED, [7, 5], '.', [0, 5], '.')
    log = Koholint::ExploreLog.new
    log.absorb({ from: { room: 1, map: 0 }, exits: [{ row: 0, col: 5, direction: :up, outcome: :left, to: [3, 0] }, { row: 7, col: 5, direction: :down, outcome: :left, to: [2, 0] }] })
    log.absorb({ from: { room: 3, map: 0 }, exits: [{ row: 7, col: 5, direction: :down, outcome: :left, to: [1, 0] }], survey: { sides: { down: [{ row: 7, col: 5 }] }, doors: [] } })
    assert_equal({ 1 => 0, 2 => 1, 3 => 1 }, log.hops([1, 0]).transform_keys(&:first))
    assert_equal({ goal: [3, 0], next: [3, 0], via: :up }, log.route([1, 0], goal: [3, 0]))
    result, = explore(rows, exits: [[[0, 5], :up]], explore_log: log, aim: { place: [3, 0] })
    assert_equal({ goal: [3, 0], next: [3, 0] }, result[:route])
    assert_equal({ kind: :exit, row: 0, col: 5, direction: :up }, result[:target])
  end

  def test_a_clearable_object_here_comes_before_an_aimed_place_and_keeps_the_place_pending
    require 'koholint/learn'
    rows = with(CLOSED, [0, 5], '.')
    log = Koholint::ExploreLog.new
    log.absorb({ from: { room: 1, map: 0 }, exits: [{ row: 0, col: 5, direction: :up, outcome: :left, to: [3, 0] }] })
    log.absorb({ from: { room: 3, map: 0 }, exits: [{ row: 7, col: 5, direction: :down, outcome: :left, to: [1, 0] }], survey: { sides: { down: [{ row: 7, col: 5 }] }, doors: [] } })
    objects = Array.new(8) { Array.new(10, 0) }.tap { |grid| grid[4][9] = 92 }
    composite = Koholint::Skills::Composite.new(Koholint::Learn.hypothesis(gain: { item: 1, frame: 1 }, object: 92, run: 'r'))
    @registry = Koholint::Skills::Registry.default(extra: [composite])
    result, = explore(rows, exits: [[[0, 5], :up]], explore_log: log, aim: { place: [3, 0] }, room_objects: -> { objects }, held: [1], limit: 1)
    assert_equal({ kind: :frontier, row: 4, col: 8, direction: :right }, result[:target])
    assert result[:survey][:pending]
    log.absorb({ from: { room: 1, map: 0 }, clears: [{ target: { row: 4, col: 9 }, effect: false }] })
    assert_equal [[4, 9]], log.failed_clears([1, 0])
    result, = explore(rows, exits: [[[0, 5], :up]], explore_log: log, aim: { place: [3, 0] }, room_objects: -> { objects }, held: [1], limit: 1)
    assert_equal({ kind: :exit, row: 0, col: 5, direction: :up }, result[:target], 'a failed clear is no longer a frontier')
    refute result[:survey][:pending]
    @registry = nil
    result, = explore(rows, exits: [[[0, 5], :up]], explore_log: log, aim: { place: [3, 0] }, room_objects: -> { objects }, held: [1], limit: 1)
    assert_equal({ kind: :exit, row: 0, col: 5, direction: :up }, result[:target])
  end

  def test_frontiers_behind_an_object_cleared_in_this_call_come_before_an_aimed_place
    rows = with(CLOSED, [0, 5], '.', [4, 8], '?')
    log = Koholint::ExploreLog.new
    log.absorb({ from: { room: 1, map: 0 }, exits: [{ row: 0, col: 5, direction: :up, outcome: :left, to: [3, 0] }], survey: { sides: { up: [{ row: 0, col: 5 }] }, doors: [] } })
    log.absorb({ from: { room: 3, map: 0 }, exits: [{ row: 7, col: 5, direction: :down, outcome: :left, to: [1, 0] }], survey: { sides: { down: [{ row: 7, col: 5 }] }, doors: [] } })
    cleared = Struct.new(:uses) do
      def cells = {}
      def active? = false
      def start(*) = nil
    end
    original = Koholint::Skills::Clearing.method(:of)
    targets = [[{ effect: true }], []].map do |uses|
      Koholint::Skills::Clearing.define_singleton_method(:of) { |_context| cleared.new(uses) }
      result, = explore(rows, exits: [[[0, 5], :up]], explore_log: log, aim: { place: [3, 0] }, limit: 1)
      result[:target][:kind]
    end
    assert_equal %i[frontier exit], targets
  ensure
    Koholint::Skills::Clearing.define_singleton_method(:of, original) if original
  end

  def test_a_route_whose_first_exit_cannot_be_reached_from_link_takes_the_next_route
    rows = with(CLOSED, [7, 5], '.', [0, 5], '.', [1, 5], '#')
    log = Koholint::ExploreLog.new
    log.absorb({ from: { room: 1, map: 0 }, exits: [{ row: 0, col: 5, direction: :up, outcome: :left, to: [3, 0] }, { row: 7, col: 5, direction: :down, outcome: :left, to: [2, 0] }] })
    log.absorb({ from: { room: 3, map: 0 }, exits: [{ row: 3, col: 9, direction: :right, outcome: :left, to: [4, 0] }] })
    log.absorb({ from: { room: 2, map: 0 }, exits: [{ row: 3, col: 9, direction: :right, outcome: :left, to: [4, 0] }] })
    assert_equal [{ via: :up, to: [3, 0] }, { via: :right, to: [4, 0] }], log.path([1, 0], goal: [4, 0])
    assert_equal({ goal: [4, 0], next: [2, 0], via: :down }, log.route([1, 0], goal: [4, 0], avoid: [:up]))
    result, = explore(rows, exits: [[[7, 5], :down]], explore_log: log, aim: { place: [4, 0] })
    assert_equal({ goal: [4, 0], next: [2, 0] }, result[:route])
    assert_equal({ kind: :exit, row: 7, col: 5, direction: :down }, result[:target])
  end

  def test_when_no_hop_of_the_route_has_a_reachable_exit_explore_stops_at_once_and_lists_the_skipped_exits
    rows = with(CLOSED, [0, 5], '.', [1, 5], '#', [7, 5], '.', [6, 5], '#')
    log = Koholint::ExploreLog.new
    log.absorb({ from: { room: 1, map: 0 }, exits: [{ row: 0, col: 5, direction: :up, outcome: :left, to: [3, 0] }, { row: 7, col: 5, direction: :down, outcome: :left, to: [2, 0] }] })
    log.absorb({ from: { room: 3, map: 0 }, exits: [{ row: 3, col: 9, direction: :right, outcome: :left, to: [4, 0] }] })
    log.absorb({ from: { room: 2, map: 0 }, exits: [{ row: 3, col: 9, direction: :right, outcome: :left, to: [4, 0] }] })
    result, inputs = explore(rows, explore_log: log, aim: { place: [4, 0] }, limit: 1000)
    assert_equal [:no_frontier, %i[up down]], result.values_at(:stopped_by, :unreachable)
    assert_operator inputs.size, :<, 20
  end

  def test_a_pocket_found_by_an_aimed_route_is_left_the_way_link_came_and_routed_around
    log = Koholint::ExploreLog.new
    log.absorb({ from: { room: 2, map: 0 }, exits: [{ row: 0, col: 9, direction: :up, outcome: :left, to: [1, 0] }, { row: 3, col: 9, direction: :right, outcome: :left, to: [3, 0] }], survey: { sides: {}, doors: [] } })
    log.absorb({ from: { room: 3, map: 0 }, exits: [{ row: 0, col: 4, direction: :up, outcome: :left, to: [4, 0] }], survey: { sides: {}, doors: [] } })
    log.absorb({ from: { room: 4, map: 0 }, exits: [{ row: 3, col: 9, direction: :right, outcome: :left, to: [1, 0] }], survey: { sides: {}, doors: [] } })
    log.absorb({ from: { room: 7, map: 0 }, exits: [{ row: 7, col: 0, direction: :left, outcome: :left, to: [1, 0] }], survey: { sides: {}, doors: [] } })
    log.absorb({ from: { room: 5, map: 0 }, exits: [{ row: 7, col: 5, direction: :down, outcome: :left, to: [1, 0] }], survey: { sides: {}, doors: [] } })
    assert_equal [1, 0], log.route([2, 0], goal: [5, 0])[:next]
    stuck = { skill: 'explore', from: { room: 1, map: 0, row: 7, col: 9 }, stopped_by: 'no_frontier', cells_walked: 0, route: { goal: [5, 0], next: [5, 0] }, dead_end: true }
    2.times { log.absorb(stuck) }
    assert_includes %i[down right], log.pocket_side([1, 0], [7, 9])
    assert_equal [1, 0], log.route([2, 0], goal: [5, 0])[:next], 'one visit blocked (an urchin, an enemy) is not a pocket yet'
    log.note({ skill: 'walk', params: { direction: :up }, from: { room: 2, map: 0, row: 0, col: 9 }, to: { room: 1, map: 0, row: 7, col: 9 } })
    log.absorb(stuck.merge(stopped_by: 'known_place', cells_walked: 1))
    assert_equal [[3, 0], [4, 0], [1, 0], [5, 0]], log.path([2, 0], goal: [5, 0]).map { |hop| hop[:to] }
    assert_nil log.route([7, 0], goal: [5, 0])
    pocket = with(CLOSED, [7, 9], '.', [6, 9], '#', [7, 8], '#')
    result, = explore(pocket, start: [148, 124], exits: [[[7, 9], :down], [[7, 9], :right]], explore_log: log, aim: { place: [5, 0] })
    assert_equal [:exit, 7, 9], result[:target].values_at(:kind, :row, :col)
  end

  def test_a_way_back_never_crossed_is_dropped_when_an_explore_finds_no_exit_for_it
    log = Koholint::ExploreLog.new
    log.absorb({ from: { room: 5, map: 0 }, exits: [{ row: 7, col: 5, direction: :down, outcome: :left, to: [1, 0] }] })
    log.absorb({ from: { room: 6, map: 0 }, exits: [{ row: 3, col: 9, direction: :right, outcome: :left, to: [1, 0] }] })
    assert_equal [1, 0], log.route([6, 0], goal: [5, 0])[:next]
    rows = with(CLOSED, [0, 5], '.', [1, 5], '#')
    result, = explore(rows, explore_log: log, aim: { place: [5, 0] }, limit: 50)
    assert_equal [:no_frontier, [:up], true], result.values_at(:stopped_by, :unreachable, :dead_end)
    failed = result.merge(skill: 'explore', from: { room: 1, map: 0, row: 4, col: 5 })
    2.times { log.absorb(failed) }
    assert_equal [1, 0], log.route([6, 0], goal: [5, 0])[:next], 'one visit cannot tell a ledge from a passing block'
    log.note({ skill: 'walk', params: { direction: :right }, from: { room: 6, map: 0, row: 3, col: 9 }, to: { room: 1, map: 0, row: 3, col: 0 } })
    log.absorb(failed)
    assert_nil log.route([6, 0], goal: [5, 0])
    log.absorb({ from: { room: 6, map: 0 }, unreachable: ['right'] })
    assert_equal [1, 0], log.route([6, 0], goal: [1, 0])[:next]
  end

  def test_the_side_a_place_was_entered_by_counts_as_left
    log = Koholint::ExploreLog.new
    log.absorb({ from: { room: 1, map: 0 }, exits: [{ row: 7, col: 5, direction: :down, outcome: :left, to: [2, 0] }] })
    assert log.side_left?([2, 0], :up)
    refute log.side_left?([2, 0], :down)
    assert log.side_left?([1, 0], :down)
    refute log.surveyed?([2, 0])
  end

  def test_a_place_never_surveyed_is_explored_before_leaving_for_another_place
    rows = with(CLOSED, [0, 5], '.', [4, 7], '?')
    log = Koholint::ExploreLog.new
    log.absorb({ from: { room: 1, map: 0 }, exits: [{ row: 0, col: 5, direction: :up, outcome: :left, to: [3, 0] }] })
    log.absorb({ from: { room: 3, map: 0 }, survey: { sides: { down: [{ row: 7, col: 5 }] }, doors: [], pending: true } })
    result, = explore(rows, truth: with(rows, [4, 7], '#'), exits: [[[0, 5], :up]], explore_log: log, limit: 200)
    assert_includes result[:walls], { row: 4, col: 7 }, result.inspect
    refute_equal :known_place, result[:stopped_by], result.inspect
  end

  def test_a_straight_walk_across_a_border_records_both_sides_in_its_direction
    log = Koholint::ExploreLog.new
    log.note({ skill: 'walk', params: { direction: 'down', cells: 2 }, from: { room: 208, map: 0, row: 7, col: 2 }, to: { room: 224, map: 0, row: 7, col: 2 } })
    assert log.side_left?([208, 0], :down)
    assert log.side_left?([224, 0], :up)
    assert_equal [[208, 0]], log.hops([224, 0]).keys - [[224, 0]]
  end

  def test_a_walk_or_goto_into_a_door_records_the_door_and_no_side
    log = Koholint::ExploreLog.new
    log.absorb({ from: { room: 161, map: 0 }, stopped_by: :no_frontier, cells_walked: 5, survey: { sides: { up: [{ row: 0, col: 5 }] }, doors: [{ row: 3, col: 5 }], pending: nil } })
    log.note({ skill: 'goto', params: { row: 0, col: 5 }, from: { room: 161, map: 0, row: 4, col: 5 }, to: { room: 178, map: 18, row: 7, col: 5 }, exit: { row: 4, col: 5, direction: :up } })
    assert log.door_tried?([161, 0], [3, 5])
    refute log.side_left?([161, 0], :up)
    refute log.side_left?([178, 18], :down)
    assert_equal [[178, 18]], log.hops([161, 0]).keys - [[161, 0]]
  end

  def test_a_house_left_by_its_bottom_door_assumes_no_side_of_the_place_outside
    log = Koholint::ExploreLog.new
    log.note({ skill: 'walk', params: { direction: 'down', cells: 1 }, from: { room: 178, map: 18, row: 7, col: 4 }, to: { room: 161, map: 0, row: 3, col: 5 }, exit: { row: 7, col: 4, direction: :down, walk_in: true } })
    log.absorb({ from: { room: 167, map: 16 }, exits: [{ row: 7, col: 5, direction: :down, outcome: :left, to: [161, 0], walk_in: true }] })
    assert log.side_left?([178, 18], :down)
    assert log.side_left?([167, 16], :down)
    refute log.side_left?([161, 0], :up)
  end

  def test_a_goto_or_a_walk_that_started_on_a_border_cell_records_no_wrong_side
    log = Koholint::ExploreLog.new
    log.note({ skill: 'goto', params: {}, from: { room: 1, map: 0, row: 4, col: 9 }, to: { room: 2, map: 0, row: 4, col: 4 } })
    log.note({ skill: 'walk', params: { cells: 2 }, from: { room: 1, map: 0, row: 4, col: 9 }, to: { room: 2, map: 0, row: 4, col: 4 } })
    refute log.side_left?([1, 0], :right)
    refute log.side_left?([1, 0], :down)
    refute log.side_left?([2, 0], :left)
  end

  def test_a_place_left_after_a_few_cells_stays_unexplored_until_a_longer_visit
    log = Koholint::ExploreLog.new
    thin = { from: { room: 240, map: 0 }, stopped_by: :known_place, cells_walked: 1, survey: { sides: { up: [{ row: 0, col: 1 }] }, doors: [], pending: false } }
    log.absorb(thin)
    assert log.untried?([240, 0])
    refute log.surveyed?([240, 0])
    log.absorb(thin.merge(stopped_by: :no_frontier, cells_walked: 9))
    refute log.untried?([240, 0])
    assert log.surveyed?([240, 0])
    log.absorb(thin)
    refute log.untried?([240, 0])
  end

  def test_a_landing_cell_that_leads_nowhere_is_not_routed_into
    log = Koholint::ExploreLog.new
    log.absorb({ from: { room: 208, map: 0 }, exits: [{ row: 0, col: 9, direction: :up, outcome: :left, to: [192, 0] }, { row: 5, col: 9, direction: :right, outcome: :left, to: [209, 0] }],
                 survey: { sides: {}, doors: [], pending: false } })
    log.absorb({ from: { room: 192, map: 0 }, exits: [{ row: 0, col: 5, direction: :up, outcome: :left, to: [176, 0] }], survey: { sides: {}, doors: [], pending: false } })
    log.absorb({ from: { room: 209, map: 0 }, exits: [{ row: 2, col: 9, direction: :right, outcome: :left, to: [210, 0] }], survey: { sides: {}, doors: [], pending: false } })
    log.absorb({ from: { room: 210, map: 0 }, survey: { sides: { up: [{ row: 0, col: 3 }] }, doors: [], pending: true } })
    log.absorb({ from: { room: 176, map: 0 }, survey: { sides: { up: [{ row: 0, col: 3 }] }, doors: [], pending: true } })
    assert_equal [192, 0], log.route([208, 0])[:next]
    log.absorb({ from: { room: 192, map: 0, row: 7, col: 9 }, stopped_by: :no_frontier, cells_walked: 0 })
    assert_equal [209, 0], log.route([208, 0])[:next]
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

  # 69/0 in the 21b0 forks: the only way to the place's untried work pushes a rock the grid reads as open, and the game answers with a
  # dialogue. Without the barred edge the place stayed untried and every explore from next door came back to push it again.
  def test_a_dialogue_the_game_opens_mid_walk_bars_the_edge_so_the_place_reads_as_exhausted
    rows = with(CLOSED, *(1..6).flat_map { |row| [[row, 3], '#'] }, [3, 3], '.', [3, 0], '.', [7, 6], '.')
    log = Koholint::ExploreLog.new
    log.absorb({ from: { room: 1, map: 0 }, exits: [{ row: 3, col: 0, direction: :left, outcome: :left, to: [2, 0] }] })
    assert_equal({ goal: PLACE, next: PLACE, via: :right }, log.route([2, 0]))
    result, = explore(rows, rocks: [[3, 3]], start: Koholint::Geometry.center_of(3, 1), explore_log: log)
    assert_equal :dialogue, result[:stopped_by]
    assert_equal({ kind: :exit, row: 7, col: 6, direction: :down }, result[:target])
    assert_includes result[:blocked_edges], { row: 3, col: 2, direction: :right }
    refute result.dig(:survey, :pending)
    log.absorb(result)
    refute log.untried?(PLACE)
    assert_nil log.route([2, 0])
  end

  def test_a_dialogue_that_opens_while_link_walks_bars_nothing
    rows = with(CLOSED, *(1..6).flat_map { |row| [[row, 3], '#'] }, [3, 3], '.', [3, 0], '.', [7, 6], '.')
    log = Koholint::ExploreLog.new
    log.absorb({ from: { room: 1, map: 0 }, exits: [{ row: 3, col: 0, direction: :left, outcome: :left, to: [2, 0] }] })
    result, = explore(rows, callouts: [[3, 4]], start: Koholint::Geometry.center_of(3, 1), explore_log: log)
    assert_equal :dialogue, result[:stopped_by]
    assert_empty result[:blocked_edges]
    assert result.dig(:survey, :pending)
    log.absorb(result)
    assert log.untried?(PLACE)
  end

  def test_a_dialogue_the_game_opens_on_an_outward_step_bars_that_edge
    rows = with(CLOSED, [3, 3], '?')
    result, = explore(rows, truth: with(CLOSED, [3, 3], '.'), rocks: [[3, 3]], start: Koholint::Geometry.center_of(3, 2))
    assert_equal :dialogue, result[:stopped_by]
    assert_equal({ kind: :frontier, row: 3, col: 2, direction: :right }, result[:target])
    assert_equal [{ row: 3, col: 2, direction: :right }], result[:blocked_edges]
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

  def test_a_walked_room_whose_frontiers_are_walls_stalls_instead_of_probing_them_all
    rows = CLOSED.map { |line| line.tr('#', '?') }
    log = Koholint::ExploreLog.new
    (1..6).to_a.product((1..8).to_a).each { |cell| log.walk(PLACE, cell) }
    result, inputs = explore(rows, truth: CLOSED, explore_log: log)
    assert_equal :stalled, result[:stopped_by]
    assert_equal 3, result[:legs]
    assert_equal 3, result[:walls].size
    assert_nil result[:blocked_at]
    assert_operator inputs.size, :<, 200
    log.absorb(result)
    again, = explore(rows, truth: CLOSED, explore_log: log)
    assert_equal :stalled, again[:stopped_by]
    assert_empty again[:walls] & result[:walls]
  end

  def test_a_new_cell_between_wall_probes_resets_the_stall
    rows = with(CLOSED.map { |line| line.tr('#', '?') }, [4, 7], '?')
    log = Koholint::ExploreLog.new
    ((1..6).to_a.product((1..8).to_a) - [[4, 7]]).each { |cell| log.walk(PLACE, cell) }
    result, = explore(rows, truth: CLOSED, explore_log: log)
    assert_operator result[:legs], :>, 3
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
