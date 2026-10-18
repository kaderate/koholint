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

  def http(port, path)
    Net::HTTP.start('127.0.0.1', port.to_i, open_timeout: 10, read_timeout: 20) { |h| h.get(path).body }
  end
end
