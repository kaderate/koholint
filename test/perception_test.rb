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

  def test_milestone_maps_the_shield_level
    assert_equal :none, Koholint::Perception.milestone_for(0)
    assert_equal :shield, Koholint::Perception.milestone_for(1)
    assert_equal :shield, Koholint::Perception.milestone_for(2)
  end

  def test_no_milestone_before_the_shield_is_given
    skip_without_rom!
    assert_equal :none, Koholint::Perception.read(EmulatorCache.at(700)).milestone
  end

  def test_the_shield_addresses_are_verified
    entries = JSON.parse(File.read(Koholint::Addresses::DEFAULT_PATH)).to_h { |entry| [entry['name'], entry] }
    assert_equal 'verified', entries.fetch('shield_level')['confidence']
    assert_equal 0xDB44, Koholint::Addresses.load.fetch(:shield_level)
  end

  def test_phase_before_control_and_while_playing
    skip_without_rom!
    assert_equal :playing, Koholint::Perception.read(EmulatorCache.interactive).phase
    refute Koholint::Perception.read(EmulatorCache.interactive).dialog_open?
  end

  def test_dialogue_chain_is_dialogue_phase
    skip_without_rom!
    emulator = Koholint::Emulator.restore(EmulatorCache.at(700).dump)
    400.times do
      break if Koholint::Perception.read(emulator).dialog_open?

      emulator.step
    end
    assert_equal :playing, Koholint::Perception.read(EmulatorCache.at(700)).phase
    assert_equal :dialogue, Koholint::Perception.read(emulator).phase
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

  def test_the_mode_addresses_record_what_their_values_mean
    entries = JSON.parse(File.read(Koholint::Addresses::DEFAULT_PATH)).to_h { |entry| [entry['name'], entry] }
    %w[game_mode game_submode].each do |name|
      assert_match(/\S/, entries.fetch(name)['note'].to_s, name)
      Koholint::Addresses.validate!(entries.fetch(name))
    end
  end
end
