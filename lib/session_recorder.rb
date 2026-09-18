# frozen_string_literal: true

require "fileutils"
require "time"

gemboy_home = ENV.fetch("GEMBOY_HOME", File.expand_path("../../gemboy", __dir__))
$LOAD_PATH.unshift(File.join(gemboy_home, "lib")) unless $LOAD_PATH.include?(File.join(gemboy_home, "lib"))
require "utils/gif_writer"
require "ppu"

module Koholint
  # Records a bounded task's gameplay to an animated GIF, purely emulator-side -- no agent ever
  # reads the frames back (that would burn vision tokens for nothing), this is traceability only.
  # Callers are responsible for scoping one recorder to one bounded task, not a whole session.
  class SessionRecorder
    def initialize(motherboard, label:, out_dir: "data/recordings", delay_cs: 10)
      @motherboard = motherboard
      @label = label
      @out_dir = out_dir
      @delay_cs = delay_cs
      @frames = []
    end

    # PPU::Framebuffer#pixels_frame already returns @pixels.dup (see gemboy's lib/ppu/framebuffer.rb),
    # so the appended frame is already independent of the PPU's single reused pixel buffer.
    def snapshot!
      @frames << @motherboard.ppu.framebuffer.pixels_frame
    end

    # No-op on zero captured frames -- a recorder that was created but never snapshotted is normal,
    # not an error.
    def save!
      return nil if @frames.empty?

      FileUtils.mkdir_p(@out_dir)
      path = unique_path
      GifWriter.write(path, @frames, width: PPU::WINDOW_WIDTH, height: PPU::WINDOW_HEIGHT, delay_cs: @delay_cs)
      path
    end

    private

    def unique_path
      base = File.join(@out_dir, "#{Time.now.strftime('%Y-%m-%d')}_#{@label}")
      return "#{base}.gif" unless File.exist?("#{base}.gif")

      suffix = 1
      suffix += 1 while File.exist?("#{base}_#{suffix.to_s(16)}.gif")
      "#{base}_#{suffix.to_s(16)}.gif"
    end
  end
end
