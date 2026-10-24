require_relative 'test_helper'
require 'json'
require 'tmpdir'
require 'koholint/game_state'
require 'koholint/modes'

class ModesTest < Minitest::Test
  def state(**fields) = Koholint::GameState.new(milestone: :none, **fields)

  def entry(name, match, **extra)
    { 'name' => name, 'kind' => 'menu', 'phase' => 'menu', 'match' => match, 'enter' => nil, 'exit' => nil, 'inputs' => {},
      'source' => 'test', 'confidence' => 'hypothesis', 'verified_count' => 0, **extra.transform_keys(&:to_s) }
  end

  def load(entries)
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'modes.json')
      File.write(path, JSON.generate(entries))
      Koholint::Modes.load(path)
    end
  end

  def test_the_catalogue_is_valid_and_covers_the_required_kinds
    kinds = Koholint::Modes.catalogue.map(&:kind).uniq
    %w[play dialogue menu map save game_over transition cutscene title].each { |kind| assert_includes kinds, kind }
  end

  def test_required_keys
    error = assert_raises(Koholint::Modes::Invalid) { load([entry('a', { 'game_mode' => 1 }).except('exit')]) }
    assert_match(/missing exit/, error.message)
  end

  def test_verified_needs_two_checks
    error = assert_raises(Koholint::Modes::Invalid) { load([entry('a', { 'game_mode' => 1 }, confidence: 'verified', verified_count: 1)]) }
    assert_match(/verified_count >= 2/, error.message)
  end

  def test_unknown_kind_phase_or_field
    assert_raises(Koholint::Modes::Invalid) { load([entry('a', { 'game_mode' => 1 }, kind: 'shop')]) }
    assert_raises(Koholint::Modes::Invalid) { load([entry('a', { 'game_mode' => 1 }, phase: 'shopping')]) }
    assert_raises(Koholint::Modes::Invalid) { load([entry('a', { 'room_id' => 1 })]) }
    assert_raises(Koholint::Modes::Invalid) { load([entry('a', { 'game_mode' => 'one' })]) }
  end

  def test_overlapping_matches_must_be_nested
    error = assert_raises(Koholint::Modes::Invalid) do
      load([entry('a', { 'game_mode' => 11, 'dialog_state' => 'nonzero' }), entry('b', { 'game_mode' => 11, 'motion_blocked' => 'nonzero' })])
    end
    assert_match(/ambiguously/, error.message)
    assert_raises(Koholint::Modes::Invalid) { load([entry('a', { 'game_mode' => 7 }), entry('b', { 'game_mode' => [7] })]) }
    assert_raises(Koholint::Modes::Invalid) { load([entry('a', { 'game_mode' => 7 }), entry('a', { 'game_mode' => 8 })]) }
    modes = load([entry('wide', { 'game_mode' => 11 }), entry('narrow', { 'game_mode' => 11, 'dialog_state' => { 'not' => 0 } })])
    assert_equal 'narrow', Koholint::Modes.for(state(game_mode: 11, dialog_state: 3), modes).name
    assert_equal 'wide', Koholint::Modes.for(state(game_mode: 11, dialog_state: 0), modes).name
  end

  MEASURED = {
    [0, 3, 0, 0, 0, 0, 0] => 'intro', [2, 7, 0, 0, 0, 0, 0] => 'file_select', [3, 2, 0, 0, 0, 0, 0] => 'name_entry',
    [11, 3, 0, 0, 0, 0, 0] => 'loading', [11, 7, 0, 0, 0, 0, 0] => 'play', [11, 7, 0, 0, 3, 0, 0] => 'play',
    [11, 7, 134, 0, 3, 0, 0] => 'dialogue', [11, 7, 0, 2, 3, 0, 0] => 'motion_lock', [11, 7, 0, 0, 1, 0, 0] => 'scene_lock',
    [11, 7, 0, 0, 0, 7, 0] => 'dying', [11, 7, 0, 0, 0, 7, 4] => 'game_over',
    [12, 1, 0, 0, 0, 0, 0] => 'inventory', [12, 5, 0, 0, 1, 0, 0] => 'inventory', [12, 8, 0, 0, 0, 0, 0] => 'inventory',
    [7, 5, 0, 0, 0, 0, 0] => 'map', [7, 5, 3, 0, 0, 0, 0] => 'map', [6, 5, 0, 0, 0, 0, 0] => 'save_screen'
  }.freeze

  def tuple(values) = Koholint::Modes::FIELDS.zip(values).to_h

  def test_measured_tuples_resolve_to_their_mode
    MEASURED.each { |values, name| assert_equal name, Koholint::Modes.for(state(**tuple(values)))&.name, values.inspect }
  end

  def test_phases_of_measured_tuples
    phases = { [12, 1, 0, 0, 0, 0, 0] => :menu, [12, 5, 0, 0, 0, 0, 0] => :menu, [7, 5, 0, 0, 0, 0, 0] => :map, [6, 5, 0, 0, 0, 0, 0] => :save,
               [11, 7, 0, 0, 0, 7, 4] => :game_over, [11, 7, 0, 0, 0, 7, 0] => :cutscene, [11, 7, 0, 0, 1, 0, 0] => :locked,
               [11, 7, 0, 2, 0, 0, 0] => :locked, [11, 2, 0, 0, 0, 0, 0] => :loading, [0, 7, 0, 0, 0, 0, 0] => :boot }
    phases.each { |values, phase| assert_equal phase, state(**tuple(values)).phase(booted: true), values.inspect }
  end

  def test_screens_are_ready_only_once_settled
    refute Koholint::Modes.ready?(state(game_mode: 12, game_submode: 5))
    assert Koholint::Modes.ready?(state(game_mode: 12, game_submode: 8))
    assert Koholint::Modes.ready?(state(game_mode: 11, game_submode: 7))
  end

  def test_an_uncatalogued_tuple_is_unknown_once_booted_and_boot_before
    assert_nil Koholint::Modes.for(state(game_mode: 0x0D, game_submode: 1))
    assert_equal :unknown, state(game_mode: 0x0D, game_submode: 1).phase(booted: true)
    assert_equal :boot, state(game_mode: 0x0D, game_submode: 1).phase
    assert_equal :boot, state(game_mode: 12, game_submode: 8).phase
  end

  def test_values_must_be_bytes_and_lists_non_empty
    assert_raises(Koholint::Modes::Invalid) { load([entry('a', { 'game_mode' => [] })]) }
    assert_raises(Koholint::Modes::Invalid) { load([entry('a', { 'game_mode' => 256 })]) }
    assert_raises(Koholint::Modes::Invalid) { load([entry('a', { 'game_mode' => [-1, 3] })]) }
    assert_raises(Koholint::Modes::Invalid) { load([entry('a', { 'game_mode' => { 'not' => [300] } })]) }
  end

  def test_counts_and_keys_are_strict
    assert_raises(Koholint::Modes::Invalid) { load([entry('a', { 'game_mode' => 1 }, verified_count: '2')]) }
    assert_raises(Koholint::Modes::Invalid) { load([entry('a', { 'game_mode' => 1 }, colour: 'green')]) }
  end

  def test_cursor_and_options_must_agree_with_the_addresses
    cursor = { 'field' => 'menu_option', 'addr' => '0xC13F', 'count' => 2 }
    load([entry('a', { 'game_mode' => 6 }, cursor:, options: [{ 'text' => 'back' }, { 'text' => 'quit', 'quits' => true }])])
    assert_raises(Koholint::Modes::Invalid) { load([entry('a', { 'game_mode' => 6 }, cursor:, options: [{ 'text' => 'back' }])]) }
    assert_raises(Koholint::Modes::Invalid) { load([entry('a', { 'game_mode' => 6 }, cursor: cursor.merge('field' => 'nowhere'))]) }
    assert_raises(Koholint::Modes::Invalid) { load([entry('a', { 'game_mode' => 6 }, options: [{ 'text' => 'back' }])]) }
    assert_raises(Koholint::Modes::Invalid) { load([entry('a', { 'game_mode' => 6 }, cursor:, options: [{ 'text' => 'a' }, { 'text' => 'b', 'quits' => 'yes' }])]) }
  end

  def test_quitting_options_are_flagged_and_hidden_from_choices
    over = Koholint::Modes.catalogue.find { |mode| mode.name == 'game_over' }
    assert over.quits?(1)
    assert_equal [0, 2], over.choices.map(&:first)
    assert_equal [0], Koholint::Modes.catalogue.find { |mode| mode.name == 'save_screen' }.choices.map(&:first)
  end
end
