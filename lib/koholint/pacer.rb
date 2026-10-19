module Koholint
  class Pacer
    MAX_LAG = 1.0
    MONOTONIC = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }

    def initialize(fps: 60, clock: MONOTONIC, sleeper: Kernel.method(:sleep))
      @fps = fps.to_f
      @clock = clock
      @sleeper = sleeper
      @played = 0
    end

    def pace(frames)
      @played += frames
      @start ||= @clock.call
      now = @clock.call
      wait = @start + @played / @fps - now
      if wait < -MAX_LAG
        @start = now - (@played - frames) / @fps
        wait = frames / @fps
      end
      @sleeper.call(wait) if wait.positive?
    end
  end
end
