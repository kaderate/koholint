require 'json'

module Gates
  # Calls at or below this health count as calls at low health (two hearts).
  LOW_HP = 8
  FIELDS = %i[calls low lost deaths delivery].freeze

  module_function

  # What a gate measures in a run, from its parent frame on: model calls, calls at low health, hp lost, deaths and the first delivery
  # (a use_item that opened a dialogue).
  def metrics(dir)
    manifest = JSON.parse(File.read(File.join(dir, 'manifest.json')))
    start = manifest.dig('parent', 'frame') || 0
    out = { calls: 0, low: 0, lost: 0, deaths: 0, delivery: nil }
    health = nil
    File.foreach(File.join(dir, 'trace.jsonl')) do |line|
      event = JSON.parse(line)
      next if event['frame'].to_i < start

      case event['type']
      when 'decision'
        hp = event.dig('input', 'hp')
        if event['agent'] == 'claude'
          out[:calls] += 1
          out[:low] += 1 if hp <= LOW_HP
        end
        out[:lost] += health - hp if health && hp < health
        health = hp
      when 'action'
        out[:delivery] ||= event['frame'] if event['skill'] == 'use_item' && event.dig('result', 'stopped_by') == 'dialogue'
      when 'notable'
        out[:deaths] += 1 if event['kind'] == 'death'
      end
    end
    out
  end

  # Each field whose measured value differs from the expected one: [field, expected, measured].
  def mismatches(expected, measured)
    FIELDS.filter_map { |field| [field, expected[field.to_s], measured[field]] if expected[field.to_s] != measured[field] }
  end
end

puts JSON.generate(Gates.metrics(ARGV.fetch(0))) if $PROGRAM_NAME == __FILE__
