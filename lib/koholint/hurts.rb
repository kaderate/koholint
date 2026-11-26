require 'koholint/entities'

module Koholint
  # Hostility learned from damage. The typed fact is the `hurts` entry of data/entities.json (hit, confidence, verified_count, source), written
  # offline from the census; a run adds the `hurt` notables of its own lineage: an hp drop with a thing not catalogued as an enemy or a person
  # nearest Link in the census window, its hit the drop. Either makes the type an enemy.
  class Hurts
    SOURCE = 'hp drop with it nearest Link in the census window'

    def self.from_events(events)
      hurts = new
      events.each do |event|
        next unless event['type'] == 'notable' && event['kind'] == 'hurt'

        detail = event['detail']
        hurts.add(type: detail['type'], hit: detail['hit'], place: detail['place'], frame: event['frame'])
      end
      hurts
    end

    def self.in_contact(state, entities)
      link = { x: state.x, y: state.y }
      Array(entities).select { |entity| Entities.creature?(entity) && entity[:x] && Entities.sprite_of?(link, entity) }
                     .min_by { |entity| [(entity[:x] - state.x).abs + (entity[:y] - state.y).abs, entity[:slot].to_i] }
    end

    attr_reader :facts

    def initialize
      @facts = {}
    end

    def add(type:, hit:, place:, frame:)
      hit = [hit, @facts.dig(type, :hit).to_i].max
      @facts[type] = { hit:, confidence: 'hypothesis', verified_count: 1, source: "#{SOURCE}: #{hit} hp at #{frame} in #{Array(place).join('-')}" }
    end

    def hit(type) = @facts.dig(type, :hit)

    # A type that hurt Link counts as an enemy: routes keep out of its reach, and it is no talk target.
    def overlay(entities)
      entities.map do |entity|
        hit = [hit(entity[:type]), entity[:hurts]].compact.max
        hit && Entities.creature?(entity) ? entity.merge(kind: :enemy, moves: true, hurt: hit) : entity
      end
    end
  end
end
