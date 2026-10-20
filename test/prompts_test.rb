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

  def test_the_plan_line_is_mandatory
    points.each do |point|
      text = Koholint::Agents::Prompts.system_for(point)
      assert_includes text, 'The plan field is mandatory on every call'
      refute_match(/optional(ly)? (short )?plan|and plan\b.*optionally/i, text)
    end
  end

  def test_no_game_facts
    points.each do |point|
      text = Koholint::Agents::Prompts.system_for(point).downcase
      %w[sword shield beach marin tarin owl dungeon zelda rupee bed house].each { |word| refute_match(/\b#{word}/, text, word) }
    end
  end

  def test_goal_and_leads_are_offered_with_a_generic_rubric
    objective, skill = points.map { |p| Koholint::Agents::Prompts.system_for(p) }
    assert_includes skill, 'revise it only when new information changes it, omit it to keep it'
    assert_includes objective, 'Review it at every objective: re-read the leads'
    assert_includes points.first.json_schema[:required], 'goal'
    refute_includes points.last.json_schema[:required], 'goal'
    assert_includes objective, 'give its id in because'
    assert_includes skill, 'signs or objects you read'
    assert_includes skill, 'high: it states a goal, a destination, an item to obtain, a condition or obstacle, or a danger.'
    assert_includes Koholint::Agents::Prompts.system_for(points.last, sheets: true), 'then extract its leads'
    assert_equal %i[goal because], points.first.json_schema[:properties].keys & %i[goal because leads]
    leads = points.last.json_schema[:properties][:leads]
    quote = leads[:items][:properties][:quote]
    assert_equal [5, %w[high normal low], 1, nil], [leads[:maxItems], leads[:items][:properties][:importance][:enum], quote[:minLength], quote[:maxLength]]
    assert_nil leads[:items][:properties][:claim][:maxLength]
    assert_equal 120, points.last.json_schema[:properties][:goal][:maxLength]
  end

  def test_unknown_point_raises
    assert_raises(ArgumentError) { Koholint::Agents::Prompts.system_for(Koholint::DecisionPoint.move) }
  end
end
