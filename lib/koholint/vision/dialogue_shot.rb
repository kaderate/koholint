require 'koholint/png'

module Koholint
  module Vision
    module DialogueShot
      BANDS = [0, 80].freeze
      WIDTH = 160
      BAND_HEIGHT = 48
      SCALE = 4

      PAGE_HEIGHT = BANDS.size * BAND_HEIGHT * SCALE

      def self.rgb(emulator)
        frame = emulator.frame_rgb
        BANDS.flat_map { |top| (top...(top + BAND_HEIGHT)).map { |y| scaled_row(frame, y) } }.join
      end

      def self.crop(emulator) = Png.encode(rgb: rgb(emulator), width: WIDTH * SCALE, height: PAGE_HEIGHT)

      def self.sheets(pages, per_sheet: 8)
        pages.each_slice(per_sheet).map { |group| Png.encode(rgb: group.join, width: WIDTH * SCALE, height: PAGE_HEIGHT * group.size) }
      end

      def self.scaled_row(rgb, y)
        row = rgb.byteslice(y * WIDTH * 3, WIDTH * 3).unpack('a3' * WIDTH).map { |pixel| pixel * SCALE }.join
        row * SCALE
      end
    end
  end
end
