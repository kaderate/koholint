require 'digest'
require 'fileutils'
require 'zlib'
require 'koholint'
require 'koholint/boot_script'
require 'koholint/emulator'

module EmulatorCache
  class << self
    attr_writer :dir

    def dir = @dir || File.join(Koholint::Config::ROOT, 'tmp', 'emulator_cache')

    def at(frame, expect_hash: nil)
      cached = load(frame)
      return cached if cached && (expect_hash.nil? || cached.state_hash == expect_hash)

      build(frame).tap { |emulator| store(frame, emulator) }
    end

    private

    def path(frame) = File.join(dir, "#{Digest::SHA256.file(Koholint.rom_path).hexdigest[0, 12]}-#{frame}.zlib")

    def load(frame)
      Koholint::Emulator.restore(Zlib::Inflate.inflate(File.binread(path(frame)))) if File.file?(path(frame))
    rescue Zlib::Error, TypeError, ArgumentError
      nil
    end

    def build(frame)
      Koholint::Emulator.boot.tap { |emulator| frame.times { |f| emulator.step(Koholint::BootScript.input_at(f)) } }
    end

    def store(frame, emulator)
      FileUtils.mkdir_p(dir)
      tmp = "#{path(frame)}.tmp"
      File.binwrite(tmp, Zlib::Deflate.deflate(emulator.dump))
      File.rename(tmp, path(frame))
    end
  end
end
