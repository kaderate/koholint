require 'koholint/talk_log'
require 'koholint/vision/grid'

module Koholint
  module PlaceCard
    SIDES = { up: ->(row, _col) { row.zero? }, down: ->(row, _col) { row == Vision::Grid::ROWS - 1 },
              left: ->(_row, col) { col.zero? }, right: ->(_row, col) { col == Vision::Grid::COLS - 1 } }.freeze
    DIRECTIONS = %i[up down left right].freeze

    module_function

    def build(place:, entities:, objects:, grid:)
      on_screen = entities.select { |entity| entity[:cell] }
      of = ->(kind) { on_screen.select { |entity| entity[:kind].to_s == kind } }
      { place:,
        people: of.('npc').map { |entity| { type: entity[:type], cell: entity[:cell], verified: entity[:verified] == true } },
        enemies: of.('enemy').map { |entity| entity.slice(:type, :cell) },
        unknown: of.('unknown').map { |entity| entity.slice(:type, :cell, :moves) },
        signs: objects.select { |object| object[:kind].to_s == 'sign' }.map { |object| { cell: object[:cell], object: object[:object], verified: object[:verified] == true } },
        objects: of.('object').map { |entity| { cell: entity[:cell], type: entity[:type] } } +
          objects.select { |object| object[:kind].to_s == 'object' }.map { |object| object.slice(:cell, :object) },
        doors: objects.select { |object| object[:kind].to_s == 'door' }.map { |object| { cell: object[:cell], object: object[:object], verified: object[:verified] == true } },
        exits: exits(grid) }
    end

    def exits(grid)
      return {} unless grid

      SIDES.filter_map do |side, border|
        cells = (0...Vision::Grid::ROWS).to_a.product((0...Vision::Grid::COLS).to_a).select do |row, col|
          border.(row, col) && !grid.static_sprite(row, col) && DIRECTIONS.any? { |direction| grid.passable(row, col, direction) == :yes }
        end
        [side, cells] unless cells.empty?
      end.to_h
    end

    def world(events)
      log = TalkLog.from_events(events)
      cards = events.select { |event| event['type'] == 'place_card' }
      cards.group_by { |event| event['place'] }.to_h do |place, seen|
        last = seen.last
        card = last.slice('people', 'enemies', 'unknown', 'signs', 'objects', 'doors', 'exits')
        card['people'] = card['people'].map do |person|
          name = log.name_of(place, person['type'])
          person.merge(**(name ? { 'name' => name } : {}), 'status' => log.last_status(place:, entity: person['type']).to_s)
        end
        card['signs'] = card['signs'].map { |sign| sign.merge('status' => log.sign_status(place:, cell: sign['cell']).to_s) }
        [place.join('-'), { 'place' => place, 'visits' => seen.size, 'first_frame' => seen.first['frame'], 'last_frame' => last['frame'], **card }]
      end
    end
  end
end
