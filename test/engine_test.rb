require_relative 'test_helper'
require 'tmpdir'
require 'koholint/engine'
require 'koholint/policies/walk_and_talk'

class EngineTest < Minitest::Test
  def with_run(**options)
    Dir.mktmpdir do |dir|
      yield dir, Koholint::Run.create(root: dir, flow_version: Koholint::FLOW_VERSION, budget: {}, **options)
    end
  end

  def engine(run, **limits)
    Koholint::Engine.new(run: run, policy: Koholint::Policies::WalkAndTalk.new, budget: Koholint::Budget.new(**limits))
  end

  def events(run, type = nil)
    Koholint::Trace.read(File.join(run.dir, 'trace.jsonl')).then { |all| type ? all.select { |e| e['type'] == type.to_s } : all }
  end

  def test_stops_at_frame_budget_with_single_stop_event
    skip_without_rom!
    with_run do |_dir, run|
      assert_equal :frames, engine(run, frames: 900).run
      assert_equal 1, events(run, :stop).size
      assert_equal 'stopped', Koholint::Run.open(run.dir, flow_version: Koholint::FLOW_VERSION).manifest['status']
      assert_equal 900, Koholint::InputLog.load(File.join(run.dir, 'inputs.log')).frames
      stop_save = events(run, :save).find { |e| e['source'] == 'stop' }
      assert File.file?(File.join(run.dir, 'save', stop_save['path']))
    end
  end

  def test_request_stop_in_unlimited_run_takes_stop_path
    skip_without_rom!
    with_run do |_dir, run|
      eng = engine(run)
      Thread.new { sleep 0.5 until run.trace && Koholint::Trace.read(File.join(run.dir, 'trace.jsonl')).size > 20; eng.request_stop }
      assert_equal :stopped, eng.run
      assert_equal 1, events(run, :stop).size
      assert_equal 'stopped', events(run, :stop).first['reason']
    end
  end

  def test_resume_replays_to_the_same_state_as_its_journal
    skip_without_rom!
    with_run do |_dir, run|
      engine(run, frames: 600).run
      first_hash = Koholint::Replay.to(run, 600).state_hash
      resumed = Koholint::Engine.resume(run.dir, policy: Koholint::Policies::WalkAndTalk.new,
                                                 budget: Koholint::Budget.new(frames: 600))
      resumed.run
      reopened = Koholint::Run.open(run.dir, flow_version: Koholint::FLOW_VERSION)
      assert_equal 1200, reopened.inputs.frames
      assert_equal first_hash, Koholint::Replay.to(reopened, 600).state_hash
      assert_equal 2, events(reopened, :stop).size
      assert_equal [], Koholint::Replay.verify(reopened, every: 600).reject(&:last)
    end
  end

  def test_resume_survives_truncated_trace_line
    skip_without_rom!
    with_run do |_dir, run|
      engine(run, frames: 300).run
      File.open(File.join(run.dir, 'trace.jsonl'), 'a') { |f| f.write('{"v":1,"type":"perc') }
      Koholint::Engine.resume(run.dir, policy: Koholint::Policies::WalkAndTalk.new,
                                       budget: Koholint::Budget.new(frames: 90)).run
      assert_equal 390, Koholint::Run.open(run.dir, flow_version: Koholint::FLOW_VERSION).inputs.frames
    end
  end

  def test_every_decision_has_matching_perception_before_it
    skip_without_rom!
    with_run do |_dir, run|
      engine(run, frames: 300).run
      all = events(run)
      all.each_with_index.select { |e, _| e['type'] == 'decision' }.each do |decision, index|
        before = all[index - 1]
        assert_equal 'perception', before['type']
        assert_equal decision['frame'], before['frame']
      end
    end
  end

  class SavingPolicy < Koholint::Policies::WalkAndTalk
    def initialize(emulator) = (@emulator = emulator
                                super())

    def decide(point, state, context)
      @emulator.instance_variable_get(:@driver).motherboard.mmu.mbc.external_ram.bytes[3] = 0x42 if state.frame >= 120
      super
    end
  end

  def test_game_save_becomes_trace_event
    skip_without_rom!
    with_run do |_dir, run|
      emulator = Koholint::Emulator.boot
      Koholint::Engine.new(run: run, policy: SavingPolicy.new(emulator), emulator: emulator,
                           budget: Koholint::Budget.new(frames: 240)).run
      saves = events(run, :save)
      game_save = saves.find { |e| e['source'] == 'game' && e['frame'] >= 120 }
      assert game_save, 'expected a game save event after the poke'
      file = File.join(run.dir, 'save', game_save['path'])
      assert_equal game_save['sav_sha256'], Digest::SHA256.file(file).hexdigest
      assert_equal 0x42, File.binread(file).getbyte(3)
    end
  end

  def test_journal_on_disk_covers_the_last_keyframe_without_a_clean_stop
    skip_without_rom!
    with_run do |_dir, run|
      eng = Koholint::Engine.new(run: run, policy: Koholint::Policies::WalkAndTalk.new,
                                 budget: Koholint::Budget.new, keyframe_every: 120)
      eng.send(:iterate) while eng.instance_variable_get(:@emulator).frame < 300
      assert_operator Koholint::InputLog.load(File.join(run.dir, 'inputs.log')).frames, :>=, 240
    end
  end

  def test_journal_on_disk_has_exactly_the_frames_played_after_one_macro
    skip_without_rom!
    with_run do |_dir, run|
      eng = Koholint::Engine.new(run: run, policy: Koholint::Policies::WalkAndTalk.new, budget: Koholint::Budget.new)
      eng.send(:iterate)
      assert_operator eng.instance_variable_get(:@emulator).frame, :>, 0
      assert_equal eng.instance_variable_get(:@emulator).frame, Koholint::InputLog.load(File.join(run.dir, 'inputs.log')).frames
    end
  end

  def test_sigint_on_unlimited_cli_run_takes_the_stop_path
    skip_without_rom!
    Dir.mktmpdir do |dir|
      bin = File.expand_path('../bin/koholint', __dir__)
      pid = Process.spawn(bin, 'run', '--root', dir, %i[out err] => File::NULL)
      trace = nil
      deadline = Time.now + 90
      sleep 0.5 until Time.now > deadline || (trace = Dir.glob(File.join(dir, '*', 'trace.jsonl')).first) && File.size(trace) > 2000
      Process.kill('INT', pid)
      _, status = Process.wait2(pid)
      assert status.success?
      stops = Koholint::Trace.read(trace).select { |e| e['type'] == 'stop' }
      assert_equal ['stopped'], stops.map { |e| e['reason'] }
      assert_equal 'stopped', JSON.parse(File.read(File.join(File.dirname(trace), 'manifest.json')))['status']
    end
  end
end
