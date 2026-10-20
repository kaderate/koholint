require 'digest'
require 'fileutils'

module Koholint
  module CanonicalSave
    module_function

    def write(emulator, run)
      ram = emulator.cartridge_ram
      FileUtils.mkdir_p(File.join(run.dir, 'save'))
      path = File.join(run.dir, 'save', format('%09d.sav', emulator.frame))
      File.binwrite(path, ram)
      [path, Digest::SHA256.hexdigest(ram)]
    end
  end
end
