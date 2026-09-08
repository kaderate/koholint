# frozen_string_literal: true

module Koholint
  # D8: terrain/collision read from the BG tilemap (VRAM), not live-probed -- see DECISIONS.md.
  # A cell's walkability is a categorical property of its 2x2 BG tile-ID block ("signature"), but
  # that partition is per-room (different tilesets reuse the same numeric IDs for different
  # things), so there's no fixed global table. RoomClassifier learns it on the fly: the first time
  # a signature is seen, the caller supplies how to learn its verdict (Link's own cell is a free
  # walkable sample; anything else falls back to one Navigator probe) -- bounded by the number of
  # distinct signatures in the room (2-9 measured so far), not by cell count.
  class Terrain
    def self.bg_tile_map_addr(mmu) = mmu.read(0xFF40).anybits?(0x08) ? 0x9C00 : 0x9800

    # world (row,col) -> the 2x2 block of BG tile IDs at tilemap rows/cols (2*row, 2*col).
    # Wraps mod 32 (tilemap is a 32x32 wraparound canvas) -- untested far from where SCX/SCY were
    # confirmed 0 (see data/ram_registry.json's terrain_collision entry).
    def self.signature_at(mmu, row, col)
      base = bg_tile_map_addr(mmu)
      tile_row, tile_col = row * 2, col * 2
      [0, 1].flat_map do |dr|
        [0, 1].map { |dc| mmu.debug_read(base + (((tile_row + dr) % 32) * 32) + ((tile_col + dc) % 32)) }
      end
    end

    class RoomClassifier
      def initialize
        @signatures = {}
        @probes = 0
      end

      attr_reader :probes

      # Returns the cached verdict for this cell's signature, or learns it via the block (called
      # only on a genuinely new signature) and caches it for every future cell sharing it.
      def verdict_at(mmu, row, col)
        sig = Terrain.signature_at(mmu, row, col)
        return @signatures[sig] if @signatures.key?(sig)

        @probes += 1
        @signatures[sig] = yield(sig)
      end
    end
  end
end
