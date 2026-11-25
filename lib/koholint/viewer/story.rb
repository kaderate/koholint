require 'koholint'
require 'koholint/atlas'
require 'koholint/dialogues'
require 'koholint/summary'
require 'koholint/trace'

module Koholint
  module Viewer
    # One run as the cockpit's Direct view reads it: what the agent thought and aimed at, what it read, which skills it called and
    # where it went, each stamped with its frame so the page can show any frame of the run.
    module Story
      CACHE = {}
      CACHE_LOCK = Mutex.new
      MAX_RUNS = 6
      STUB = 'stub'.freeze
      MIN_THOUGHT = 12
      THOUGHT_CAP = 300

      module_function

      def for(run_dir)
        trace = Trace.located(File.join(run_dir, Atlas::TRACE))
        stamp = File.exist?(trace) ? [File.mtime(trace).to_f, File.size(trace)] : nil
        CACHE_LOCK.synchronize do
          found = CACHE.delete(run_dir)
          if found && found[:stamp] == stamp
            CACHE[run_dir] = found
            return found[:value]
          end
        end
        value = build(run_dir)
        CACHE_LOCK.synchronize do
          CACHE[run_dir] = { stamp:, value: }
          CACHE.shift while CACHE.size > MAX_RUNS
        end
        value
      end

      def build(run_dir)
        manifest = Summary.read_json(File.join(run_dir, 'manifest.json'))
        events = Trace.read(File.join(run_dir, Atlas::TRACE))
        fork = manifest.dig('parent', 'frame').to_i
        story = { run: File.basename(run_dir), flow: manifest['flow_version'], parent: manifest.dig('parent', 'id'), fork:, end: fork,
                  thoughts: [], objectives: [], skills: [], marks: [], trail: [], body: [], held: [] }
        titles = {}
        seen = {}
        current = nil
        events.each do |event|
          frame = event['frame'].to_i
          story[:end] = frame if frame > story[:end]
          case event['type']
          when 'perception'
            place = Summary.perceived_place(event)
            next unless place

            state = event['state']
            label = Atlas.label(place)
            body = [state['hp'], state['max_hp']]
            story[:body] << [frame, *body] if story[:body].last&.drop(1) != body
            next if label == current

            current = label
            story[:trail] << [frame, label]
            next if seen[label] || frame < fork

            seen[label] = true
            story[:marks] << [frame, 'place', label]
          when 'decision'
            next unless event['agent'] == 'claude'

            skill = event.dig('choice', 'skill')
            story[:skills] << [frame, skill] if skill
            text = Dialogues.clean(event['justification'], THOUGHT_CAP)
            story[:thoughts] << [frame, skill, text, current] if text.size >= MIN_THOUGHT && text != STUB
          when 'objective'
            titles[event['id']] ||= event['title'] || event.dig('predicate', 'kind')
            story[:objectives] << [frame, event['status'], titles[event['id']], event['autopilot'] ? true : false]
          when 'item_gained'
            story[:held] << [frame, Array(event['held'])]
            story[:marks] << [frame, 'item', event['item']] if frame >= fork
          when 'notable'
            story[:marks] << [frame, 'death', current] if event['kind'] == 'death' && frame >= fork
          end
        end
        story.merge(dialogues: merged(Dialogues.from_events(events)))
      end

      # A text the game types out over several reads is traced as successive pieces; each piece that continues the one before
      # in the same place is joined to it.
      def merged(dialogues)
        dialogues.each_with_object([]) do |talk, out|
          text = talk[:text].to_s
          place = talk[:place].is_a?(Array) ? Atlas.label(talk[:place]) : talk[:place]
          last = out.last
          if last && last[:place] == place
            before = Dialogues.compact(last[:text])
            now = Dialogues.compact(text)
            joined = if before.include?(now) then last[:text]
                     elsif now.start_with?(before) then text
                     else Dialogues.join(last[:text], text)
                     end
            next last[:text] = joined if joined
          end
          out << { frame: talk[:frame], place:, text:, speaker: talk[:speaker] }.compact
        end
      end
    end
  end
end
