require_relative 'test_helper'
require 'tmpdir'
require 'koholint/config'

class ConfigTest < Minitest::Test
  def with_env_file(content)
    Dir.mktmpdir do |dir|
      path = File.join(dir, '.env')
      File.write(path, content)
      old = Koholint::Config.env_path
      Koholint::Config.env_path = path
      yield
    ensure
      Koholint::Config.env_path = old
    end
  end

  def with_env(vars)
    old = vars.keys.to_h { |k| [k, ENV[k]] }
    vars.each { |k, v| ENV[k] = v }
    yield
  ensure
    old.each { |k, v| ENV[k] = v }
  end

  def test_parse_handles_comments_quotes_export_and_blank_lines
    parsed = Koholint::Config.parse(<<~ENVFILE)
      # a comment

      KOHOLINT_ROM=/roms/zelda.gbc
      export EMU_GB_HOME="/opt/emu gb"
      OTHER='x y'
      EMPTY=
    ENVFILE
    assert_equal({ 'KOHOLINT_ROM' => '/roms/zelda.gbc', 'EMU_GB_HOME' => '/opt/emu gb', 'OTHER' => 'x y', 'EMPTY' => '' }, parsed)
  end

  def test_get_reads_the_env_file
    with_env_file("KOHOLINT_TEST_KEY=from-file\n") do
      with_env('KOHOLINT_TEST_KEY' => nil) { assert_equal 'from-file', Koholint::Config.get('KOHOLINT_TEST_KEY') }
    end
  end

  def test_real_environment_wins_over_the_env_file
    with_env_file("KOHOLINT_TEST_KEY=from-file\n") do
      with_env('KOHOLINT_TEST_KEY' => 'from-env') { assert_equal 'from-env', Koholint::Config.get('KOHOLINT_TEST_KEY') }
    end
  end

  def test_unset_rom_points_to_the_example_file_and_leaks_no_path
    with_env_file("\n") do
      with_env('KOHOLINT_ROM' => nil) do
        error = assert_raises(Koholint::Error) { Koholint.rom_path }
        assert_match(/KOHOLINT_ROM.*\.env\.example/, error.message)
      end
    end
  end

  def test_unset_emu_gb_points_to_the_example_file
    with_env_file("\n") do
      with_env('EMU_GB_HOME' => nil) do
        assert_match(/EMU_GB_HOME.*\.env\.example/, assert_raises(Koholint::Error) { Koholint.emu_gb_home }.message)
      end
    end
  end

  def test_no_machine_specific_path_in_lib
    leaks = Dir.glob(File.expand_path('../lib/**/*.rb', __dir__)).select { |f| File.read(f).match?(%r{~/|/Users/|/home/}) }
    assert_empty leaks
  end
end
