require 'zlib'

module Koholint
  module Png
    SIGNATURE = "\x89PNG\r\n\x1a\n".b

    def self.encode(rgb:, width:, height:)
      raise ArgumentError, "rgb has #{rgb.bytesize} bytes, expected #{width * height * 3}" unless rgb.bytesize == width * height * 3

      stride = width * 3
      raw = String.new(encoding: Encoding::BINARY)
      height.times { |row| raw << 0 << rgb.byteslice(row * stride, stride) }
      header = [width, height, 8, 2, 0, 0, 0].pack('NNCCCCC')
      SIGNATURE + chunk('IHDR', header) + chunk('IDAT', Zlib::Deflate.deflate(raw)) + chunk('IEND', ''.b)
    end

    def self.chunk(type, data)
      [data.bytesize].pack('N') + type.b + data + [Zlib.crc32(type.b + data)].pack('N')
    end
  end
end
