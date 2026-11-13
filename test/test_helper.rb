$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'minitest/autorun'
require 'koholint'
require 'koholint/emulator'

module RomHelper
  def skip_without_rom!
    skip 'ROM not available' unless File.exist?(Koholint.rom_path)
  rescue Koholint::Error
    skip 'ROM not available'
  end
end

Minitest::Test.include(RomHelper)

module FrameCount
  @frames = 0
  class << self
    attr_accessor :frames
  end

  def step(...)
    FrameCount.frames += 1
    super
  end
end

Koholint::Emulator.prepend(FrameCount)
Minitest.after_run { File.write(ENV['KOHOLINT_FRAMES_LOG'], FrameCount.frames.to_s) if ENV['KOHOLINT_FRAMES_LOG'] }
