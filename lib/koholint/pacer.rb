module Koholint
  class Pacer
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
      wait = @start + @played / @fps - @clock.call
      @sleeper.call(wait) if wait.positive?
    end
  end
end
