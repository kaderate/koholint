# frozen_string_literal: true
# Regenerates the house2_interior checkpoint lib/-only: continues from villager_screen, enters the
# building's own door (a real interior, not yet in data/ram_registry.json -- confirmed live by
# this script, room identity read after arrival). Not the same transition as screen3_north's
# north-edge crossing into 161/0 -- a first attempt at x=100 landed in 161/0 too (the "building
# footprint blocks x=100" world_topology note turned out not to hold at Link's exact villager_
# screen entry row; the whole north edge was open from there), so this approaches from well south
# and west of the building first (legacy's old route also detoured down+left before the door
# ever resolved), rejecting 161/0 as a false-positive landing and trying the next column instead.
# No legacy/ file required.
#
# Run: ruby lib/validation/checkpoint_house2_interior.rb

require_relative 'checkpoint_support'

include Koholint::CheckpointSupport

VILLAGER_SCREEN = [177, 0].freeze
SCREEN3_NORTH = [161, 0].freeze
SOUTH_Y = 100 # well below the building, clear of its footprint, before approaching from below
DOOR_X_CANDIDATES = [76, 60, 44, 92, 108, 30].freeze

def build
  base_snapshot = load_checkpoint('villager_screen').dump
  calls = 0
  room = nil
  used_x = nil

  DOOR_X_CANDIDATES.each do |x|
    motherboard = Motherboard.load(base_snapshot)
    _, n = nudge_axis!(motherboard, :y, SOUTH_Y, tolerance: 6, max_steps: 10)
    calls += n
    _, n = nudge_axis!(motherboard, :x, x, tolerance: 4, max_steps: 12)
    calls += n
    room, n = cross_until_room_change!(motherboard, :up, max_taps: 20)
    calls += n
    next unless room && room != VILLAGER_SCREEN && room != SCREEN3_NORTH

    used_x = x
    wait_frames(motherboard, 20)
    return [motherboard, calls, used_x]
  end
  raise "never found the door across x candidates #{DOOR_X_CANDIDATES.inspect} (kept landing in #{VILLAGER_SCREEN.inspect} or #{SCREEN3_NORTH.inspect})"
end

if File.exist?(Koholint::CheckpointSupport.checkpoint_path('house2_interior'))
  motherboard = load_checkpoint('house2_interior')
  calls = used_x = nil
else
  motherboard, calls, used_x = build
  save_checkpoint('house2_interior', motherboard)
end

room = room_of(motherboard)
puts "room_id/map_id: #{room.inspect} (a new interior, not previously known)"
puts "door column used: x=#{used_x}" if used_x
if calls
  puts "move! calls this build: #{calls} (<= #{calls * Koholint::CheckpointSupport::MOVE_FRAMES_UPPER_BOUND} frames)"
end
raise "still in villager_screen -- door never triggered" if room == VILLAGER_SCREEN
raise "landed in screen3_north, not a new interior -- door not found" if room == SCREEN3_NORTH

png_path = File.join(Koholint::CheckpointSupport::CHECKPOINT_DIR, 'lib_house2_interior.png')
motherboard.ppu.export_framebuffer_png(png_path)
puts "framebuffer: #{png_path}"
puts 'OK: house2_interior reached (new room -- inspect the PNG to confirm it is an interior).'
