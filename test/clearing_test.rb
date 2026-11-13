require_relative 'test_helper'
require 'koholint/game_state'
require 'koholint/learn'
require 'koholint/skills/registry'

class ClearingTest < Minitest::Test
  class Once
    def next_input(_state) = (@done = !@done) ? [] : nil
    def result(_state) = { stopped_by: :done, capability: { id: 'sword-on-object-92', version: 1 }, object_before: 92, object_after: 4 }
  end

  class StubRegistry
    attr_reader :started, :composites

    def initialize(composites) = (@composites = composites) && (@started = [])

    def start(name, _state, params, _context)
      @started << [name, params]
      Once.new
    end
  end

  def state = Koholint::GameState.new(frame: 0, room_id: 160, map_id: 0, x: 88, y: 82, hp: 16, item_a: 1, item_b: 4, dialog_state: 0, game_mode: 0x0B, game_submode: 7)

  def composite = Koholint::Skills::Composite.new(Koholint::Learn.hypothesis(gain: { item: 1, frame: 1 }, object: 92, run: '20261112-103604-0c64'))

  def objects(*cells)
    grid = Array.new(8) { Array.new(10, 0) }
    cells.each { |r, c| grid[r][c] = 92 }
    -> { grid }
  end

  def test_needs_published_composites_and_the_room_objects
    assert_nil Koholint::Skills::Clearing.of({ registry: StubRegistry.new([]), room_objects: objects([1, 1]) })
    assert_nil Koholint::Skills::Clearing.of({ registry: StubRegistry.new([composite]) })
    assert_nil Koholint::Skills::Clearing.of({ registry: StubRegistry.new([composite]), room_objects: objects([1, 1]), held: [4] }), 'not without the item it was learned with'
    refute_nil Koholint::Skills::Clearing.of({ registry: StubRegistry.new([composite]), room_objects: objects([1, 1]), held: [1, 4] })
    clearing = Koholint::Skills::Clearing.of({ registry: StubRegistry.new([composite]), room_objects: objects([1, 1], [2, 3]), held: [1] })
    assert_equal [[1, 1], [2, 3]], clearing.cells.keys
  end

  def test_runs_the_composite_once_when_blocked_facing_its_object
    row, col = state.cell
    registry = StubRegistry.new([composite])
    clearing = Koholint::Skills::Clearing.of({ registry:, room_objects: objects([row + 1, col]), held: [1] })
    assert_nil clearing.start(state, :up)
    assert_equal [], clearing.start(state, :down)
    assert clearing.active?
    assert_equal [], clearing.step(state)
    refute clearing.active?
    assert_equal [[composite.name, { row:, col:, direction: 'down' }]], registry.started
    assert_equal [4], clearing.uses.map { |use| use[:object_after] }
    assert_nil clearing.start(state, :down)
  end

  def test_a_use_records_the_tile_it_cleared
    row, col = state.cell
    grid = Struct.new(:look) { def appearance(_row, _col) = look }.new('5ba789e1')
    clearing = Koholint::Skills::Clearing.of({ registry: StubRegistry.new([composite]), room_objects: objects([row + 1, col]), held: [1], grid: })
    clearing.start(state, :down)
    clearing.step(state)
    assert_equal ['5ba789e1'], clearing.uses.map { |use| use[:look] }
  end

  def test_a_composite_never_clears_from_its_own_steps
    registry = StubRegistry.new([composite])
    context = { registry:, room_objects: objects([1, 1]), held: [1] }
    run = composite.start(state, { row: 1, col: 0, direction: 'right' }, context)
    steps = run.instance_variable_get(:@context)
    assert_equal composite.name, steps[:composite]
    assert_nil Koholint::Skills::Clearing.of(steps)
    assert_equal [], Array(Koholint::Skills::Execution.new(skill: 'goto', params: {}, state:).send(:pushable_of, steps)&.call)
    refute_nil Koholint::Skills::Clearing.of(context)
  end

  def test_object_cells_join_the_pushable_cells
    context = { registry: StubRegistry.new([composite]), room_objects: objects([3, 8]), held: [1, 4], entities: -> { [{ kind: 'enemy', moves: false, cell: [1, 1] }] } }
    host = Koholint::Skills::Execution.new(skill: 'goto', params: {}, state:)
    assert_equal [[1, 1], [3, 8]], host.send(:pushable_of, context).call
    assert_equal [[3, 8]], host.send(:pushable_of, context.merge(held: [1])).call, 'urchins are pushed aside only with the shield held'
  end
end
