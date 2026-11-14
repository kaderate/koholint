require 'json'
require 'koholint/lead_check'
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
    REFUTE_AT = 2
    NAVIGATION_REASONS = %w[loop stall unreachable resume].freeze
    PLACE_ID = /\A\[?\s*(\d+)\s*[-,\/ ]\s*(\d+)\s*\]?\z/

    attr_reader :all, :goal, :goal_frame, :goal_objectives, :names

    def self.from_events(events)
      leads = new
      done = 0
      started = {}
      events.each do |event|
        case Ledger.pick(event, :type).to_s
        when 'lead' then leads.restore(event)
        when 'dialogue' then leads.note_read(Ledger.pick(event, :text))
        when 'perception' then leads.note_held(Items.held_ids(Ledger.pick(event, :state) || {}))
        when 'place_name' then leads.name_place(Ledger.pick(event, :place), Ledger.pick(event, :name))
        when 'goal' then leads.change_goal(Ledger.pick(event, :text), frame: Ledger.pick(event, :frame), objectives: done)
        when 'objective'
          id = Ledger.pick(event, :id)
          started[id] = event if Ledger.pick(event, :status).to_s == 'started'
          next unless Objectives::TERMINAL.include?(Ledger.pick(event, :status).to_s)

          done += 1
          leads.note_objective(started.fetch(id, {}).merge(event))
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
      File.write("#{path}.tmp", "#{JSON.pretty_generate({ goal: leads.goal, leads: leads.with_status, places: PlaceCard.world(events, names: leads.names) })}\n")
      File.rename("#{path}.tmp", path)
    end

    def initialize
      @all = []
      @goal = nil
      @names = {}
      @attempts = {}
      @read = []
      @held = Set.new
    end

    def note_read(text) = (@read << text.to_s unless text.to_s.strip.empty?)

    def note_held(ids) = @held.merge(ids)

    # A finished objective that followed a lead (its because, or a lead candidate's target) is evidence about that lead.
    def note_objective(done)
      id = Ledger.pick(done, :id)
      target = Ledger.pick(done, :target) || {}
      lead = Ledger.pick(done, :because) || Ledger.pick(target, :lead)
      return if id.nil? || lead.nil? || @attempts.key?(id)

      @attempts[id] = { objective: id, lead:, title: Ledger.pick(done, :title), outcome: (Ledger.pick(done, :outcome) || Ledger.pick(done, :status)).to_s,
                        place: Ledger.pick(target, :place) || Ledger.pick(Ledger.pick(done, :predicate) || {}, :place),
                        frame: Ledger.pick(done, :ended_frame) || Ledger.pick(done, :frame), reason: Ledger.pick(done, :reason)&.to_s }.compact
    end

    # tested: an objective that followed the lead was achieved; refuted: REFUTE_AT of them failed, navigation and restarts not counted.
    def status(lead)
      tries = @attempts.values.select { |attempt| attempt[:lead] == lead[:id] }
      refuting = tries.count { |attempt| attempt[:outcome] == 'failed' || (attempt[:outcome] == 'abandoned' && !NAVIGATION_REASONS.include?(attempt[:reason])) }
      verdict = if tries.any? { |attempt| attempt[:outcome] == 'achieved' } then 'tested'
                elsif refuting >= REFUTE_AT then 'refuted'
                else 'open'
                end
      { status: verdict, evidence: tries }
    end

    def with_status = @all.map { |lead| lead.merge(status(lead)) }

    # A lead stays a candidate unless refuted or an achieved objective reached the place it points to.
    def settled?(lead)
      found = status(lead)
      found[:status] == 'refuted' || found[:evidence].any? { |attempt| attempt[:outcome] == 'achieved' && attempt[:place] && attempt[:place] == place_for(lead) }
    end

    def restore(event)
      lead = %w[id place source quote claim importance].to_h { |key| [key.to_sym, Ledger.pick(event, key)] }
      where = Ledger.pick(event, :where)
      lead[:where] = where if where
      contact = Ledger.pick(event, :contact)
      lead[:contact] = contact.transform_keys(&:to_sym) if contact.is_a?(Hash)
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

    # A lead naming an item no text of the run has named and Link never held is general knowledge of the game: dropped and returned as leaked.
    def absorb(raw, transcription:, place:, source:)
      haystacks = Array(transcription).map { |text| self.class.compact(text) }
      accepted = []
      leaked = []
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

        named = LeadCheck.named(claim:, where: lead['where'], texts: [*Array(transcription), *@read, *@all.map { |known| known[:quote] }], held: @held)
        if named.any?
          leaked << { quote: self.class.clean(quote), claim: self.class.clean(claim, CLAIM_MAX), items: named }
          next
        end

        added = { id: "lead-#{@all.size + 1}", place:, source:, quote: self.class.clean(quote), claim: self.class.clean(claim, CLAIM_MAX), importance: }
        where = self.class.clean(lead['where'], WHERE_MAX)
        added[:where] = where unless where.empty?
        @all << added
        accepted << added
      end
      [accepted, rejected, leaked]
    end

    # A text the game opened while Link pressed toward something: one lead per thing and text, a few per place.
    def contact(contact, text:, place:)
      quote = self.class.clean(text, QUOTE_MAX)
      thing = contact.slice(:object, :entity)
      key = self.class.compact(quote)
      return if self.class.normalize(quote).length < QUOTE_MIN || thing.empty?
      return if @all.count { |known| known[:contact] && known[:place] == place } >= LIMIT
      return if @all.any? do |known|
        (known[:place] == place || known[:contact]&.slice(:object, :entity) == thing) &&
          (key.include?(self.class.compact(known[:quote])) || self.class.compact(known[:quote]).include?(key))
      end

      what = contact[:entity] ? "person #{contact[:entity]}" : "object #{contact[:object]}"
      claim = "Contact with #{what} at (#{contact[:row]},#{contact[:col]}) opened this text"
      lead = { id: "lead-#{@all.size + 1}", place:, source: contact.slice(:row, :col, :entity), quote:, claim:, importance: 'normal', where: place.join('-'), contact: }
      @all << lead
      lead
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
