require 'minitest/autorun'
require 'koholint/dialogues'

class DialoguesTest < Minitest::Test
  SHOP = ["M' sieu! Po", "M' sieu! Pour sauvegard", "M' sieu! Pour sauvegarder,", 'sauvegarder, appuyez s', 'appuyez sur tous les',
          'appuyez sur tous les boutons', 'les boutons à la fois', 'à la fois! Heu, je', "à la fois! Heu, je n'en sais pas",
          "je n'en sais pas plus, je", "plus, je ne suis qu'", "plus, je ne suis qu'un gosse!"].freeze

  def assert_keeps_words(pages, out)
    haystack = Koholint::Dialogues.compact(out.join(' '))
    start = 0
    pages.each do |page|
      at = start
      first = nil
      page.split.each do |word|
        found = haystack.index(Koholint::Dialogues.compact(word), at)
        assert found, "#{word.inspect} of #{page.inspect} missing from #{out.inspect}"
        first ||= found
        at = found + Koholint::Dialogues.compact(word).size
      end
      start = first || start
    end
  end

  def test_the_scrolling_shop_text_becomes_one_paragraph
    out = Koholint::Dialogues.stitch(SHOP)
    assert_equal ["M' sieu! Pour sauvegarder, appuyez sur tous les boutons à la fois! Heu, je n'en sais pas plus, je ne suis qu'un gosse!"], out
    assert_keeps_words(SHOP, out)
  end

  def test_pages_without_overlap_are_returned_unchanged
    pages = ['Hello there.', 'The forest is dark.', 'Go north!']
    assert_equal pages, Koholint::Dialogues.stitch(pages)
    assert_equal "Hello there.\n\nThe forest is dark.\n\nGo north!", Koholint::Dialogues.text(pages)
  end

  def test_an_overlap_shorter_than_seven_characters_is_not_joined
    pages = ['I saw a big cat', 'big cat ran off']
    assert_equal pages, Koholint::Dialogues.stitch(pages)
  end

  def test_overlaps_only_start_on_a_word_boundary
    pages = ['the treasure', 'reasure chest']
    assert_equal pages, Koholint::Dialogues.stitch(pages)
    assert_keeps_words(pages, Koholint::Dialogues.stitch(pages))
  end

  def test_a_repeated_page_and_whitespace_differences_are_absorbed
    pages = ['Take  this sword', 'Take this sword', "this\nsword with you, and go"]
    out = Koholint::Dialogues.stitch(pages)
    assert_equal ['Take this sword with you, and go'], out
    assert_keeps_words(pages, out)
    assert_equal ['same text'], Koholint::Dialogues.stitch(['Same text', 'Same  text', 'same text'])
  end

  def test_a_page_contained_in_a_neighbour_is_kept
    [['Yes.', 'Oh, yes. I see.'], ['Go.', "Let's go. Now"], ['Ok.', 'Ok. Ok?'], ['Oh, yes. I see.', 'yes.']].each do |pages|
      assert_equal pages, Koholint::Dialogues.stitch(pages)
    end
  end

  def test_a_short_overlap_or_a_repeated_phrase_is_not_merged
    [['He said no way.', 'No way. I mean it.'], ['I will go. Go now!', 'Go now! Go now! Go!']].each do |pages|
      out = Koholint::Dialogues.stitch(pages)
      assert_equal pages, out
      assert_keeps_words(pages, out)
    end
  end

  def test_random_windows_over_a_text_keep_every_word
    words = %w[one bright morning the old keeper said the key lies under the third stone near the well]
    text = words.join(' ')
    rng = Random.new(7)
    20.times do
      pages = []
      at = 0
      while at < text.size
        size = rng.rand(8..24)
        pages << text[at, size].strip
        at += rng.rand(3..size)
      end
      pages.reject!(&:empty?)
      assert_keeps_words(pages, Koholint::Dialogues.stitch(pages))
    end
  end

  def test_events_are_grouped_by_frame_and_place_with_the_last_talk_target
    events = [
      { 'type' => 'perception', 'frame' => 1, 'state' => { 'room_id' => 1, 'map_id' => 0, 'game_mode' => 0x0B, 'game_submode' => 7, 'milestone' => 'none' } },
      { 'type' => 'action', 'frame' => 2, 'skill' => 'talk_to', 'params' => { 'row' => 3, 'col' => 4 }, 'result' => { 'talked' => true } },
      { 'type' => 'action', 'frame' => 3, 'skill' => 'advance_dialogue', 'params' => {}, 'result' => {} },
      *SHOP.first(3).map { |text| { 'type' => 'dialogue', 'frame' => 2, 'place' => [1, 0], 'text' => text } },
      { 'type' => 'lead', 'frame' => 5 },
      { 'type' => 'action', 'frame' => 6, 'skill' => 'walk', 'params' => {}, 'result' => {} },
      { 'type' => 'dialogue', 'frame' => 7, 'place' => [1, 0], 'text' => 'A sign.' }
    ]
    first, second = Koholint::Dialogues.from_events(events)
    assert_equal({ frame: 2, place: [1, 0], source: { row: 3, col: 4 }, text: "M' sieu! Pour sauvegarder,", stamp: ['none', 1, 0] },
                 first.except(:pages))
    assert_equal [nil, 'A sign.', ['none', 1, 1]], second.values_at(:source, :text, :stamp)
  end

  def test_an_explore_between_a_talk_and_a_text_clears_the_source
    events = [
      { 'type' => 'action', 'frame' => 2, 'skill' => 'talk_to', 'params' => { 'row' => 3, 'col' => 4 }, 'result' => { 'talked' => true } },
      { 'type' => 'action', 'frame' => 6, 'skill' => 'explore', 'params' => {}, 'result' => { 'stopped_by' => 'dialogue' } },
      { 'type' => 'dialogue', 'frame' => 7, 'place' => [1, 0], 'text' => 'A sign.' }
    ]
    assert_nil Koholint::Dialogues.from_events(events).first[:source]
  end
end
