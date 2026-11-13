require 'digest'
require 'fileutils'
require 'tmpdir'
require 'zlib'
require 'koholint'
require 'koholint/boot_script'
require 'koholint/emulator'
require 'koholint/input_log'
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

    def dir = @dir || ENV['KOHOLINT_CACHE_DIR'] || File.join(shared_root, 'tmp', 'emulator_cache')

    def shared_root
      common = `git -C #{Koholint::Config::ROOT} rev-parse --git-common-dir 2>/dev/null`.strip
      common.empty? ? Koholint::Config::ROOT : File.dirname(File.expand_path(common, Koholint::Config::ROOT))
    end

    def at(frame, expect_hash: nil) = fetch("#{key}-#{frame}", expect_hash) { build(frame) }

    def playable(expect_hash: nil) = fetch("#{key}-playable", expect_hash) { build(nil) }

    def interactive(expect_hash: nil) = fetch("#{key}-interactive", expect_hash) { build_interactive }

    def replayed(run_dir, frame) = fetch("#{replay_key}-#{File.basename(run_dir)}-#{frame}", nil) { replay(run_dir, frame) }

    def recorded(name, into:, sources:)
      stem = "#{key_for(key_sources + recording_sources + sources.map { |f| File.read(f) })}-#{name}"
      stored = File.join(dir, stem)
      unless File.directory?(stored)
        FileUtils.mkdir_p(dir)
        File.open(lock_path(stem), File::RDWR | File::CREAT) do |lock|
          lock.flock(File::LOCK_EX)
          unless File.directory?(stored)
            root = Dir.mktmpdir('recording', dir)
            yield root
            File.rename(root, stored)
          end
        end
      end
      run_dir = Dir.children(stored).map { |child| File.join(stored, child) }.find { |child| File.directory?(child) }
      FileUtils.cp_r(run_dir, into)
      File.join(into, File.basename(run_dir))
    end

    private

    def build_interactive
      emulator = playable
      start = emulator.frame
      until !Koholint::Perception.read(emulator).dialog_open? && moves?(emulator, :right)
        raise Koholint::Error, 'dialogue chain never released Link' if emulator.frame - start > INTERACTIVE_FRAME_LIMIT

        TALK_PRESS_FRAMES.times { emulator.step([:a]) }
        TALK_IDLE_FRAMES.times { emulator.step }
      end
      EXIT_HOLD_FRAMES.times { emulator.step([:right]) }
      EXIT_SETTLE_FRAMES.times { emulator.step }
      raise Koholint::Error, 'Link still locked after leaving the bed' unless moves?(emulator, :down)

      emulator
    end

    def replay(run_dir, frame)
      emulator = nearest_replayed(run_dir, frame) || Koholint::Emulator.boot
      Koholint::InputLog.new(File.join(run_dir, 'inputs.log')).each_frame.with_index do |buttons, index|
        next if index < emulator.frame
        break if emulator.frame >= frame

        emulator.step(buttons)
      end
      emulator
    end

    def nearest_replayed(run_dir, frame)
      prefix = "#{replay_key}-#{File.basename(run_dir)}-"
      earlier = Dir[File.join(dir, "#{prefix}*.zlib")].map { |f| File.basename(f, '.zlib').delete_prefix(prefix) }
                                                      .grep(/\A\d+\z/).map(&:to_i).select { |f| f < frame }.max
      load("#{prefix}#{earlier}") if earlier
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

    def fetch(stem, expect_hash)
      usable = ->(cached) { cached && (expect_hash.nil? || cached.state_hash == expect_hash) }
      cached = load(stem)
      return cached if usable.call(cached)

      FileUtils.mkdir_p(dir)
      File.open(lock_path(stem), File::RDWR | File::CREAT) do |lock|
        lock.flock(File::LOCK_EX)
        cached = load(stem)
        return cached if usable.call(cached)

        yield.tap { |emulator| store(stem, emulator) }
      end
    end

    def lock_path(stem) = File.join(Dir.tmpdir, "koholint-emulator-cache-#{Digest::SHA256.hexdigest(File.join(dir, stem))[0, 16]}.lock")

    def key_sources
      lib = %w[boot_script perception game_state emulator].map { |f| File.read(File.join(Koholint::Config::ROOT, 'lib', 'koholint', "#{f}.rb")) }
      lib << File.read(__FILE__)
    end

    def recording_sources = Dir[File.join(Koholint::Config::ROOT, '{lib,data}', '**', '*.{rb,json}')].sort.map { |f| File.read(f) }

    def key_for(sources) = Digest::SHA256.hexdigest(Digest::SHA256.file(Koholint.rom_path).hexdigest + sources.join)[0, 12]

    def key = key_for(key_sources)

    def replay_key = key_for([File.read(File.join(Koholint::Config::ROOT, 'lib', 'koholint', 'emulator.rb')), File.read(__FILE__)])

    def path(stem) = File.join(dir, "#{stem}.zlib")

    def load(stem)
      Koholint::Emulator.restore(Zlib::Inflate.inflate(File.binread(path(stem)))) if File.file?(path(stem))
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

    def store(stem, emulator)
      tmp = "#{path(stem)}.#{Process.pid}.tmp"
      File.binwrite(tmp, Zlib::Deflate.deflate(emulator.dump))
      File.rename(tmp, path(stem))
    end
  end
end
