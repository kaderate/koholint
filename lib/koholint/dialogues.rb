require 'koholint/summary'

module Koholint
  module Dialogues
    OVERLAP_MIN = 6
    MOVES = %w[walk step goto talk_to].freeze

    module_function

    def compact(text) = text.to_s.gsub(/\s+/, '').downcase

    def stitch(pages)
      out = []
      kept = nil
      pages.each_with_index do |page, index|
        key = compact(page)
        next if key.empty? || (kept && compact(kept).include?(key))
        next if index + 1 < pages.size && compact(pages[index + 1]).include?(key)

        kept = page
        joined = out.last && join(out.last, page)
        joined ? out[-1] = joined : out << page
      end
      out
    end

    def text(pages) = stitch(pages).join("\n\n")

    def join(before, page)
      head = compact(page)
      starts = [0] + before.enum_for(:scan, /\s+/).map { Regexp.last_match.end(0) }
      starts.each do |start|
        tail = compact(before[start..])
        next if tail.size < OVERLAP_MIN || tail.size > head.size || !head.start_with?(tail)

        return before + page[cut(page, tail.size)..]
      end
      nil
    end

    def cut(page, count)
      seen = 0
      page.each_char.with_index do |char, index|
        return index if seen == count
        seen += 1 unless char.match?(/\s/)
      end
      page.size
    end

    def stamp(milestone:, places:, leads:) = [milestone.to_s, places, leads]

    def from_events(events)
      source = nil
      places = []
      milestone = nil
      leads = 0
      found = []
      events.each do |event|
        type = event['type']
        open = type == 'dialogue' && found.last&.dig(:open)
        found.last[:open] = false if found.last && !open
        case type
        when 'perception'
          place = Summary.perceived_place(event)
          places << place if place && !places.include?(place)
          milestone = event.dig('state', 'milestone')
        when 'lead' then leads += 1
        when 'action'
          next unless MOVES.include?(event['skill'].to_s)

          result = event['result']
          talked = event['skill'] == 'talk_to' && result.is_a?(Hash) && result['talked'] == true
          source = talked ? { row: event.dig('params', 'row'), col: event.dig('params', 'col') } : nil
        when 'dialogue'
          last = found.last
          if open && last[:frame] == event['frame'] && last[:place] == event['place']
            last[:pages] << event['text'].to_s
          else
            found << { frame: event['frame'], place: event['place'], source:, pages: [event['text'].to_s], open: true,
                       stamp: stamp(milestone:, places: places.size, leads:) }
          end
        end
      end
      found.map { |entry| entry.except(:open).merge(text: text(entry[:pages])) }
    end
  end
end
