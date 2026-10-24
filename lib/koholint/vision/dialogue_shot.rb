require 'digest'
require 'koholint/png'

module Koholint
  module Vision
    module DialogueShot
      BANDS = [0, 80].freeze
      WIDTH = 160
      BAND_HEIGHT = 48
      SCALE = 4
      # Text columns inside the box; the blinking next-page arrow sits at x 143..150 and is left out.
      TEXT_COLUMNS = (12...143)
      BOX_SHARE = 0.9
      BOX_ROWS = 8
      HASH_CHARS = 16

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

      def self.text_rows(page)
        rows = (0...(BANDS.size * BAND_HEIGHT)).map do |y|
          page.byteslice(y * SCALE * WIDTH * SCALE * 3, WIDTH * SCALE * 3).unpack('a3' * WIDTH * SCALE).each_slice(SCALE).map(&:first)
        end
        darkest = rows.flatten.uniq.min_by { |pixel| pixel.unpack('C3').sum }
        bands = rows.each_slice(BAND_HEIGHT).map { |band| band.map { |row| TEXT_COLUMNS.map { |x| row[x] == darkest ? '0' : '1' }.join } }
        boxes = bands.map { |band| band.each_index.select { |i| band[i].count('0') >= TEXT_COLUMNS.size * BOX_SHARE } }
        chosen = bands.each_index.select { |i| boxes[i].size >= BOX_ROWS }.max_by { |i| boxes[i].size }
        return [] unless chosen

        bands[chosen][boxes[chosen].min..boxes[chosen].max].select { |row| row.include?('1') }
      end

      def self.page_hash(page) = Digest::SHA256.hexdigest(text_rows(page).join("\n"))[0, HASH_CHARS]

      # Pages are captured mid-typing at a phase that varies; a typed row only grows, so its partial forms are dropped.
      def self.signature(pages_rows)
        rows = pages_rows.flatten.uniq
        return nil if rows.empty?

        full = rows.reject { |row| (head = row.sub(/0+\z/, '')) && rows.any? { |other| other != row && other.start_with?(head) } }
        Digest::SHA256.hexdigest(full.sort.join("\n"))[0, HASH_CHARS]
      end
    end
  end
end
