require_relative 'delegated_policy_test'

class RevisitPolicyTest < Minitest::Test
  include DelegatedHelpers

  OPEN = DelegatedPolicyTest::OPEN
  SHOT = DelegatedPolicyTest::SHOT
  PAGE = DelegatedPolicyTest::PAGE
  DARK = [27, 42, 9].pack('C3')
  LIGHT = [154, 158, 63].pack('C3')
  TARKIN = { slot: 1, type: 63, x: 120, y: 80, cell: [4, 7], kind: :npc }.freeze

  def text_page(width)
    rows = Array.new(96) { |y| y < 48 ? [DARK * 0, LIGHT * 160].join : Array.new(160) { |x| y == 60 && x.between?(20, 20 + width - 1) ? LIGHT : DARK }.join }
    rows.map { |row| row.unpack('a3' * 160).map { |pixel| pixel * 4 }.join * 4 }.join
  end

  def setup_revisit(skill:, entities: [TARKIN], goal: objective)
    @client = ScriptedClient.new(objective: goal, skill:)
    @objectives = Koholint::Objectives.new(trace:)
    @talk_log = Koholint::TalkLog.new
    @people = entities
    Koholint::Policies::Delegated.new(client: @client, registry: Koholint::Skills::Registry.default, objectives: @objectives, manual: 'notes', talk_log: @talk_log)
  end

  def context(page = nil) = { grid:, dialogue_shot: -> { SHOT }, dialogue_rgb: -> { page || PAGE }, entities: -> { @people } }

  def step(policy, at, page = nil) = policy.decide(policy.decision_point_for(at), at, context(page))

  def converse(policy, page, from:)
    2.times do |i|
      at = state(frame: from + (i * 30), milestone: :shield, **OPEN)
      result = step(policy, at, page)
      assert_equal 'advance_dialogue', result[:choice][:skill]
      policy.after_action(choice: result[:choice], outcome: { stopped_by: 'done' }, state: at, frame: at.frame + 30)
    end
    waited = step(policy, state(frame: from + 100, milestone: :shield), page)
    assert_equal 'wait', waited[:choice][:skill]
    policy.after_action(choice: waited[:choice], outcome: { stopped_by: 'done' }, state: state(frame: from + 110, milestone: :shield), frame: from + 110)
    step(policy, state(frame: from + 110, milestone: :shield), page)
  end

  def talked(policy, result, frame)
    policy.after_action(choice: result[:choice], outcome: { stopped_by: 'done', talked: true, entity: { type: 63, slot: 1, kind: 'npc' } },
                        state: state(frame:, milestone: :shield), frame:)
  end

  def exhaust_before_the_shield
    stamp = Koholint::Dialogues.stamp(milestone: :none, places: 1, leads: 0)
    2.times { @talk_log.remember(place: [163, 16], cell: [4, 7], text: 'Hello, take this.', stamp:, entity: 63, conversation: 'e' * 16) }
  end

  def test_the_revisit_fires_right_after_a_milestone_change_without_a_model_call
    sheet = ok('skill' => 'explore', 'params' => {}, 'transcription' => 'By the way, something was left on the beach.', 'speaker' => 'Tarkin')
    p = setup_revisit(skill: [walk, sheet, walk])
    exhaust_before_the_shield
    p.observe(state, frame: 100)
    step(p, state)
    _, before = decide(p, state)
    assert_equal ['walk', 'claude'], [before[:choice][:skill], before[:agent]]
    calls = @client.calls.size

    revisit = step(p, state(frame: 200, milestone: :shield))
    assert_equal [{ skill: 'talk_to', params: { row: 4, col: 7 } }, 'delegated', 0.0, false], revisit.values_at(:choice, :agent, :cost_usd, :fallback)
    assert_match(/\Arevisit npc: entity type 63 at \(4,7\), round 1/, revisit[:justification])
    assert_equal calls, @client.calls.size
    talked(p, revisit, 220)

    read = converse(p, text_page(40), from: 230)
    assert_equal calls + 1, @client.calls.size
    assert_equal 1, @client.calls.last[:images].size
    assert_equal [{ skill: 'talk_to', params: { row: 4, col: 7 } }, 'claude'], read.values_at(:choice, :agent)
    assert_includes read[:justification], "replaces the model's choice explore"
    assert_equal ['Tarkin'], read[:transcription].map { |entry| entry[:speaker] }
    assert_match(/\A\h{16}\z/, read[:transcription].first[:conversation])
    assert_equal [{ npc: { place: [163, 16], type: 63, cell: [4, 7] }, round: 1, outcome: 'new' }], read[:notables].map { |note| note[:detail] }
    talked(p, read, 400)

    again = converse(p, text_page(40), from: 410)
    assert_equal calls + 2, @client.calls.size
    assert_nil @client.calls.last[:images]
    assert_includes @client.calls.last[:prompt], 'repeated a text already read (not sent again): By the way'
    assert_equal [[true, 'Tarkin']], again[:transcription].map { |entry| entry.values_at(:cached, :speaker) }
    assert_equal [[2, 'exhausted']], again[:notables].map { |note| note[:detail].values_at(:round, :outcome) }
    assert_equal 'walk', again[:choice][:skill]
    assert_includes @client.calls.last[:prompt], 'People on screen: Tarkin (4,7)'
    assert_includes @client.calls.last[:prompt], '- at (4,7): entity type 63 (npc, name Tarkin): talked to 2 times (dialogue opened 2)'
  end

  def test_no_revisit_without_an_npc_entity_or_while_a_dialogue_is_open
    p = setup_revisit(skill: [walk, walk], entities: [TARKIN.merge(kind: :unknown)])
    step(p, state)
    assert_equal 'claude', step(p, state(frame: 200, milestone: :shield))[:agent]
    @people = [TARKIN]
    assert_equal 'advance_dialogue', step(p, state(frame: 300, milestone: :shield, **OPEN), text_page(10))[:choice][:skill]
  end

  def test_a_revisit_also_replaces_a_choose_objective_point
    p = setup_revisit(skill: [walk], goal: failing('no objective'))
    step(p, state(frame: 50), nil)
    assert_nil @objectives.current
    @client.calls.clear
    point = p.decision_point_for(state)
    assert_equal :choose_skill, point.name
    assert_equal ['talk_to', 'delegated'], p.decide(point, state, context).then { |r| [r[:choice][:skill], r[:agent]] }
    assert_empty @client.calls
  end

  def test_no_revisit_when_the_budget_is_nearly_exhausted
    budget = Koholint::Budget.new(frames: 1500, clock: ->(*) { 0 })
    p = Koholint::Policies::Delegated.new(client: (@client = ScriptedClient.new(objective: objective, skill: [walk, walk])), registry: Koholint::Skills::Registry.default,
                                          objectives: (@objectives = Koholint::Objectives.new(trace:)), manual: 'notes', budget:)
    @people = [TARKIN]
    step(p, state)
    assert_equal 'claude', step(p, state(frame: 200))[:agent]
  end
end
