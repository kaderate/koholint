require_relative 'test_helper'
require 'koholint/engine'

class EngineChestsTest < Minitest::Test
  ROOM = Koholint::Entities::ADDRESSES.fetch(:room_objects)

  Trace = Struct.new(:events) do
    def emit(type, frame:, **fields) = events << { type:, frame:, **fields }
  end

  def setup
    @objects = Hash.new(0)
    reader = Object.new
    objects = @objects
    reader.define_singleton_method(:read) { |addr| objects[addr] }
    @trace = Trace.new([])
    @engine = Koholint::Engine.allocate
    @engine.instance_variable_set(:@emulator, reader)
    @engine.instance_variable_set(:@run, Struct.new(:trace).new(@trace))
  end

  def put(cell, object) = @objects[ROOM + (cell[0] * Koholint::Entities::ROOM_ROW_STRIDE) + cell[1]] = object

  def look(frame, room: 1) = @engine.send(:note_chests, Koholint::GameState.new(frame:, room_id: room, map_id: 0, x: 72, y: 80, hp: 24, max_hp: 24, game_mode: 0x0B, game_submode: 7))

  def test_a_chest_closed_at_the_last_look_and_open_now_is_traced_once
    put([3, 4], 160)
    look(10)
    put([3, 4], 161)
    look(20)
    look(30)
    assert_equal [{ type: :chest_opened, frame: 20, place: [1, 0], cell: [3, 4] }], @trace.events
  end

  def test_a_chest_already_open_or_seen_in_another_place_is_not_traced
    put([3, 4], 160)
    look(10, room: 2)
    put([3, 4], 161)
    look(20)
    assert_empty @trace.events
  end
end
