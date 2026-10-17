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

  def test_object_choice_is_formatted_readably
    event = { frame: 5, type: 'decision', agent: 'a', choice: { buttons: %w[a b], frames: 58 }, confidence: 0.5 }
    assert_equal '5 decision a a+b 58f 0.5', evaluate("formatEvent(#{JSON.generate(event)})")
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
