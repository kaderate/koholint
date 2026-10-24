require 'koholint/dialogues'
require 'koholint/ledger'
require 'koholint/vision/grid'

module Koholint
  class TalkLog
    MAX_ROWS = 2
    MAX_COLS = 2
    ATTEMPT_STOPS = %w[done no_response].freeze

    def self.attempt?(result)
      return false unless result.is_a?(Hash)

      Ledger.pick(result, :talked) == true || ATTEMPT_STOPS.include?(Ledger.pick(result, :stopped_by).to_s)
    end

    def self.from_events(events)
      log = new
      events.each do |event|
        next unless Ledger.pick(event, :type).to_s == 'action' && Ledger.pick(event, :skill).to_s == 'talk_to'

        result = Ledger.pick(event, :result)
        params = Ledger.pick(event, :params)
        place = result.is_a?(Hash) ? Ledger.place_of(Ledger.pick(result, :from)) : nil
        row = Ledger.pick(params, :row)
        col = Ledger.pick(params, :col)
        next unless place && row && col && attempt?(result)

        log.record(place:, row:, col:, talked: Ledger.pick(result, :talked) == true, standing: standing_of(result), entity: entity_of(result))
      end
      Dialogues.from_events(events).each do |dialogue|
        log.store_pages(dialogue[:conversation], dialogue[:pages]) if dialogue[:conversation] && !dialogue[:cached]
        source = dialogue[:source] or next
        log.remember(place: dialogue[:place], cell: [source[:row], source[:col]], text: dialogue[:text], stamp: dialogue[:stamp], entity: source[:entity],
                     conversation: dialogue[:conversation], speaker: dialogue[:speaker])
      end
      log
    end

    def self.entity_of(result)
      entity = Ledger.pick(result, :entity)
      entity.is_a?(Hash) ? Ledger.pick(entity, :type) : nil
    end

    def self.standing_of(result)
      tried = Ledger.pick(result, :standing_cells_tried)
      if tried.is_a?(Array)
        return tried.filter_map do |entry|
          cell = [Ledger.pick(entry, :row), Ledger.pick(entry, :col)]
          [cell, Ledger.pick(entry, :outcome).to_s == 'no_response'] if cell.all?
        end
      end
      standing = Ledger.pick(result, :standing_cell)
      cell = standing.is_a?(Hash) ? [Ledger.pick(standing, :row), Ledger.pick(standing, :col)] : nil
      cell&.all? ? [[cell, Ledger.pick(result, :stopped_by).to_s == 'no_response']] : []
    end

    def self.objects(grid)
      sprites = (0...Vision::Grid::ROWS).to_a.product((0...Vision::Grid::COLS).to_a).select { |row, col| grid.static_sprite(row, col) }
      seen = {}
      sprites.filter_map do |start|
        next if seen[start]

        cells = []
        queue = [start]
        seen[start] = true
        until queue.empty?
          cell = queue.shift
          cells << cell
          [[-1, 0], [1, 0], [0, -1], [0, 1]].each do |dr, dc|
            near = [cell[0] + dr, cell[1] + dc]
            next if seen[near] || !sprites.include?(near)

            seen[near] = true
            queue << near
          end
        end
        split(cells.sort)
      end.flatten(1).sort
    end

    def self.split(cells)
      left = cells.dup
      blocks = []
      until left.empty?
        row, col = left.first
        block = left.select { |r, c| r.between?(row, row + MAX_ROWS - 1) && c.between?(col, col + MAX_COLS - 1) }
        left -= block
        blocks << block
      end
      blocks
    end

    def initialize
      @attempts = Hash.new(0)
      @talked = Hash.new(0)
      @silent = Hash.new { |hash, key| hash[key] = [] }
      @texts = []
      @pages = {}
    end

    def remember(place:, cell:, text:, stamp:, entity: nil, conversation: nil, speaker: nil)
      key = Dialogues.key(text)
      return if key.empty? || !cell.all?(Integer)

      @texts << { place:, cell:, key:, stamp:, entity:, conversation:, speaker: }.compact
    end

    def store_pages(conversation, pages) = (@pages[conversation] ||= pages.dup.freeze)

    def pages_for(conversation) = @pages[conversation]

    def speaker_for(conversation) = @texts.reverse.find { |talk| talk[:conversation] == conversation && talk[:speaker] }&.dig(:speaker)

    def record(place:, row:, col:, talked:, standing: [], entity: nil)
      @attempts[[place, [row, col]]] += 1
      @talked[[place, [row, col]]] += 1 if talked
      if entity
        @attempts[[place, [:entity, entity]]] += 1
        @talked[[place, [:entity, entity]]] += 1 if talked
      end
      standing.each do |cell, silent|
        list = @silent[[place, [row, col]]]
        silent ? (list << cell unless list.include?(cell)) : list.delete(cell)
      end
    end

    def failed_sides(place, cell) = @silent.fetch([place, cell], []).dup

    def lines(grid, place, limit: nil, stamp: nil, entities: [])
      shown_entities = entities.select { |entity| entity[:cell] }.sort_by { |entity| [entity[:cell], entity[:slot]] }
      objects = self.class.objects(grid).reject { |cells| shown_entities.any? { |entity| cells.include?(entity[:cell]) } }
      stats = objects.to_h { |cells| [cells, [0, 0, []]] }
      talks = objects.to_h { |cells| [cells, []] }
      @texts.each do |talk|
        next unless talk[:place] == place && !talk[:entity]

        owner = owner_of(objects, talk[:cell]) or next
        talks[owner] << talk
      end
      @attempts.each do |(where, cell), tried|
        next unless where == place && cell[0] != :entity

        owner = owner_of(objects, cell) or next
        stats[owner][0] += tried
        stats[owner][1] += @talked[[where, cell]]
        stats[owner][2] |= @silent.fetch([where, cell], [])
      end
      things = shown_entities.map { |entity| [:entity, entity] } + objects.map { |cells| [:sprite, cells] }
      tried = ->((what, it)) { what == :entity ? @attempts[[place, [:entity, it[:type]]]] : stats[it][0] }
      shown = limit && things.size > limit ? things.partition { |thing| tried.(thing).positive? }.flatten(1).first(limit).sort_by { |what, it| [what == :entity ? 0 : 1, what == :entity ? it[:cell] : it] } : things
      out = shown.map do |what, it|
        next "- at #{label(it)}: #{[describe(*stats[it]), memory(talks[it], stamp)].compact.join('; ')}" if what == :sprite

        "- at #{label([it[:cell]])}: #{entity_label(place, it)}: #{[describe(*entity_stats(place, it)), memory(talks_with(place, it[:type]), stamp)].compact.join('; ')}"
      end
      out << "... #{things.size - shown.size} more objects" if shown.size < things.size
      out
    end

    def talks_with(place, type) = @texts.select { |talk| talk[:place] == place && talk[:entity] == type }

    def name_of(place, type) = talks_with(place, type).reverse.find { |talk| talk[:speaker] }&.dig(:speaker)

    def people(place, entities)
      entities.filter_map { |entity| (name = name_of(place, entity[:type])) && entity[:cell] && "#{name} (#{entity[:cell][0]},#{entity[:cell][1]})" }
    end

    def status(place:, entity:, stamp:) = assess(talks_with(place, entity), stamp)[:status]

    def last_status(place:, entity:)
      talks = talks_with(place, entity)
      talks.empty? ? :never : assess(talks, talks.last[:stamp])[:status]
    end

    def attempts(place, cells) = cells.sum { |cell| @attempts[[place, cell]] }

    def talked(place, cells) = cells.sum { |cell| @talked[[place, cell]] }

    def tried?(objects, place, cells) = @attempts.any? { |(where, cell), _| where == place && owner_of(objects, cell) == cells }

    private

    def owner_of(objects, cell)
      objects.find { |cells| cells.include?(cell) } ||
        objects.select { |cells| cells.any? { |r, c| (r - cell[0]).abs <= 1 && (c - cell[1]).abs <= 1 } }
               .min_by { |cells| cells.map { |r, c| (r - cell[0]).abs + (c - cell[1]).abs }.min }
    end

    def describe(tried, talked, silent = [])
      return 'never tried' if tried.zero?

      text = "talked to #{tried} #{tried == 1 ? 'time' : 'times'} (dialogue opened #{talked})"
      silent.empty? ? text : "#{text}; no response from #{silent.map { |r, c| "(#{r},#{c})" }.join(', ')}"
    end

    def assess(talks, stamp)
      return { status: :never } if talks.empty?

      keys = talks.map { |talk| talk[:key] }
      seen = talks.map { |talk| talk[:conversation] }
      fresh = keys.each_index.map { |i| !Dialogues.known?(keys[i], keys.first(i)) && !(seen[i] && seen.first(i).include?(seen[i])) }
      dry = fresh.reverse.take_while { |new| !new }.size
      changed = stamp && stamp != talks.last[:stamp]
      same = talks.size >= 2 && talks[-1][:stamp] == talks[-2][:stamp] &&
             ((!fresh.last && Dialogues.known?(keys[-1], [keys[-2]])) || (talks[-1][:conversation] && talks[-1][:conversation] == talks[-2][:conversation]))
      status = if changed then :changed
               elsif fresh.last then :new
               elsif same then :exhausted
               else :repeat
               end
      { status:, count: talks.size, fresh: fresh.last, dry: }
    end

    def memory(talks, stamp)
      return if talks.empty?

      found = assess(talks, stamp)
      text = "#{found[:count]} #{found[:count] == 1 ? 'text' : 'texts'} read, last talk #{found[:fresh] ? 'gave new text' : 'gave nothing new'}"
      text += " (#{found[:dry]} #{found[:dry] == 1 ? 'talk' : 'talks'} in a row with nothing new)" if found[:dry].positive?
      case found[:status]
      when :changed then "#{text}, worth retrying: yes (something changed since the last talk)"
      when :new then "#{text}, worth retrying: yes"
      when :exhausted then "#{text}, exhausted"
      else text
      end
    end

    def entity_stats(place, entity)
      key = [place, [:entity, entity[:type]]]
      [@attempts[key], @talked[key], @silent.fetch([place, entity[:cell]], [])]
    end

    def entity_label(place, entity)
      name = name_of(place, entity[:type])
      kind = entity[:kind].to_s == 'unknown' ? 'kind unknown' : entity[:kind].to_s
      "entity type #{entity[:type]} (#{kind}#{name ? ", name #{name}" : ''})"
    end

    def label(cells)
      return "(#{cells[0][0]},#{cells[0][1]})" if cells.size == 1

      rows = cells.map(&:first)
      cols = cells.map(&:last)
      "(#{rows.min},#{cols.min})-(#{rows.max},#{cols.max})"
    end
  end
end
