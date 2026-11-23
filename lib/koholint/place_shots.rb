require 'fileutils'
require 'koholint'
require 'koholint/game_state'
require 'koholint/modes'

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

    def initialize(run_dir)
      @dir = File.join(run_dir, DIR)
      @captured = self.class.places(run_dir)
      @place = nil
      @since = nil
    end

    def due(state, frame: state.frame, settled: false)
      return nil unless state.room_id && state.map_id && state.phase(booted: true) == :playing && !state.dialog_open? &&
                    Modes.ready?(state)

      place = state.place
      return nil if @captured[place]

      unless place == @place
        @place = place
        @since = frame
      end
      place if settled || frame - @since >= SETTLE_FRAMES
    end

    def capture(emulator, state, settled: false)
      place = due(state, frame: emulator.frame, settled:)
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
