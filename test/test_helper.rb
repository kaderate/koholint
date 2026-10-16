$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'minitest/autorun'
require 'koholint'

module RomHelper
  def skip_without_rom!
    skip 'ROM not available' unless File.exist?(Koholint.rom_path)
  rescue Koholint::Error
    skip 'ROM not available'
  end
end

Minitest::Test.include(RomHelper)
