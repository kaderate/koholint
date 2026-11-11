require_relative 'test_helper'
require 'tmpdir'
require 'json'
require 'koholint/checkpoints'

class CheckpointsTest < Minitest::Test
  POINT = { 'name' => 'sword-obtained', 'run' => '20261111-194737-9ba1', 'frame' => 60_404, 'flow' => 'flow-37', 'source' => 's' }.freeze
  Parent = Struct.new(:id, :manifest)

  def load(entries)
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'checkpoints.json')
      File.write(path, JSON.generate(entries))
      Koholint::Checkpoints.load(path)
    end
  end

  def test_the_catalogue_loads_the_sword_checkpoint
    point = Koholint::Checkpoints.load.fetch('sword-obtained')
    assert_equal ['20261111-194737-9ba1', 60_404, 'flow-37'], point.values_at('run', 'frame', 'flow')
  end

  def test_bad_entries_are_refused
    bad = [POINT.except('source'), POINT.merge('extra' => 1), POINT.merge('name' => 'Sword Obtained'), POINT.merge('run' => '9ba1'),
           POINT.merge('frame' => -1), POINT.merge('frame' => '60404'), POINT.merge('flow' => '37'), POINT.merge('source' => ' '), 'sword']
    bad.each { |entry| assert_raises(Koholint::Checkpoints::Invalid, entry.inspect) { load([entry]) } }
    assert_raises(Koholint::Checkpoints::Invalid) { load([POINT, POINT.merge('frame' => 1)]) }
    assert_raises(Koholint::Checkpoints::Invalid) { load({}) }
    assert_equal({ 'sword-obtained' => POINT }, load([POINT.merge('note' => 'n')]).transform_values { |p| p.except('note') })
  end

  def test_a_frame_or_a_checkpoint_of_the_same_run_and_flow_resolves_to_a_frame
    points = load([POINT])
    parent = Parent.new('20261111-194737-9ba1', { 'flow_version' => 'flow-37' })
    assert_equal 60_404, Koholint::Checkpoints.frame_for(parent, 'sword-obtained', points)
    assert_equal 1200, Koholint::Checkpoints.frame_for(parent, '1200', points)
    assert_equal [8, 10], %w[08 010].map { |at| Koholint::Checkpoints.frame_for(parent, at, points) }
    assert_raises(Koholint::Error) { Koholint::Checkpoints.frame_for(parent, 'shield-obtained', points) }
    assert_raises(Koholint::Error) { Koholint::Checkpoints.frame_for(Parent.new('20261111-142812-34ca', parent.manifest), 'sword-obtained', points) }
    assert_raises(Koholint::Error) { Koholint::Checkpoints.frame_for(Parent.new(parent.id, { 'flow_version' => 'flow-36' }), 'sword-obtained', points) }
  end
end
