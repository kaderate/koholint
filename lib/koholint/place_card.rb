require 'koholint/dialogues'
require 'koholint/geometry'
require 'koholint/items'
require 'koholint/talk_log'
require 'koholint/vision/grid'

module Koholint
  module PlaceCard
    SIDES = { up: ->(row, _col) { row.zero? }, down: ->(row, _col) { row == Vision::Grid::ROWS - 1 },
              left: ->(_row, col) { col.zero? }, right: ->(_row, col) { col == Vision::Grid::COLS - 1 } }.freeze

    module_function

    def build(place:, entities:, objects:, grid:)
      on_screen = entities.select { |entity| entity[:cell] }
      of = ->(kind) { on_screen.select { |entity| entity[:kind].to_s == kind } }
      { place:,
        people: of.('npc').map { |entity| { type: entity[:type], cell: entity[:cell], verified: entity[:verified] == true } },
        enemies: of.('enemy').map { |entity| entity.slice(:type, :cell) },
        unknown: of.('unknown').map { |entity| entity.slice(:type, :cell, :moves) },
        creatures: of.('creature').map { |entity| entity.slice(:type, :cell, :moves) },
        signs: objects.select { |object| object[:kind].to_s == 'sign' }.map { |object| { cell: object[:cell], object: object[:object], verified: object[:verified] == true } },
        objects: of.('object').map { |entity| { cell: entity[:cell], type: entity[:type] } } +
          objects.select { |object| object[:kind].to_s == 'object' }.map { |object| object.slice(:cell, :object) },
        doors: objects.select { |object| object[:kind].to_s == 'door' }.map { |object| { cell: object[:cell], object: object[:object], verified: object[:verified] == true } },
        chests: objects.select { |object| object[:kind].to_s == 'chest' }.map { |object| { cell: object[:cell], open: object[:open] == true } },
        exits: exits(grid) }
    end

    def exits(grid)
      return {} unless grid

      SIDES.filter_map do |side, border|
        cells = (0...Vision::Grid::ROWS).to_a.product((0...Vision::Grid::COLS).to_a).select do |row, col|
          border.(row, col) && !grid.static_sprite(row, col) && Geometry::DIRECTIONS.any? { |direction| grid.passable(row, col, direction) == :yes }
        end
        [side, cells] unless cells.empty?
      end.to_h
    end

    # Chests come back closed as the last card saw them, less those opened since; their reachability is checked again on arrival.
    # Uncatalogued things keep the items Link held when the card saw them.
    def latest(events)
      opened = events.select { |event| event['type'] == 'chest_opened' }
      held = nil
      events.each_with_object({}) do |event, cards|
        state = event['state'] if event['type'] == 'perception'
        held = Dialogues.items(state['inventory'], state['item_a'], state['item_b']) if state
        next unless event['type'] == 'place_card' && event['place'].is_a?(Array)

        later = opened.select { |open| open['place'] == event['place'] && open['frame'] >= event['frame'] }.map { |open| open['cell'] }
        chests = Array(event['chests']).reject { |chest| chest['open'] }.map { |chest| chest['cell'] } - later
        cards[event['place']] = { people: Array(event['people']).map { |person| { type: person['type'], cell: person['cell'] } },
                                  signs: Array(event['signs']).map { |sign| { cell: sign['cell'] } }, chests:,
                                  unknown: Array(event['unknown']).map { |thing| { type: thing['type'], cell: thing['cell'] } }, held: }
      end
    end

    # Every talk_to aimed at an entity type in a place: how many, how many opened a dialogue, and whether talk_to had to chase it; and every touch, how many picked something up.
    def tries(events)
      found = Hash.new { |hash, key| hash[key] = { tries: 0, answered: 0, moved: false } }
      events.each do |event|
        next unless event['type'] == 'action' && event['skill'] == 'talk_to' && event['result'].is_a?(Hash)

        result = event['result']
        from = result['from'] or next
        type = result['target_type'] || result.dig('entity', 'type') or next
        tried = found[[[from['room'], from['map']], type]]
        tried[:tries] += 1
        tried[:answered] += 1 if result['talked'] == true
        tried[:moved] ||= result['tracked'].to_i.positive?
      end
      touches(events).each do |touch|
        tried = found[[touch['place'], touch['type']]]
        tried[:touched] = tried[:touched].to_i + 1
        tried[:picked_up] = tried[:picked_up].to_i + (touch['picked_up'] ? 1 : 0)
      end
      found
    end

    SETTLE_CAP = 900
    AFTER_TOUCH = %w[advance_dialogue wait].freeze

    # Every touch that reached its cell, judged on the item bytes between arrival and the game settling. A touch a scene or a text
    # ended unsettled is judged on the first settled perception within SETTLE_CAP frames of arrival, before any skill other than
    # the harness's own dialogue advances and waits; with none, it is undecided and picks nothing up.
    def touches(events)
      events.each_with_index.filter_map do |event, index|
        result = event['result']
        next unless event['type'] == 'action' && event['skill'] == 'touch' && result.is_a?(Hash) && result['items_before'] && result['from']

        after = result['settled'] ? result['items_after'] : settled_items(events.drop(index + 1), result['arrival_frame'].to_i + SETTLE_CAP)
        { 'place' => result['from'].values_at('room', 'map'), 'type' => result['target_type'], 'frame' => event['frame'], 'cell' => event['params'].values_at('row', 'col'),
          'items_before' => result['items_before'], 'items_after' => after, 'picked_up' => !after.nil? && after != result['items_before'] }
      end
    end

    def settled_items(later, until_frame)
      later.each do |event|
        break if event['frame'].to_i > until_frame || (event['type'] == 'action' && !AFTER_TOUCH.include?(event['skill']))
        next unless event['type'] == 'perception'

        state = event['state'] || {}
        next unless state['dialog_state'].to_i.zero? && state['link_frozen'].to_i.zero? && state['game_mode'] == ItemWatch::PLAY_MODE

        return { 'held' => [state['item_a'], state['item_b'], *Array(state['inventory']).first(Items::SLOTS)].map(&:to_i).reject(&:zero?).uniq.sort, 'rupees' => state['rupees'].to_i }
      end
      nil
    end

    # The entity types a touch picked something up from, with each touch as provenance: observed from one place, verified from 2.
    def pickups(events)
      touches(events).select { |touch| touch['picked_up'] }.group_by { |touch| touch['type'] }.map do |type, seen|
        places = seen.map { |touch| touch['place'] }.uniq
        { 'type' => type, 'confidence' => places.size >= 2 ? 'verified' : 'observed', 'verified_count' => places.size,
          'touches' => seen.map { |touch| touch.slice('place', 'frame', 'cell', 'items_before', 'items_after') } }
      end
    end

    def world(events, names: {})
      log = TalkLog.from_events(events)
      cards = events.select { |event| event['type'] == 'place_card' }
      tries = tries(events)
      items = events.select { |event| event['type'] == 'item_gained' && event['place'] }.group_by { |event| event['place'] }
      cards.group_by { |event| event['place'] }.to_h do |place, seen|
        last = seen.last
        card = last.slice('people', 'enemies', 'creatures', 'unknown', 'signs', 'objects', 'doors', 'chests', 'exits')
        types = Array(card['unknown']).map { |entity| entity['type'] }.uniq
        card['unknown_types'] = types.map { |type| { 'type' => type, **tries[[place, type]].transform_keys(&:to_s) } } unless types.empty?
        card['items_gained'] = items[place].map { |event| event['name'] || event['item'] } if items[place]
        card['people'] = card['people'].map do |person|
          name = log.name_of(place, person['type'])
          person.merge(**(name ? { 'name' => name } : {}), 'status' => log.last_status(place:, entity: person['type']).to_s)
        end
        card['signs'] = card['signs'].map { |sign| sign.merge('status' => log.sign_status(place:, cell: sign['cell']).to_s) }
        name = names[place]
        [place.join('-'), { 'place' => place, **(name ? { 'name' => name } : {}), 'visits' => seen.size, 'first_frame' => seen.first['frame'], 'last_frame' => last['frame'], **card }]
      end
    end
  end
end
