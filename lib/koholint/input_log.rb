require 'zlib'
require 'koholint'
require 'koholint/emulator'

module Koholint
  class InputLog
    FORMAT_VERSION = 2
    LEGACY_VERSION = 1
    ENTRY_SIZE = 5
    BUTTONS = Emulator::BUTTONS

    attr_reader :frames

    def self.load(path) = new(path)

    def self.read_from(path, offset)
      data = File.open(path, 'rb') { |file| file.seek(offset) && file.read } || ''
      count = data.bytesize / ENTRY_SIZE
      entries = Array.new(count) { |i| data.byteslice(i * ENTRY_SIZE, ENTRY_SIZE).unpack('CV') }
      [entries, offset + count * ENTRY_SIZE]
    end

    def initialize(path)
      @path = path
      @runs = []
      @frames = 0
      @pending = []
      @disk_entries = 0
      @rewrite = true
      read_existing if File.exist?(path)
    end

    def append(buttons)
      mask = buttons.sum { |button| 1 << BUTTONS.index(button) }
      extend_run(@runs, mask)
      extend_run(@pending, mask)
      @frames += 1
      nil
    end

    def flush
      if @rewrite
        tmp = "#{@path}.tmp"
        File.open(tmp, 'wb') do |file|
          file.write([FORMAT_VERSION].pack('C') + pack(@runs))
          file.fsync
        end
        File.rename(tmp, @path)
        sync_directory
        @disk_entries = @runs.size
        @rewrite = false
      elsif @pending.any?
        File.open(@path, 'r+b') do |file|
          file.truncate(1 + @disk_entries * ENTRY_SIZE)
          file.seek(0, IO::SEEK_END)
          file.write(pack(@pending))
          file.fsync
        end
        @disk_entries += @pending.size
      end
      @pending.clear
      nil
    end

    def each_frame
      return to_enum(:each_frame) unless block_given?

      @runs.each do |mask, count|
        buttons = BUTTONS.each_index.select { |i| mask[i] == 1 }.map { |i| BUTTONS[i] }
        count.times { yield buttons }
      end
    end

    private

    def extend_run(runs, mask)
      if runs.last && runs.last[0] == mask
        runs.last[1] += 1
      else
        runs << [mask, 1]
      end
    end

    def sync_directory
      File.open(File.dirname(@path)) { |dir| dir.fsync }
    rescue SystemCallError, IOError
      nil
    end

    def pack(runs) = runs.map { |mask, count| [mask, count].pack('CV') }.join

    def read_existing
      data = File.binread(@path)
      case data.getbyte(0)
      when FORMAT_VERSION then load_entries(data.byteslice(1..), disk: true)
      when LEGACY_VERSION then load_entries(inflate(data.byteslice(1..)), disk: false)
      else raise Error, "unsupported input log version #{data.getbyte(0).inspect}"
      end
    end

    def inflate(compressed)
      Zlib::Inflate.inflate(compressed)
    rescue Zlib::Error
      raise Error, "input log #{@path} is corrupt"
    end

    def load_entries(raw, disk:)
      entries = raw.scan(/.{5}/m).map { |entry| entry.unpack('CV') }
      entries.each do |mask, count|
        if @runs.last && @runs.last[0] == mask
          @runs.last[1] += count
        else
          @runs << [mask, count]
        end
        @frames += count
      end
      return unless disk

      @rewrite = false
      @disk_entries = entries.size
    end
  end
end
