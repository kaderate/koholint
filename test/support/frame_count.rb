require 'koholint/emulator'

# Emulated frames of a test process: its own steps plus the history of every state the emulator cache hands it
module FrameCount
  @frames = 0
  @paused = 0
  @charged = {}

  class << self
    attr_reader :frames

    def add(count)
      @frames += count if @paused.zero?
    end

    def charge(key)
      @charged[key] ||= add(yield) || 0
    end

    def uncounted
      @paused += 1
      yield
    ensure
      @paused -= 1
    end
  end

  def step(...)
    FrameCount.add(1)
    super
  end
end

Koholint::Emulator.prepend(FrameCount)
at_exit { File.write(ENV['KOHOLINT_FRAMES_LOG'], "#{FrameCount.frames}\n", mode: 'a') if ENV['KOHOLINT_FRAMES_LOG'] }
