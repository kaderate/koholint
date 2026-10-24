require_relative 'test_helper'
require 'stringio'
require 'tmpdir'
require 'json'
require 'koholint/ab'
require 'koholint/cli'

class ABTest < Minitest::Test
  PLAYING = { 'game_mode' => 0x0B, 'game_submode' => 7, 'room_id' => 1, 'map_id' => 0, 'x' => 40, 'y' => 40, 'hp' => 24, 'max_hp' => 24 }.freeze

  def test_plan_writes_the_fork_and_resume_commands_of_every_arm_and_fork
    Dir.mktmpdir do |dir|
      record, script = Koholint::AB.plan(parent: 'runs/p', at_frame: 6100, forks: 2, root: File.join(dir, 'runs'), out_dir: dir, model: 'haiku')
      assert_equal %w[ab-autopilot-1 ab-off-1 ab-autopilot-2 ab-off-2], record[:runs].map { |run| run[:tag] }
      plan = JSON.parse(File.read(File.join(dir, 'plan.json')))
      assert_equal [6100, 0.8, 3000], plan.values_at('at_frame', 'max_dollars', 'frames')
      text = File.read(script)
      assert File.executable?(script)
      assert_includes text, "fork runs/p --at-frame 6100 --root #{File.join(dir, 'runs')} --tag ab-off-2 --autopilot off | sed -n 's/^run //p')"
      assert_includes text, 'resume "$child" --agent --autopilot on --max-dollars 0.8 --frames 3000 --model haiku'
      assert_equal 4, text.scan('resume "$child"').size
      assert text.end_with?("ab-report ab --root #{File.join(dir, 'runs')}\n")
      assert_raises(Koholint::Error) { Koholint::AB.plan(parent: 'p', at_frame: 1, arms: %w[jev], out_dir: dir) }
    end
  end

  def fixture(root, tag, cost:, places:, autopilot:, stalls: 0)
    dir = File.join(root, tag)
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, 'manifest.json'), JSON.generate('tag' => tag, 'parent' => { 'id' => 'p', 'frame' => 1000 }, 'autopilot' => autopilot))
    events = [{ 'type' => 'perception', 'frame' => 10, 'state' => PLAYING },
              { 'type' => 'decision', 'frame' => 20, 'agent' => 'claude', 'cost_usd' => 5.0, 'prompt_sha' => 'x' }]
    places.times do |n|
      events << { 'type' => 'perception', 'frame' => 1000 + n * 100, 'state' => PLAYING.merge('room_id' => n + 2, 'x' => 40 + n * 16) }
      events << { 'type' => 'decision', 'frame' => 1000 + n * 100, 'agent' => 'claude', 'cost_usd' => cost, 'prompt_sha' => 'x' }
      events << { 'type' => 'decision', 'frame' => 1050 + n * 100, 'agent' => 'delegated', 'cost_usd' => 0.0, 'autopilot' => true } if autopilot
    end
    events << { 'type' => 'perception', 'frame' => 1050, 'state' => PLAYING }
    stalls.times { |n| events << { 'type' => 'action', 'frame' => 1060 + n, 'skill' => 'explore', 'params' => {}, 'result' => { 'stopped_by' => 'stalled' } } }
    events << { 'type' => 'objective', 'frame' => 1070, 'id' => 'obj-9', 'status' => 'abandoned', 'reason' => 'loop' }
    events << { 'type' => 'stop', 'frame' => 3000, 'reason' => 'frames' }
    File.write(File.join(dir, 'trace.jsonl'), events.map { |event| "#{JSON.generate(event)}\n" }.join)
  end

  def test_report_measures_each_arm_after_the_fork_frame_and_applies_the_criterion
    Dir.mktmpdir do |root|
      fixture(root, 'ab-autopilot-1', cost: 0.01, places: 4, autopilot: true)
      fixture(root, 'ab-autopilot-2', cost: 0.01, places: 4, autopilot: true, stalls: 1)
      fixture(root, 'ab-off-1', cost: 0.05, places: 4, autopilot: false)
      fixture(root, 'other-off-1', cost: 9.0, places: 1, autopilot: false)
      result = Koholint::AB.report(prefix: 'ab', root:)
      assert_equal %w[autopilot off], result[:arms].keys
      on = result[:arms]['autopilot']
      assert_equal [2, 4000, 0.08, 0.02, 2.0, 2.0, 2.0, 3, 8], on.values_at(:runs, :frames, :usd, :usd_per_1000f, :calls_per_1000f, :places_per_1000f,
                                                                       :cells_per_1000f, :stalls, :autopilot_decisions)
      assert_equal [0.1, 2.0], result[:arms]['off'].values_at(:usd_per_1000f, :places_per_1000f)
      assert_equal ['pass', 0.2, 1.0], result[:criterion].values_at(:verdict, :cost_ratio, :places_ratio)
      text = Koholint::AB.markdown(result)
      assert_includes text, '| autopilot | 2 | 4000 | 0.08 | 0.02 | 2.0 | 2.0 | 2.0 | 3 | 8 |'
      assert_includes text, 'Criterion (autopilot cost per 1000 frames <= 50 % of off and places per 1000 frames >= 90 % of off): pass'
      fixture(root, 'ab-off-2', cost: 0.01, places: 8, autopilot: false)
      assert_equal 'fail', Koholint::AB.report(prefix: 'ab', root:)[:criterion][:verdict]
      assert_equal 'incomplete', Koholint::AB.report(prefix: 'other', root:)[:criterion][:verdict]
    end
  end

  def cli(*argv)
    out = StringIO.new
    err = StringIO.new
    [Koholint::CLI.run(argv, out:, err:), out.string, err.string]
  end

  def test_the_cli_plans_from_a_run_and_reports_a_root
    skip_without_rom!
    Dir.mktmpdir do |dir|
      parent = Koholint::Run.create(root: dir, flow_version: 'flow-old', budget: {})
      200.times { parent.inputs.append([]) }
      parent.inputs.flush
      Dir.chdir(dir) do
        assert_equal 1, cli('ab-plan', parent.dir, '--at-frame', '500')[0]
        code, out, = cli('ab-plan', parent.dir, '--at-frame', '150', '--forks', '1', '--max-dollars', '0.5', '--frames', '900', '--tag', 'x')
        assert_equal 0, code
        assert_includes out, '--tag x-off-1 --autopilot off'
        assert_includes out, '--max-dollars 0.5 --frames 900'
        assert File.file?(File.join(dir, 'tmp/ab/plan.json'))
      end
      fixture(dir, 'x-off-1', cost: 0.01, places: 1, autopilot: false)
      code, out, = cli('ab-report', 'x', '--root', dir)
      assert_equal 0, code
      assert_match(/^\| off \| 1 \| 2000 /, out)
      assert_includes out, ': incomplete'
    end
  end
end
