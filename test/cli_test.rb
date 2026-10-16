require_relative 'test_helper'
require 'stringio'
require 'tmpdir'
require 'json'
require 'koholint/cli'

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
end
