require 'zlib'
require 'koholint'
require 'koholint/emulator'

module Koholint
  class InputLog
    FORMAT_VERSION = 1
    BUTTONS = Emulator::BUTTONS

    attr_reader :frames

    def self.load(path) = new(path)

    def initialize(path)
      @path = path
      @runs = []
      @frames = 0
      read_existing if File.exist?(path)
    end

    def append(buttons)
      mask = buttons.sum { |button| 1 << BUTTONS.index(button) }
      if @runs.last && @runs.last[0] == mask
        @runs.last[1] += 1
      else
        @runs << [mask, 1]
      end
      @frames += 1
      nil
    end

    def flush
      packed = @runs.map { |mask, count| [mask, count].pack('CV') }.join
      File.binwrite(@path, [FORMAT_VERSION].pack('C') + Zlib::Deflate.deflate(packed))
    end

    def each_frame
      @runs.each do |mask, count|
        buttons = BUTTONS.each_index.select { |i| mask[i] == 1 }.map { |i| BUTTONS[i] }
        count.times { yield buttons }
      end
    end

    private

    def read_existing
      data = File.binread(@path)
      raise Error, "unsupported input log version #{data.getbyte(0).inspect}" unless data.getbyte(0) == FORMAT_VERSION

      Zlib::Inflate.inflate(data.byteslice(1..)).scan(/.{5}/m) do |entry|
        mask, count = entry.unpack('CV')
        @runs << [mask, count]
        @frames += count
      end
    end
  end
end
