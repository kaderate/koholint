require 'fileutils'
require 'zlib'
require 'koholint/emulator'

module Koholint
  class Keyframes
    def initialize(dir)
      @dir = dir
      FileUtils.mkdir_p(dir)
    end

    def save(emulator)
      path = File.join(@dir, format('kf-%09d.zlib', emulator.frame))
      File.binwrite(path, Zlib::Deflate.deflate(emulator.dump))
      path
    end

    def nearest_at_or_before(frame)
      frames = Dir.children(@dir).filter_map { |name| name[/\Akf-(\d+)\.zlib\z/, 1]&.to_i }
      best = frames.select { |f| f <= frame }.max
      best && [best, File.join(@dir, format('kf-%09d.zlib', best))]
    end

    def self.load(path) = Emulator.restore(Zlib::Inflate.inflate(File.binread(path)))
  end
end
