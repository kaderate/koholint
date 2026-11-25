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

  class HoledMapGrid < MapGrid
    def initialize(rows, margin)
      super(rows)
      @margin = margin
    end

    def hole_margin = @margin
  end

  def test_a_step_into_a_cell_beside_a_hole_is_no_frontier
    rows = with(CLOSED, [4, 7], '?')
    result, = explore(rows, grid: HoledMapGrid.new(rows, [[4, 7]]))
    assert_equal :no_frontier, result[:stopped_by]
    assert_nil result[:target]
    refute_includes result[:crossed], [4, 6, :right]
  end

  def test_a_leg_to_a_frontier_never_plans_across_the_margin_from_any_cell
    rows = with(CLOSED, [1, 6], '#', [2, 6], '#', [4, 6], '#', [5, 6], '#', [6, 6], '#')
    planner = Koholint::Navigation::Planner.new(grid: HoledMapGrid.new(rows, [[3, 6]]), ledger: nil, place: PLACE, mode: :free_only)
    [[4, 5], [3, 5]].each do |cell|
      x, y = Koholint::Geometry.center_of(*cell)
      leg = ->(cross_margin) { Koholint::Skills::Explore::Leg.new(skill: 'goto', params: { row: 5, col: 8 }, state: state(x:, y:), target: [5, 8], planner:, cross_margin:) }
      assert_equal 0, leg.(false).result[:path_length], cell.inspect
      assert leg.(false).result[:cause], cell.inspect
      assert_operator leg.(true).result[:path_length], :>, 0, cell.inspect
    end
  end

  def test_a_frontier_reached_only_past_a_hole_is_not_a_target
    rows = with(CLOSED, [1, 6], '#', [2, 6], '#', [4, 6], '#', [5, 6], '#', [6, 6], '#', [5, 8], '?')
    plain, = explore(rows, limit: 400)
    assert_equal :frontier, plain[:target]&.dig(:kind), plain.inspect
    holed, = explore(rows, grid: HoledMapGrid.new(rows, [[3, 6]]), limit: 400)
    assert_nil holed[:target], holed.inspect
    assert_equal :no_frontier, holed[:stopped_by]
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

  def test_a_place_whose_last_card_lists_an_uncatalogued_type_never_aimed_at_is_untried_work
    events = [{ 'type' => 'action', 'skill' => 'explore', 'result' => { from: { room: 1, map: 0 }, survey: { sides: {}, doors: [] },
                                                                          exits: [{ row: 7, col: 5, direction: :down, outcome: :left, to: [2, 0] }] } },
              { 'type' => 'action', 'skill' => 'explore', 'result' => { from: { room: 2, map: 0 }, survey: { sides: {}, doors: [] } } }]
    assert_nil Koholint::ExploreLog.from_events(events).route([1, 0])
    events << { 'type' => 'place_card', 'place' => [2, 0], 'unknown' => [{ 'type' => 9, 'cell' => [3, 3] }] }
    assert_nil Koholint::ExploreLog.from_events(events).route([1, 0]), 'type 9 is catalogued since the card'
    events << { 'type' => 'place_card', 'place' => [2, 0], 'unknown' => [{ 'type' => 79, 'cell' => [3, 3] }, { 'type' => 79, 'cell' => [4, 3] }] }
    refute Koholint::ExploreLog.from_events(events).work?([2, 0]), 'one look cannot tell a still thing from a roaming one'
    events << { 'type' => 'place_card', 'place' => [2, 0], 'unknown' => [{ 'type' => 99, 'cell' => [5, 5] }, { 'type' => 79, 'cell' => [4, 3] }] }
    log = Koholint::ExploreLog.from_events(events)
    assert_equal [79], log.unmet([2, 0]), 'type 99 roams in by the second look'
    assert_equal [2, 0], log.route([1, 0])[:goal]
    assert log.work?([2, 0])
    refute log.untried?([2, 0])
    events << { 'type' => 'action', 'skill' => 'talk_to', 'result' => { 'skill' => 'talk_to', 'from' => { 'room' => 2, 'map' => 0 }, 'target_type' => 79, 'stopped_by' => 'no_path' } }
    log = Koholint::ExploreLog.from_events(events)
    assert log.met?([2, 0], 79)
    assert_nil log.route([1, 0])
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
    log.absorb({ from: { room: 2, map: 1 }, exits: [{ row: 0, col: 9, direction: :up, outcome: :left, to: [1, 0] }, { row: 3, col: 9, direction: :right, outcome: :left, to: [3, 1] }], survey: { sides: {}, doors: [] } })
    log.absorb({ from: { room: 3, map: 1 }, exits: [{ row: 0, col: 4, direction: :up, outcome: :left, to: [4, 1] }], survey: { sides: {}, doors: [] } })
    log.absorb({ from: { room: 4, map: 1 }, exits: [{ row: 3, col: 9, direction: :right, outcome: :left, to: [1, 0] }], survey: { sides: {}, doors: [] } })
    log.absorb({ from: { room: 7, map: 1 }, exits: [{ row: 7, col: 0, direction: :left, outcome: :left, to: [1, 0] }], survey: { sides: {}, doors: [] } })
    log.absorb({ from: { room: 5, map: 1 }, exits: [{ row: 7, col: 5, direction: :down, outcome: :left, to: [1, 0] }], survey: { sides: {}, doors: [] } })
    assert_equal [1, 0], log.route([2, 1], goal: [5, 1])[:next]
    stuck = { skill: 'explore', from: { room: 1, map: 0, row: 7, col: 9 }, stopped_by: 'no_frontier', cells_walked: 0, route: { goal: [5, 1], next: [5, 1] }, dead_end: true }
    2.times { log.absorb(stuck) }
    assert_includes %i[down right], log.pocket_side([1, 0], [7, 9])
    assert_equal [1, 0], log.route([2, 1], goal: [5, 1])[:next], 'one visit blocked (an urchin, an enemy) is not a pocket yet'
    log.note({ skill: 'walk', params: { direction: :up }, from: { room: 2, map: 1, row: 0, col: 9 }, to: { room: 1, map: 0, row: 7, col: 9 } })
    log.absorb(stuck.merge(stopped_by: 'known_place', cells_walked: 1))
    assert_equal [[3, 1], [4, 1], [1, 0], [5, 1]], log.path([2, 1], goal: [5, 1]).map { |hop| hop[:to] }
    assert_nil log.route([7, 1], goal: [5, 1])
    pocket = with(CLOSED, [7, 9], '.', [6, 9], '#', [7, 8], '#')
    result, = explore(pocket, start: [148, 124], exits: [[[7, 9], :down], [[7, 9], :right]], explore_log: log, aim: { place: [5, 1] })
    assert_equal [:exit, 7, 9], result[:target].values_at(:kind, :row, :col)
  end

  def test_a_landing_whose_only_reachable_way_on_is_the_side_link_came_in_by_is_a_dead_end
    log = Koholint::ExploreLog.new
    log.absorb({ from: { room: 1, map: 0 }, exits: [{ row: 3, col: 9, direction: :right, outcome: :left, to: [2, 0] }, { row: 3, col: 0, direction: :left, outcome: :left, to: [0, 0] }] })
    log.absorb({ from: { room: 2, map: 0 }, survey: { sides: { up: [{ row: 0, col: 3 }] }, doors: [], pending: true } })
    log.absorb({ from: { room: 0, map: 0 }, exits: [{ row: 3, col: 9, direction: :right, outcome: :left, to: [1, 0] }, { row: 7, col: 5, direction: :down, outcome: :left, to: [16, 0] }] })
    log.absorb({ from: { room: 16, map: 0 }, survey: { sides: { down: [{ row: 7, col: 4 }] }, doors: [], pending: true } })
    assert_equal({ goal: [2, 0], next: [2, 0], via: :right }, log.route([1, 0]))
    pocket = with(CLOSED, [3, 0], '.', [3, 9], '.', [1, 2], '#', [2, 2], '#', [3, 2], '#', [4, 2], '#', [5, 2], '#', [6, 2], '#')
    result, = explore(pocket, start: Koholint::Geometry.center_of(3, 0), exits: [[[3, 0], :left]], explore_log: log)
    assert_equal [:exit, 3, 0, :left, true], result[:target].values_at(:kind, :row, :col, :direction) + [result[:dead_end]]
    2.times { log.absorb(result.merge(skill: 'explore', from: { room: 1, map: 0, row: 3, col: 0 })) }
    assert_equal :left, log.pocket_side([1, 0], [3, 0])
    log.absorb({ from: { room: 16, map: 0 }, exits: [{ row: 3, col: 9, direction: :right, outcome: :left, to: [2, 0] }] })
    open = with(pocket, [7, 1], '.')
    aimed, = explore(open, start: Koholint::Geometry.center_of(3, 0), exits: [[[3, 0], :left]], explore_log: log, aim: { place: [2, 0] })
    assert_nil aimed[:dead_end], 'an aimed route is taken before the work here is weighed, so it proves no dead end'
  end

  def test_least_visited_skips_a_place_whose_landing_from_here_is_a_pocket
    log = Koholint::ExploreLog.new
    log.absorb({ from: { room: 2, map: 1 }, exits: [{ row: 0, col: 9, direction: :up, outcome: :left, to: [1, 0] }, { row: 3, col: 9, direction: :right, outcome: :left, to: [3, 1] }], survey: { sides: {}, doors: [] } })
    others = [[3, 1]]
    assert_equal [1, 0], log.least_visited([2, 1], avoid: others)[:goal]
    stuck = { skill: 'explore', from: { room: 1, map: 0, row: 7, col: 9 }, stopped_by: 'no_frontier', cells_walked: 0, route: { goal: [3, 1], next: [2, 1] }, dead_end: true }
    2.times { log.absorb(stuck) }
    assert log.pocket_side([1, 0], [7, 9])
    log.note({ skill: 'walk', params: { direction: :up }, from: { room: 2, map: 1, row: 0, col: 9 }, to: { room: 1, map: 0, row: 7, col: 9 } })
    assert_nil log.least_visited([2, 1], avoid: others)
  end

  def test_a_way_back_never_crossed_is_dropped_when_an_explore_finds_no_exit_for_it
    log = Koholint::ExploreLog.new
    log.absorb({ from: { room: 5, map: 1 }, exits: [{ row: 7, col: 5, direction: :down, outcome: :left, to: [1, 0] }] })
    log.absorb({ from: { room: 6, map: 1 }, exits: [{ row: 3, col: 9, direction: :right, outcome: :left, to: [1, 0] }] })
    assert_equal [1, 0], log.route([6, 1], goal: [5, 1])[:next]
    rows = with(CLOSED, [0, 5], '.', [1, 5], '#')
    result, = explore(rows, explore_log: log, aim: { place: [5, 1] }, limit: 50)
    assert_equal [:no_frontier, [:up], true], result.values_at(:stopped_by, :unreachable, :dead_end)
    failed = result.merge(skill: 'explore', from: { room: 1, map: 0, row: 4, col: 5 })
    2.times { log.absorb(failed) }
    assert_equal [1, 0], log.route([6, 1], goal: [5, 1])[:next], 'one visit cannot tell a ledge from a passing block'
    log.note({ skill: 'walk', params: { direction: :right }, from: { room: 6, map: 1, row: 3, col: 9 }, to: { room: 1, map: 0, row: 3, col: 0 } })
    log.absorb(failed)
    assert_nil log.route([6, 1], goal: [5, 1])
    log.absorb({ from: { room: 6, map: 1 }, unreachable: ['right'] })
    assert_equal [1, 0], log.route([6, 1], goal: [1, 0])[:next]
  end

  def test_a_first_crossing_away_from_the_neighbour_screen_is_a_puzzle_and_invents_no_way_back
    log = Koholint::ExploreLog.new
    up = { from: { room: 81, map: 0 }, exits: [{ row: 0, col: 3, direction: :up, outcome: :left, to: [99, 0] }] }
    log.absorb(up, frame: 75199)
    refute log.side_left?([99, 0], :down), 'the way back of a surprise is not assumed'
    fresh = log.new_puzzles(place: [99, 0], cell: [7, 3])
    assert_equal [['unexpected_arrival', { to: [65, 0], source: 'neighbour' }, { to: [99, 0], landing: [7, 3] }]], fresh.map { |p| p.values_at(:kind, :expected, :observed) }
    assert_empty log.new_puzzles
    log.absorb(up, frame: 80000)
    assert_empty log.new_puzzles, 'the same arrival again is no new puzzle'
    assert_equal [75199, 80000], log.puzzles([81, 0]).first[:frames]
    log.absorb({ from: { room: 81, map: 0 }, exits: [{ row: 7, col: 5, direction: :down, outcome: :left, to: [97, 0] }] })
    assert log.side_left?([97, 0], :up), 'a crossing to the neighbour screen still assumes its way back'
  end

  def test_a_second_destination_through_the_same_way_is_kept_as_a_contradiction_and_routed_last
    log = Koholint::ExploreLog.new
    log.absorb({ from: { room: 5, map: 1 }, exits: [{ row: 3, col: 9, direction: :right, outcome: :left, to: [6, 1] }] }, frame: 10)
    log.absorb({ from: { room: 5, map: 1 }, exits: [{ row: 3, col: 9, direction: :right, outcome: :left, to: [7, 1] }] }, frame: 20)
    assert_equal [['contradiction', { to: [6, 1], source: 'observed' }, { to: [7, 1] }, [20]]], log.new_puzzles.map { |p| p.values_at(:kind, :expected, :observed, :frames) }
    assert log.contradicted?([5, 1], :right)
    log.absorb({ from: { room: 5, map: 1 }, exits: [{ row: 0, col: 4, direction: :up, outcome: :left, to: [8, 1] }] })
    log.absorb({ from: { room: 8, map: 1 }, exits: [{ row: 3, col: 9, direction: :right, outcome: :left, to: [7, 1] }] })
    assert_equal [[8, 1], [7, 1]], log.path([5, 1], goal: [7, 1]).map { |hop| hop[:to] }, 'a way that led to two places is taken only without another route'
    assert_equal [[7, 1]], log.path([8, 1], goal: [7, 1]).map { |hop| hop[:to] }
  end

  def test_an_assumed_way_back_that_leads_elsewhere_is_refuted
    log = Koholint::ExploreLog.new
    log.absorb({ from: { room: 5, map: 1 }, exits: [{ row: 7, col: 5, direction: :down, outcome: :left, to: [6, 1] }] })
    assert log.side_left?([6, 1], :up)
    log.absorb({ from: { room: 6, map: 1 }, exits: [{ row: 0, col: 5, direction: :up, outcome: :left, to: [9, 1] }] }, frame: 40)
    assert_equal [['refuted', { to: [5, 1], source: 'reverse' }, { to: [9, 1] }]], log.new_puzzles.map { |p| p.values_at(:kind, :expected, :observed) }
    refute log.contradicted?([6, 1], :up), 'an assumption is no observation'
  end

  def test_a_way_back_assumed_from_another_map_predicts_nothing
    log = Koholint::ExploreLog.new
    log.absorb({ from: { room: 178, map: 18 }, exits: [{ row: 7, col: 4, direction: :down, outcome: :left, to: [161, 0] }] })
    assert_equal [178, 18], log.route([161, 0], goal: [178, 18])[:next], 'the way back is still routed'
    log.absorb({ from: { room: 161, map: 0 }, exits: [{ row: 0, col: 2, direction: :up, outcome: :left, to: [145, 0] }] })
    assert_empty log.new_puzzles
    log.absorb({ from: { room: 5, map: 0 }, exits: [{ row: 0, col: 4, direction: :up, outcome: :left, to: [165, 16] }] })
    log.absorb({ from: { room: 165, map: 16 }, exits: [{ row: 7, col: 4, direction: :down, outcome: :left, to: [166, 16] }] })
    assert_empty log.new_puzzles
  end

  def test_a_way_with_two_destinations_routes_to_the_one_seen_most
    log = Koholint::ExploreLog.new
    [[6, 1], [6, 1], [7, 1]].each_with_index { |to, n| log.absorb({ from: { room: 5, map: 1 }, exits: [{ row: 3, col: 9, direction: :right, outcome: :left, to: }] }, frame: n) }
    assert_equal [['contradiction', { to: [6, 1], source: 'observed' }]], log.new_puzzles.map { |p| p.values_at(:kind, :expected) }
    assert_equal [6, 1], log.route([5, 1], goal: [6, 1])[:next]
    assert_nil log.route([5, 1], goal: [7, 1])
  end

  def test_a_fork_between_a_crossing_and_its_puzzle_event_still_emits_the_puzzle
    crossing = { 'type' => 'action', 'frame' => 75199, 'skill' => 'explore', 'result' => { 'from' => { 'room' => 81, 'map' => 0 },
                                                                                        'exits' => [{ 'row' => 0, 'col' => 3, 'direction' => 'up', 'outcome' => 'left', 'to' => [99, 0] }] } }
    log = Koholint::ExploreLog.from_events([crossing])
    assert_equal ['unexpected_arrival-81-0-up'], log.new_puzzles(place: [99, 0], cell: [7, 3]).map { |p| p[:id] }
  end

  def test_a_rebuilt_log_emits_no_puzzle_again_and_keeps_the_traced_landing
    crossing = { 'type' => 'action', 'frame' => 75199, 'skill' => 'explore', 'result' => { 'from' => { 'room' => 81, 'map' => 0 },
                                                                                        'exits' => [{ 'row' => 0, 'col' => 3, 'direction' => 'up', 'outcome' => 'left', 'to' => [99, 0] }] } }
    traced = { 'type' => 'puzzle', 'frame' => 75210, 'id' => 'unexpected_arrival-81-0-up', 'observed' => { 'to' => [99, 0], 'landing' => [7, 3] } }
    log = Koholint::ExploreLog.from_events([crossing, traced])
    assert_empty log.new_puzzles(place: [99, 0], cell: [5, 5])
    assert_equal [7, 3], log.puzzles([81, 0]).first[:observed][:landing]
  end

  def test_the_side_a_place_was_entered_by_counts_as_left
    log = Koholint::ExploreLog.new
    log.absorb({ from: { room: 1, map: 0 }, exits: [{ row: 7, col: 5, direction: :down, outcome: :left, to: [17, 0] }] })
    assert log.side_left?([17, 0], :up)
    refute log.side_left?([17, 0], :down)
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
    log.absorb({ from: { room: 193, map: 0 }, exits: [{ row: 3, col: 0, direction: :left, outcome: :left, to: [192, 0] }] })
    log.absorb({ from: { room: 192, map: 0 }, exits: [{ row: 0, col: 5, direction: :up, outcome: :left, to: [176, 0] }], survey: { sides: {}, doors: [], pending: false } })
    log.absorb({ from: { room: 209, map: 0 }, exits: [{ row: 2, col: 9, direction: :right, outcome: :left, to: [210, 0] }], survey: { sides: {}, doors: [], pending: false } })
    log.absorb({ from: { room: 210, map: 0 }, survey: { sides: { up: [{ row: 0, col: 3 }] }, doors: [], pending: true } })
    log.absorb({ from: { room: 176, map: 0 }, survey: { sides: { up: [{ row: 0, col: 3 }] }, doors: [], pending: true } })
    assert_equal [192, 0], log.route([208, 0])[:next]
    log.absorb({ from: { room: 192, map: 0, row: 7, col: 9 }, stopped_by: :no_frontier, cells_walked: 0 })
    assert_equal [192, 0], log.route([208, 0])[:next], 'one idle stop (an enemy in the way) is not a pocket yet'
    log.note({ from: { room: 208, map: 0 }, to: { room: 192, map: 0 } })
    log.absorb({ from: { room: 192, map: 0, row: 7, col: 9 }, stopped_by: :no_frontier, cells_walked: 0 })
    assert_equal [209, 0], log.route([208, 0])[:next]
    refute log.hops([208, 0]).key?([192, 0]), 'hops reach no further than routes do'
  end

  def test_a_place_entered_without_a_crossing_forgets_the_side_link_last_came_in_by
    log = Koholint::ExploreLog.new
    log.absorb({ from: { room: 128, map: 0 }, exits: [{ row: 7, col: 6, direction: :down, outcome: :left, to: [144, 0] }] })
    log.note({ from: { room: 128, map: 0 }, to: { room: 144, map: 0 } })
    log.note({ from: { room: 101, map: 0 }, to: { room: 101, map: 0 } })
    log.note({ from: { room: 144, map: 0 }, to: { room: 160, map: 0 } })
    log.absorb({ from: { room: 144, map: 0 }, exits: [{ row: 7, col: 4, direction: :down, outcome: :left, to: [160, 0] }] })
    log.absorb({ from: { room: 160, map: 0 }, survey: { sides: { up: [{ row: 0, col: 3 }] }, doors: [], pending: true } })
    2.times do
      log.note({ from: { room: 128, map: 0 }, to: { room: 144, map: 0 } })
      log.absorb({ from: { room: 144, map: 0, row: 0, col: 6 }, stopped_by: :no_frontier, cells_walked: 0, dead_end: true })
    end
    assert_nil log.route([128, 0], goal: [160, 0]), 'leaving 144 after a respawn there says nothing of its top landing'
  end

  def test_a_landing_link_walked_out_of_by_another_side_never_becomes_a_pocket
    log = Koholint::ExploreLog.new
    log.absorb({ from: { room: 128, map: 0 }, exits: [{ row: 7, col: 6, direction: :down, outcome: :left, to: [144, 0] }] })
    log.absorb({ from: { room: 144, map: 0 }, exits: [{ row: 7, col: 4, direction: :down, outcome: :left, to: [160, 0] }] })
    log.absorb({ from: { room: 160, map: 0 }, survey: { sides: { up: [{ row: 0, col: 3 }] }, doors: [], pending: true } })
    2.times do
      log.note({ from: { room: 128, map: 0 }, to: { room: 144, map: 0 } })
      log.absorb({ from: { room: 144, map: 0, row: 0, col: 6 }, stopped_by: :no_frontier, cells_walked: 0, dead_end: true })
    end
    assert_equal({ goal: [160, 0], next: [144, 0], via: :down }, log.route([128, 0], goal: [160, 0]))
    assert_equal 2, log.hops([128, 0])[[160, 0]]
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
    log.absorb({ from: { room: 1, map: 0 }, exits: [{ row: 3, col: 0, direction: :left, outcome: :left, to: [0, 0] }] })
    assert_equal({ goal: PLACE, next: PLACE, via: :right }, log.route([0, 0]))
    result, = explore(rows, rocks: [[3, 3]], start: Koholint::Geometry.center_of(3, 1), explore_log: log)
    assert_equal :dialogue, result[:stopped_by]
    assert_equal({ kind: :exit, row: 7, col: 6, direction: :down }, result[:target])
    assert_includes result[:blocked_edges], { row: 3, col: 2, direction: :right }
    refute result.dig(:survey, :pending)
    log.absorb(result)
    refute log.untried?(PLACE)
    assert_nil log.route([0, 0])
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

  def test_a_stationary_enemy_cell_link_walked_into_is_no_frontier_again
    cells = [[4, 4], [4, 5]]
    rows = with(CLOSED, *cells.flat_map { |cell| [cell, '#'] })
    entities = -> { cells.map { |cell| { kind: 'enemy', moves: false, cell: } } }
    result, = explore(rows, truth: CLOSED, held: [Koholint::Items::SHIELD], entities:)
    assert_equal :no_frontier, result[:stopped_by]
    assert_equal [[4, 5, :left]], result[:crossed]
    assert_operator result[:frames], :<, 20
  end

  def test_an_uncleared_capability_target_cell_link_walked_into_is_no_frontier_again
    cells = [[4, 4], [4, 5]]
    rows = with(CLOSED, *cells.flat_map { |cell| [cell, '#'] })
    clearing = Struct.new(:cells) do
      def uses = []
      def active? = false
      def start(*) = nil
    end.new(cells.to_h { |cell| [cell, :skill] })
    original = Koholint::Skills::Clearing.method(:of)
    Koholint::Skills::Clearing.define_singleton_method(:of) { |_context| clearing }
    result, = explore(rows, truth: CLOSED)
    assert_equal :no_frontier, result[:stopped_by]
    assert_empty result[:crossed], "objects among known cells lead nowhere"
    assert_operator result[:frames], :<, 20
  ensure
    Koholint::Skills::Clearing.define_singleton_method(:of, original) if original
  end

  def with_clearing(cells)
    clearing = Struct.new(:cells) do
      def uses = []
      def active? = false
      def start(*) = nil
    end.new(cells.to_h { |cell| [cell, :skill] })
    original = Koholint::Skills::Clearing.method(:of)
    Koholint::Skills::Clearing.define_singleton_method(:of) { |_context| clearing }
    yield
  ensure
    Koholint::Skills::Clearing.define_singleton_method(:of, original) if original
  end

  def test_an_object_is_cut_only_on_the_way_to_an_unknown_cell_that_is_not_one
    with_clearing([[2, 4], [2, 5]]) do
      result, = explore(with(CLOSED, [2, 4], '?', [2, 5], '?'), limit: 1)
      assert_nil result[:target], 'objects among known cells lead nowhere'
      result, = explore(with(CLOSED, [2, 4], '?', [2, 5], '?', [2, 6], '?'), limit: 1)
      assert_equal({ kind: :frontier, row: 3, col: 5, direction: :up }, result[:target], 'objects in front of an unknown cell are cut')
    end
    log = Koholint::ExploreLog.new
    log.absorb({ from: { room: 1, map: 0 }, exits: [{ row: 0, col: 5, direction: :up, outcome: :left, to: [3, 0] }] })
    with_clearing([[0, 4], [1, 4]]) do
      result, = explore(with(CLOSED, [0, 4], '?', [1, 4], '?'), explore_log: log, limit: 1)
      assert_nil result[:target], 'objects on a border already crossed lead nowhere'
    end
  end

  def test_an_object_in_front_of_a_cell_link_stood_in_on_an_earlier_visit_is_no_frontier
    log = Koholint::ExploreLog.new
    log.note({ skill: 'walk', from: { room: 1, map: 0, row: 4, col: 3 }, to: { room: 1, map: 0, row: 4, col: 4 }, crossed: [[4, 3, :right]] })
    with_clearing([[4, 4]]) do
      result, = explore(with(CLOSED, [4, 4], '?', [4, 5], '?'), explore_log: log, limit: 1)
      refute_equal [4, 3, :right], result[:target]&.values_at(:row, :col, :direction)
    end
  end

  def test_an_object_is_worth_cutting_only_when_an_untried_door_lies_behind_it
    rows = with(CLOSED, [3, 7], '?', [2, 8], '#', [4, 8], '#', [2, 7], '#', [4, 7], '#')
    with_clearing([[3, 7]]) do
      result, = explore(rows, limit: 1)
      assert_nil result[:target], 'nothing lies behind the object'
      result, = explore(rows, objects: -> { [{ kind: 'door', cell: [2, 8] }] }, limit: 1)
      assert_equal({ kind: :door, row: 3, col: 8, direction: :up }, result[:target])
    end
  end

  def test_a_side_known_only_as_an_assumed_way_back_is_an_untried_exit
    log = Koholint::ExploreLog.new
    log.absorb({ from: { room: 17, map: 0 }, exits: [{ row: 0, col: 5, direction: :up, outcome: :left, to: [1, 0] }] })
    log.absorb({ from: { room: 1, map: 0 }, survey: { sides: { down: [{ row: 7, col: 5 }] }, doors: [] } })
    assert log.side_left?(PLACE, :down)
    refute log.side_crossed?(PLACE, :down)
    assert log.surveyed_untried?(PLACE)
    result, = explore(with(CLOSED, [7, 5], '.'), exits: [[[7, 5], :down]], explore_log: log, limit: 1)
    assert_equal({ kind: :exit, row: 7, col: 5, direction: :down }, result[:target])
    log.absorb({ from: { room: 1, map: 0 }, exits: [{ row: 7, col: 5, direction: :down, outcome: :left, to: [17, 0] }] })
    assert log.side_crossed?(PLACE, :down)
    refute log.surveyed_untried?(PLACE)
  end

  # 64/0 (run 20261125-035532-e8c3, from frame 97527): its never crossed way back down was out of reach from the right landing too,
  # yet only the side up was reported while the route went right, so 64/0 kept work for a route that landed there from the right.
  def test_an_assumed_way_back_no_path_reaches_is_unreachable_while_a_route_leads_elsewhere
    log = Koholint::ExploreLog.new
    log.absorb({ from: { room: 17, map: 0 }, exits: [{ row: 0, col: 5, direction: :up, outcome: :left, to: [1, 0] }] })
    log.absorb({ from: { room: 1, map: 0 }, exits: [{ row: 3, col: 9, direction: :right, outcome: :left, to: [2, 0] }] })
    log.absorb({ from: { room: 17, map: 0 }, survey: { sides: {}, doors: [], pending: false } })
    rows = with(CLOSED, [7, 5], '.', [6, 5], '#', [3, 9], '.', [3, 6], '.', [3, 7], '.', [3, 8], '.')
    result, = explore(rows, exits: [[[7, 5], :down], [[3, 9], :right]], explore_log: log, limit: 1)
    assert_equal [2, 0], result.dig(:route, :goal), result.inspect
    assert_equal [:down], result[:unreachable]
  end

  def test_an_assumed_way_back_ranks_after_the_other_reachable_work_of_the_place
    log = Koholint::ExploreLog.new
    log.absorb({ from: { room: 17, map: 0 }, exits: [{ row: 0, col: 5, direction: :up, outcome: :left, to: [1, 0] }] })
    rows = with(CLOSED, [7, 5], '.', [3, 9], '.')
    result, = explore(rows, exits: [[[7, 5], :down], [[3, 9], :right]], explore_log: log, limit: 1)
    assert_equal({ kind: :exit, row: 3, col: 9, direction: :right }, result[:target])
    result, = explore(with(CLOSED, [7, 5], '.', [2, 3], '?'), exits: [[[7, 5], :down]], explore_log: log, limit: 1)
    assert_equal :frontier, result[:target][:kind]
    result, = explore(with(CLOSED, [7, 5], '.'), exits: [[[7, 5], :down]], explore_log: log, limit: 1)
    assert_equal({ kind: :exit, row: 7, col: 5, direction: :down }, result[:target], 'with nothing else here, the way back is still taken')
  end

  def test_a_way_unreachable_from_the_side_entered_on_two_visits_is_not_routed_through_that_side
    log = Koholint::ExploreLog.new
    walk = ->(from, to, direction) { log.note({ skill: 'walk', params: { direction: }, from: { room: from, map: 0, row: 3, col: 5 }, to: { room: to, map: 0, row: 3, col: 5 } }) }
    [[17, 18, 'right'], [18, 19, 'right'], [17, 1, 'up'], [1, 2, 'right'], [2, 3, 'right'], [3, 19, 'down'], [19, 18, 'left'], [18, 17, 'left']].each { |hop| walk.(*hop) }
    assert_equal [18, 0], log.route([17, 0], goal: [19, 0])[:next]
    walk.(17, 18, 'right')
    log.absorb({ from: { room: 18, map: 0 }, unreachable: ['right'] })
    assert_equal [18, 0], log.route([17, 0], goal: [19, 0])[:next], 'one visit cannot tell'
    walk.(18, 17, 'left')
    walk.(17, 18, 'right')
    log.absorb({ from: { room: 18, map: 0 }, unreachable: ['right'] })
    assert_equal [1, 0], log.route([17, 0], goal: [19, 0])[:next]
    assert_equal [17, 0], log.route([18, 0], goal: [19, 0])[:next], 'inside the place too, the way is not taken from that side'
    walk.(18, 19, 'right')
    assert_equal [18, 0], log.route([17, 0], goal: [19, 0])[:next], 'a crossing from that side reopens the way'
  end

  # 64/0 and 65/0 (run 20261125-035532-e8c3, from frame 97527): each one's only untried side was cut off from the side Link entered it by,
  # and each routed him to the other.
  def test_a_place_whose_untried_ways_are_all_cut_off_from_the_landing_a_route_reaches_is_no_goal
    log = Koholint::ExploreLog.new
    walk = ->(from, to, direction) { log.note({ skill: 'walk', params: { direction: }, from: { room: from, map: 0, row: 3, col: 5 }, to: { room: to, map: 0, row: 3, col: 5 } }) }
    survey = ->(room, side) { log.absorb({ from: { room:, map: 0, row: 3, col: 5 }, survey: { sides: { side => [{ row: 0, col: 4 }] }, doors: [], pending: true } }) }
    walk.(17, 18, 'right')
    survey.(18, 'up')
    walk.(18, 17, 'left')
    survey.(17, 'down')
    assert_equal [18, 0], log.route([17, 0])[:goal]
    2.times do
      walk.(17, 18, 'right')
      log.absorb({ from: { room: 18, map: 0 }, unreachable: ['up'] })
      walk.(18, 17, 'left')
      log.absorb({ from: { room: 17, map: 0 }, unreachable: ['down'] })
    end
    assert log.route([17, 0])[:lifted], 'each cut is still lifted once'
    walk.(17, 18, 'right')
    log.absorb({ from: { room: 18, map: 0 }, unreachable: ['up'] })
    walk.(18, 17, 'left')
    log.absorb({ from: { room: 17, map: 0 }, unreachable: ['down'] })
    assert_nil log.route([17, 0])
    assert_nil log.route([18, 0])
  end

  def test_a_place_cut_off_from_one_side_is_still_routed_through_from_another
    log = Koholint::ExploreLog.new
    walk = ->(from, to, direction) { log.note({ skill: 'walk', params: { direction: }, from: { room: from, map: 0, row: 3, col: 5 }, to: { room: to, map: 0, row: 3, col: 5 } }) }
    [[17, 18, 'right'], [18, 19, 'right'], [17, 1, 'up'], [1, 2, 'right'], [2, 18, 'down'], [18, 17, 'left']].each { |hop| walk.(*hop) }
    2.times do
      walk.(17, 18, 'right')
      log.absorb({ from: { room: 18, map: 0 }, unreachable: ['right'] })
      walk.(18, 17, 'left')
    end
    assert_equal [[2, 0], [18, 0], [19, 0]], log.path([17, 0], goal: [19, 0]).map { |hop| hop[:to] }.last(3), 'entered from above, 18 still leads right'
  end

  def test_a_way_cut_off_from_the_only_side_that_reaches_a_place_leaves_no_route_to_it
    log = Koholint::ExploreLog.new
    walk = ->(from, to, direction) { log.note({ skill: 'walk', params: { direction: }, from: { room: from, map: 0, row: 3, col: 5 }, to: { room: to, map: 0, row: 3, col: 5 } }) }
    [[17, 18, 'right'], [18, 19, 'right'], [19, 18, 'left'], [18, 17, 'left']].each { |hop| walk.(*hop) }
    2.times do
      walk.(17, 18, 'right')
      log.absorb({ from: { room: 18, map: 0 }, unreachable: ['right'] })
      walk.(18, 17, 'left')
    end
    assert_nil log.path([17, 0], goal: [19, 0]), 'routing back and forth through it would only shuttle'
  end

  def test_with_no_work_reachable_under_the_cuts_each_cut_is_lifted_once_oldest_first
    log = Koholint::ExploreLog.new
    walk = ->(from, to, direction) { log.note({ skill: 'walk', params: { direction: }, from: { room: from, map: 0, row: 3, col: 5 }, to: { room: to, map: 0, row: 3, col: 5 } }) }
    [[17, 18, 'right'], [18, 19, 'right'], [19, 18, 'left'], [18, 17, 'left'], [17, 33, 'down'], [33, 34, 'right'], [34, 33, 'left'], [33, 17, 'up']].each { |hop| walk.(*hop) }
    [[17, 0], [18, 0], [33, 0]].each { |place| log.absorb({ from: { room: place[0], map: 0, row: 3, col: 5 }, survey: { sides: {}, doors: [], pending: false } }) }
    [[33, 'right', 'up'], [18, 'right', 'left']].each do |room, way, back|
      2.times do
        walk.(17, room, room == 18 ? 'right' : 'down')
        log.absorb({ from: { room:, map: 0 }, unreachable: [way] })
        walk.(room, 17, back)
      end
    end
    assert_nil log.path([17, 0], goal: [19, 0]), 'a goal route keeps every cut'
    assert_equal [[33, 0], [34, 0]], log.path([17, 0]).map { |hop| hop[:to] }, 'the cut through 33 is the older one'
    assert log.route([17, 0])[:lifted]
    [[33, 'right', 'down', 'up'], [18, 'right', 'right', 'left']].each do |room, way, there, back|
      walk.(17, room, there)
      log.absorb({ from: { room:, map: 0 }, unreachable: [way] })
      walk.(room, 17, back)
    end
    assert_nil log.route([17, 0]), 'each cut is lifted once per episode, so both tried leave no route'
    log.in_context({ 'milestone' => 'none', 'held' => [1] })
    log.in_context({ 'milestone' => 'none', 'held' => [1, 2] })
    refute log.route([17, 0])[:lifted], 'a new context clears the cuts and what was spent'
  end

  def cut_between(log, walk)
    [[17, 18, 'right'], [18, 19, 'right'], [19, 18, 'left'], [18, 17, 'left']].each { |hop| walk.(*hop) }
    2.times do
      walk.(17, 18, 'right')
      log.absorb({ from: { room: 18, map: 0 }, unreachable: ['right'] })
      walk.(18, 17, 'left')
    end
  end

  def test_a_cut_way_reopens_with_a_new_context
    log = Koholint::ExploreLog.new
    walk = ->(from, to, direction) { log.note({ skill: 'walk', params: { direction: }, from: { room: from, map: 0, row: 3, col: 5 }, to: { room: to, map: 0, row: 3, col: 5 } }) }
    log.in_context({ 'milestone' => 'none', 'held' => [1] })
    cut_between(log, walk)
    assert_nil log.path([17, 0], goal: [19, 0])
    log.in_context({ 'milestone' => 'none', 'held' => [1] })
    assert_nil log.path([17, 0], goal: [19, 0]), 'the same context keeps the cut'
    log.in_context({ 'milestone' => 'none', 'held' => [1, 2] })
    assert_equal [[18, 0], [19, 0]], log.path([17, 0], goal: [19, 0]).map { |hop| hop[:to] }
  end

  def test_a_cut_way_stays_cut_however_many_visits_pass
    log = Koholint::ExploreLog.new
    walk = ->(from, to, direction) { log.note({ skill: 'walk', params: { direction: }, from: { room: from, map: 0, row: 3, col: 5 }, to: { room: to, map: 0, row: 3, col: 5 } }) }
    cut_between(log, walk)
    10.times do
      walk.(17, 18, 'right')
      walk.(18, 17, 'left')
    end
    assert_nil log.path([17, 0], goal: [19, 0])
  end

  def test_a_way_unreachable_from_a_door_landing_is_cut_for_that_landing_and_ends_the_shuttle_through_it
    explore = lambda do |frame, from, to, exit, unreachable = nil|
      { 'type' => 'action', 'frame' => frame, 'skill' => 'explore',
        'result' => { 'from' => { 'room' => from[0], 'map' => 10, 'row' => from[1], 'col' => from[2] }, 'to' => { 'room' => to[0], 'map' => to[0] == 80 ? 0 : 10, 'row' => to[1], 'col' => to[2] },
                      'exits' => [exit.merge('outcome' => 'left', 'to' => [to[0], to[0] == 80 ? 0 : 10])], 'unreachable' => unreachable }.compact }
    end
    out = ->(frame, unreachable = nil) { explore.(frame, [171, 5, 6], [80, 7, 5], { 'row' => 7, 'col' => 5, 'direction' => 'down', 'walk_in' => true }, unreachable) }
    into = ->(frame) { explore.(frame, [80, 2, 8], [171, 7, 5], { 'row' => 3, 'col' => 8, 'direction' => 'up', 'kind' => 'door' }).tap { |event| event['result']['from']['map'] = 0 } }
    events = [explore.(1, [171, 2, 8], [172, 2, 0], { 'row' => 2, 'col' => 9, 'direction' => 'right' }),
              explore.(2, [172, 2, 0], [171, 2, 9], { 'row' => 2, 'col' => 0, 'direction' => 'left' }), out.(3), into.(4)]
    assert_equal [171, 10], Koholint::ExploreLog.from_events(events).route([80, 0], goal: [172, 10])[:next]
    once = events + [out.(5, ['right']), into.(6)]
    assert_equal [171, 10], Koholint::ExploreLog.from_events(once).route([80, 0], goal: [172, 10])[:next], 'an enemy may block the way once'
    log = Koholint::ExploreLog.from_events(once + [out.(7, ['right']), into.(8)])
    assert_nil log.route([80, 0], goal: [172, 10]), 'through the door, the way on is never reached'
    assert_nil log.route([171, 10], goal: [172, 10])
  end

  def test_a_rebuilt_log_reopens_cuts_at_the_context_change_the_trace_records
    walk = ->(from, to, direction, frame) { { 'type' => 'action', 'frame' => frame, 'skill' => 'walk', 'result' => { 'skill' => 'walk', 'params' => { 'direction' => direction }, 'from' => { 'room' => from, 'map' => 0, 'row' => 3, 'col' => 5 }, 'to' => { 'room' => to, 'map' => 0, 'row' => 3, 'col' => 5 } } } }
    blocked = ->(frame) { { 'type' => 'action', 'frame' => frame, 'skill' => 'explore', 'result' => { 'from' => { 'room' => 18, 'map' => 0 }, 'unreachable' => ['right'] } } }
    decision = ->(frame, held) { { 'type' => 'decision', 'frame' => frame, 'input' => { 'milestone' => 'none', 'inventory' => held } } }
    events = [decision.(0, []), walk.(17, 18, 'right', 1), walk.(18, 19, 'right', 2), walk.(19, 18, 'left', 3), walk.(18, 17, 'left', 4),
              walk.(17, 18, 'right', 5), blocked.(6), walk.(18, 17, 'left', 7), walk.(17, 18, 'right', 8), blocked.(9), walk.(18, 17, 'left', 10)]
    assert_nil Koholint::ExploreLog.from_events(events).path([17, 0], goal: [19, 0])
    refute_nil Koholint::ExploreLog.from_events(events + [decision.(11, [2])]).path([17, 0], goal: [19, 0])
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

  # g1 post-gain stub b11c: a continue put Link back in 171/10 with no crossing, and every explore there found the right exit
  # unreachable from frame 95960 to 99633 while the route kept aiming through it.
  def test_a_landing_without_a_crossing_is_cut_on_its_own_after_three_findings_and_the_route_goes_round
    explore = lambda do |frame, from, to, exit, unreachable = nil|
      { 'type' => 'action', 'frame' => frame, 'skill' => 'explore',
        'result' => { 'from' => { 'room' => from[0], 'map' => from[0] == 80 ? 0 : 10, 'row' => from[1], 'col' => from[2] },
                      'to' => { 'room' => to[0], 'map' => to[0] == 80 ? 0 : 10, 'row' => to[1], 'col' => to[2] },
                      'exits' => exit ? [exit.merge('outcome' => 'left', 'to' => [to[0], to[0] == 80 ? 0 : 10])] : [], 'unreachable' => unreachable }.compact }
    end
    events = [explore.(1, [171, 2, 8], [172, 2, 0], { 'row' => 2, 'col' => 9, 'direction' => 'right' }),
              explore.(2, [172, 2, 0], [171, 2, 9], { 'row' => 2, 'col' => 0, 'direction' => 'left' }),
              explore.(3, [171, 5, 6], [80, 7, 5], { 'row' => 7, 'col' => 5, 'direction' => 'down', 'walk_in' => true }),
              explore.(4, [80, 2, 8], [171, 7, 5], { 'row' => 3, 'col' => 8, 'direction' => 'up', 'kind' => 'door' }),
              explore.(5, [171, 3, 7], [172, 2, 9], { 'row' => 2, 'col' => 9, 'direction' => 'right' }),
              { 'type' => 'action', 'frame' => 6, 'skill' => 'choose_option',
                'result' => { 'skill' => 'choose_option', 'from' => { 'room' => 172, 'map' => 10, 'row' => 4, 'col' => 1 }, 'to' => { 'room' => 171, 'map' => 10, 'row' => 4, 'col' => 1 } } }]
    stalled = ->(count) { events + Array.new(count) { |n| explore.(7 + n, [171, 4, 6], [171, 4, 6], nil, ['right']) } }
    assert_equal [172, 10], Koholint::ExploreLog.from_events(stalled.(2)).route([171, 10], goal: [172, 10])[:next], 'two calls of one visit may meet a passing block'
    log = Koholint::ExploreLog.from_events(stalled.(3))
    assert_equal [[80, 0], [171, 10], [172, 10]], log.path([171, 10], goal: [172, 10]).map { |hop| hop[:to] }, 'round through the door, whose landing reaches it'
  end

  def test_an_untried_exit_no_path_reaches_is_unreachable_unless_the_room_has_crumbling_floor
    rows = with(CLOSED, [7, 5], '.', [6, 5], '#')
    result, = explore(rows, explore_log: Koholint::ExploreLog.new, limit: 200)
    assert_equal [:down], result[:unreachable], result.inspect
    result, = explore(rows, explore_log: Koholint::ExploreLog.new, objects: -> { [{ kind: :crumbling, cell: [2, 2] }] }, limit: 200)
    assert_nil result[:unreachable]
  end

  def test_an_unreachable_door_is_reported_by_its_own_cell
    rows = with(CLOSED, [2, 5], '#', [3, 4], '#', [3, 6], '#', [4, 5], '#')
    door = -> { [{ kind: :door, cell: [2, 5] }] }
    result, = explore(rows, explore_log: Koholint::ExploreLog.new, objects: door, start: [40, 96], limit: 200)
    assert_equal [[2, 5]], result[:unreachable], result.inspect
  end

  def test_a_fall_and_an_enemy_to_fight_stop_explore
    falling = Koholint::GameState.new(**state.to_h, link_motion_state: Koholint::FALL_MOTION)
    execution = registry.start('explore', state, {}, { grid: MapGrid.new(with(CLOSED, [2, 5], '?')) })
    execution.next_input(state)
    execution.next_input(falling)
    assert_equal [:fell, []], execution.result(state).values_at(:stopped_by, :blocked_edges)
    result, = explore(with(CLOSED, [2, 5], '?'), fight: ->(_now) { true })
    assert_equal [:enemy, 0], result.values_at(:stopped_by, :cells_walked)
  end
