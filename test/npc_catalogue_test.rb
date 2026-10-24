require_relative 'test_helper'
require 'json'
require 'stringio'
require 'tmpdir'
require 'koholint/cli'
require 'koholint/trace'

class NpcCatalogueTest < Minitest::Test
  def perception(milestone) = { 'type' => 'perception', 'frame' => 1, 'state' => { 'room_id' => 163, 'map_id' => 16, 'game_mode' => 0x0B, 'game_submode' => 7, 'milestone' => milestone } }

  def talk(frame, entity: nil)
    { 'type' => 'action', 'frame' => frame, 'skill' => 'talk_to', 'params' => { 'row' => 4, 'col' => 7 },
      'result' => { 'talked' => true, 'stopped_by' => 'done', 'from' => { 'room' => 163, 'map' => 16, 'row' => 4, 'col' => 6 }, 'entity' => entity }.compact }
  end

  def said(frame, text, speaker: nil) = { 'type' => 'dialogue', 'frame' => frame, 'place' => [163, 16], 'text' => text, 'source' => 'agent', 'page' => 1, 'speaker' => speaker }.compact

  def write_run(root, name, events, gzip: false)
    dir = File.join(root, name)
    FileUtils.mkdir_p(dir)
    path = File.join(dir, 'trace.jsonl')
    File.write(path, events.map { |event| JSON.generate(event) }.join("\n") << "\n")
    return unless gzip

    Koholint::Trace.compress(path)
    File.delete(path)
  end

  def test_npcs_lists_people_with_names_and_distinct_texts_across_runs
    Dir.mktmpdir do |root|
      tarkin = { 'type' => 63, 'slot' => 1 }
      write_run(root, 'run-a', [perception('none'), talk(10, entity: tarkin), said(10, 'Hi! I am Tarkin.', speaker: 'Tarkin'),
                                perception('shield'), talk(50, entity: tarkin), said(50, 'Something was left on the beach.')])
      write_run(root, 'run-b', [perception('none'), talk(10, entity: tarkin), said(10, 'Hi!   I am Tarkin'),
                                { 'type' => 'action', 'frame' => 80, 'skill' => 'walk', 'params' => {}, 'result' => {} }, said(90, 'Wake up!')], gzip: true)
      write_run(root, 'run-c', [perception('none'), talk(10), said(10, 'Old run text.')])
      out = StringIO.new
      assert_equal 0, Koholint::CLI.run(['npcs', '--root', root], out:, err: StringIO.new)
      rows = out.string.lines.map(&:chomp)
      assert_equal '| place | person | names | talks | runs | dialogues (milestone when first read, runs) |', rows[0]
      assert_includes rows, '| 163/16 | entity type 63 | Tarkin | 3 | 2 | [none, 2] Hi! I am Tarkin.<br>[shield, 1] Something was left on the beach. |'
      assert_includes rows, '| 163/16 | cell (4,7) |  | 1 | 1 | [none, 1] Old run text. |'
      assert_includes rows, '| 163/16 | opened by itself |  | 0 | 1 | [none, 1] Wake up! |'
    end
  end
end
