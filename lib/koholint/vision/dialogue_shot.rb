require 'koholint/png'

module Koholint
  module Vision
    module DialogueShot
      X = 0
      Y = 80
      WIDTH = 160
      HEIGHT = 48
      SCALE = 4
      SOURCE_WIDTH = 160

      def self.crop(emulator)
        rgb = emulator.frame_rgb
        rows = (Y...(Y + HEIGHT)).map do |y|
          row = rgb.byteslice((y * SOURCE_WIDTH + X) * 3, WIDTH * 3).unpack('a3' * WIDTH).map { |pixel| pixel * SCALE }.join
          row * SCALE
        end
        Png.encode(rgb: rows.join, width: WIDTH * SCALE, height: HEIGHT * SCALE)
      end
    end
  end
end
