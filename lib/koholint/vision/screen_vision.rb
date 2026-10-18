require 'digest'
require 'koholint/addresses'
require 'koholint/vision/screen_snapshot'

module Koholint
  module Vision
    module ScreenVision
      LCDC = 0xFF40
      SCY = 0xFF42
      SCX = 0xFF43
      WY = 0xFF4A
      WX = 0xFF4B
      PLAYFIELD_LINES = 128
      SCREEN_RIGHT_WX = 167
      # Values and meaning: notes of game_mode and game_submode in data/addresses.json (one boot run, hypotheses).
      PLAY_MODE = 0x0B
      PLAY_SETTLED_SUBMODE = 7
      ADDRESSES = Addresses.load.slice(:game_mode, :game_submode, :dialog_state).freeze
      OAM = 0xFE00
      OAM_SPRITES = 40
      CELL_ROWS = 8
      CELL_COLS = 10
      MAP_SIZE = 32
      TILE_BYTES = 16
      DIGEST_CHARS = 8

      module_function

      # DMG mode only: no VBK bank or BG attribute map.
      def snapshot(reader, place:)
        lcdc = reader.read(LCDC)
        scx = reader.read(SCX)
        scy = reader.read(SCY)
        cells = Array.new(CELL_ROWS) { |row| Array.new(CELL_COLS) { |col| cell(reader, lcdc, scx, scy, row, col) } }
        ScreenSnapshot.new(reader.respond_to?(:frame) ? reader.frame : 0, place, [scx, scy], cells, sprites(reader, lcdc),
                           overlay?(reader, lcdc, scx, scy))
      end

      def overlay?(reader, lcdc, scx, scy)
        ram = ->(name) { reader.read(ADDRESSES.fetch(name)) }
        lcdc.nobits?(0x80) || lcdc.nobits?(0x01) ||
          # Mid-transition the tilemap holds parts of two rooms.
          (scx % 8).positive? || (scy % 8).positive? ||
          (lcdc.anybits?(0x20) && reader.read(WY) < PLAYFIELD_LINES && reader.read(WX) < SCREEN_RIGHT_WX) ||
          (ram.(:game_mode) == PLAY_MODE && ram.(:game_submode) != PLAY_SETTLED_SUBMODE) ||
          # Dialogue boxes are drawn into the BG tilemap itself, with no window register change.
          ram.(:dialog_state).positive?
      end

      def cell(reader, lcdc, scx, scy, row, col)
        base = lcdc.anybits?(0x08) ? 0x9C00 : 0x9800
        tiles = [[0, 0], [0, 1], [1, 0], [1, 1]].map do |dr, dc|
          map_row = ((scy >> 3) + (row * 2) + dr) % MAP_SIZE
          map_col = ((scx >> 3) + (col * 2) + dc) % MAP_SIZE
          reader.read(base + (map_row * MAP_SIZE) + map_col)
        end
        Cell.new(digest(tiles.flat_map { |number| tile_bytes(reader, lcdc, number) }), tiles)
      end

      def tile_bytes(reader, lcdc, number)
        addr = if lcdc.anybits?(0x10) then 0x8000 + (number * TILE_BYTES)
               else 0x9000 + (((number < 128) ? number : number - 256) * TILE_BYTES)
               end
        Array.new(TILE_BYTES) { |i| reader.read(addr + i) }
      end

      def sprites(reader, lcdc)
        Array.new(OAM_SPRITES) { |i| OAM + (i * 4) }.filter_map do |addr|
          y, x, tile, attr = Array.new(4) { |i| reader.read(addr + i) }
          # OAM entries parked off screen are hidden, not sprites.
          next if y.zero? || y >= 160 || x.zero? || x >= 168

          { x:, y:, tile:, attr:, pattern: digest(sprite_bytes(reader, lcdc, tile)) }
        end
      end

      def sprite_bytes(reader, lcdc, tile)
        numbers = lcdc.anybits?(0x04) ? [tile & 0xFE, tile | 1] : [tile]
        numbers.flat_map { |number| tile_bytes(reader, 0x10, number) }
      end

      def digest(bytes) = Digest::SHA256.hexdigest(bytes.pack('C*'))[0, DIGEST_CHARS]
    end
  end
end
