module Koholint
  class Budget
    DEFAULT_CLOCK = ->(*) { Process.clock_gettime(Process::CLOCK_MONOTONIC) }

    def initialize(frames: nil, steps: nil, active_seconds: nil, dollars: nil, clock: DEFAULT_CLOCK, sleep_gap: 120)
      @limits = { frames: frames, steps: steps, time: active_seconds, dollars: dollars }
      @clock = clock
      @sleep_gap = sleep_gap
      @used = { frames: 0, steps: 0, time: 0.0, dollars: 0.0 }
      @last_tick = clock.call
      @stopped = nil
    end

    def unlimited? = @limits.values.all?(&:nil?)

    def tick(frames: 0, cost: 0.0)
      now = @clock.call
      delta = now - @last_tick
      @used[:time] += delta if delta <= @sleep_gap
      @last_tick = now
      @used[:frames] += frames
      @used[:dollars] += cost
      nil
    end

    def step_done = @used[:steps] += 1

    def stop!(reason = :stopped) = @stopped ||= reason

    def nearly_exhausted?(frames: 0, share: 0.0)
      return true if exhausted

      @limits.any? do |kind, limit|
        next false unless limit

        left = limit - @used[kind]
        left < limit * share || (kind == :frames && left < frames)
      end
    end

    def exhausted
      return @stopped if @stopped

      @limits.find { |kind, limit| limit && @used[kind] >= limit }&.first
    end
  end
end
