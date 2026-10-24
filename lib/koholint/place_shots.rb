require 'fileutils'
require 'json'
require 'koholint'
require 'koholint/game_state'
require 'koholint/emulator'
require 'koholint/input_log'
require 'koholint/modes'
require 'koholint/run'
require 'koholint/trace'

module Koholint
  class PlaceShots
    DIR = 'screens'.freeze
    SETTLE_FRAMES = 20
    NAME = /\A(\d{1,3})-(\d{1,3})\.png\z/

    def self.name(place) = "#{place[0]}-#{place[1]}.png"

    def self.names(run_dir)
      dir = File.join(run_dir, DIR)
      File.directory?(dir) ? Dir.children(dir).grep(NAME) : []
    end

    def self.places(run_dir) = names(run_dir).to_h { |file| [file.match(NAME).captures.map(&:to_i), true] }

    def self.backfill(dir, out: $stdout)
      manifest = JSON.parse(File.read(File.join(dir, 'manifest.json')))
      raise Error, "run #{File.basename(dir)} was recorded with another ROM" if manifest['rom_sha256'] != Run.rom_hash(Koholint.rom_path)

      shots = new(dir)
      targets = []
      Trace.read(File.join(dir, 'trace.jsonl')).each do |event|
        next unless event['type'] == 'perception' && event['state'].is_a?(Hash)

        state = GameState.new(**event['state'].slice(*GameState.members.map(&:to_s)).transform_keys(&:to_sym))
        place = shots.due(state, frame: event['frame'])
        next unless place

        shots.skip(place)
        targets << [event['frame'], place]
      end
      return 0 if targets.empty?

      emulator = Emulator.boot
      frames = InputLog.new(File.join(dir, 'inputs.log')).each_frame
      targets.each do |frame, place|
        while emulator.frame < frame
          emulator.step(frames.next)
        end
        shots.write(emulator, place)
      end
      out.puts "#{targets.size} screens written to #{File.join(dir, DIR)}"
      targets.size
    end

    def initialize(run_dir)
      @dir = File.join(run_dir, DIR)
      @captured = self.class.places(run_dir)
      @place = nil
      @since = nil
    end

    def due(state, frame: state.frame)
      return nil unless state.room_id && state.map_id && state.phase(booted: true) == :playing && !state.dialog_open? &&
                    Modes.ready?(state)

      place = [state.room_id, state.map_id]
      return nil if @captured[place]

      unless place == @place
        @place = place
        @since = frame
      end
      place if frame - @since >= SETTLE_FRAMES
    end

    def skip(place) = @captured[place] = true

    def capture(emulator, state)
      place = due(state, frame: emulator.frame)
      write(emulator, place) if place
    end

    def write(emulator, place)
      FileUtils.mkdir_p(@dir)
      path = File.join(@dir, self.class.name(place))
      File.binwrite("#{path}.tmp", emulator.frame_png)
      File.rename("#{path}.tmp", path)
      @captured[place] = true
    rescue StandardError => e
      @captured[place] = true
      warn "koholint: screenshot #{self.class.name(place)} not written: #{e.message}"
    end
  end
end
