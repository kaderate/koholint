require_relative 'test_helper'
require 'koholint/agents/context'
require 'koholint/autopilot'
require 'koholint/entities'
require 'koholint/explore_log'
require 'koholint/game_state'
require 'koholint/navigation/planner'
require 'koholint/skills/registry'
require 'koholint/talk_log'

class StonesTest < Minitest::Test
  DELTA = { up: [0, -1], down: [0, 1], left: [-1, 0], right: [1, 0] }.freeze
  STEP = { up: [-1, 0], down: [1, 0], left: [0, -1], right: [0, 1] }.freeze
  FLOOR = 13
  STONE = 167
  FIXED = 166
  SLIDE = 20

  class MapGrid
    def initialize(rows) = @rows = rows
    def static_sprite(_row, _col) = nil
    def passable(row, col, _direction) = { '.' => :yes, '#' => :no, 's' => :no }.fetch(@rows[row][col], :unknown)
  end

  # Link moves a pixel a frame; a held stone slides when its far cell is floor, as measured in 171/10 (data/entities.json).
  # The screen as the room draws it now: a slid stone's cell shows floor.
  class LiveGrid
    def initialize(room, rows) = (@room = room; @rows = rows)
    def static_sprite(_row, _col) = nil
    def passable(row, col, _direction) = @rows[row][col] == '#' || @room.stone?([row, col]) ? :no : :yes
  end

  class Room
    attr_reader :objects, :x, :y, :room_id

    def initialize(rows, start:, exits: [])
      @rows = rows
      @objects = rows.map { |line| line.chars.map { |char| { 's' => STONE, '#' => 1 }.fetch(char, FLOOR) } }
      @x, @y = start
      @exits = exits
      @room_id = 1
      @held = 0
      @landing = nil
    end

    def reader = -> { @objects.map(&:dup) }

    def wall?(cell) = @rows[cell[0]][cell[1]] == '#'

    def stone?(cell) = [STONE, FIXED].include?(@objects.dig(*cell))

    def step(buttons)
      land
      direction = Array(buttons).first
      dx, dy = DELTA.fetch(direction, [0, 0])
      return if dx.zero? && dy.zero?

      cell = Koholint::Geometry.cell_for(@x, @y)
      ahead = Koholint::Geometry.cell_for(@x + dx + (7 * dx), @y + dy + (7 * dy))
      if ahead.nil?
        @room_id = 2 if @exits.include?([cell, direction])
        return
      end
      return push(ahead, direction) if stone?(ahead)

      @held = 0
      return if wall?(ahead)

      @x += dx
      @y += dy
    end

    private

    def push(cell, direction)
      @held += 1
      return unless @held >= 32 && @objects.dig(*cell) == STONE

      dr, dc = STEP.fetch(direction)
      far = [cell[0] + dr, cell[1] + dc]
      return unless far.all? { |v| v >= 0 } && @objects.dig(*far) == FLOOR && !wall?(far)

      @objects[cell[0]][cell[1]] = FLOOR
      @landing = [far, SLIDE]
      @held = 0
    end

    def land
      return unless @landing

      far, left = @landing
      @landing = left > 1 ? [far, left - 1] : nil
      @objects[far[0]][far[1]] = FIXED unless @landing
    end
  end

  def state(room)
    Koholint::GameState.new(frame: 0, room_id: room.room_id, map_id: 0, x: room.x, y: room.y, hp: 24, dialog_state: 0, game_mode: 0x0B, game_submode: 7, milestone: :none)
  end

  def play(skill, params, room, rows, limit: 600, grid: MapGrid.new(rows), **context)
    run = Koholint::Skills::Registry.default.start(skill, state(room), params, { grid:, room_objects: room.reader, **context })
    inputs = []
    limit.times do
      buttons = run.next_input(state(room)) or break
      inputs << buttons
      room.step(buttons)
    end
    [run.result(state(room)), inputs]
  end

  CLOSED = ['##########', *Array.new(6) { '#........#' }, '##########'].freeze

  def with(rows, *edits)
    rows = rows.map(&:dup)
    edits.each_slice(2) { |(row, col), char| rows[row][col] = char }
    rows
  end

  def at(cell) = Koholint::Geometry.center_of(*cell)

  def test_the_catalogue_holds_the_measured_stones_and_the_heavy_rock
    catalogue = Koholint::Entities.object_catalogue
    assert_equal({ kind: :stone, verified: true, push: 32 }, catalogue[167])
    assert_equal({ kind: :stone, verified: true }, catalogue[166])
    assert_equal({ kind: :object, verified: true }, catalogue[32])
    entry = JSON.parse(File.read(Koholint::Entities::DEFAULT_PATH)).find { |e| e['object'] == 167 }
    assert_equal 2, entry.dig('push', 'verified_count')
    assert_includes entry.dig('push', 'source'), '20261113-235935-9618'
  end

  def test_a_push_fact_needs_its_provenance
    bad = { 'object' => 167, 'kind' => 'stone', 'source' => 's', 'confidence' => 'hypothesis', 'verified_count' => 1, 'push' => { 'value' => 32 } }
    assert_raises(Koholint::Entities::Invalid) { Koholint::Entities.validate!(bad) }
    bad['push'].merge!('confidence' => 'verified', 'verified_count' => 1, 'source' => 's')
    assert_raises(Koholint::Entities::Invalid) { Koholint::Entities.validate!(bad) }
  end

  def test_a_walk_into_a_stone_holds_until_it_slides_then_stops_once_it_has_landed
    rows = with(CLOSED, [3, 4], 's')
    room = Room.new(rows, start: at([2, 4]))
    result, inputs = play('walk', { direction: 'down', cells: 3 }, room, rows)
    assert_equal :pushed, result[:stopped_by]
    assert_equal({ row: 3, col: 4, direction: :down }, result[:pushed])
    assert_equal FIXED, room.objects[4][4]
    assert_equal FLOOR, room.objects[3][4]
    assert_equal 32, inputs.count([:down])
    assert_equal SLIDE, inputs.count([])
    assert_equal [], inputs.last
  end

  def test_a_stone_with_no_floor_beyond_holds_for_the_measured_delay_then_reads_blocked
    rows = with(CLOSED, [3, 4], 's', [4, 4], '#')
    room = Room.new(rows, start: at([2, 4]))
    result, inputs = play('walk', { direction: 'down', cells: 3 }, room, rows)
    assert_equal :blocked, result[:stopped_by]
    assert_equal STONE, room.objects[3][4]
    assert_equal 32 + Koholint::Skills::Execution::PUSH_MARGIN, inputs.size
  end

  def test_a_wall_still_reads_blocked_after_eight_still_frames
    rows = with(CLOSED, [3, 4], '#')
    _, stone = play('walk', { direction: 'down', cells: 3 }, Room.new(with(CLOSED, [3, 4], 's', [4, 4], '#'), start: at([2, 4])), with(CLOSED, [3, 4], 's', [4, 4], '#'))
    result, wall = play('walk', { direction: 'down', cells: 3 }, Room.new(rows, start: at([2, 4])), rows)
    assert_equal :blocked, result[:stopped_by]
    assert_operator wall.size + 30, :<, stone.size
  end

  def test_goto_holds_into_a_stone_on_its_path_and_stops_once_it_has_slid
    rows = with(CLOSED, [3, 1], '#', [3, 2], '#', [3, 3], '#', [3, 4], 's', [3, 5], '#', [3, 6], '#', [3, 7], '#', [3, 8], '#')
    room = Room.new(rows, start: at([1, 4]))
    result, = play('goto', { row: 5, col: 4 }, room, rows)
    assert_equal :pushed, result[:stopped_by]
    assert_equal({ row: 3, col: 4, direction: :down }, result[:pushed])
  end

  def test_stones_join_the_pushable_cells_only_in_directions_whose_far_cell_is_floor
    rows = with(CLOSED, [3, 4], 's', [4, 4], '#', [3, 5], 's')
    room = Room.new(rows, start: at([1, 1]))
    host = Koholint::Skills::Execution.new(skill: 'goto', params: {}, state: state(room))
    pushes = host.send(:pushable_of, { grid: MapGrid.new(rows), room_objects: room.reader }).call
    assert_equal [[[3, 4], :left], [[3, 4], :up], [[3, 5], :down], [[3, 5], :right], [[3, 5], :up]], pushes.sort_by { |cell, d| [cell, d.to_s] }
    refute_includes pushes, [[3, 4], :down]
    refute_includes pushes, [[3, 4], :right], 'a stone beyond is no floor'
  end

  def test_the_planner_crosses_a_stone_only_in_a_direction_it_slides
    grid = MapGrid.new(with(CLOSED, [3, 1], '#', [3, 2], '#', [3, 3], '#', [3, 4], 's', [3, 5], '#', [3, 6], '#', [3, 7], '#', [3, 8], '#'))
    down = Koholint::Navigation::Planner.new(grid:, ledger: nil, place: [1, 0], pushable: -> { [[[3, 4], :down]] })
    assert_includes down.path(from: [1, 4], to: [5, 4]), [3, 4]
    up = Koholint::Navigation::Planner.new(grid:, ledger: nil, place: [1, 0], pushable: -> { [[[3, 4], :up]] })
    assert_nil up.path(from: [1, 4], to: [5, 4])
  end

  def test_explore_pushes_a_stone_that_walls_off_an_untried_exit_and_stops_for_a_fresh_screen
    rows = ['##########', '#........#', '#........#', '####s#####', '#........#', '#........#', '#........#', '####.#####']
    room = Room.new(rows, start: at([1, 4]))
    result, = play('explore', {}, room, rows, limit: 1200)
    assert_equal :pushed, result[:stopped_by], result.inspect
    assert_equal({ row: 3, col: 4, direction: :down }, result[:pushed])
    assert_equal FIXED, room.objects[4][4]
  end

  def test_explore_holds_its_outward_step_into_a_stone_frontier_until_it_slides
    rows = with(CLOSED, [3, 4], 's')
    room = Room.new(rows, start: at([2, 4]))
    result, = play('explore', {}, room, rows)
    assert_equal({ kind: :frontier, row: 2, col: 4, direction: :down }, result[:target])
    assert_equal :pushed, result[:stopped_by], result.inspect
    assert_equal({ row: 3, col: 4, direction: :down }, result[:pushed])
  end

  def test_a_stone_cell_walked_before_the_room_put_it_back_is_a_frontier_again
    rows = with(CLOSED, [3, 4], 's', [2, 4], '#')
    room = Room.new(rows, start: at([4, 4]))
    log = Koholint::ExploreLog.new
    log.absorb({ from: { room: 1, map: 0 }, crossed: [[4, 4, :up]] })
    assert_includes log.walked([1, 0]), [3, 4]
    run = Koholint::Skills::Registry.default.start('explore', state(room), {}, { grid: MapGrid.new(rows), room_objects: room.reader, explore_log: log })
    assert_equal :frontier, run.send(:frontier_kind, [3, 3], :right)
  end

  def test_a_stone_with_floor_beyond_is_a_frontier
    rows = with(CLOSED, [3, 4], 's', [2, 4], '#')
    room = Room.new(rows, start: at([4, 4]))
    run = Koholint::Skills::Registry.default.start('explore', state(room), {}, { grid: MapGrid.new(rows), room_objects: room.reader })
    assert_equal :frontier, run.send(:frontier_kind, [3, 3], :right)
    assert_nil run.send(:frontier_kind, [4, 4], :up), 'pushed up, it would land on a wall'
  end

  def test_the_prompt_lists_a_stone_that_slides_and_not_a_fixed_one
    stones = [{ object: 167, cell: [4, 8], kind: :stone, verified: true, push: 32 }, { object: 166, cell: [1, 4], kind: :stone, verified: true }]
    text = Koholint::Agents::Context.send(:things_block, MapGrid.new(CLOSED), Koholint::TalkLog.new, [171, 10], nil, [], stones).join("\n")
    assert_includes text, '- at (4,8): stone: slides one cell when Link holds a direction into it for about 32 frames and the cell beyond is floor'
    refute_includes text, '(1,4)'
  end

  def test_a_push_keeps_the_autopilot_exploring
    assert_includes Koholint::Autopilot::BENIGN, 'pushed'
  end
  JAM = ['##########', '#.....#..#', '#.....#..#', '#....s....', '#.....#..#', '#.....#..#', '##########', '##########'].freeze

  def test_the_search_pushes_a_stone_aside_where_pushing_it_on_would_jam_the_corridor
    floor = ->(cell, _direction) { JAM[cell[0]][cell[1]] == '.' }
    plans = Koholint::Navigation::Stones.plans(link: [3, 1], stones: [[3, 5]], fixed: [], step: ->(_from, to, direction) { floor.(to, direction) }, slide: floor)[:plans]
    push = plans.fetch([3, 9]).first
    assert_includes %i[up down], push[:direction], 'pushed right it lands in the corridor and walls it'
    assert_equal [3, 5], push[:stone]
    assert_equal 1, plans.fetch([3, 9]).size
    refute plans.key?([3, 4]), 'a cell Link reaches already needs no push'
  end

  def test_explore_opens_an_untried_exit_with_the_pushes_the_search_found_and_leaves_by_it
    room = Room.new(JAM, start: at([3, 1]), exits: [[[3, 9], :right]])
    results = []
    6.times do
      break if room.room_id == 2

      result, = play('explore', {}, room, JAM, limit: 1500, grid: LiveGrid.new(room, JAM))
      results << result
    end
    assert_equal 2, room.room_id, results.map { |r| r.slice(:stopped_by, :target, :pushed) }.inspect
    assert_equal :push, results.first.dig(:target, :kind)
    assert_includes [room.objects[2][5], room.objects[4][5]], FIXED
    assert_equal FLOOR, room.objects[3][6]
  end
  class StuckRoom < Room
    private

    def push(_cell, _direction) = nil
  end

  def test_a_push_that_leaves_its_stone_in_place_is_not_planned_again_this_visit
    room = StuckRoom.new(JAM, start: at([3, 1]))
    log = Koholint::ExploreLog.new
    failed = Array.new(3) do
      result, = play('explore', {}, room, JAM, limit: 1500, grid: LiveGrid.new(room, JAM), explore_log: log)
      log.note(result)
      log.absorb(result)
      result[:failed_push]
    end
    assert_equal({ row: 3, col: 5, direction: :up }, failed.first)
    assert_includes log.failed_pushes([1, 0]), [[3, 5], :up]
    refute_includes failed.drop(1), failed.first, failed.inspect
  end

  def test_a_landed_stone_blocks_its_cell
    rows = ['##########', '##########', '##########', '#....s....', '##########', '##########', '##########', '##########']
    floor = ->(cell, _direction) { rows[cell[0]][cell[1]] == '.' }
    plans = Koholint::Navigation::Stones.plans(link: [3, 1], stones: [[3, 5]], fixed: [], step: ->(_from, to, direction) { floor.(to, direction) }, slide: floor)[:plans]
    refute plans.key?([3, 9]), 'pushed on, the stone lands in the corridor and walls it'
    assert plans.key?([3, 5])
  end

  def test_a_stone_slides_only_onto_a_cell_it_can_land_on
    rows = ['##########', '##########', '######..##', '#.....s###', '##########', '##########', '##########', '##########']
    floor = ->(cell, _direction) { rows[cell[0]][cell[1]] == '.' }
    plans = Koholint::Navigation::Stones.plans(link: [3, 1], stones: [[3, 6]], fixed: [], step: ->(_from, to, direction) { floor.(to, direction) }, slide: floor)[:plans]
    refute plans.key?([2, 7]), 'the wall beyond holds the stone'
  end

  def test_explore_takes_a_route_way_that_only_pushes_open
    room = Room.new(JAM, start: at([3, 1]), exits: [[[3, 9], :right]])
    log = Koholint::ExploreLog.new
    log.absorb({ from: { room: 1, map: 0 }, survey: { sides: { right: [{ row: 3, col: 9 }] }, doors: [] },
                 exits: [{ row: 3, col: 9, direction: :right, outcome: :left, to: [2, 0] }] })
    result, = play('explore', {}, room, JAM, limit: 1500, grid: LiveGrid.new(room, JAM), explore_log: log)
    assert_equal :push, result.dig(:target, :kind), result.inspect
    assert_equal [2, 0], result.dig(:route, :goal)
  end

  def test_a_room_whose_exit_needs_a_push_still_has_work
    room = Room.new(JAM, start: at([3, 1]))
    run = Koholint::Skills::Explore.new.start(state(room), {}, { grid: LiveGrid.new(room, JAM), room_objects: room.reader })
    run.instance_variable_set(:@pushable, [])
    assert run.send(:pending?)
  end
  def test_a_push_ranks_by_the_exit_it_opens
    room = Room.new(JAM, start: at([3, 1]))
    run = Koholint::Skills::Explore.new.start(state(room), { direction: 'right' }, { grid: LiveGrid.new(room, JAM), room_objects: room.reader })
    push = { kind: :push, cell: [4, 5], direction: :up, path: Array.new(6), opens: { kind: :exit, cell: [3, 9], direction: :right } }
    frontier = { kind: :frontier, cell: [2, 2], direction: :up, path: Array.new(2) }
    assert_equal [push, frontier], run.send(:order, [frontier, push]), 'the hint names the exit, not the push'
  end

  # A held 167 slides only with Link centred across the push (measured in 171/10, data/entities.json); off by more it never slides here.
  class OffCentreRoom < Room
    private

    def push(cell, direction)
      cx, cy = Koholint::Geometry.center_of(*cell)
      across = %i[left right].include?(direction) ? @y - cy : @x - cx
      across.abs > 3 ? (@held = 0) : super
    end
  end

  def test_explore_centres_link_across_a_push_before_holding_it
    x, y = at([4, 5])
    room = OffCentreRoom.new(JAM, start: [x + 4, y], exits: [[[3, 9], :right]])
    result, = play('explore', {}, room, JAM, limit: 1500, grid: LiveGrid.new(room, JAM))
    assert_equal :push, result.dig(:target, :kind)
    assert_equal({ row: 3, col: 5, direction: :up }, result[:pushed], result.slice(:stopped_by, :target, :failed_push).inspect)
  end
end
