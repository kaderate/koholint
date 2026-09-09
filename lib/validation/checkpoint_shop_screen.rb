# frozen_string_literal: true
# Regenerates the shop_screen checkpoint lib/-only: continues from overworld_screen2, crosses its
# east edge into a new room (not yet in data/ram_registry.json -- confirmed live by this script,
# room identity read after arrival). The east edge isn't registry-documented (only front_yard's
# own neighbors are), so this tries a spread of rows rather than assuming one -- legacy/'s old
# hint (a specific upper-screen row) is a starting guess, not a dependency. No legacy/ file
# required.
#
# Run: ruby lib/validation/checkpoint_shop_screen.rb

require_relative 'checkpoint_support'

include Koholint::CheckpointSupport

OVERWORLD_SCREEN2 = [178, 0].freeze
ROW_Y_CANDIDATES = [8, 120, 24, 104, 40, 56, 72, 88].freeze

def build
  base_snapshot = load_checkpoint('overworld_screen2').dump
  calls = 0
  used_y = nil

  ROW_Y_CANDIDATES.each do |y|
    motherboard = Motherboard.load(base_snapshot)
    _, n = nudge_axis!(motherboard, :y, y, tolerance: 4, max_steps: 10)
    calls += n
    room, n = cross_until_room_change!(motherboard, :right, max_taps: 20)
    calls += n
    if room
      used_y = y
      wait_frames(motherboard, 20)
      return [motherboard, calls, used_y]
    end
  end
  raise "never found the east exit across y candidates #{ROW_Y_CANDIDATES.inspect}"
end

if File.exist?(Koholint::CheckpointSupport.checkpoint_path('shop_screen'))
  motherboard = load_checkpoint('shop_screen')
  calls = used_y = nil
else
  motherboard, calls, used_y = build
  save_checkpoint('shop_screen', motherboard)
end

room = room_of(motherboard)
puts "room_id/map_id: #{room.inspect} (a new room, not previously known)"
puts "row used: y=#{used_y}" if used_y
if calls
  puts "move! calls this build: #{calls} (<= #{calls * Koholint::CheckpointSupport::MOVE_FRAMES_UPPER_BOUND} frames)"
end
raise "still in overworld_screen2 -- east exit never crossed" if room == OVERWORLD_SCREEN2

png_path = File.join(Koholint::CheckpointSupport::CHECKPOINT_DIR, 'lib_shop_screen.png')
motherboard.ppu.export_framebuffer_png(png_path)
puts "framebuffer: #{png_path}"
puts 'OK: shop_screen reached (new room -- inspect the PNG to confirm it looks like a shop).'
