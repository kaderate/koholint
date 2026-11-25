require_relative 'test_helper'
require 'koholint/engine'

class EngineFloorTest < Minitest::Test
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
    @engine.instance_variable_set(:@gave_way, Set.new)
  end

  def put(cell, object) = @objects[ROOM + (cell[0] * Koholint::Entities::ROOM_ROW_STRIDE) + cell[1]] = object

  def look(frame, room: 189) = @engine.send(:note_floor, Koholint::GameState.new(frame:, room_id: room, map_id: 10, x: 72, y: 80, hp: 24, max_hp: 24, game_mode: 0x0B, game_submode: 7))

  def crumbling = @engine.send(:observed_floors, Koholint::Entities.objects(@engine.instance_variable_get(:@emulator))).select { |object| object[:kind] == :crumbling }

  def test_a_floor_is_crumbling_in_a_place_only_once_a_cell_of_it_was_seen_turning_into_a_hole_there
    put([1, 4], 223)
    put([1, 5], 223)
    look(10)
    assert_empty crumbling
    put([1, 4], 174)
    look(11)
    look(12)
    assert_equal [{ type: :floor_gave_way, frame: 11, place: [189, 10], cell: [1, 4], object: 223 }], @trace.events
    assert_equal [[1, 5]], crumbling.map { |object| object[:cell] }
  end

  def test_the_same_floor_in_a_place_where_it_never_gave_way_is_not_crumbling
    put([1, 4], 223)
    look(10)
    put([1, 4], 174)
    look(11)
    put([1, 4], 223)
    look(20, room: 172)
    assert_empty crumbling
  end
end
