require 'digest'
require 'fileutils'
require 'zlib'
require 'koholint'
require 'koholint/boot_script'
require 'koholint/emulator'
require 'koholint/perception'

module EmulatorCache
  BOOT_FRAME_LIMIT = 3000

  class << self
    attr_writer :dir

    def dir = @dir || File.join(Koholint::Config::ROOT, 'tmp', 'emulator_cache')

    def at(frame, expect_hash: nil) = fetch(frame.to_s, expect_hash) { build(frame) }

    def playable(expect_hash: nil) = fetch('playable', expect_hash) { build(nil) }

    private

    def fetch(name, expect_hash)
      cached = load(name)
      return cached if cached && (expect_hash.nil? || cached.state_hash == expect_hash)

      yield.tap { |emulator| store(name, emulator) }
    end

    def key
      sources = %w[boot_script perception game_state].map { |f| File.read(File.join(Koholint::Config::ROOT, 'lib', 'koholint', "#{f}.rb")) }
      Digest::SHA256.hexdigest(Digest::SHA256.file(Koholint.rom_path).hexdigest + sources.join)[0, 12]
    end

    def path(name) = File.join(dir, "#{key}-#{name}.zlib")

    def load(name)
      Koholint::Emulator.restore(Zlib::Inflate.inflate(File.binread(path(name)))) if File.file?(path(name))
    rescue Zlib::Error, TypeError, ArgumentError
      nil
    end

    def build(frame)
      emulator = Koholint::Emulator.boot
      loop do
        state = Koholint::Perception.read(emulator)
        break if frame ? emulator.frame >= frame : state.controllable?
        raise Koholint::Error, 'boot sequence never became controllable' if emulator.frame > BOOT_FRAME_LIMIT

        macro = Koholint::BootScript.macro_for(state)
        count = frame ? [macro[:frames], frame - emulator.frame].min : macro[:frames]
        count.times { emulator.step(macro[:buttons]) }
      end
      emulator
    end

    def store(name, emulator)
      FileUtils.mkdir_p(dir)
      tmp = "#{path(name)}.tmp"
      File.binwrite(tmp, Zlib::Deflate.deflate(emulator.dump))
      File.rename(tmp, path(name))
    end
  end
end
