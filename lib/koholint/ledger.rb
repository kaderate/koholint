module Koholint
  class Ledger
    DOUBT_AT = 2

    def self.from_events(events)
      ledger = new
      events.each do |event|
        next unless (event[:type] || event['type']).to_s == 'action'

        result = pick(event, :result)
        next unless result.is_a?(Hash)

        blocked_at = pick(result, :blocked_at)
        from = pick(result, :from)
        next unless blocked_at && from

        place = [pick(from, :room), pick(from, :map)]
        ledger.reset_unless(place)
        ledger.record(place:, blocked_at:)
      end
      ledger
    end

    def self.pick(hash, key) = hash.key?(key) ? hash[key] : hash[key.to_s]
    private_class_method :pick

    def initialize
      @counts = Hash.new(0)
    end

    def record(place:, blocked_at:)
      @counts[edge(place, [pick(blocked_at, :row), pick(blocked_at, :col)], pick(blocked_at, :direction))] += 1
    end

    def entered(place:, cell:, direction:) = @counts.delete(edge(place, cell, direction))

    def count(place, cell, direction) = @counts[edge(place, cell, direction)]

    def doubtful?(place, cell, direction) = count(place, cell, direction) >= DOUBT_AT

    def reset_unless(place)
      @counts.select! { |key, _| key[0] == place }
    end

    private

    def edge(place, cell, direction) = [place, cell, direction.to_sym]

    def pick(hash, key) = self.class.send(:pick, hash, key)
  end
end
