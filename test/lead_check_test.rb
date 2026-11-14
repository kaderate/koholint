require_relative 'test_helper'
require 'stringio'
require 'koholint/lead_check'

class LeadCheckTest < Minitest::Test
  def lead(claim, quote: 'Tu ne peux pas passer.', where: nil, frame: 200) = { 'type' => 'lead', 'id' => 'lead-1', 'frame' => frame, 'place' => [1, 0], 'quote' => quote, 'claim' => claim, 'where' => where }.compact

  def perception(frame, **state) = { 'type' => 'perception', 'frame' => frame, 'state' => { 'milestone' => 'none' }.merge(state.transform_keys(&:to_s)) }

  def test_an_item_named_by_the_claim_alone_and_never_held_is_a_leak
    leaks = Koholint::LeadCheck.leaks([perception(100), lead('An item (e.g. Power Bracelet) is needed')])
    assert_equal [{ id: 'lead-1', frame: 200, place: [1, 0], items: ['power bracelet'], claim: 'An item (e.g. Power Bracelet) is needed' }], leaks
    assert_equal ['hookshot'], Koholint::LeadCheck.leaks([lead('Go there', where: 'Hookshot cave')]).first[:items]
  end

  def test_an_item_the_quote_names_or_link_holds_is_not_a_leak
    assert_empty Koholint::LeadCheck.leaks([lead('the bow is sold here', quote: 'A bow for 980 rupees')])
    assert_empty Koholint::LeadCheck.leaks([perception(100, item_a: 1), lead('Use the sword on the bush')])
    assert_empty Koholint::LeadCheck.leaks([perception(100, milestone: 'shield'), lead('Link got his shield back')])
    assert_empty Koholint::LeadCheck.leaks([lead('A swordsman lives here')])
    refute_empty Koholint::LeadCheck.leaks([lead('Use the sword'), perception(300, item_a: 1)])
  end

  def test_aliases_in_the_games_language_plurals_and_short_names_count_on_both_sides
    assert_empty Koholint::LeadCheck.leaks([lead('the shield costs 20', quote: 'Bouclier: 20 rubis')])
    assert_empty Koholint::LeadCheck.leaks([lead('pegasus boots are sold', quote: 'Des bottes de Pégase!')])
    assert_equal ['magic powder'], Koholint::LeadCheck.leaks([lead('he wants some powder', quote: "J'aime pas du tout c'qu'est poudreux")]).first[:items]
    assert_equal ['bombs'], Koholint::LeadCheck.leaks([lead('blow it up with a bomb')]).first[:items]
  end

  def test_a_text_read_earlier_in_the_run_counts_as_read
    dialogue = { 'type' => 'dialogue', 'frame' => 150, 'text' => 'Il y a une épée sur la plage.' }
    assert_empty Koholint::LeadCheck.leaks([dialogue, lead('the sword is on the beach')])
    assert_equal [1, 4], Koholint::Items.held_ids({ item_a: 1, milestone: :shield, inventory: [0] * 10 }).sort
  end

  def test_the_committed_bundle_shows_the_one_leak_it_carries
    out = StringIO.new
    assert_equal 1, Koholint::LeadCheck.check([File.expand_path('../runs/20261111-194737-9ba1', __dir__)], out:)
    assert_match(/\A20261111-194737-9ba1 lead-5 \(163-16, frame 4678\): names sword: Another item \(probably the sword\) was left on the beach\n1 lead/, out.string)
  end
end
