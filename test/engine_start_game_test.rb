require_relative 'test_helper'
require 'koholint/engine'
require 'koholint/explore_log'
require 'koholint/policies/delegated'
require 'koholint/policies/start_game'
require 'koholint/skills/registry'
require 'support/delegated_helpers'

class EngineStartGameTest < Minitest::Test
  include DelegatedHelpers

  Trace = Struct.new(:events) do
    def emit(type, frame:, **fields) = events << { type:, frame:, **fields }
  end

  def setup
    slot = Koholint::Entities::ADDRESSES.slice(:entity_status, :entity_type, :entity_x, :entity_y).to_h { |name, addr| [addr, { entity_status: 5, entity_type: 250, entity_x: 88, entity_y: 64 }.fetch(name)] }
    reader = Object.new
    reader.define_singleton_method(:read) { |addr| slot.fetch(addr, 0) }
    @log = Koholint::ExploreLog.new
    @delegated = Koholint::Policies::Delegated.new(client: ScriptedClient.new, registry: Koholint::Skills::Registry.default, objectives: Koholint::Objectives.new(trace: Trace.new([])),
                                                   manual: 'notes', memory: Koholint::Policies::Memory.new(explore_log: @log))
    @engine = Koholint::Engine.allocate
    @engine.instance_variable_set(:@emulator, reader)
    @engine.instance_variable_set(:@run, Struct.new(:trace).new(Trace.new([])))
    @engine.instance_variable_set(:@policy, Koholint::Policies::StartGame.new(@delegated))
  end

  def playing = Koholint::GameState.new(frame: 10, room_id: 5, map_id: 0, x: 72, y: 80, hp: 24, max_hp: 24, game_mode: 0x0B, game_submode: 7)

  def test_a_live_run_feeds_the_place_card_to_the_explore_log_through_start_game
    @engine.send(:note_place, playing, nil)
    assert_equal [250], @log.unmet([5, 0])
  end

  def test_a_live_run_traces_the_objective_candidates_offered_through_start_game
    candidate = { id: 'place-1-0', label: 'go to place 1-0', title: 'Go to place 1-0', predicate: { kind: 'reach_place', place: [1, 0] }, target: { kind: 'place', place: [1, 0] } }
    @delegated.instance_variable_set(:@candidates, [candidate])
    offered = @engine.send(:offered, Struct.new(:name, :options).new(:choose_objective, nil))
    refute_empty offered
    assert_equal @delegated.offered_candidates, offered
  end
end
