require 'digest'
require 'fileutils'
require 'tmpdir'
require 'koholint'
require 'koholint/png'

module Koholint
  class Emulator
    SCREEN_WIDTH = 160
    SCREEN_HEIGHT = 144
    RGB_UNPACK = ('a3x' * (SCREEN_WIDTH * SCREEN_HEIGHT)).freeze
    BUTTONS = %i[up down left right a b start select].freeze

    @roms = {}

    class << self
      def boot(rom_path = Koholint.rom_path)
        load_driver
        driver = nil
        Dir.mktmpdir('koholint-rom') do |dir|
          copy = File.join(dir, 'game.gbc')
          FileUtils.cp(rom_path, copy)
          driver = Driver.build(copy)
        end
        detach_battery(driver)
        @roms[rom_path] = driver.motherboard.mmu.mbc.rom
        new(driver, 0)
      end

      def restore(bytes, rom_path = Koholint.rom_path)
        load_driver
        boot(rom_path) unless @roms.key?(rom_path)
        data = Marshal.load(bytes) # rubocop:disable Security/MarshalLoad -- our own #dump
        motherboard = Motherboard.load(data[:motherboard], rom_bytes: @roms.fetch(rom_path))
        driver = Driver.new(motherboard)
        detach_battery(driver)
        new(driver, data[:frame])
      end

      private

      def load_driver
        lib = File.join(Koholint.emu_gb_home, 'lib')
        $LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
        require 'driver'
      end

      # The game would otherwise read and overwrite a .sav next to the ROM; the engine owns saves
      def detach_battery(driver)
        ram = driver.motherboard.mmu.mbc.external_ram
        ram.instance_variable_set(:@battery_path, nil)
      end
    end

    attr_reader :frame

    def initialize(driver, frame)
      @driver = driver
      @frame = frame
    end

    def step(buttons = [])
      unknown = buttons - BUTTONS
      raise ArgumentError, "unknown buttons #{unknown}" unless unknown.empty?

      @driver.clear_keys
      @driver.press(*buttons)
      @driver.advance_frames(1)
      @frame += 1
      nil
    end

    def read(addr) = @driver.debug_read(addr)

    def cartridge_ram = @driver.motherboard.mmu.mbc.external_ram.bytes.pack('C*')

    def state_hash
      digest = Digest::SHA256.new
      digest << (0x8000..0xFFFF).map { |addr| read(addr) }.pack('C*')
      digest << cartridge_ram
      cpu = @driver.motherboard.cpu
      digest << [cpu.registers, cpu.pc, cpu.sp, cpu.ime, cpu.halted].inspect
      digest.hexdigest
    end

    def dump = Marshal.dump(frame: @frame, motherboard: @driver.motherboard.dump(with_rom: false))

    def frame_rgb
      @driver.motherboard.ppu.framebuffer.pixels_frame.pack('V*').unpack(RGB_UNPACK).join
    end

    def frame_png = Png.encode(rgb: frame_rgb, width: SCREEN_WIDTH, height: SCREEN_HEIGHT)

    def framebuffer_png(path) = @driver.framebuffer_png(path)
  end
end
