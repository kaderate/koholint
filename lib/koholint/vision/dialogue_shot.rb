require 'koholint/png'

module Koholint
  module Vision
    module DialogueShot
      BANDS = [0, 80].freeze
      WIDTH = 160
      BAND_HEIGHT = 48
      SCALE = 4

      def self.crop(emulator)
        rgb = emulator.frame_rgb
        rows = BANDS.flat_map { |top| (top...(top + BAND_HEIGHT)).map { |y| scaled_row(rgb, y) } }
        Png.encode(rgb: rows.join, width: WIDTH * SCALE, height: BANDS.size * BAND_HEIGHT * SCALE)
      end

      def self.scaled_row(rgb, y)
        row = rgb.byteslice(y * WIDTH * 3, WIDTH * 3).unpack('a3' * WIDTH).map { |pixel| pixel * SCALE }.join
        row * SCALE
      end
    end
  end
end
