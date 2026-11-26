require 'minitest/autorun'
require 'json'
require 'tmpdir'
require 'koholint'
require_relative '../tools/gates/metrics'

class GatesTest < Minitest::Test
  def run_dir(events)
    dir = Dir.mktmpdir
    File.write(File.join(dir, 'manifest.json'), JSON.generate('parent' => { 'frame' => 100 }, 'flow_version' => 'flow-111'))
    File.write(File.join(dir, 'trace.jsonl'), events.map { |event| JSON.generate(event) }.join("\n"))
    dir
  end

  def decision(frame, hp, agent = 'claude') = { 'type' => 'decision', 'frame' => frame, 'agent' => agent, 'input' => { 'hp' => hp } }

  def test_metrics_count_from_the_parent_frame
    dir = run_dir([decision(50, 4), decision(100, 24), decision(110, 16, 'delegated'), decision(120, 8), decision(130, 24),
                   { 'type' => 'action', 'frame' => 140, 'skill' => 'use_item', 'result' => { 'stopped_by' => 'done' } },
                   { 'type' => 'action', 'frame' => 150, 'skill' => 'use_item', 'result' => { 'stopped_by' => 'dialogue' } },
                   { 'type' => 'notable', 'frame' => 160, 'kind' => 'death' }])
    assert_equal({ calls: 3, low: 1, lost: 16, deaths: 1, delivery: 150 }, Gates.metrics(dir))
  ensure
    FileUtils.rm_rf(dir)
  end

  def test_mismatches_name_each_field_that_moved
    expected = { 'calls' => 69, 'low' => 0, 'lost' => 12, 'deaths' => 0, 'delivery' => 100_084 }
    assert_empty Gates.mismatches(expected, { calls: 69, low: 0, lost: 12, deaths: 0, delivery: 100_084 })
    assert_equal [[:calls, 69, 70], [:delivery, 100_084, nil]], Gates.mismatches(expected, { calls: 70, low: 0, lost: 12, deaths: 0, delivery: nil })
  end

  def test_every_gate_has_expected_numbers_for_the_current_flow
    gates = JSON.parse(File.read(File.expand_path('../tools/gates/gates.json', __dir__)))['gates'].keys
    JSON.parse(File.read(File.expand_path('../tools/gates/expected.json', __dir__))).each do |flow, numbers|
      assert_empty numbers.keys - gates, flow
      assert_equal gates.sort, numbers.keys.sort, flow if flow == Koholint::FLOW_VERSION
      numbers.each_value { |want| assert_equal Gates::FIELDS.map(&:to_s).sort, want.keys.sort }
    end
  end

  def test_a_flow_bump_records_its_gate_numbers
    expected = JSON.parse(File.read(File.expand_path('../tools/gates/expected.json', __dir__)))
    assert expected.key?(Koholint::FLOW_VERSION), "play the gates at #{Koholint::FLOW_VERSION} and add their numbers to tools/gates/expected.json"
  end
end
