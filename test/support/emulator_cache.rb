require 'digest'
require 'fileutils'
require 'zlib'
require 'koholint'
require 'koholint/boot_script'
require 'koholint/emulator'
require 'koholint/perception'

module EmulatorCache
  BOOT_FRAME_LIMIT = 3000
  INTERACTIVE_FRAME_LIMIT = 3000
  TALK_PRESS_FRAMES = 3
  TALK_IDLE_FRAMES = 57
  FREE_PROBE_FRAMES = 40
  EXIT_HOLD_FRAMES = 40
  EXIT_SETTLE_FRAMES = 30

  class << self
    attr_writer :dir

    def dir = @dir || File.join(Koholint::Config::ROOT, 'tmp', 'emulator_cache')

    def at(frame, expect_hash: nil) = fetch(frame.to_s, expect_hash) { build(frame) }

    def playable(expect_hash: nil) = fetch('playable', expect_hash) { build(nil) }

    def interactive(expect_hash: nil) = fetch('interactive', expect_hash) { build_interactive }

    private

    def build_interactive
      emulator = playable
      start = emulator.frame
      until moves?(emulator, :right)
        raise Koholint::Error, 'dialogue chain never released Link' if emulator.frame - start > INTERACTIVE_FRAME_LIMIT

        TALK_PRESS_FRAMES.times { emulator.step([:a]) }
        TALK_IDLE_FRAMES.times { emulator.step }
      end
      EXIT_HOLD_FRAMES.times { emulator.step([:right]) }
      EXIT_SETTLE_FRAMES.times { emulator.step }
      raise Koholint::Error, 'Link still locked after leaving the bed' unless moves?(emulator, :down)

      emulator
    end

    def moves?(emulator, direction)
      moved = Koholint::Emulator.restore(emulator.dump)
      control = Koholint::Emulator.restore(emulator.dump)
      FREE_PROBE_FRAMES.times do
        moved.step([direction])
        control.step
      end
      Koholint::Perception.read(moved).to_h.values_at(:x, :y) != Koholint::Perception.read(control).to_h.values_at(:x, :y)
    end

    def fetch(name, expect_hash)
      cached = load(name)
      return cached if cached && (expect_hash.nil? || cached.state_hash == expect_hash)

      yield.tap { |emulator| store(name, emulator) }
    end

    def key_sources
      lib = %w[boot_script perception game_state].map { |f| File.read(File.join(Koholint::Config::ROOT, 'lib', 'koholint', "#{f}.rb")) }
      lib << File.read(__FILE__)
    end

    def key_for(sources) = Digest::SHA256.hexdigest(Digest::SHA256.file(Koholint.rom_path).hexdigest + sources.join)[0, 12]

    def key = key_for(key_sources)

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
