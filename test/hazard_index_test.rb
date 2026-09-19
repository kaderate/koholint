# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/hazard_index"

class HazardIndexTest < Minitest::Test
  # Inline fixture, independent of the live (ever-changing) data/ram_registry.json. Shaped after
  # the real riverside_flower_clearing_sign case (dialogue claim + a room_labels description
  # field that echoes the same hazard term in one sentence and an unrelated test in another).
  def fixture_registry
    {
      "visual_catalog" => {
        "test_creature" => {
          "hazard_status" => "hostile -- tile=0x60 family, contact damage confirmed",
          "rooms_seen" => ["100/0 (test_room)"],
          "tile_ids_seen" => {"100/0" => [0x60, 0x62]}
        }
      },
      "room_labels" => {
        "100/0" => {
          "label" => "test_room",
          "description" => "A grassy room with a spiky hazard sprite, tile=0x50 pairs, near the " \
                            "entrance. Sea-urchin-shaped objects (oursins) sit along the south " \
                            "wall, matching the signpost's warning. Later, in a totally separate " \
                            "part of this same room, a contact test against an unrelated wandering " \
                            "creature confirmed the shield mitigates its damage."
        }
      },
      "world_topology" => {
        "test_room_survey" => {
          "room_id" => 100,
          "map_id" => 0,
          "sprite_survey" => "Confirmed OAM sprite tile=0x6c wandering near the west wall.",
          "note" => "Open discussion: could a 'Loupe' be somewhere in this room? Not observed, " \
                     "just debated, tile=0x99 hypothesized."
        }
      },
      "dialogues" => {
        "test_sign" => {
          "text" => "Attention aux oursins! Se protéger avec un bouclier!"
        },
        "unrelated_npc" => {
          "text" => "Bonjour, il fait beau aujourd'hui."
        }
      }
    }
  end

  # (a) a tile ID present in visual_catalog/room_labels is reported.
  def test_tile_query_returns_visual_catalog_and_room_labels_hits
    hits = Koholint::HazardIndex.tile_hits(fixture_registry, 0x60)

    assert(hits.any? { |h| h.collection == "visual_catalog" && h.key == "test_creature" && h.field.start_with?("tile_ids_seen") })
    hits = Koholint::HazardIndex.tile_hits(fixture_registry, 0x50)
    assert(hits.any? { |h| h.collection == "room_labels" && h.key == "100/0" })
  end

  # (b) HOSTILE_TILE_IDS / UNKNOWN_HAZARD_TILE_IDS membership is reported correctly.
  def test_hazard_membership_reports_hostile_and_unknown_hazard_correctly
    hostile = Koholint::HazardIndex.hazard_membership(Koholint::Navigator::HOSTILE_TILE_IDS.first)
    assert hostile[:hostile]
    refute hostile[:unknown_hazard]

    unknown = Koholint::HazardIndex.hazard_membership(Koholint::Navigator::UNKNOWN_HAZARD_TILE_IDS.first)
    refute unknown[:hostile]
    assert unknown[:unknown_hazard]

    neither = Koholint::HazardIndex.hazard_membership(0x02)
    refute neither[:hostile]
    refute neither[:unknown_hazard]
  end

  # (c) the untested-claim scan finds the fixture's "shield counters oursins"-style claim and does
  # NOT mark it as tested, even though the same room_labels field mentions a test elsewhere --
  # for a DIFFERENT creature, in a different sentence (the real room_labels['225/0'] trap).
  def test_untested_claim_scan_surfaces_specific_claim_without_false_positive_suppression
    claims = Koholint::HazardIndex.untested_claims(fixture_registry)
    claim = claims.find { |c| c.dialogue_path == "dialogues.test_sign.text" }

    refute_nil claim, "expected the oursins/shield claim to be surfaced as untested"
    assert_includes claim.terms, "oursins"
  end

  def test_untested_claim_scan_ignores_dialogue_with_no_claim
    claims = Koholint::HazardIndex.untested_claims(fixture_registry)

    refute claims.any? { |c| c.dialogue_path.start_with?("dialogues.unrelated_npc") }
  end

  # A claim genuinely reflected as tested elsewhere (same claim term + test-evidence term in one
  # sentence, in an entry OTHER than the dialogue itself) must be suppressed.
  def test_untested_claim_scan_suppresses_a_claim_actually_tested_elsewhere
    registry = fixture_registry
    registry["world_topology"]["test_room_survey"]["contact_test"] =
      "Contact test against the oursins confirmed the bouclier fully blocks their damage."

    claims = Koholint::HazardIndex.untested_claims(registry)

    refute claims.any? { |c| c.dialogue_path == "dialogues.test_sign.text" }
  end

  # (d) grounding regression: a term appearing ONLY in world_topology.*.note (open-discussion
  # prose) must never be reported as an already-grounded fact -- the hazard-index analog of
  # clue_cross_reference_test.rb's own "Loupe" regression test.
  def test_term_only_present_in_world_topology_note_is_never_grounded
    hits = Koholint::HazardIndex.tile_hits(fixture_registry, 0x99)

    assert_empty hits, "tile 0x99 is only mentioned in world_topology's open-discussion note and must not read as grounded"

    room_hits = Koholint::HazardIndex.room_hits(fixture_registry, "100/0")
    refute room_hits.any? { |h| h.field == "note" }, "world_topology.*.note must never surface as a grounded room hit"
  end

  def test_tile_report_combines_membership_and_hits
    report = Koholint::HazardIndex.tile_report(fixture_registry, 0x60)

    assert report[:hostile]
    refute report[:unknown_hazard]
    refute_empty report[:hits]
  end

  def test_chr_hits_matches_on_hex_signature_substring
    registry = fixture_registry
    registry["visual_catalog"]["test_creature"]["chr_pattern_match"] = "tile 96 = 00c00060007100330037003600160014"

    hits = Koholint::HazardIndex.chr_hits(registry, "00c00060007100330037003600160014")
    assert(hits.any? { |h| h.collection == "visual_catalog" && h.key == "test_creature" })
  end

  def test_room_hits_narrows_to_hint_words
    all_hits = Koholint::HazardIndex.room_hits(fixture_registry, "100/0")
    refute_empty all_hits

    hinted = Koholint::HazardIndex.room_hits(fixture_registry, "100/0", hint: "spiky hazard sprite")
    assert(hinted.any? { |h| h.field == "description" })
  end
end
