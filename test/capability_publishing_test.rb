require_relative 'support/delegated_helpers'
require 'koholint/ab'
require 'koholint/capabilities'
require 'koholint/learn'
require 'koholint/run'

class CapabilityPublishingTest < Minitest::Test
  include DelegatedHelpers

  C = Koholint::Capabilities

  def success(place) = { 'outcome' => 'success', 'place' => place, 'run' => '20261112-163010-2c3c', 'parent' => '20261112-103604-0c64', 'frame' => 64134 }

  def validated
    entry = Koholint::Learn.hypothesis(gain: { item: 1, frame: 60404 }, object: 92, run: '20261112-103604-0c64')
    C.transition(entry, 'validated', 'test', evidence: [success([224, 0]), success([193, 0])])
  end

  def operational = C.publish([validated], 'sword-on-object-92', 'test').first

  def test_publish_and_retire_move_the_status_and_the_digest
    published = C.publish([validated], 'sword-on-object-92', 'reviewed')
    assert_equal 'operational', published.first['status']
    refute_equal C.empty_digest, C.digest(C.operational(published))
    assert_equal C.digest(C.operational(published)), C.digest(C.operational(published.map(&:dup)))
    retired = C.retire(published, 'sword-on-object-92', 'regressed')
    assert_equal %w[hypothesis validated operational deprecated], retired.first['history'].map { |record| record['status'] }
    assert_equal C.empty_digest, C.digest(C.operational(retired))
    assert_equal 'operational', C.publish(retired, 'sword-on-object-92', 'again').first['status']
    assert_raises(C::Invalid) { C.retire([validated], 'sword-on-object-92', 'x') }
    assert_raises(C::Invalid) { C.publish([validated], 'nothing', 'x') }
    C.validate_all!(retired)
  end

  def test_describe_names_the_item_the_object_and_the_places
    assert_equal 'uses the sword facing object 92 and steps into its cell; validated by experiment in 224-0 and 193-0: the object was cleared and Link walked into its cell',
                 C.describe(operational)
  end

  def with_run(**options)
    Dir.mktmpdir do |dir|
      rom = File.join(dir, 'game.gbc')
      File.binwrite(rom, 'fake rom bytes')
      yield Koholint::Run.create(root: dir, flow_version: 'f1', budget: {}, rom_path: rom, **options), rom, dir
    end
  end

  def test_runs_record_the_digest_and_resume_only_with_it
    with_run(capabilities: 'abc') do |run, rom|
      assert_equal 'abc', run.manifest['capabilities']
      run.check_capabilities!('abc')
      error = assert_raises(Koholint::Run::CapabilitiesMismatch) { run.check_capabilities!('def') }
      assert_includes error.message, 'recorded with capabilities abc, current is def'
      assert_includes error.message, "koholint fork #{run.dir} --at-frame 0"
      assert_equal 'abc', Koholint::Run.open(run.dir, flow_version: 'f1', rom_path: rom).manifest['capabilities']
    end
  end

  def test_a_missing_key_is_the_empty_set_and_false_always_opens
    with_run do |run|
      run.manifest.delete('capabilities')
      run.check_capabilities!(C.empty_digest)
      assert_raises(Koholint::Run::CapabilitiesMismatch) { run.check_capabilities!('def') }
      run.manifest['capabilities'] = false
      run.check_capabilities!('def')
    end
  end

  def test_fork_takes_the_current_set_unless_turned_off
    with_run(capabilities: 'old') do |run, rom|
      assert_equal C.digest, run.fork(at_frame: 0, flow_version: 'f1', rom_path: rom).manifest['capabilities']
      off = run.fork(at_frame: 0, flow_version: 'f1', rom_path: rom, capabilities: false)
      assert_equal false, off.manifest['capabilities']
      assert_equal false, off.fork(at_frame: 0, flow_version: 'f1', rom_path: rom).manifest['capabilities']
      assert_equal C.digest, off.fork(at_frame: 0, flow_version: 'f1', rom_path: rom, capabilities: true).manifest['capabilities']
    end
  end

  def skill_names(policy, context)
    policy.prepare(context)
    policy.decision_point_for(state).registry.names
  end

  def test_the_policy_offers_a_capability_only_while_its_object_is_on_screen
    composite = Koholint::Skills::Composite.new(operational)
    client = ScriptedClient.new(objective: objective, default: walk)
    policy = Koholint::Policies::Delegated.new(client:, registry: Koholint::Skills::Registry.default(extra: [composite]),
                                               objectives: (@objectives = Koholint::Objectives.new(trace:)), manual: 'notes')
    objects = Array.new(8) { Array.new(10, 4) }
    context = -> { { grid:, room_objects: -> { objects } } }
    point = policy.tap { |p| p.prepare(context.call) }.decision_point_for(state)
    policy.decide(point, state, context.call)
    refute_includes skill_names(policy, context.call), 'sword_on_object_92'
    policy.decide(policy.decision_point_for(state), state, context.call)
    refute_includes client.calls.last[:prompt], 'Learned skills'
    objects[6][5] = 92
    assert_includes skill_names(policy, context.call), 'sword_on_object_92'
    policy.decide(policy.decision_point_for(state), state, context.call)
    assert_includes client.calls.last[:prompt], 'Learned skills'
    assert_includes client.calls.last[:prompt], 'sword_on_object_92 (row, col, direction): uses the sword facing object 92'
    assert_includes client.calls.last[:prompt], 'Object 92 here at (6,5)'
    assert_includes client.calls.last[:schema].to_s, 'sword_on_object_92'
    without = -> { { grid:, room_objects: -> { objects }, held: [4] } }
    refute_includes skill_names(policy, without.call), 'sword_on_object_92', 'not offered without its item (fef5: 194 uses before the sword)'
    assert_includes skill_names(policy, without.call.merge(held: [1, 4])), 'sword_on_object_92'
  end

  def test_a_use_records_the_object_before_and_after
    composite = Koholint::Skills::Composite.new(operational)
    cells = Array.new(8) { Array.new(10, 4) }
    cells[6][5] = 92
    registry = Koholint::Skills::Registry.default(extra: [composite])
    execution = registry.start('sword_on_object_92', state, { row: 5, col: 5, direction: 'down' }, { room_objects: -> { cells } })
    cells[6][5] = 4
    result = execution.result(state)
    assert_equal [92, 4], result.values_at(:object_before, :object_after)
    assert_equal({ id: 'sword-on-object-92', version: 3 }, result[:capability])
  end

  def test_progress_counts_new_places_items_and_milestones_over_the_fork_start
    seen = ->(frame, room, milestone) { { 'type' => 'perception', 'frame' => frame, 'state' => { 'game_mode' => 0x0B, 'game_submode' => 7, 'room_id' => room, 'map_id' => 0, 'milestone' => milestone } } }
    before = [seen.(10, 1, 'shield'), seen.(20, 2, 'shield')]
    assert_equal 0, Koholint::AB.progress(before, [seen.(100, 1, 'sword'), seen.(200, 2, 'sword')])
    assert_equal 3, Koholint::AB.progress(before, [seen.(100, 1, 'shield'), seen.(200, 3, 'sword'), { 'type' => 'item_gained', 'frame' => 150 }])
  end

  def test_the_ab_plan_and_the_usage_criterion
    Dir.mktmpdir do |dir|
      record, = Koholint::AB.plan(parent: 'runs/p', at_frame: 60404, arms: %w[capabilities no-capabilities], forks: 3, dollars: 1.0, frames: 6000, out_dir: dir)
      fork = record[:runs].find { |run| run[:tag] == 'ab-no-capabilities-2' }
      assert_equal %w[--autopilot on --capabilities off], fork[:fork].last(4)
      assert_equal %w[--agent --autopilot on --max-dollars], fork[:resume][2, 4]
    end
    row = ->(chosen, cleared) { { 'capabilities' => { chosen_forks: chosen, capability_cleared: cleared } } }
    assert_equal 'pass', Koholint::AB.criterion(row.(2, 1))[:verdict]
    assert_equal 'fail', Koholint::AB.criterion(row.(1, 3))[:verdict]
    assert_equal 'fail', Koholint::AB.criterion(row.(3, 0))[:verdict]
    assert_equal 'incomplete', Koholint::AB.criterion({ 'no-capabilities' => {}, 'capabilities' => nil })[:verdict]
  end
end
