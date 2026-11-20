require 'koholint/exits'
require 'koholint/ledger'

module Koholint
  # Identical results (same place, skill and stop) of at most one frame come back without the game moving; past LIMIT the
  # harness answers instead of the model. Its own answer keeps the count, so each further instant repeat costs one model call.
  # Explores that find no frontier and walk no cell count the same way over a visit of a place, until an explore walks, Link leaves,
  # an item or milestone changes, a lead or goal comes, or a skill other than a move runs longer than FEW frames.
  class ZeroWatch
    LIMIT = 3
    MARK = 'in at most one frame'
    IDLE_MARK = 'walking no cell'
    IDLE = %w[no_frontier stalled].freeze
    MOVES = %w[explore goto walk step wait].freeze
    FEW = 8

    attr_reader :key, :count

    def self.from_events(events)
      watch = new
      events.each do |event|
        case event['type']
        when 'lead', 'goal' then watch.news!
        when 'decision'
          watch.in_context(Exits.context(event['input'])) if event['input']
          justification = event['justification'].to_s
          watch.capping(event.dig('choice', 'skill')) if justification.include?(MARK) || justification.include?(IDLE_MARK)
        when 'action'
          result = event['result'].is_a?(Hash) ? event['result'] : {}
          watch.note(place: Ledger.place_of(result['from']), skill: event['skill'], stop: result['stopped_by'], frames: result['frames'],
                     cells: result['cells_walked'], to: Ledger.place_of(result['to']))
        end
      end
      watch
    end

    def initialize
      @key = @acting = @idle = nil
      @count = 0
      @fresh = @spent = @idle_fresh = false
    end

    def capping(skill) = @acting = skill.to_s

    def in_context(context)
      forget_idle if @context && context != @context
      @context = context
    end

    def news! = forget_idle

    def note(place:, skill:, stop:, frames:, cells: nil, to: nil)
      instant = !frames.nil? && frames.to_i <= 1
      idle = skill.to_s == 'explore' && IDLE.include?(stop.to_s) && (instant || (!cells.nil? && cells.to_i.zero?))
      note_idle(place, skill, idle && stop.to_s, to, harness: !@acting.nil?, worked: !MOVES.include?(skill.to_s) && frames.to_i > FEW)
      if @acting
        @spent ||= @acting == 'explore' && (instant || idle)
        @fresh = false
        @acting = nil
        return
      end
      key = [place, skill.to_s, stop.to_s]
      return (@key = nil) && (@count = 0) unless instant

      same = key == @key
      @count = same ? @count + 1 : 1
      @spent &&= same || idle
      @key = key
      @fresh = true
    end

    def due?(place) = instant_due?(place) || idle_due?(place)

    # What the harness answers for: the instant streak, else the idle explores of this visit.
    def streak
      return { skill: @key[1], stop: @key[2], count: @count, mark: MARK } if @key && instant_due?(@key.first)

      { skill: 'explore', stop: @idle[:stop], count: @idle[:count], mark: IDLE_MARK } if @idle
    end

    # A harness explore that came back instantly or idle too is not offered again for this streak.
    def explore? = !@spent

    private

    def instant_due?(place) = @fresh && @count >= LIMIT && @key&.first == place

    def idle_due?(place) = @idle_fresh && @idle && @idle[:count] >= LIMIT && @idle[:place] == place

    def note_idle(place, skill, idle, to, harness:, worked:)
      if idle
        @idle = { place:, stop: idle, count: @idle&.dig(:place) == place ? @idle[:count] + 1 : 1 }
        @idle_fresh = !harness
        return
      end
      @idle_fresh = false
      left = to && to != place
      return unless left || worked || skill.to_s == 'explore'

      @idle = nil
      @spent = false if left || worked
    end

    def forget_idle
      @idle = nil
      @idle_fresh = @spent = false
    end
  end
end