end
class ExploreCutCallsTest < Minitest::Test
  DOOR = [[80, 0], [2, 8]].freeze

  def explore(frame, from, to, exit = nil, unreachable = nil)
    map = ->(room) { room == 80 ? 0 : 10 }
    { 'type' => 'action', 'frame' => frame, 'skill' => 'explore',
      'result' => { 'from' => { 'room' => from[0], 'map' => map.(from[0]), 'row' => from[1], 'col' => from[2] },
                    'to' => { 'room' => to[0], 'map' => map.(to[0]), 'row' => to[1], 'col' => to[2] },
                    'exits' => exit ? [exit.merge('outcome' => 'left', 'to' => [to[0], map.(to[0])])] : [], 'unreachable' => unreachable }.compact }
  end

  def through_the_door(frame)
    [explore(frame, [171, 5, 6], [80, 7, 5], { 'row' => 7, 'col' => 5, 'direction' => 'down', 'walk_in' => true }),
     explore(frame + 1, [80, 2, 8], [171, 7, 5], { 'row' => 3, 'col' => 8, 'direction' => 'up', 'kind' => 'door' })]
  end

  def stalled(frame, count) = Array.new(count) { |n| explore(frame + n, [171, 5, 6], [171, 5, 6], nil, ['right']) }

  def test_a_crossing_lifts_a_cut_by_calls_and_starts_its_count_over
    events = [explore(1, [171, 2, 8], [172, 2, 0], { 'row' => 2, 'col' => 9, 'direction' => 'right' }),
              explore(2, [172, 2, 0], [171, 2, 9], { 'row' => 2, 'col' => 0, 'direction' => 'left' })] +
             through_the_door(3) + stalled(5, 3)
    assert Koholint::ExploreLog.from_events(events).cut?([171, 10], DOOR, :right), 'three calls of one visit'
    events << explore(8, [171, 2, 8], [172, 2, 0], { 'row' => 2, 'col' => 9, 'direction' => 'right' })
    refute Koholint::ExploreLog.from_events(events).cut?([171, 10], DOOR, :right), 'the crossing from that landing lifts it'
    events += [explore(9, [172, 2, 0], [171, 2, 9], { 'row' => 2, 'col' => 0, 'direction' => 'left' })] + through_the_door(10) + stalled(12, 1)
    refute Koholint::ExploreLog.from_events(events).cut?([171, 10], DOOR, :right), 'one later finding does not cut it again'
  end

  def test_calls_of_different_visits_add_up_only_through_the_two_visit_rule
    events = [explore(1, [171, 2, 8], [172, 2, 0], { 'row' => 2, 'col' => 9, 'direction' => 'right' }),
              explore(2, [172, 2, 0], [171, 2, 9], { 'row' => 2, 'col' => 0, 'direction' => 'left' })] +
             through_the_door(3) + stalled(5, 2)
    log = Koholint::ExploreLog.from_events(events)
    refute log.cut?([171, 10], DOOR, :right)
    assert_equal 2, log.instance_variable_get(:@cut_calls)[[[171, 10], DOOR, :right]].last
    log = Koholint::ExploreLog.from_events(events + through_the_door(7) + stalled(9, 1))
    assert_equal 1, log.instance_variable_get(:@cut_calls)[[[171, 10], DOOR, :right]].last, 'the count starts over on a new visit'
  end

  def test_a_place_reached_without_a_crossing_from_where_link_was_is_a_landing_of_its_own
    events = [explore(1, [171, 2, 8], [172, 2, 0], { 'row' => 2, 'col' => 9, 'direction' => 'right' }),
              explore(2, [172, 2, 0], [171, 2, 9], { 'row' => 2, 'col' => 0, 'direction' => 'left' }),
              explore(3, [171, 2, 9], [172, 2, 0], { 'row' => 2, 'col' => 9, 'direction' => 'right' })] + stalled(4, 3)
    log = Koholint::ExploreLog.from_events(events)
    assert log.cut?([171, 10], :landed, :right), 'Link left off in 172/10 and the next result starts in 171/10'
    refute log.cut?([171, 10], :right, :right)
  end
