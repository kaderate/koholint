require_relative 'test_helper'

class AgentManualTest < Minitest::Test
  PATH = File.expand_path('../docs/AGENT_MANUAL.md', __dir__)
  FORBIDDEN = %w[house starting_house interior marin tarin tarkin ulrira tracy owl bidule koholint hypothesis project
                 decisions agents.md roadmap walkthrough trace.jsonl world.json emu-gb v1 d14 telephone witch pond].freeze

  def text = File.read(PATH)

  def test_is_short
    assert_operator text.size, :<, 3000
  end

  def test_has_no_room_ids
    refute_match(%r{\d+\s*/\s*\d+}, text)
  end

  def test_has_no_game_facts_or_project_commentary
    FORBIDDEN.each { |word| refute_match(/\b#{Regexp.escape(word)}\b/i, text, word) }
    refute_match(/\bMr\./, text)
    refute_match(/\b\w+\.(rb|md|json|jsonl)\b/, text.sub(/\A# Game manual/, ''))
  end

  def test_cli_loads_the_digest_not_the_developer_notes
    source = File.read(File.expand_path('../lib/koholint/cli.rb', __dir__))
    assert_includes source, 'docs/AGENT_MANUAL.md'
    refute_includes source, 'GAME_MANUAL_NOTES'
  end
end
