require_relative 'test_helper'
require 'koholint/ledger'
require 'koholint/decision'
require 'koholint/game_state'
require 'koholint/perception'
require 'koholint/vision/grid_builder'
require 'koholint/calibration/walk_probe'
require 'koholint/navigation/planner'
require 'koholint/triggers'
require 'koholint/talk_log'
require 'koholint/skills/registry'
require 'support/emulator_cache'

class TalkToTest < Minitest::Test
  class FakeGrid
    def initialize(walls: [], sprites: [])
      @walls = walls
      @sprites = sprites
    end

    def static_sprite(row, col) = @sprites.include?([row, col]) ? true : nil
    def passable(row, col, _direction) = @walls.include?([row, col]) ? :no : :yes
  end

  def registry = @registry ||= Koholint::Skills::Registry.default

  def state(x:, y:, hp: 24, dialog_state: 0, room_id: 1)
    Koholint::GameState.new(frame: 0, room_id:, map_id: 0, x:, y:, hp:, dialog_state:, game_mode: 0x0B, game_submode: 7, milestone: :none)
  end

  def centre(row, col) = Koholint::Geometry.center_of(row, col)

  def talk(row, col, from: [4, 5], grid: FakeGrid.new(sprites: [[row, col]]), ledger: nil, solid: [row, col], opens_after: 1, free: false,
           dialogue_at: nil, room_change_at: nil, damage_at: nil, limit: 600, blocked: [], triggers: nil, open_cells: nil, talk_log: nil, entities: nil)
    x, y = centre(*from)
    start = state(x:, y:)
    execution = registry.start('talk_to', start, { row:, col: }, { grid:, ledger:, triggers:, talk_log:, entities: }.compact)
    inputs = []
    a_presses = 0
    dialog = 0
    limit.times do |i|
      current = state(x:, y:, dialog_state: dialog, hp: damage_at == i ? 20 : 24, room_id: room_change_at == i ? 2 : 1)
      current = state(x:, y:, dialog_state: 3) if dialogue_at == i
      buttons = execution.next_input(current)
      break unless buttons

      inputs << buttons
      dialog = 3 if dialogue_at && i >= dialogue_at
      if buttons == [:a]
        a_presses += 1
        dialog = 3 if opens_after && a_presses >= opens_after && (open_cells.nil? || open_cells.include?(Koholint::Geometry.cell_for(x, y)))
        next
      end
      dx, dy = { up: [0, -1], down: [0, 1], left: [-1, 0], right: [1, 0] }.fetch(buttons.first, [0, 0])
      cell = Koholint::Geometry.cell_for(x + dx + (7 * dx), y + dy + (7 * dy))
      next if cell == solid && !free
      next if blocked.include?(cell)
      next if cell && grid.passable(*cell, nil) == :no

      x += dx
      y += dy
    end
    [execution.result(state(x:, y:, dialog_state: dialog)), inputs]
  end

  def test_standing_cell_is_the_nearest_reachable_neighbour
    result, = talk(4, 8, from: [4, 5])
    assert_equal({ row: 4, col: 7 }, result[:standing_cell])
    assert_equal :right, result[:facing]
    assert_equal 2, result[:path_length]
  end

  def test_an_unreachable_neighbour_is_skipped
    grid = FakeGrid.new(sprites: [[4, 8]], walls: [[4, 7]])
    result, = talk(4, 8, grid:)
    refute_equal({ row: 4, col: 7 }, result[:standing_cell])
    refute_nil result[:standing_cell]
  end

  def test_a_doubtful_edge_is_avoided
    ledger = Koholint::Ledger.new
    2.times { ledger.record(place: [1, 0], blocked_at: { row: 4, col: 6, direction: :right }) }
    result, = talk(4, 8, ledger:)
    refute_equal({ row: 4, col: 7 }, result[:standing_cell])
  end

  def test_fewest_turns_breaks_a_distance_tie
    result, = talk(2, 6, from: [4, 5])
    assert_equal({ row: 2, col: 5 }, result[:standing_cell])
    assert_equal :done, result[:stopped_by], result.inspect
  end

  def test_talks_and_a_dialogue_opens
    result, inputs = talk(4, 8)
    assert_equal :done, result[:stopped_by]
    assert result[:talked]
    assert_equal [4, 7], [result[:to][:row], result[:to][:col]]
    assert_equal :right, result[:facing]
    assert_includes inputs, [:a]
    assert result[:dialog_after]
  end

  def test_the_entity_faced_when_the_dialogue_opens_is_reported
    people = [{ slot: 1, type: 63, x: 136, y: 80, cell: [4, 8], kind: :npc }, { slot: 0, type: 62, x: 40, y: 32, cell: [1, 2], kind: :npc }]
    result, = talk(4, 8, entities: -> { people })
    assert_equal({ type: 63, slot: 1, kind: 'npc' }, result[:entity])
    result, = talk(4, 8, entities: -> { [people.last] })
    refute result.key?(:entity)
    result, = talk(4, 8)
    refute result.key?(:entity)
  end

  def test_already_standing_next_to_the_person_skips_walking
    result, = talk(4, 6, from: [4, 5])
    assert_equal 0, result[:path_length]
    assert_equal({ row: 4, col: 5 }, result[:standing_cell])
    assert result[:talked]
  end

  def test_no_response_when_nothing_opens
    result, inputs = talk(4, 8, opens_after: nil)
    assert_equal :no_response, result[:stopped_by]
    assert_equal false, result[:talked]
    assert_equal 9, inputs.count([:a])
    assert_equal 3, result[:standing_cells_tried].size
    assert_operator result[:frames], :<=, 400
  end

  def tried(result) = result[:standing_cells_tried].map { |t| [t[:row], t[:col], t[:outcome]] }

  def test_no_response_from_the_first_side_tries_another_one
    result, = talk(4, 8, open_cells: [[3, 8], [5, 8], [4, 9]])
    assert_equal :done, result[:stopped_by], result.inspect
    assert result[:talked]
    assert_equal 2, result[:standing_cells_tried].size
    assert_equal [4, 7, :no_response], tried(result).first
    assert_equal :done, tried(result).last.last
    assert_equal 1, result[:replans]
  end

  def test_every_side_failing_is_no_response_after_three_tries
    result, = talk(4, 8, open_cells: [])
    assert_equal :no_response, result[:stopped_by]
    assert_equal false, result[:talked]
    assert_equal 3, result[:standing_cells_tried].size
    assert_equal %i[no_response], tried(result).map(&:last).uniq
    assert_equal 3, tried(result).map { |r, c, _| [r, c] }.uniq.size
    assert_operator result[:frames], :<=, 400
  end

  def test_a_blocked_path_to_the_second_side_then_the_third
    result, = talk(4, 8, blocked: [[3, 8]], open_cells: [[4, 9]])
    assert_equal :done, result[:stopped_by], result.inspect
    assert_equal [[4, 7, :no_response], [5, 8, :no_response], [4, 9, :done]], tried(result)
    assert_operator result[:replans], :>=, 3
    assert_operator result[:frames], :<=, 400
  end

  def test_sides_known_to_give_no_response_come_last
    log = Koholint::TalkLog.new
    log.record(place: [1, 0], row: 4, col: 8, talked: false, standing: [[[4, 7], true]])
    result, = talk(4, 8, talk_log: log)
    assert_equal :done, result[:stopped_by], result.inspect
    refute_equal({ row: 4, col: 7 }, result[:standing_cell])
    assert_equal 1, result[:standing_cells_tried].size
  end

  def test_when_every_side_is_known_the_exclusion_does_not_prevent_a_retry
    log = Koholint::TalkLog.new
    log.record(place: [1, 0], row: 4, col: 8, talked: false, standing: [[[4, 7], true], [[3, 8], true], [[5, 8], true], [[4, 9], true]])
    result, = talk(4, 8, talk_log: log)
    assert_equal :done, result[:stopped_by], result.inspect
    assert_equal({ row: 4, col: 7 }, result[:standing_cell])
  end

  def test_target_free_when_link_walks_into_the_cell
    result, inputs = talk(4, 8, grid: FakeGrid.new(sprites: [[4, 8]]), free: true, opens_after: nil)
    assert_equal :target_free, result[:stopped_by]
    assert_equal false, result[:talked]
    refute_includes inputs, [:a]
  end

  def test_a_blocked_standing_cell_is_replaced_by_another_neighbour
    result, = talk(4, 8, blocked: [[4, 7]])
    assert_equal :done, result[:stopped_by], result.inspect
    assert result[:talked]
    assert_equal 1, result[:replans]
    refute_equal({ row: 4, col: 7 }, result[:standing_cell])
    assert_equal :right, result[:blocked_at][:direction]
  end

  def test_all_neighbours_blocked_is_no_path_naming_the_cells
    result, = talk(4, 9, grid: FakeGrid.new(sprites: [[4, 9]]), blocked: [[3, 9], [5, 9], [4, 8]])
    assert_equal :no_path, result[:stopped_by], result.inspect
    assert_equal 3, result[:replans]
    assert_equal false, result[:talked]
    assert_match(/blocked standing cells (\(\d,\d\)(, )?){3}/, result[:cause])
    refute_nil result[:blocked_at]
    assert_operator result[:frames], :<=, 400
  end

  def test_replans_are_bounded
    result, = talk(4, 8, grid: FakeGrid.new(sprites: [[4, 8]]), blocked: [[4, 7], [3, 8], [5, 8], [4, 9]])
    assert_equal :blocked, result[:stopped_by], result.inspect
    assert_equal Koholint::Skills::TalkTo::TALK_REPLANS, result[:replans]
    refute_nil result[:blocked_at]
    assert_operator result[:frames], :<=, 400
  end

  def test_target_free_carries_the_standing_cell_and_a_cause
    result, = talk(4, 8, free: true, opens_after: nil)
    assert_equal :target_free, result[:stopped_by]
    assert_equal({ row: 4, col: 7 }, result[:standing_cell])
    assert_match(/may not hold a person any more/, result[:cause])
  end

  def face_run(positions, grid: FakeGrid.new(sprites: [[4, 6]]), target: [4, 6], dialog_at: nil)
    x, y = centre(4, 5)
    execution = registry.start('talk_to', state(x:, y:), { row: target[0], col: target[1] }, { grid: })
    inputs = []
    index = 0
    400.times do |i|
      px, py = positions.call(i, x, y)
      buttons = execution.next_input(state(x: px, y: py, dialog_state: dialog_at && i >= dialog_at ? 3 : 0))
      break unless buttons

      inputs << buttons
      index += 1
    end
    [execution.result, inputs]
  end

  def test_contact_after_closing_some_pixels_goes_on_to_press_a
    [5, 8].each do |closing|
      positions = ->(i, x, y) { [x + [i, closing].min, y] }
      result, inputs = face_run(positions, dialog_at: 20)
      assert_equal :done, result[:stopped_by], "closing #{closing}: #{result.inspect}"
      assert result[:talked]
      assert_includes inputs, [:a]
      assert_equal [:right], inputs.flatten.uniq - [:a]
    end
  end

  def test_still_moving_after_the_cap_is_target_free
    positions = ->(i, x, y) { [x + (i / 3), y] }
    result, inputs = face_run(positions)
    assert_equal :target_free, result[:stopped_by]
    refute_includes inputs, [:a]
    assert_operator inputs.size, :<=, 18
  end

  def test_twelve_pixels_along_the_facing_axis_is_target_free
    result, inputs = face_run(->(i, x, y) { [x + i, y] })
    assert_equal :target_free, result[:stopped_by]
    refute_includes inputs, [:a]
    assert_operator result[:frames], :<=, 15
  end

  def test_a_target_the_grid_believes_free_finishes_without_pressing
    result, inputs = face_run(->(_i, x, y) { [x, y] }, grid: FakeGrid.new)
    assert_equal :target_free, result[:stopped_by]
    assert_equal [[]], inputs
    assert_equal 1, result[:frames]
  end

  def test_a_tall_target_is_approached_from_next_to_a_covered_cell
    grid = FakeGrid.new(sprites: [[3, 8], [4, 8]])
    [[3, 8], [4, 8]].each do |row, col|
      result, = talk(row, col, grid:, solid: [row, col])
      assert_equal :done, result[:stopped_by], result.inspect
      standing = [result[:standing_cell][:row], result[:standing_cell][:col]]
      refute_includes [[3, 8], [4, 8]], standing
      assert_includes [[row - 1, col], [row + 1, col], [row, col - 1], [row, col + 1]], standing
    end
  end

  def test_a_covered_neighbour_is_never_the_standing_cell
    result, = talk(4, 6, from: [4, 5], grid: FakeGrid.new(sprites: [[4, 6], [4, 5]]))
    refute_equal({ row: 4, col: 5 }, result[:standing_cell])
  end

  def test_a_person_at_the_edge_of_the_grid
    result, = talk(4, 9, grid: FakeGrid.new(sprites: [[4, 9]]))
    assert_equal({ row: 4, col: 8 }, result[:standing_cell])
    assert_equal :right, result[:facing]
    assert_equal :done, result[:stopped_by]
  end

  def test_a_dialogue_open_at_the_start_is_not_a_talk
    x, y = centre(4, 5)
    execution = registry.start('talk_to', state(x:, y:, dialog_state: 3), { row: 4, col: 6 }, { grid: FakeGrid.new(sprites: [[4, 6]]) })
    60.times { break unless execution.next_input(state(x:, y:, dialog_state: 3)) }
    assert_equal false, execution.result[:talked]
  end

  def test_a_dialogue_before_a_is_pressed_is_an_interruption
    result, inputs = talk(4, 8, dialogue_at: 1)
    assert_equal :dialogue, result[:stopped_by]
    assert_equal false, result[:talked]
    refute_includes inputs, [:a]
  end

  def test_a_dialogue_while_facing_is_an_interruption
    result, inputs = talk(4, 6, dialogue_at: 3)
    assert_equal :dialogue, result[:stopped_by]
    refute_includes inputs, [:a]
  end

  def test_room_change_and_damage_interrupt
    assert_equal :room_change, talk(4, 8, room_change_at: 3)[0][:stopped_by]
    assert_equal :damage, talk(4, 8, damage_at: 3)[0][:stopped_by]
    assert_equal :room_change, talk(4, 6, room_change_at: 4)[0][:stopped_by]
    assert_equal :damage, talk(4, 6, damage_at: 4)[0][:stopped_by]
  end

  def test_no_path_cause_carries_the_forbidden_trigger_text
    triggers = Koholint::Triggers.new
    triggers.record(place: [1, 0], cell: [4, 5], skill: 'walk', input: :right)
    walls = [[3, 5], [5, 5], [3, 6], [5, 6], [4, 4], [3, 7], [5, 7], [3, 8], [5, 8], [4, 9]]
    result, = talk(4, 7, from: [4, 5], grid: FakeGrid.new(sprites: [[4, 7]], walls:), triggers:)
    assert_equal :no_path, result[:stopped_by], result.inspect
    assert_includes result[:cause], 'edges where the game opens a dialogue by itself: (4,5) right'
  end

  def test_no_reachable_neighbour_is_no_path_after_one_idle_frame
    walls = [[4, 7], [3, 8], [5, 8], [4, 9]]
    result, inputs = talk(4, 8, grid: FakeGrid.new(walls:, sprites: [[4, 8]]))
    assert_equal :no_path, result[:stopped_by]
    assert_equal 1, result[:frames]
    assert_equal [[]], inputs
    assert_nil result[:standing_cell]
    assert_match(/no reachable cell next to the target/, result[:cause])
    assert_equal false, result[:talked]
  end

  def test_without_a_grid_is_no_path
    execution = registry.start('talk_to', state(x: 88, y: 72), { row: 4, col: 8 })
    assert_equal [], execution.next_input(state(x: 88, y: 72))
    assert_nil execution.next_input(state(x: 88, y: 72))
    result = execution.result
    assert_equal :no_path, result[:stopped_by]
    assert_equal 'no grid', result[:cause]
  end

  def test_blocked_walk_reports_blocked_at
    result, = talk(4, 8, grid: FakeGrid.new(sprites: [[4, 8]]), blocked: [[4, 7], [3, 8], [5, 8], [4, 9]])
    assert_equal :blocked, result[:stopped_by]
    assert_kind_of Symbol, result[:blocked_at][:direction]
  end

  def test_frame_cap
    execution = registry.start('talk_to', state(x: 88, y: 72), { row: 4, col: 9 }, { grid: FakeGrid.new })
    count = 0
    count += 1 while execution.next_input(state(x: 88 + (count % 2), y: 72)) && count < 1000
    assert_equal 400, count
    assert_equal :frame_cap, execution.result[:stopped_by]
  end

  def test_params_validation
    [{ row: 8, col: 0 }, { row: 0, col: 10 }, { row: -1, col: 0 }, { row: '1', col: 0 }, { row: 1 }, { row: 1, col: 1, x: 2 }, 5].each do |bad|
      assert_raises(ArgumentError, bad.inspect) { registry.validate('talk_to', bad) }
      assert_raises(ArgumentError, bad.inspect) { registry.start('talk_to', state(x: 88, y: 72), bad) }
    end
    assert_equal({ row: 2, col: 3 }, registry.validate('talk_to', { 'row' => 2, 'col' => 3 }))
  end

  def test_decision_point_lists_talk_to
    point = Koholint::DecisionPoint.choose_skill(registry)
    assert_includes point.json_schema.to_json, '"talk_to"'
    assert_equal 'talk_to', point.validate({ 'skill' => 'talk_to', 'params' => { 'row' => 2, 'col' => 3 } })[:skill]
    assert_raises(Koholint::DecisionPoint::Invalid) { point.validate({ 'skill' => 'talk_to', 'params' => { 'row' => 9, 'col' => 3 } }) }
  end

  def test_rom_talk_to_a_person_in_the_house
    skip_without_rom!
    emulator = Koholint::Emulator.restore(EmulatorCache.interactive.dump)
    state = Koholint::Perception.read(emulator)
    trace = Struct.new(:events) { def emit(*, **) = nil }.new([])
    builder = Koholint::Vision::GridBuilder.new(trace:, prober: ProbeAdapter.new)
    grid = 2.times.map { builder.observe(emulator, state) }.last
    people = (0...8).to_a.product((0...10).to_a).select { |r, c| grid.static_sprite(r, c) }
    report = people.to_h do |cell|
      copy = Koholint::Emulator.restore(emulator.dump)
      execution = registry.start('talk_to', Koholint::Perception.read(copy), { row: cell[0], col: cell[1] }, { grid: })
      while (buttons = execution.next_input(Koholint::Perception.read(copy)))
        copy.step(buttons)
      end
      [cell, execution.result(Koholint::Perception.read(copy)).slice(:stopped_by, :talked, :standing_cell, :facing, :frames, :cause, :to, :dialog_after)]
    end
    puts "\nROM talk_to: #{report.inspect}"
    refute(report.values.any? { |r| r[:stopped_by] == :no_path })
    [[2, 5], [4, 7]].each do |cell|
      assert_equal :done, report.fetch(cell)[:stopped_by], cell.inspect
      assert report.fetch(cell)[:talked], cell.inspect
      assert report.fetch(cell)[:dialog_after], cell.inspect
    end
  end

  def test_rom_talk_to_with_the_nearest_side_excluded_talks_from_another
    skip_without_rom!
    emulator = Koholint::Emulator.restore(EmulatorCache.interactive.dump)
    state = Koholint::Perception.read(emulator)
    trace = Struct.new(:events) { def emit(*, **) = nil }.new([])
    builder = Koholint::Vision::GridBuilder.new(trace:, prober: ProbeAdapter.new)
    grid = 2.times.map { builder.observe(emulator, state) }.last
    log = Koholint::TalkLog.new
    log.record(place: [state.room_id, state.map_id], row: 4, col: 7, talked: false, standing: [[[3, 7], true], [[4, 6], true]])
    copy = Koholint::Emulator.restore(emulator.dump)
    execution = registry.start('talk_to', Koholint::Perception.read(copy), { row: 4, col: 7 }, { grid:, talk_log: log })
    while (buttons = execution.next_input(Koholint::Perception.read(copy)))
      copy.step(buttons)
    end
    result = execution.result(Koholint::Perception.read(copy))
    puts "\nROM talk_to with (3,7) and (4,6) excluded: #{result.slice(:stopped_by, :talked, :standing_cell, :standing_cells_tried, :frames).inspect}"
    assert_equal :done, result[:stopped_by], result.inspect
    assert result[:talked]
    refute_equal({ row: 3, col: 7 }, result[:standing_cells_tried].first.slice(:row, :col))
    assert_operator result[:replans], :>=, 1
  end

  class ProbeAdapter
    def run(emulator, **options) = Koholint::Calibration::WalkProbe.run(emulator, **options)
  end
end
