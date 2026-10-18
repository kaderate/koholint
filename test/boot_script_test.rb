require_relative 'test_helper'
require 'koholint/boot_script'
require 'koholint/game_state'

class BootScriptTest < Minitest::Test
  def state(mode, sub: 0, name_length: 0, frame: 0)
    Koholint::GameState.new(frame:, game_mode: mode, game_submode: sub, name_length:, milestone: :none)
  end

  def macro(...) = Koholint::BootScript.macro_for(state(...))

  def test_title_pulses_start_then_waits_out_the_rest_of_the_period
    assert_equal({ buttons: [:start], frames: 3 }, macro(0, frame: 0))
    assert_equal({ buttons: [:start], frames: 1 }, macro(0, frame: 2))
    assert_equal({ buttons: [], frames: 17 }, macro(0, frame: 3))
    assert_equal({ buttons: [], frames: 15 }, macro(0, frame: 25))
    assert_equal({ buttons: [:start], frames: 3 }, macro(0, frame: 40))
  end

  def test_file_select_presses_a_only_when_ready
    assert_equal({ buttons: [], frames: 5 }, macro(2, sub: 3))
    assert_equal({ buttons: [:a], frames: 3 }, macro(2, sub: 7))
    assert_equal({ buttons: [], frames: 5 }, macro(2, sub: 8))
  end

  def test_name_entry_validates_a_letter_before_confirming
    assert_equal({ buttons: [:a], frames: 3 }, macro(3, sub: 2, name_length: 0))
    assert_equal({ buttons: [:start], frames: 3 }, macro(3, sub: 2, name_length: 1))
    assert_equal({ buttons: [], frames: 5 }, macro(3, sub: 0, name_length: 0))
    assert_equal({ buttons: [], frames: 5 }, macro(3, sub: 1, name_length: 1))
  end

  def test_other_modes_just_wait
    assert_equal({ buttons: [], frames: 5 }, macro(0x0B))
    assert_equal({ buttons: [], frames: 5 }, macro(1))
    assert_equal({ buttons: [], frames: 5 }, macro(nil))
  end
end
