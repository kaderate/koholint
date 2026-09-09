# frozen_string_literal: true
# Regenerates the house2_interior checkpoint lib/-only: continues from villager_screen, follows
# the narrow-alignment route confirmed by the Explorer session in
# data/ram_registry.json's world_topology.room177_exits ("DOOR FOUND AND CONFIRMED"). The earlier
# BFS walkability-map sweep (16px-cell-snapped Terrain::RoomClassifier) never found this door --
# not a tap-budget gap, but a trigger column narrower than one grid cell. No legacy/ file
# required.
#
# Route: nudge to x=140 first (avoids the building's own false-floor wall at x=100 on the row
# directly south of the door), down to row6 (y=110 -- row5, y=80..95, is a genuine wall when
# approached from the west, confirmed 0px progress across 38 raw taps; y=102, right at the row5/6
# boundary, is STILL inside the blocked band -- confirmed live this session, a leftward nudge
# stalled after one step there. y=110 is the value this session's own probing found clear), then
# left into the ~8px door column (x=72..76 -- x=64/68/80/88, each only 4-8px off, do NOT trigger),
# then north.
#
# Run: ruby lib/validation/checkpoint_house2_interior.rb

require_relative 'checkpoint_support'

include Koholint::CheckpointSupport

HOUSE2_INTERIOR = [169, 16].freeze
CLEAR_X = 140
ROW6_Y = 110
DOOR_X = 74
DOOR_X_TOLERANCE = 2 # keeps the landing inside the confirmed ~8px trigger band (x=72..76)

def build
  motherboard = load_checkpoint('villager_screen')
  calls = 0

  _, n = nudge_axis!(motherboard, :x, CLEAR_X, tolerance: 6, max_steps: 15)
  calls += n

  _, n = nudge_axis!(motherboard, :y, ROW6_Y, tolerance: 4, max_steps: 20)
  calls += n

  _, n = nudge_axis!(motherboard, :x, DOOR_X, tolerance: DOOR_X_TOLERANCE, max_steps: 20)
  calls += n

  room, n = cross_until_room_change!(motherboard, :up, max_taps: 10)
  calls += n
  if room.nil?
    pos = Koholint::Navigator.position(motherboard.mmu)
    raise "never crossed north into house2_interior -- still at #{room_of(motherboard).inspect}, position #{pos.inspect}"
  end

  wait_frames(motherboard, 20)
  [motherboard, calls]
end

if File.exist?(Koholint::CheckpointSupport.checkpoint_path('house2_interior'))
  motherboard = load_checkpoint('house2_interior')
  calls = nil
else
  motherboard, calls = build
  save_checkpoint('house2_interior', motherboard)
end

room = room_of(motherboard)
puts "room_id/map_id: #{room.inspect} (expected #{HOUSE2_INTERIOR.inspect})"
if calls
  puts "move! calls this build: #{calls} (<= #{calls * Koholint::CheckpointSupport::MOVE_FRAMES_UPPER_BOUND} frames)"
end
raise "room mismatch: expected #{HOUSE2_INTERIOR.inspect}, got #{room.inspect}" unless room == HOUSE2_INTERIOR

png_path = File.join(Koholint::CheckpointSupport::CHECKPOINT_DIR, 'lib_house2_interior.png')
motherboard.ppu.export_framebuffer_png(png_path)
puts "framebuffer: #{png_path}"
puts 'OK: house2_interior reached.'
