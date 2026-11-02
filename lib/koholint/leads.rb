require 'json'
require 'koholint/ledger'
require 'koholint/objectives'
require 'koholint/place_card'
require 'koholint/trace'

module Koholint
  class Leads
    IMPORTANCE = %w[high normal low tip].freeze
    LIMIT = 5
    CLAIM_MAX = 160
    QUOTE_MIN = 8
    QUOTE_MAX = 300
    GOAL_MAX = 120
    WHERE_MAX = 40
    NAME_MAX = 40
    PLACE_ID = /\A\[?\s*(\d+)\s*[-,\/ ]\s*(\d+)\s*\]?\z/

    attr_reader :all, :goal, :goal_frame, :goal_objectives, :names

    def self.from_events(events)
      leads = new
      done = 0
      events.each do |event|
        case Ledger.pick(event, :type).to_s
        when 'lead' then leads.restore(event)
        when 'place_name' then leads.name_place(Ledger.pick(event, :place), Ledger.pick(event, :name))
        when 'goal' then leads.change_goal(Ledger.pick(event, :text), frame: Ledger.pick(event, :frame), objectives: done)
        when 'objective' then done += 1 if Objectives::TERMINAL.include?(Ledger.pick(event, :status).to_s)
        end
      end
      leads
    end

    def self.normalize(text) = text.to_s.gsub(/\s+/, ' ').strip.downcase

    def self.compact(text) = text.to_s.gsub(/\s+/, '').downcase

    def self.clean(text, cap = nil) = text.to_s.gsub(/[[:cntrl:]]/, ' ').gsub(/\s+/, ' ').strip.then { |t| cap ? t[0, cap] : t }

    def self.write_world(dir)
      events = Trace.read(File.join(dir, 'trace.jsonl'))
      leads = from_events(events)
      path = File.join(dir, 'world.json')
      File.write("#{path}.tmp", "#{JSON.pretty_generate({ goal: leads.goal, leads: leads.all, places: PlaceCard.world(events, names: leads.names) })}\n")
      File.rename("#{path}.tmp", path)
    end

    def initialize
      @all = []
      @goal = nil
      @names = {}
    end

    def restore(event)
      lead = %w[id place source quote claim importance].to_h { |key| [key.to_sym, Ledger.pick(event, key)] }
      where = Ledger.pick(event, :where)
      lead[:where] = where if where
      @all << lead unless known?(lead[:id])
    end

    def name_place(place, name)
      name = self.class.clean(name, NAME_MAX)
      return unless place.is_a?(Array) && place.size == 2 && place.all?(Integer) && !name.empty? && @names[place] != name

      @names[place] = name
    end

    def name_of(place) = @names[place]

    def place_for(lead)
      where = lead[:where].to_s.strip
      return if where.empty?

      found = where.match(PLACE_ID)
      return [found[1].to_i, found[2].to_i] if found

      @names.find { |_, name| self.class.normalize(name) == self.class.normalize(where) }&.first
    end

    def absorb(raw, transcription:, place:, source:)
      haystacks = Array(transcription).map { |text| self.class.compact(text) }
      accepted = []
      rejected = 0
      (raw.is_a?(Array) ? raw.first(LIMIT) : []).each do |entry|
        lead = entry.is_a?(Hash) ? entry.transform_keys(&:to_s) : {}
        quote, claim, importance = lead.values_at('quote', 'claim', 'importance')
        key = self.class.compact(quote)
        unless quote.is_a?(String) && claim.is_a?(String) && IMPORTANCE.include?(importance) && self.class.normalize(quote).length.between?(QUOTE_MIN, QUOTE_MAX) &&
               haystacks.any? { |haystack| haystack.include?(key) } && !self.class.clean(claim).empty?
          rejected += 1
          next
        end
        next if @all.any? { |known| self.class.compact(known[:quote]) == key }

        added = { id: "lead-#{@all.size + 1}", place:, source:, quote: self.class.clean(quote), claim: self.class.clean(claim, CLAIM_MAX), importance: }
        where = self.class.clean(lead['where'], WHERE_MAX)
        added[:where] = where unless where.empty?
        @all << added
        accepted << added
      end
      [accepted, rejected]
    end

    def change_goal(text, frame: nil, objectives: nil)
      goal = text.is_a?(String) ? self.class.clean(text, GOAL_MAX) : ''
      return if goal.empty? || goal == @goal

      @goal_frame = frame
      @goal_objectives = objectives
      @goal = goal
    end

    def known?(id) = @all.any? { |lead| lead[:id] == id }
  end
end
