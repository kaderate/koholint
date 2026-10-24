require_relative 'test_helper'
require 'tmpdir'
require 'json'
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
      summary = JSON.parse(File.read(File.join(run.dir, 'summary.json')))
      assert_equal [run.id, 900, 'frames', 0, false], summary.values_at('run_id', 'frames', 'stop_reason', 'calls', 'starred')
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

    def decide(decision_point, state, context)
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

  class ScriptedPolicy
    def initialize(choices, registry = Koholint::Skills::Registry.default)
      @choices = choices.dup
      @registry = registry
    end

    def decision_point_for(_state) = Koholint::DecisionPoint.choose_skill(@registry)

    def decide(_decision_point, _state, _context)
      { choice: @choices.shift || { skill: 'wait', params: { frames: 1 } }, justification: 'script', confidence: 1.0, agent: 'scripted' }
    end
  end

  SKILL_SCRIPT = [{ skill: 'wait', params: { frames: 20 } }, { skill: 'press', params: { button: :a, frames: 3 } },
                  { skill: 'walk', params: { direction: :right, cells: 1 } }].freeze

  def play_script(frames)
    with_run do |_dir, run|
      Koholint::Engine.new(run: run, policy: ScriptedPolicy.new(SKILL_SCRIPT), budget: Koholint::Budget.new(frames:)).run
      yield run
    end
  end

  def test_skill_choices_journal_frames_and_emit_results
    skip_without_rom!
    play_script(800) do |run|
      actions = events(run, :action)
      assert_equal %w[wait press walk], actions.first(3).map { |a| a['skill'] }
      assert_equal 20, actions[0]['result']['frames']
      assert_equal 13, actions[1]['result']['frames']
      assert_equal({ 'button' => 'a', 'frames' => 3 }, actions[1]['params'])
      assert_equal 'wait', events(run, :decision).first['choice']['skill']
      assert_equal 'choose_skill', events(run, :decision).first['decision_point']
      assert_equal 800, Koholint::InputLog.load(File.join(run.dir, 'inputs.log')).frames
    end
  end

  def test_same_skill_choices_give_identical_journals_and_state_hashes
    skip_without_rom!
    runs = Array.new(2) do
      play_script(600) do |run|
        break [File.binread(File.join(run.dir, 'inputs.log')), Koholint::Replay.to(run, 600).state_hash]
      end
    end
    refute_empty runs[0][0]
    assert_equal runs[0], runs[1]
  end

  class Endless
    def name = 'endless'

    def normalize(_params) = {}

    def start(state, _params, _context = {}) = Koholint::Skills::Wait::Run.new(skill: name, params: {}, state:, duration: 10_000)
  end

  def test_budget_exhausted_mid_execution_is_reported
    skip_without_rom!
    with_run do |_dir, run|
      policy = ScriptedPolicy.new([{ skill: 'wait', params: { frames: 100 } }])
      Koholint::Engine.new(run: run, policy:, budget: Koholint::Budget.new(frames: 40)).run
      action = events(run, :action).first
      assert_equal 'budget', action['result']['stopped_by']
      assert_equal 40, action['result']['frames']
      assert_equal 40, Koholint::InputLog.load(File.join(run.dir, 'inputs.log')).frames
    end
  end

  def test_hard_cap_and_single_flush_per_execution
    skip_without_rom!
    with_run do |_dir, run|
      flushes = 0
      inputs = run.inputs
      inputs.define_singleton_method(:flush) { |*args| (flushes += 1) && super(*args) }
      registry = Koholint::Skills::Registry.new([Endless.new])
      policy = ScriptedPolicy.new([{ skill: 'endless', params: {} }], registry)
      eng = Koholint::Engine.new(run: run, policy:, budget: Koholint::Budget.new, keyframe_every: 100_000)
      eng.send(:iterate)
      outcome = events(run, :action).first['result']
      assert_equal 400, outcome['frames']
      assert_equal 'frame_cap', outcome['stopped_by']
      assert_equal 1, flushes
    end
  end

  class ContextProbe
    attr_reader :seen

    def name = 'probe'

    def normalize(_params) = {}

    def start(state, _params, context = {})
      @seen = context
      Koholint::Skills::Wait::Run.new(skill: name, params: {}, state:, duration: 1)
    end
  end

  def test_the_policy_context_reaches_the_skill
    skip_without_rom!
    with_run do |_dir, run|
      probe = ContextProbe.new
      registry = Koholint::Skills::Registry.new([probe])
      policy = ScriptedPolicy.new([{ skill: 'probe', params: {} }], registry)
      eng = Koholint::Engine.new(run:, policy:, budget: Koholint::Budget.new, keyframe_every: 100_000, grid: true)
      eng.send(:iterate)
      assert_kind_of Koholint::Vision::Grid, probe.seen[:grid]
      assert probe.seen[:dialogue_shot].respond_to?(:call)
    end
  end

  def test_activity_ends_stopped_and_is_never_read_by_verify_or_resume
    skip_without_rom!
    with_run do |_dir, run|
      engine(run, frames: 300).run
      path = File.join(run.dir, 'activity.json')
      assert_equal 'stopped', JSON.parse(File.read(path))['kind']
      refute File.exist?("#{path}.tmp")
      File.write(path, 'not json{')
      assert_equal [], Koholint::Replay.verify(run, every: 600).reject(&:last)
      resumed = Koholint::Engine.resume(run.dir, policy: Koholint::Policies::WalkAndTalk.new, budget: Koholint::Budget.new(frames: 300))
      assert_equal 600, resumed.run.then { Koholint::InputLog.load(File.join(run.dir, 'inputs.log')).frames }
    end
  end

  def test_a_failing_summary_write_still_ends_stopped_with_the_budget_reason
    skip_without_rom!
    with_run do |_dir, run|
      FileUtils.mkdir_p(File.join(run.dir, 'summary.json', 'blocker'))
      reason = nil
      _out, err = capture_io { reason = engine(run, frames: 60).run }
      assert_equal :frames, reason
      assert_match(/summary.json not written/, err)
      refute File.exist?(File.join(run.dir, 'summary.json.tmp'))
      assert_equal 'stopped', JSON.parse(File.read(File.join(run.dir, 'activity.json')))['kind']
    end
  end

  def test_a_failing_activity_write_changes_neither_trace_nor_journal
    skip_without_rom!
    outputs = [false, true].map do |failing|
      with_run do |_dir, run|
        FileUtils.mkdir_p(File.join(run.dir, 'activity.json.tmp')) if failing
        engine(run, frames: 200).run
        [File.read(File.join(run.dir, 'trace.jsonl')), File.binread(File.join(run.dir, 'inputs.log'))]
      end
    end
    assert_equal outputs.first, outputs.last
  end
  class MenuEmulator
    attr_reader :frame

    def initialize = (@frame = 0)
    def step(_buttons) = @frame += 1
    def state_hash = @frame.to_s
    def cartridge_ram = "\0" * 16
    def dump = 'state'

    def read(addr)
      name = Koholint::Perception::ADDRESSES.key(addr)
      { hp: 24, max_hearts: 3, link_x: 80, link_y: 60, game_mode: @frame < 300 ? 0x0B : 0x0C, game_submode: 7 }.fetch(name, 0)
    end
  end

  class BootForever
    def decision_point_for(_state) = Koholint::DecisionPoint.macro(:boot)
    def decide(*) = { choice: { buttons: [], frames: 5 }, agent: 'start_game' }
  end

  def test_the_boot_script_stuck_in_a_menu_after_play_stops_the_run
    with_run do |_dir, run|
      reason = Koholint::Engine.new(run:, policy: BootForever.new, emulator: MenuEmulator.new, budget: Koholint::Budget.new(frames: 20_000)).run
      assert_equal :stuck_boot, reason
      assert_equal 'stuck_boot', events(run, :budget_stop).first['kind']
      assert_operator run.inputs.frames, :<=, 300 + Koholint::Engine::STUCK_BOOT_FRAMES + 10
      assert File.file?(File.join(run.dir, 'summary.json'))
    end
  end

  def unknown_screen_emulator
    emulator = MenuEmulator.new
    emulator.define_singleton_method(:read) do |addr|
      { hp: 24, max_hearts: 3, link_x: 80, link_y: 60, game_mode: frame < 300 ? 0x0B : 0x0D, game_submode: 7 }.fetch(Koholint::Perception::ADDRESSES.key(addr), 0)
    end
    emulator
  end

  def test_an_uncatalogued_screen_is_noted_once_per_tuple_and_once_across_a_resume
    with_run do |_dir, run|
      Koholint::Engine.new(run:, policy: BootForever.new, emulator: unknown_screen_emulator, budget: Koholint::Budget.new(frames: 600)).run
      unknown = events(run, :notable).select { |e| e['kind'] == 'unknown_mode' }
      assert_equal 1, unknown.size
      assert_includes unknown.first['detail'], 'game_mode=13 game_submode=7'
      Koholint::Engine.new(run:, policy: BootForever.new, emulator: unknown_screen_emulator, budget: Koholint::Budget.new(frames: 600)).run
      assert_equal 1, events(run, :notable).count { |e| e['kind'] == 'unknown_mode' }
    end
  end

  class AgentForever
    def decision_point_for(_state) = Koholint::DecisionPoint.macro(:boot)
    def decide(*) = { choice: { buttons: [], frames: 5 }, agent: 'claude' }
  end

  def test_an_uncatalogued_screen_held_too_long_stops_the_run
    with_run do |_dir, run|
      reason = Koholint::Engine.new(run:, policy: AgentForever.new, emulator: unknown_screen_emulator, budget: Koholint::Budget.new(frames: 20_000)).run
      assert_equal :unknown_mode_stuck, reason
      assert_equal 'unknown_mode_stuck', events(run, :budget_stop).first['kind']
      assert_operator run.inputs.frames, :<=, 300 + Koholint::Engine::STUCK_UNKNOWN_FRAMES + 10
      assert_operator run.inputs.frames, :>, 300 + Koholint::Engine::STUCK_UNKNOWN_FRAMES
    end
  end

  def test_the_boot_script_deciding_forever_stops_the_run_even_before_play
    with_run do |_dir, run|
      emulator = MenuEmulator.new
      emulator.define_singleton_method(:read) { |addr| Koholint::Perception::ADDRESSES.key(addr) == :game_mode ? 0x02 : 0 }
      assert_equal :stuck_boot, Koholint::Engine.new(run:, policy: BootForever.new, emulator:, budget: Koholint::Budget.new(frames: 20_000)).run
      assert_operator run.inputs.frames, :>, Koholint::Engine::STUCK_BOOT_ANY_FRAMES
      assert_operator run.inputs.frames, :<=, Koholint::Engine::STUCK_BOOT_ANY_FRAMES + 10
    end
  end
  def test_a_resumed_run_that_played_keeps_the_short_stuck_limit
    with_run do |_dir, run|
      run.trace.emit(:perception, frame: 0, state: { game_mode: 0x0B })
      emulator = MenuEmulator.new
      emulator.define_singleton_method(:read) { |addr| Koholint::Perception::ADDRESSES.key(addr) == :game_mode ? 0x0C : 24 }
      assert_equal :stuck_boot, Koholint::Engine.new(run:, policy: BootForever.new, emulator:, budget: Koholint::Budget.new(frames: 20_000)).run
      assert_operator run.inputs.frames, :<=, Koholint::Engine::STUCK_BOOT_FRAMES + 10
    end
  end
end
