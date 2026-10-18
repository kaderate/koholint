require_relative 'test_helper'
require 'json'
require 'open3'

class PageTest < Minitest::Test
  PAGE = File.read(File.expand_path('../lib/koholint/viewer/page.html', __dir__))

  def pure_source
    PAGE[%r{// pure:begin\n(.*?)// pure:end}m, 1] or flunk 'page has no pure section'
  end

  def evaluate(expression)
    skip 'node is not installed' unless system('which node > /dev/null 2>&1')
    out, status = Open3.capture2('node', '-e', "#{pure_source}\nconsole.log(JSON.stringify(#{expression}));")
    assert status.success?
    JSON.parse(out)
  end

  def test_decisions_read_as_a_sentence
    event = { frame: 5, type: 'decision', agent: 'start_game', choice: { buttons: %w[a b], frames: 58 }, confidence: 1 }
    assert_equal 'f5 · start_game decides a+b 58f', evaluate("formatEventPretty(#{JSON.generate(event)})")
  end

  def test_low_confidence_is_shown_as_a_percentage
    event = { frame: 5, type: 'decision', agent: 'jev', choice: { buttons: [], frames: 30 }, confidence: 0.5 }
    assert_equal 'f5 · jev decides idle 30f (50%)', evaluate("formatEventPretty(#{JSON.generate(event)})")
  end

  def test_actions_read_as_what_was_pressed
    event = { frame: 8, type: 'action', skill: 'press', params: { buttons: %w[start], frames: 3 } }
    assert_equal 'f8 · press start 3f', evaluate("formatEventPretty(#{JSON.generate(event)})")
  end

  def test_unknown_event_types_still_get_a_line
    assert_equal 'f1 · budget_stop', evaluate("formatEventPretty({frame: 1, type: 'budget_stop'})")
  end

  def test_json_mode_is_the_raw_event
    event = { frame: 8, type: 'action', skill: 'press', params: { buttons: %w[a], frames: 3 } }
    assert_equal JSON.generate(event), evaluate("formatEventJson(#{JSON.generate(event)})")
  end

  def test_the_mode_toggle_alternates_and_rejects_garbage
    assert_equal 'json', evaluate("nextMode('pretty')")
    assert_equal 'pretty', evaluate("nextMode('json')")
    assert_equal 'pretty', evaluate("normalizeMode('whatever')")
    assert_equal 'json', evaluate("normalizeMode('json')")
  end

  def test_page_has_a_toggle_that_remembers_the_choice
    assert_match(/id="mode"/, PAGE)
    assert_match(/localStorage/, PAGE)
  end

  def test_each_poll_keeps_its_own_error
    assert_match(/frameError/, PAGE)
    assert_match(/stateError/, PAGE)
  end

  def test_empty_buttons_read_as_idle
    assert_equal 'idle 58f', evaluate('formatChoice({buttons: [], frames: 58})')
  end

  def test_other_choices_never_render_as_object_object
    refute_includes evaluate('formatChoice({to: 3})').to_s, '[object Object]'
    assert_equal 'wait', evaluate("formatChoice('wait')")
  end

  def test_hearts_show_a_dash_before_the_game_starts
    assert_equal '-', evaluate('formatHearts({status: {hearts: null, max_hearts: null}})')
    assert_equal '-', evaluate('formatHearts({status: {hearts: 0, max_hearts: 0}})')
    assert_equal '2/3', evaluate('formatHearts({status: {hearts: 2, max_hearts: 3}})')
  end

  def test_unknown_health_is_styled_neutrally
    assert_match(/health-unknown/, PAGE)
  end

  def test_error_field_of_a_failed_response_is_shown
    assert_match(/\.error/, PAGE)
  end
end
