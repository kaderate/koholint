require_relative 'test_helper'
require 'tmpdir'
require 'koholint/entities'
require 'koholint/talk_log'
require 'koholint/vision/beliefs'
require 'koholint/vision/capabilities'
require 'koholint/vision/grid'
require 'koholint/vision/grid_builder'
require 'koholint/vision/screen_vision'
require 'support/emulator_cache'

class EntitiesTest < Minitest::Test
  STARTING_HOUSE_RUN = File.expand_path('../runs/20261020-085011-8330', __dir__)

  class FakeReader
    def initialize = @memory = Hash.new(0)
    def read(addr) = @memory[addr]
    def write(addr, value) = @memory[addr] = value
  end

  def put(reader, slot, x:, y:, type:, status: 5, state: 0)
    { 0xC200 => x, 0xC210 => y, 0xC280 => status, 0xC290 => state, 0xC3A0 => type }.each { |base, value| reader.write(base + slot, value) }
  end

  def test_reads_active_slots_with_their_cell_and_measured_kind
    reader = FakeReader.new
    put(reader, 0, x: 80, y: 56, type: 62, state: 3)
    put(reader, 1, x: 120, y: 80, type: 63, status: 0)
    put(reader, 4, x: 250, y: 20, type: 200)
    found = Koholint::Entities.read(reader, kinds: { 62 => :npc })
    assert_equal [{ slot: 0, type: 62, x: 80, y: 56, status: 5, state: 3, cell: [3, 5], kind: :npc },
                  { slot: 4, type: 200, x: 250, y: 20, status: 5, state: 0, cell: nil, kind: :unknown }], found
  end

  def test_the_catalogue_validates_kinds_and_provenance
    assert_equal :npc, Koholint::Entities.catalogue.fetch(63)
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'entities.json')
      bad = [{ 'type' => 1, 'kind' => 'npc', 'source' => 's', 'confidence' => 'verified', 'verified_count' => 1 }, { 'type' => 1, 'kind' => 'friend', 'source' => 's', 'confidence' => 'hypothesis', 'verified_count' => 1 },
             { 'type' => 1, 'kind' => 'npc', 'confidence' => 'hypothesis', 'verified_count' => 1 }]
      bad.each do |entry|
        File.write(path, JSON.generate([entry]))
        assert_raises(Koholint::Entities::Invalid) { Koholint::Entities.load(path) }
      end
    end
  end

  def test_near_picks_the_closest_entity_within_one_cell
    list = [{ slot: 0, type: 62, cell: [3, 5] }, { slot: 1, type: 63, cell: [4, 7] }, { slot: 2, type: 9, cell: nil }]
    assert_equal 63, Koholint::Entities.near(list, [4, 8])[:type]
    assert_equal 62, Koholint::Entities.near(list, [2, 4])[:type]
    assert_nil Koholint::Entities.near(list, [7, 0])
  end

  def test_the_starting_house_entities_sit_on_the_sprite_objects
    skip_without_rom!
    emulator = EmulatorCache.replayed(STARTING_HOUSE_RUN, 2500)
    entities = Koholint::Entities.read(emulator)
    assert_equal [[62, [3, 5], :npc], [63, [4, 7], :npc], [45, [6, 1], :unknown], [45, [6, 2], :unknown]], entities.map { |e| e.values_at(:type, :cell, :kind) }
    state = Koholint::Perception.read(emulator)
    sprites = Koholint::Vision::ScreenVision.sprites(emulator, emulator.read(Koholint::Vision::ScreenVision::LCDC))
                                             .reject { |sprite| Koholint::Vision::GridBuilder.link_sprite?(sprite, state) }
    grid = Koholint::Vision::Grid.new(cells: Array.new(8) { Array.new(10) }, static_sprites: sprites.map { |s| s.slice(:x, :y, :pattern).transform_keys(&:to_s) },
                                      beliefs: Koholint::Vision::Beliefs.new, capabilities: Koholint::Vision::Capabilities.new)
    objects = Koholint::TalkLog.objects(grid)
    visible = entities.select { |entity| entity[:kind] == :npc }
    assert_equal objects.size, visible.size
    visible.each { |entity| assert(objects.any? { |cells| cells.include?(entity[:cell]) }, "no sprite object on #{entity[:cell]}") }
  end
end
