require_relative 'test_helper'
require 'koholint/decision'
require 'koholint/agents/prompts'

class PromptsTest < Minitest::Test
  def points
    [Koholint::DecisionPoint.choose_objective, Koholint::DecisionPoint.choose_skill(Koholint::Skills::Registry.default)]
  end

  def test_system_text_for_both_points
    points.each do |point|
      text = Koholint::Agents::Prompts.system_for(point)
      assert_operator text.size, :>, 200
      assert_match(/manual/i, text)
      assert_match(/walkthrough/i, text)
      assert_match(/unknown cells are not walls/i, text)
      assert_match(/JSON/, text)
    end
  end

  def test_texts_differ_and_name_their_output
    objective, skill = points.map { |p| Koholint::Agents::Prompts.system_for(p) }
    refute_equal objective, skill
    assert_includes objective, 'predicate'
    assert_includes skill, 'skill'
  end

  def test_the_objective_prompt_lists_all_five_kinds
    text = Koholint::Agents::Prompts.system_for(Koholint::DecisionPoint.choose_objective)
    assert_includes text, 'one of five kinds: leave_place (place), reach_place (place), reach_cell (place, row, col), dialogue_closed or new_place (no fields).'
  end

  def test_no_game_facts
    points.each do |point|
      text = Koholint::Agents::Prompts.system_for(point).downcase
      %w[sword shield beach marin tarin owl dungeon zelda rupee bed house].each { |word| refute_match(/\b#{word}/, text, word) }
    end
  end

  def test_unknown_point_raises
    assert_raises(ArgumentError) { Koholint::Agents::Prompts.system_for(Koholint::DecisionPoint.move) }
  end
end
