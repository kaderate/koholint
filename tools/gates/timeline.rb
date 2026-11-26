require 'json'

# One line per decision, objective and damaging or blocked action of a run, from its parent frame on.
dir = ARGV.fetch(0)
start = JSON.parse(File.read(File.join(dir, 'manifest.json'))).dig('parent', 'frame') || 0
File.foreach(File.join(dir, 'trace.jsonl')) do |line|
  event = JSON.parse(line)
  next if event['frame'].to_i < start

  case event['type']
  when 'decision'
    input = event['input']
    choice = event['choice']
    what = choice.is_a?(Hash) ? "#{choice['skill'] || choice['buttons']} #{(choice['params'] || choice['target'] || '').to_s[0, 80]}" : choice.to_s[0, 80]
    puts "D #{event['frame']} #{input['room_id']}/#{input['map_id']} hp#{input['hp']} #{event['agent']} #{event['decision_point']} | #{what} | #{event['justification'].to_s[0, 110]}"
  when 'objective'
    puts "O #{event['frame']} #{event['status']} #{event['title']} #{(event['target'] || {}).slice('place', 'heal_below').inspect} #{event['reason']}"
  when 'action'
    stop = event.dig('result', 'stopped_by').to_s
    puts "A #{event['frame']} #{event['skill']} #{stop}" if stop.match?(/damage|held|unreach|no_path/)
  end
end
