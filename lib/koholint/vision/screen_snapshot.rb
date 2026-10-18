require 'digest'

module Koholint
  module Vision
    Cell = Struct.new(:appearance, :tiles)

    ScreenSnapshot = Struct.new(:frame, :place, :scroll, :cells, :sprites, :overlay) do
      def terrain_hash = Digest::SHA256.hexdigest([cells.flatten.map(&:appearance), overlay].inspect)

      def objects_hash
        ordered = sprites.map { |s| s.values_at(:x, :y, :tile, :attr, :pattern) }.sort_by(&:inspect)
        Digest::SHA256.hexdigest(ordered.inspect)
      end
    end
  end
end
