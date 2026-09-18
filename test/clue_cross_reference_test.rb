# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/clue_cross_reference"

class ClueCrossReferenceTest < Minitest::Test
  # Inline fixture, independent of the live (ever-changing) data/ram_registry.json.
  def fixture_registry
    {
      "select_map_screen" => {
        "note" => 'Confirmed place names read off the SELECT map legend: "Plage Coco", "Village des Mouettes".'
      },
      "room_labels" => {
        "162/0" => {"label" => "Bibliothèque entrance"}
      },
      "world_topology" => {
        "riverside_south_room" => {
          "note" => 'Open discussion, unresolved: is the "Loupe" somewhere south of here? Not observed, just debated.'
        }
      },
      "dialogues" => {
        "starting_house_npc_bench" => {
          "text" => "Les gens du village t'ont dit d'aller sur la plage."
        },
        "unrelated_npc" => {
          "text" => "Attention, il fait nuit, rentre chez toi."
        },
        "loupe_rumor_npc" => {
          "text" => "On raconte qu'une loupe se cache quelque part, mais personne ne l'a jamais vue."
        }
      }
    }
  end

  def test_lowercase_common_noun_matches_a_select_map_place_name
    matches = Koholint::ClueCrossReference.matches(fixture_registry)
    bench_match = matches.find { |m| m.dialogue_path == "dialogues.starting_house_npc_bench.text" }

    refute_nil bench_match, "expected the starting_house bench dialogue to cross-reference a place name"
    assert_includes bench_match.place_names, "Plage Coco"
  end

  def test_dialogue_with_no_place_name_overlap_is_not_reported
    matches = Koholint::ClueCrossReference.matches(fixture_registry)

    refute matches.any? { |m| m.dialogue_path == "dialogues.unrelated_npc.text" }
  end

  # Regression test for the exact bug the grounding constraint exists to prevent: a term that
  # only appears in world_topology's open-discussion notes (never in select_map_screen.note or
  # room_labels) must never read as grounded just because it's mentioned there.
  def test_term_only_present_in_world_topology_notes_is_never_grounded
    place_names = Koholint::ClueCrossReference.place_names(fixture_registry)

    refute_includes place_names, "Loupe"

    matches = Koholint::ClueCrossReference.matches(fixture_registry)
    refute matches.any? { |m| m.dialogue_path == "dialogues.loupe_rumor_npc.text" }
  end

  def test_room_labels_contribute_to_the_place_name_vocabulary
    place_names = Koholint::ClueCrossReference.place_names(fixture_registry)

    assert_includes place_names, "Bibliothèque entrance"
  end

  def test_place_word_index_skips_short_words_and_stopwords
    index = Koholint::ClueCrossReference.place_word_index(["Chez Marine", "La Plage"])

    refute index.key?("la")
    refute index.key?("chez")
    assert_includes index["plage"], "La Plage"
    assert_includes index["marine"], "Chez Marine"
  end
end
