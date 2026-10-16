require_relative 'test_helper'
require 'koholint/boot_script'
require 'koholint/input_log'

class BootScriptTest < Minitest::Test
  FIXTURE = File.expand_path('fixtures/start_game.inputs', __dir__)

  def recorded = Koholint::InputLog.load(FIXTURE).each_frame.to_a

  def test_input_at_reproduces_the_recorded_boot_sequence
    recorded.each_with_index do |buttons, frame|
      assert_equal buttons, Koholint::BootScript.input_at(frame), "frame #{frame}"
    end
  end

  def test_macros_chain_into_the_same_inputs
    expected = recorded
    frame = 0
    rebuilt = []
    while frame < expected.size
      macro = Koholint::BootScript.macro_at(frame)
      assert macro[:frames].between?(1, Koholint::BootScript::MAX_MACRO_FRAMES)
      rebuilt.concat([macro[:buttons]] * macro[:frames])
      frame += macro[:frames]
    end
    assert_equal expected, rebuilt.first(expected.size)
  end

  def test_first_macro_is_ten_frames_of_start
    assert_equal({ buttons: [:start], frames: 10 }, Koholint::BootScript.macro_at(0))
  end
end
