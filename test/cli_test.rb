require_relative 'test_helper'
require 'stringio'
require 'tmpdir'
require 'json'
require 'koholint/cli'
require 'net/http'
require 'timeout'

class CliTest < Minitest::Test
  def cli(*argv)
    out = StringIO.new
    err = StringIO.new
    code = Koholint::CLI.run(argv, out: out, err: err)
    [code, out.string, err.string]
  end

  def test_run_then_verify_exits_zero
    skip_without_rom!
    Dir.mktmpdir do |dir|
      code, out, = cli('run', '--frames', '900', '--root', dir)
      assert_equal 0, code
      run_dir = out[/^run (.+)$/, 1]
      assert File.directory?(run_dir)
      assert_equal 0, cli('verify', run_dir)[0]
      summary = JSON.parse(cli('summary', run_dir)[1])
      assert_equal 'stopped', summary['health']
      assert_equal 900, summary['frames']
    end
  end

  def test_run_accepts_the_grid_flag
    skip_without_rom!
    Dir.mktmpdir do |dir|
      code, out, = cli('run', '--frames', '120', '--grid', '--root', dir)
      assert_equal 0, code
      assert_match(/^stopped: frames$/, out)
    end
  end

  def test_fork_creates_child_run
    skip_without_rom!
    Dir.mktmpdir do |dir|
      run_dir = cli('run', '--frames', '300', '--root', dir)[1][/^run (.+)$/, 1]
      code, out, = cli('fork', run_dir, '--at-frame', '150')
      assert_equal 0, code
      child = out[/^run (.+)$/, 1]
      assert_equal 150, Koholint::InputLog.load(File.join(child, 'inputs.log')).frames
    end
  end

  def test_missing_rom_prints_one_line_error_and_exits_nonzero
    old = ENV['KOHOLINT_ROM']
    ENV['KOHOLINT_ROM'] = '/nope'
    code, _out, err = cli('run', '--frames', '10')
    assert_equal 1, code
    assert_equal 1, err.lines.size
    assert_match(/KOHOLINT_ROM/, err)
  ensure
    ENV['KOHOLINT_ROM'] = old
  end

  def test_unknown_command_exits_two
    code, _out, err = cli('bogus')
    assert_equal 2, code
    assert_match(/usage/i, err)
  end

  def test_watch_missing_run_dir_prints_one_line_error
    code, out, err = cli('watch', '/nonexistent/run')
    assert_equal 1, code
    assert_equal '', out
    assert_equal 1, err.lines.size
  end

  def test_watch_accepts_a_host_option
    code, _out, err = cli('watch', '/nonexistent/run', '--host', '0.0.0.0')
    assert_equal 1, code
    assert_match(/no run at/, err)
  end

  def test_watch_rejects_bad_options
    assert_equal 2, cli('watch', 'x', '--from', 'sideways')[0]
    assert_equal 2, cli('watch', 'x', '--speed', '0')[0]
    assert_equal 2, cli('watch', 'x', '--port', 'abc')[0]
  end

  def test_realtime_run_takes_wall_time
    skip_without_rom!
    Dir.mktmpdir do |dir|
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      assert_equal 0, cli('run', '--frames', '120', '--realtime', '--root', dir)[0]
      assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :>=, 1.5
    end
  end

  def test_watch_serves_a_finished_run_and_stops_on_sigint
    skip_without_rom!
    Dir.mktmpdir do |dir|
      run_dir = cli('run', '--frames', '300', '--root', dir)[1][/^run (.+)$/, 1]
      reader, writer = IO.pipe
      pid = Process.spawn(File.expand_path('../bin/koholint', __dir__), 'watch', run_dir, out: writer, err: File::NULL)
      writer.close
      begin
        assert reader.wait_readable(60), 'no output from watch'
        port = reader.gets[%r{^watching http://127\.0\.0\.1:(\d+)$}, 1]
        refute_nil port
        state = JSON.parse(http(port, '/state.json'))
        assert_equal 'stopped', state.dig('status', 'health')
        assert_equal "\x89PNG".b, http(port, '/frame.png')[0, 4].b
        Process.kill('INT', pid)
        _, status = Timeout.timeout(15) { Process.wait2(pid) }
        assert_equal 0, status.exitstatus
        pid = nil
      ensure
        if pid
          Process.kill('KILL', pid)
          Process.wait(pid)
        end
        reader.close
      end
    end
  end

  FAKE_CLAUDE = File.expand_path('fixtures/fake_claude', __dir__)

  def with_fake_claude
    Dir.mktmpdir do |dir|
      ENV['FAKE_CLAUDE_LOG'] = File.join(dir, 'log.json')
      yield dir
    end
  ensure
    ENV.delete('FAKE_CLAUDE_LOG')
  end

  def test_agent_run_calls_the_claude_command_and_stops_at_the_dollar_cap
    skip_without_rom!
    with_fake_claude do |dir|
      code, out, = cli('run', '--agent', '--claude-command', FAKE_CLAUDE, '--model', 'haiku', '--max-dollars', '0.02', '--root', dir)
      assert_equal 0, code
      assert_match(/^stopped: dollars$/, out)
      run_dir = out[/^run (.+)$/, 1]
      decisions = Koholint::Trace.read(File.join(run_dir, 'trace.jsonl')).select { |e| e['type'] == 'decision' && e['agent'] == 'claude' }
      assert_equal 2, decisions.size
      assert(decisions.all? { |d| d['fallback'] && d['cost_usd'] == 0.0123 })
      argv = JSON.parse(File.readlines(ENV.fetch('FAKE_CLAUDE_LOG')).first)['argv']
      assert_equal 'haiku', argv[argv.index('--model') + 1]
      assert_equal 0, cli('verify', run_dir)[0]
    end
  end

  def test_resume_accepts_the_agent_flags
    skip_without_rom!
    with_fake_claude do |dir|
      run_dir = cli('run', '--frames', '300', '--root', dir)[1][/^run (.+)$/, 1]
      code, out, = cli('resume', run_dir, '--agent', '--claude-command', FAKE_CLAUDE, '--max-dollars', '0.01')
      assert_equal 0, code
      assert_match(/^stopped: dollars$/, out)
    end
  end

  def test_resume_refuses_a_flow_1_run
    skip_without_rom!
    Dir.mktmpdir do |dir|
      run = Koholint::Run.create(root: dir, flow_version: 'flow-1', budget: {})
      code, _out, err = cli('resume', run.dir)
      assert_equal 1, code
      assert_match(/flow-1/, err)
    end
  end

  def test_resume_rebuilds_the_ledger_and_visited_places_from_the_trace
    skip_without_rom!
    Dir.mktmpdir do |dir|
      run = Koholint::Run.create(root: dir, flow_version: Koholint::FLOW_VERSION, budget: {})
      playing = { 'game_mode' => 0x0B, 'game_submode' => 7, 'x' => 40, 'y' => 40 }
      run.trace.emit(:perception, frame: 1, state: playing.merge('room_id' => 1, 'map_id' => 2), state_hash: 'h')
      run.trace.emit(:perception, frame: 2, state: playing.merge('game_submode' => 3, 'room_id' => 9, 'map_id' => 9), state_hash: 'h')
      run.trace.emit(:perception, frame: 3, state: playing.merge('game_mode' => 1, 'room_id' => 8, 'map_id' => 8), state_hash: 'h')
      run.trace.emit(:perception, frame: 4, state: playing.merge('room_id' => 3, 'map_id' => 2), state_hash: 'h')
      run.trace.emit(:perception, frame: 5, state: playing.merge('room_id' => 1, 'map_id' => 2), state_hash: 'h')
      2.times do |n|
        run.trace.emit(:action, frame: 6 + n, skill: 'goto', params: { row: 1, col: 1 },
                                result: { from: { room: 1, map: 2 }, to: { room: 1, map: 2 }, stopped_by: 'blocked',
                                          blocked_at: { row: 2, col: 3, direction: 'up' } })
      end
      2.times { |n| run.trace.emit(:objective, frame: 8 + n, id: "obj-#{n + 1}", status: 'started', title: 't', predicate: { kind: 'new_place' }) }
      run.trace.emit(:objective, frame: 11, id: 'obj-1', status: 'achieved', title: 't', predicate: { kind: 'new_place' })

      ledger = Koholint::CLI.ledger_for(run)
      assert ledger.doubtful?([1, 2], [2, 3], :up)
      assert_equal 2, ledger.count([1, 2], [2, 3], :up)
      objectives = Koholint::CLI.objectives_for(run)
      assert_equal [[1, 2], [3, 2]], objectives.visited
      objectives.start(frame: 20, title: 'next', predicate: { kind: 'new_place' })
      assert_equal 'obj-3', objectives.current[:id]
    end
  end

  def test_agent_without_claude_executable_is_a_one_line_error
    code, _out, err = cli('run', '--agent', '--claude-command', '/nope/claude', '--frames', '10')
    assert_equal 1, code
    assert_equal 1, err.lines.size
    assert_match(/claude/, err)
  end

  def http(port, path)
    Net::HTTP.start('127.0.0.1', port.to_i, open_timeout: 10, read_timeout: 20) { |h| h.get(path).body }
  end
end
