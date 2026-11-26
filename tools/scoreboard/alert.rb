require 'date'
require_relative 'runs'

module Scoreboard
  # The guardrails. `reasons` is empty when none trips.
  module Alert
    DAILY_USD = 20.0
    RISE = 1.5
    GROWTH = 1.2

    module_function

    # history: the scoreboard's lines, oldest first, each with the primary run's per-1000-frame rates, its progress vector and the branch count.
    def reasons(rows:, history:, day: Date.today)
      paid = Runs.measured(Runs.on_day(rows, day)).select { |result| result[:cost][:usd].positive? }
      today = paid.sum { |result| result[:cost][:usd] }
      found = []
      found << format('daily spend %.2f USD is above %.0f USD', today, DAILY_USD) if today > DAILY_USD
      dirty = paid.select { |result| result[:harness_dirty] }.map { |result| result[:run] }
      found << "harness_dirty on #{dirty.join(', ')}" unless dirty.empty?
      *, before, latest = history
      if latest && before
        found.concat(rose('deaths_per_1000f', before, latest), rose('calls_per_1000f', before, latest))
      end
      found.concat(piled(history))
      found
    end

    def rose(key, before, latest)
      was = before['primary'][key]
      now = latest['primary'][key]
      return [] unless was && now && now > was * RISE && now > was

      [format('%s rose from %.2f to %.2f (+%.0f%%) between the last two scoreboard runs', key, was, now, 100.0 * (now / was - 1))]
    end

    # Branch conditions up 20% over the last two batches while no component of the progress vector moved.
    def piled(history)
      return [] if history.size < 3

      base, *later = history.last(3)
      grown = base['branches'].to_f.positive? && later.last['branches'].to_f >= base['branches'] * GROWTH
      return [] unless grown && !later.any? { |entry| gained?(base['primary']['progress'], entry['primary']['progress']) }

      [format('branch conditions grew from %d to %d over 2 batches with no gain in the progress vector', base['branches'], later.last['branches'])]
    end

    def gained?(was, now)
      %w[instruments dungeons places_seen].any? { |key| now[key].to_i > was[key].to_i } ||
        now['key_items'].to_a.size > was['key_items'].to_a.size ||
        ranked(now['highest_milestone']) > ranked(was['highest_milestone'])
    end

    def ranked(milestone) = %w[none shield sword].index(milestone.to_s) || 0
  end
end
