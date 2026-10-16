require_relative 'test_helper'
require 'stringio'
require 'zlib'
require 'koholint/png'

class PngTest < Minitest::Test
  def chunks(png)
    io = StringIO.new(png)
    assert_equal "\x89PNG\r\n\x1a\n".b, io.read(8)
    list = []
    until io.eof?
      length = io.read(4).unpack1('N')
      type = io.read(4)
      data = io.read(length)
      assert_equal Zlib.crc32(type + data), io.read(4).unpack1('N')
      list << [type, data]
    end
    list
  end

  def test_encode_a_2x2_image
    rgb = [255, 0, 0, 0, 255, 0, 0, 0, 255, 10, 20, 30].pack('C*')
    list = chunks(Koholint::Png.encode(rgb:, width: 2, height: 2))
    assert_equal %w[IHDR IDAT IEND], list.map(&:first)
    assert_equal [2, 2, 8, 2, 0, 0, 0], list[0][1].unpack('NNCCCCC')
    expected = ([0] + rgb.bytes.first(6) + [0] + rgb.bytes.last(6)).pack('C*')
    assert_equal expected, Zlib::Inflate.inflate(list[1][1])
    assert_empty list[2][1]
  end

  def test_encode_rejects_a_buffer_of_the_wrong_size
    assert_raises(ArgumentError) { Koholint::Png.encode(rgb: 'x'.b * 11, width: 2, height: 2) }
  end
end
