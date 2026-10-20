require 'json'
require 'koholint/ledger'
require 'koholint/objectives'
require 'koholint/trace'

module Koholint
  class Leads
    IMPORTANCE = %w[high normal low].freeze
    LIMIT = 5
    CLAIM_MAX = 160
    QUOTE_MIN = 8
    QUOTE_MAX = 300
    GOAL_MAX = 120

    attr_reader :all, :goal, :goal_frame, :goal_objectives

    def self.from_events(events)
      leads = new
      done = 0
      events.each do |event|
        case Ledger.pick(event, :type).to_s
        when 'lead' then leads.restore(event)
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
      leads = from_events(Trace.read(File.join(dir, 'trace.jsonl')))
      path = File.join(dir, 'world.json')
      File.write("#{path}.tmp", "#{JSON.pretty_generate({ goal: leads.goal, leads: leads.all })}\n")
      File.rename("#{path}.tmp", path)
    end

    def initialize
      @all = []
      @goal = nil
    end

    def restore(event)
      lead = %w[id place source quote claim importance].to_h { |key| [key.to_sym, Ledger.pick(event, key)] }
      @all << lead unless known?(lead[:id])
    end

    def absorb(raw, transcription:, place:, source:)
      haystack = self.class.compact(transcription)
      accepted = []
      rejected = 0
      (raw.is_a?(Array) ? raw.first(LIMIT) : []).each do |entry|
        lead = entry.is_a?(Hash) ? entry.transform_keys(&:to_s) : {}
        quote, claim, importance = lead.values_at('quote', 'claim', 'importance')
        key = self.class.compact(quote)
        unless quote.is_a?(String) && claim.is_a?(String) && IMPORTANCE.include?(importance) && self.class.normalize(quote).length.between?(QUOTE_MIN, QUOTE_MAX) &&
               haystack.include?(key) && !self.class.clean(claim).empty?
          rejected += 1
          next
        end
        next if @all.any? { |known| self.class.compact(known[:quote]) == key }

        added = { id: "lead-#{@all.size + 1}", place:, source:, quote: self.class.clean(quote), claim: self.class.clean(claim, CLAIM_MAX), importance: }
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