end
class ExploreStoneRoomTest < Minitest::Test
  DOOR = [[80, 0], [2, 8]].freeze

  def explore(frame, from, to, exit, unreachable = nil, pushed = nil)
    map = ->(room) { room == 80 ? 0 : 10 }
    { 'type' => 'action', 'frame' => frame, 'skill' => 'explore',
      'result' => { 'from' => { 'room' => from[0], 'map' => map.(from[0]), 'row' => from[1], 'col' => from[2] },
                    'to' => { 'room' => to[0], 'map' => map.(to[0]), 'row' => to[1], 'col' => to[2] },
                    'exits' => exit ? [exit.merge('outcome' => 'left', 'to' => [to[0], map.(to[0])])] : [],
                    'unreachable' => unreachable, 'pushed' => pushed }.compact }
  end

  def cut_then_leave(pushed)
    [explore(1, [171, 2, 8], [172, 2, 0], { 'row' => 2, 'col' => 9, 'direction' => 'right' }),
     explore(2, [172, 2, 0], [171, 2, 9], { 'row' => 2, 'col' => 0, 'direction' => 'left' }),
     explore(3, [171, 5, 6], [80, 7, 5], { 'row' => 7, 'col' => 5, 'direction' => 'down', 'walk_in' => true }),
     explore(4, [80, 2, 8], [171, 7, 5], { 'row' => 3, 'col' => 8, 'direction' => 'up', 'kind' => 'door' }),
     explore(5, [171, 7, 5], [171, 5, 6], nil, nil, pushed)] +
      Array.new(3) { |n| explore(6 + n, [171, 5, 6], [171, 5, 6], nil, ['right']) } +
      [explore(9, [171, 7, 5], [80, 7, 5], { 'row' => 7, 'col' => 5, 'direction' => 'down', 'walk_in' => true })]
  end

  def test_a_cut_in_a_room_where_a_stone_was_pushed_expires_when_link_leaves_it
    still = Koholint::ExploreLog.from_events(cut_then_leave(nil)[0..-2])
    assert still.cut?([171, 10], DOOR, :right), 'three findings of one visit cut the way'
    gone = Koholint::ExploreLog.from_events(cut_then_leave({ 'row' => 5, 'col' => 7, 'direction' => 'right' }))
    refute gone.cut?([171, 10], DOOR, :right), 'the stones are back on re-entry'
    kept = Koholint::ExploreLog.from_events(cut_then_leave(nil))
    assert kept.cut?([171, 10], DOOR, :right), 'a room without a push keeps its cut'
  end
end
class ExploreStoneRoomLoopTest < ExploreStoneRoomTest
  def test_a_way_shut_for_another_reason_is_cut_again_at_once_and_a_visit_without_a_push_keeps_it
    events = cut_then_leave({ 'row' => 5, 'col' => 7, 'direction' => 'right' })
    refute Koholint::ExploreLog.from_events(events).cut?([171, 10], DOOR, :right), 'the visit pushed a stone'
    events += [explore(10, [80, 2, 8], [171, 7, 5], { 'row' => 3, 'col' => 8, 'direction' => 'up', 'kind' => 'door' }),
               explore(11, [171, 5, 6], [171, 5, 6], nil, ['right'])]
    assert Koholint::ExploreLog.from_events(events).cut?([171, 10], DOOR, :right), 'found again on a later visit'
    events << explore(12, [171, 7, 5], [80, 7, 5], { 'row' => 7, 'col' => 5, 'direction' => 'down', 'walk_in' => true })
    assert Koholint::ExploreLog.from_events(events).cut?([171, 10], DOOR, :right), 'that visit pushed nothing'
  end
end
