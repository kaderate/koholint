require_relative 'test_helper'
require 'koholint/vision/capabilities'
require 'koholint/vision/beliefs'

class BeliefsTest < Minitest::Test
  Caps = Koholint::Vision::Capabilities
  Beliefs = Koholint::Vision::Beliefs

  def setup
    @beliefs = Beliefs.new
    @frame = 0
  end

  def record(appearance: 'a1', action: :walk, direction: nil, result:, context: Caps.new, method: :probe, source: 'test')
    @beliefs.record(appearance:, action:, direction:, result:, method:, context:, frame: (@frame += 1), source:)
  end

  def query(appearance: 'a1', action: :walk, direction: nil, context: Caps.new)
    @beliefs.query(appearance:, action:, direction:, context:)
  end

  def test_unknown_is_not_blocked
    assert_equal :unknown, query
    record(appearance: 'b2', result: :no)
    assert_equal :unknown, query
    assert_equal :unknown, query(action: :push)
  end

  def test_blocked_without_swim_is_stale_with_swim
    record(result: :no)
    assert_equal :no, query
    assert_equal :stale, query(context: Caps.new(['swim']))
    record(result: :yes, context: Caps.new(['swim']))
    assert_equal :yes, query(context: Caps.new(['swim']))
    assert_equal :no, query
  end

  def test_one_way_ledge
    record(direction: :down, result: :yes)
    record(direction: :up, result: :no)
    assert_equal :yes, query(direction: :down)
    assert_equal :no, query(direction: :up)
    assert_equal :unknown, query
    assert_equal :unknown, query(direction: :left)
  end

  def test_direction_specific_beats_directionless
    record(result: :no)
    record(direction: :down, result: :yes)
    assert_equal :yes, query(direction: :down)
    assert_equal :no, query(direction: :left)
    assert_equal :unknown, query
  end

  def test_directionless_answers_directionless_query_but_only_directional_evidence_does_not
    record(result: :no)
    assert_equal :no, query
    record(appearance: 'c3', direction: :up, result: :no)
    record(appearance: 'c3', direction: :down, result: :no)
    assert_equal :unknown, query(appearance: 'c3')
    record(direction: :down, result: :no)
    assert_equal :no, query
  end

  def test_direction_precedence_ignores_other_context_for_deciding
    record(direction: :down, result: :yes, context: Caps.new(['swim']))
    assert_equal :stale, query(direction: :down)
  end

  def test_latest_evidence_wins_within_a_context
    record(result: :no)
    record(result: :yes)
    assert_equal :yes, query
    record(result: :no)
    assert_equal :no, query
  end

  def test_ties_on_frame_go_to_later_insertion
    @beliefs.record(appearance: 'a1', action: :walk, direction: nil, result: :no, method: :probe, context: Caps.new, frame: 5, source: 's')
    @beliefs.record(appearance: 'a1', action: :walk, direction: nil, result: :yes, method: :probe, context: Caps.new, frame: 5, source: 's')
    assert_equal :yes, query
  end

  def test_evidence_keeps_provenance
    record(direction: :left, result: :no, method: :bump, source: 'run-7')
    ev = @beliefs.evidence_for('a1', :walk).first
    assert_equal 'a1', ev[:appearance]
    assert_equal :walk, ev[:action]
    assert_equal :left, ev[:direction]
    assert_equal :no, ev[:result]
    assert_equal :bump, ev[:method]
    assert_equal Caps.new, ev[:context]
    assert_equal 1, ev[:frame]
    assert_equal 'run-7', ev[:source]
    assert_empty @beliefs.evidence_for('a1', :push)
  end

  def test_capabilities_equality_ignores_order
    a = Caps.new(%w[swim sword])
    b = Caps.new([:sword, :swim])
    assert_equal a, b
    assert a.eql?(b)
    assert_equal a.hash, b.hash
    assert_equal %w[swim sword], a.to_a
    assert_equal %w[swim sword], b.to_a
    refute_equal a, Caps.new(['swim'])
    assert_equal 1, { a => 1 }.merge(b => 2).size
  end

  def test_from_events_rebuilds_affordance_events_only
    events = [
      { 'type' => 'note', 'frame' => 1 },
      { 'type' => 'affordance', 'appearance' => 'a1', 'action' => 'walk', 'direction' => 'down',
        'result' => 'yes', 'method' => 'probe', 'context' => ['swim'], 'source' => 'r1', 'frame' => 10 },
      { 'type' => 'affordance', 'appearance' => 'a1', 'action' => 'walk', 'direction' => nil,
        'result' => 'no', 'method' => 'probe', 'context' => [], 'source' => 'r1', 'frame' => 20 }
    ]
    beliefs = Beliefs.from_events(events)
    assert_equal 2, beliefs.evidence_for('a1', :walk).size
    assert_equal :yes, beliefs.query(appearance: 'a1', action: :walk, direction: :down, context: Caps.new(['swim']))
    assert_equal :no, beliefs.query(appearance: 'a1', action: :walk, direction: nil, context: Caps.new)
    assert_equal :down, beliefs.evidence_for('a1', :walk).first[:direction]
  end
end
