require 'koholint/config'

module Koholint
  VERSION = '2.0.0'
  FLOW_VERSION = 'flow-5'

  class Error < StandardError; end

  def self.rom_path
    path = setting('KOHOLINT_ROM')
    raise Error, "ROM not found at #{path}; check KOHOLINT_ROM" unless File.file?(path)

    path
  end

  def self.emu_gb_home
    path = setting('EMU_GB_HOME')
    raise Error, "emu-gb checkout not found at #{path}; check EMU_GB_HOME" unless File.file?(File.join(path, 'lib', 'driver.rb'))

    path
  end

  def self.setting(name)
    value = Config.get(name)
    raise Error, "#{name} is not set; copy .env.example to .env and fill it in" if value.nil? || value.empty?

    File.expand_path(value)
  end
  private_class_method :setting
end
