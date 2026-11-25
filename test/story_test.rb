require_relative 'test_helper'
require 'fileutils'
require 'tmpdir'
require 'zlib'
require 'koholint/viewer/story'

class StoryTest < Minitest::Test
  RUNS = File.expand_path('../runs', __dir__)
  SWORD = '20261111-194737-9ba1'.freeze

  def test_a_run_reads_as_frames_of_thoughts_objectives_places_and_items_from_its_fork
    story = Koholint::Viewer::Story.build(File.join(RUNS, SWORD))
    assert_equal [SWORD, 'flow-37', 52_200], story.values_at(:run, :flow, :fork)
    assert_operator story[:end], :>, story[:fork]
    assert(story[:thoughts].all? { |_, _, text| text.size >= Koholint::Viewer::Story::MIN_THOUGHT && text.size <= Koholint::Viewer::Story::THOUGHT_CAP })
    assert(story[:marks].all? { |frame, _, _| frame >= story[:fork] })
    assert_includes story[:marks], [60_404, 'item', 1]
    assert_equal [[3906, [4]], [60_404, [1, 4]]], story[:held]
    assert_equal story[:trail].map(&:first), story[:trail].map(&:first).sort
    assert(story[:trail].each_cons(2).all? { |(_, a), (_, b)| a != b })
  end

  def test_pieces_of_one_text_in_one_place_merge_into_the_whole_text
    pieces = [{ frame: 1, place: [163, 16], text: 'Salut A !', speaker: 'Tarkin' },
              { frame: 2, place: [163, 16], text: 'Salut A ! T es réveillé...' },
              { frame: 3, place: [163, 16], text: 'Salut A !' },
              { frame: 9, place: [40, 0], text: 'Une autre voix' }]
    merged = Koholint::Viewer::Story.merged(pieces)
    assert_equal [['163/16', 'Salut A ! T es réveillé...', 'Tarkin'], ['I3', 'Une autre voix', nil]],
                 merged.map { |talk| talk.values_at(:place, :text, :speaker) }
  end

  def test_the_story_is_cached_until_the_trace_changes
    Dir.mktmpdir do |root|
      FileUtils.cp_r(File.join(RUNS, SWORD), root)
      dir = File.join(root, SWORD)
      trace = File.join(dir, 'trace.jsonl')
      File.write(trace, Zlib::GzipReader.open("#{trace}.gz", &:read))
      File.delete("#{trace}.gz")
      first = Koholint::Viewer::Story.for(dir)
      assert_same first, Koholint::Viewer::Story.for(dir)
      File.open(trace, 'a') { |file| file.puts(JSON.generate(frame: first[:end] + 10, type: 'objective', id: 'x', title: 'Go', status: 'started')) }
      second = Koholint::Viewer::Story.for(dir)
      refute_same first, second
      assert_equal first[:end] + 10, second[:end]
    end
  end
end
