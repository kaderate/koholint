require_relative 'test_helper'

class KoholintTest < Minitest::Test
  def with_env(vars)
    old = vars.keys.to_h { |k| [k, ENV[k]] }
    vars.each { |k, v| ENV[k] = v }
    yield
  ensure
    old.each { |k, v| ENV[k] = v }
  end

  def test_missing_rom_names_the_variable
    with_env('KOHOLINT_ROM' => '/nope') do
      error = assert_raises(Koholint::Error) { Koholint.rom_path }
      assert_match(/KOHOLINT_ROM/, error.message)
    end
  end

  def test_missing_emu_gb_names_the_variable
    with_env('EMU_GB_HOME' => '/nope') do
      error = assert_raises(Koholint::Error) { Koholint.emu_gb_home }
      assert_match(/EMU_GB_HOME/, error.message)
    end
  end
end
