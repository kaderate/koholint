require_relative 'test_helper'
require 'koholint/game_state'
require 'koholint/learn'
require 'koholint/skills/registry'

class CompositeTest < Minitest::Test
  class Scripted
    attr_reader :stopped_by

    def initialize(frames:, stop:, to: nil)
      @left = frames
      @stop = stop
      @to = to
    end

    def next_input(_state)
      return [] if (@left -= 1) >= 0

      @stopped_by = @stop
      nil
    end

    def result(_state) = { stopped_by: @stop, frames: 1, to: @to }
  end

  class StubRegistry
    attr_reader :started

    def initialize(script) = (@script = script) && (@started = [])

    def start(name, _state, params, context)
      @started << [name, params, context.key?(:registry)]
      @script.shift
    end
  end

  def state = Koholint::GameState.new(frame: 0, room_id: 224, map_id: 0, x: 88, y: 82, hp: 16, item_a: 1, item_b: 4, dialog_state: 0, game_mode: 0x0B)

  def composite = Koholint::Skills::Composite.new(Koholint::Learn.hypothesis(gain: { item: 1, frame: 1 }, object: 92, run: '20261112-103604-0c64'))

  def drive(execution, limit: 100)
    limit.times { execution.next_input(state) or break }
    execution.result(state)
  end

  def script(last_stop: :done, to: { row: 6, col: 5 }, blocked: :blocked)
    [Scripted.new(frames: 2, stop: :done), Scripted.new(frames: 1, stop: blocked), Scripted.new(frames: 3, stop: :done),
     Scripted.new(frames: 1, stop: :done), Scripted.new(frames: 2, stop: last_stop, to:)]
  end

  def test_steps_run_in_order_with_their_parameters_and_enter_the_target
    registry = StubRegistry.new(script)
    result = drive(composite.start(state, { 'row' => 5, 'col' => 5, 'direction' => 'down' }, { registry: }))
    assert_equal %w[goto step use_item wait walk], registry.started.map(&:first)
    assert_equal({ 'row' => 5, 'col' => 5 }, registry.started[0][1])
    assert_equal({ 'direction' => 'down', 'pixels' => 16 }, registry.started[1][1])
    assert_equal({ 'item' => 'sword', 'frames' => 3 }, registry.started[2][1])
    assert(registry.started.all?(&:last))
    assert_equal :done, result[:stopped_by]
    assert_equal true, result[:effect]
    assert_equal({ id: 'sword-on-object-92', version: 1 }, result[:capability])
    assert_equal({ row: 6, col: 5 }, result[:target])
    assert_equal %i[done blocked done done done], result[:steps].map { |step| step[:stopped_by] }
  end

  def test_an_unaccepted_stop_ends_the_composite
    registry = StubRegistry.new(script(blocked: :done))
    result = drive(composite.start(state, { row: 5, col: 5, direction: 'down' }, { registry: }))
    assert_equal :step_failed, result[:stopped_by]
    assert_equal false, result[:effect]
    assert_equal %i[done done], result[:steps].map { |step| step[:stopped_by] }
  end

  def test_a_room_change_on_the_last_walk_is_not_an_effect
    result = drive(composite.start(state, { row: 5, col: 5, direction: 'down' }, { registry: StubRegistry.new(script(last_stop: :room_change)) }))
    assert_equal :step_failed, result[:stopped_by]
    assert_equal false, result[:effect]
  end

  def test_ending_next_to_the_target_is_not_an_effect
    result = drive(composite.start(state, { row: 5, col: 5, direction: 'down' }, { registry: StubRegistry.new(script(to: { row: 5, col: 5 })) }))
    assert_equal :done, result[:stopped_by]
    assert_equal false, result[:effect]
  end

  def test_parameters_are_checked
    assert_raises(ArgumentError) { composite.normalize({ row: 8, col: 0, direction: 'up' }) }
    assert_raises(ArgumentError) { composite.normalize({ row: 0, col: 0, direction: 'north' }) }
    assert_raises(ArgumentError) { composite.normalize({ row: 0, col: 0 }) }
  end

  def test_the_real_registry_passes_itself_and_never_shields_the_composite
    registry = Koholint::Skills::Registry.default(extra: [composite])
    assert_includes registry.names, 'sword_on_object_92'
    assert_includes registry.schema[:skill][:enum], 'sword_on_object_92'
    execution = registry.start('sword_on_object_92', state, { row: 5, col: 5, direction: 'down' }, { entities: -> { [] } })
    refute_kind_of Koholint::Skills::Shielded, execution
    result = drive(execution)
    assert_equal 'goto', result[:steps].first[:skill]
    assert_equal :step_failed, result[:stopped_by]
    assert_equal 4500, composite.max_frames
  end
end
