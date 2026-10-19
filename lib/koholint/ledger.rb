module Koholint
  class Ledger
    DOUBT_AT = 2

    def self.from_events(events)
      ledger = new
      events.each do |event|
        next unless Ledger.pick(event, :type).to_s == 'action'

        result = Ledger.pick(event, :result)
        next unless result.is_a?(Hash)

        from = Ledger.place_of(Ledger.pick(result, :from))
        to = Ledger.place_of(Ledger.pick(result, :to))
        ledger.reset_unless(from) if from
        blocked_at = Ledger.pick(result, :blocked_at)
        if from && blocked_at
          ledger.record(place: from, blocked_at:)
        end
        ledger.reset_unless(to) if to
      end
      ledger
    end

    def self.pick(hash, key)
      return nil unless hash.is_a?(Hash)

      hash.key?(key) ? hash[key] : hash[key.to_s]
    end

    def self.place_of(hash)
      room = pick(hash, :room)
      map = pick(hash, :map)
      room && map ? [room, map] : nil
    end

    def initialize(on_doubt: nil)
      @on_doubt = on_doubt
      @counts = Hash.new(0)
    end

    def record(place:, blocked_at:)
      row = Ledger.pick(blocked_at, :row)
      col = Ledger.pick(blocked_at, :col)
      direction = Ledger.pick(blocked_at, :direction)
      return unless row && col && direction.respond_to?(:to_sym)

      key = edge(place, [row, col], direction)
      @counts[key] += 1
      @on_doubt&.call(place:, cell: [row, col], direction: key.last, count: @counts[key]) if @counts[key] == DOUBT_AT
    end

    def entered(place:, cell:, direction:) = @counts.delete(edge(place, cell, direction))

    def count(place, cell, direction) = @counts[edge(place, cell, direction)]

    def doubtful?(place, cell, direction) = count(place, cell, direction) >= DOUBT_AT

    def reset_unless(place)
      @counts.select! { |key, _| key[0] == place }
    end

    private

    def edge(place, cell, direction) = [place, cell, direction.to_sym]
  end
end
