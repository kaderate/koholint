require_relative 'test_helper'
require 'tmpdir'
require 'koholint/capabilities'
require 'koholint/learn'

class CapabilitiesTest < Minitest::Test
  C = Koholint::Capabilities

  def entry = Koholint::Learn.hypothesis(gain: { item: 1, frame: 60404 }, object: 92, run: '20261112-103604-0c64')

  def success(place) = { 'outcome' => 'success', 'place' => place, 'run' => '20261112-163010-2c3c', 'parent' => '20261112-103604-0c64', 'frame' => 64134 }

  def refuses(message, entries)
    error = assert_raises(C::Invalid) { C.validate_all!(entries) }
    assert_match message, error.message
  end

  def test_the_committed_file_loads
    assert_kind_of Array, C.load
  end

  def test_a_learned_hypothesis_is_valid_and_round_trips
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'capabilities.json')
      C.write([entry], path)
      assert_equal [entry], C.load(path)
    end
    assert_equal 'sword_on_object_92', entry['name']
    assert_equal 'sword-on-object-92', entry['id']
    refute_match(/--object/, entry['source'])
    assert_match(/selected by --object/, Koholint::Learn.hypothesis(gain: { item: 1, frame: 1 }, object: 92, run: '20261112-103604-0c64', selected: true)['source'])
  end

  def test_refusals
    refuses(/missing evidence/, [entry.except('evidence')])
    refuses(/unknown key extra/, [entry.merge('extra' => 1)])
    refuses(/status must be/, [entry.merge('status' => 'trusted', 'history' => [entry['history'][0].merge('status' => 'trusted')])])
    refuses(/skill fly cannot be composed/, [entry.merge('steps' => [{ 'skill' => 'fly', 'params' => {}, 'accept' => %w[done] }])])
    refuses(/skill explore cannot be composed/, [entry.merge('steps' => [{ 'skill' => 'explore', 'params' => {}, 'accept' => %w[done] }])])
    refuses(/unknown parameter \$speed/, [entry.merge('steps' => [{ 'skill' => 'walk', 'params' => { 'direction' => '$speed' }, 'accept' => %w[done] }])])
    refuses(/one record per version/, [entry.merge('version' => 2)])
    refuses(/used twice/, [entry, entry])
    refuses(/target must name/, [entry.merge('target' => {})])
  end

  def test_validated_needs_successes_in_two_places
    one = C.transition(entry, 'validated', 'test', evidence: [success([224, 0]), success([224, 0])])
    refuses(/successes in 2 places/, [one])
    two = C.transition(entry, 'validated', 'test', evidence: [success([224, 0]), success([209, 0])])
    C.validate_all!([two])
    %w[place run parent frame].each do |key|
      bare = C.transition(entry, 'validated', 'test', evidence: [success([224, 0]).except(key), success([209, 0])])
      refuses(/a success needs place, run, parent and frame/, [bare])
    end
    refuses(/a success needs/, [C.transition(entry, 'inconclusive', 'test', evidence: [success([224, 0]).merge('run' => 'tmp')])])
    assert_equal [], C.operational([two])
  end

  def test_transition_keeps_every_earlier_state
    later = C.transition(C.transition(entry, 'inconclusive', 'first'), 'rejected', 'second')
    assert_equal 3, later['version']
    assert_equal %w[hypothesis inconclusive rejected], later['history'].map { |record| record['status'] }
    assert_equal 'rejected', later['status']
  end
end
