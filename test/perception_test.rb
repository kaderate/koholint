require_relative 'test_helper'
require 'json'
require 'tmpdir'
require 'koholint/addresses'
require 'koholint/perception'
require 'support/emulator_cache'

class PerceptionTest < Minitest::Test
  FIXTURES = File.expand_path('fixtures', __dir__)

  def test_reads_known_state_when_the_boot_sequence_ends
    skip_without_rom!
    expected = JSON.parse(File.read(File.join(FIXTURES, 'start_game.expected.json')))
    emulator = EmulatorCache.playable(expect_hash: expected['state_hash'])
    assert_equal expected['state_hash'], emulator.state_hash
    state = Koholint::Perception.read(emulator)
    assert_equal expected['frame'], state.frame
    assert_equal [expected['room_id'], expected['map_id']], [state.room_id, state.map_id]
    assert_equal [expected['x'], expected['y'], expected['direction']], [state.x, state.y, state.direction]
    assert_equal [expected['hp'], expected['max_hp']], [state.hp, state.max_hp]
    assert_equal :none, state.milestone
  end

  def with_entries(entries)
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'addresses.json')
      File.write(path, JSON.generate(entries))
      yield path
    end
  end

  def test_schema_rejects_entry_without_verified_count
    with_entries([{ name: 'x', addr: '0xFF98', source: 'v1', confidence: 'hypothesis' }]) do |path|
      assert_raises(Koholint::Addresses::Invalid) { Koholint::Addresses.load(path) }
    end
  end

  def test_verified_confidence_needs_two_checks
    with_entries([{ name: 'x', addr: '0xFF98', source: 'v1', confidence: 'verified', verified_count: 1 }]) do |path|
      error = assert_raises(Koholint::Addresses::Invalid) { Koholint::Addresses.load(path) }
      assert_match(/verified_count/, error.message)
    end
  end

  def test_shipped_addresses_load
    table = Koholint::Addresses.load
    assert_equal 0xFFF6, table.fetch(:room_id)
  end
end
