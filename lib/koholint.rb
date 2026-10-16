module Koholint
  VERSION = '2.0.0'
  FLOW_VERSION = 'flow-1'

  class Error < StandardError; end

  DEFAULT_ROM = File.expand_path('~/Code/emu-gb/roms/zelda_dx_rev1.gbc')
  DEFAULT_EMU_GB = File.expand_path('~/Code/emu-gb')

  def self.rom_path
    path = File.expand_path(ENV.fetch('KOHOLINT_ROM', DEFAULT_ROM))
    raise Error, "ROM not found at #{path}; set KOHOLINT_ROM" unless File.file?(path)

    path
  end

  def self.emu_gb_home
    path = File.expand_path(ENV.fetch('EMU_GB_HOME', DEFAULT_EMU_GB))
    raise Error, "emu-gb checkout not found at #{path}; set EMU_GB_HOME" unless File.file?(File.join(path, 'lib', 'driver.rb'))

    path
  end
end
