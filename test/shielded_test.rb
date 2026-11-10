require_relative 'test_helper'
require 'koholint/skills/shielded'
require 'koholint/entities'

class ShieldedTest < Minitest::Test
  State = Struct.new(:x, :y, :item_a, :item_b)

  class Inner
    attr_reader :frames

    def initialize(inputs) = @inputs = inputs
    def next_input(_state) = @inputs.shift
    def result(*) = { skill: 'walk' }
  end

  def shielded(inputs, enemies)
    Koholint::Skills::Shielded.new(Inner.new(inputs), entities: -> { enemies })
  end

  NEAR = [{ kind: :enemy, type: 9, x: 80, y: 60, contact: 9 }].freeze
  FAR = [{ kind: :enemy, type: 9, x: 150, y: 120, contact: 9 }].freeze

  def test_holds_the_shield_button_beside_the_direction_while_a_threat_is_near
    walk = shielded([[:right], [:right]], NEAR)
    assert_equal %i[right b], walk.next_input(State.new(60, 60, 0, 4))
    assert_equal({ skill: 'walk', shield_frames: 1 }, walk.result)
  end

  def test_releases_it_when_far_or_when_nothing_moves_or_no_shield_is_equipped
    assert_equal [:right], shielded([[:right]], FAR).next_input(State.new(60, 60, 0, 4))
    assert_equal [], shielded([[]], NEAR).next_input(State.new(60, 60, 0, 4))
    assert_equal [:right], shielded([[:right]], NEAR).next_input(State.new(60, 60, 0, 0))
    assert_equal %i[right a], shielded([[:right]], NEAR).next_input(State.new(60, 60, 4, 0))
    assert_nil shielded([], NEAR).next_input(State.new(60, 60, 0, 4))
  end

  def test_the_threat_margin_is_a_parameter
    threats = Koholint::Navigation::Threat.of(NEAR)
    assert Koholint::Navigation::Threat.within?(threats, 100, 60, margin: 11)
    refute Koholint::Navigation::Threat.within?(threats, 100, 60, margin: 10)
  end
end
