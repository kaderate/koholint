# frozen_string_literal: true
# Regenerates the screen3_north checkpoint lib/-only: continues from villager_screen, crosses its
# north edge into 161/0 (data/ram_registry.json's world_topology.room177_exits: blocked near the
# spawn column -- the building's own footprint, not the room edge -- but clear and open from
# x=140). No legacy/ file required.
#
# Run: ruby lib/validation/checkpoint_screen3_north.rb

require_relative 'checkpoint_support'

include Koholint::CheckpointSupport

SCREEN3_NORTH = [161, 0].freeze
CLEAR_X = 140

def build
  motherboard = load_checkpoint('villager_screen')
  calls = 0

  _, n = nudge_axis!(motherboard, :x, CLEAR_X, tolerance: 6, max_steps: 15)
  calls += n

  room, n = cross_until_room_change!(motherboard, :up, max_taps: 15)
  calls += n
  raise "never left villager_screen northward (still at #{room_of(motherboard).inspect})" if room.nil?

  wait_frames(motherboard, 20)
  [motherboard, calls]
end

if File.exist?(Koholint::CheckpointSupport.checkpoint_path('screen3_north'))
  motherboard = load_checkpoint('screen3_north')
  calls = nil
else
  motherboard, calls = build
  save_checkpoint('screen3_north', motherboard)
end

room = room_of(motherboard)
puts "room_id/map_id: #{room.inspect} (expected #{SCREEN3_NORTH.inspect})"
if calls
  puts "move! calls this build: #{calls} (<= #{calls * Koholint::CheckpointSupport::MOVE_FRAMES_UPPER_BOUND} frames)"
end
raise "room mismatch: expected #{SCREEN3_NORTH.inspect}, got #{room.inspect}" unless room == SCREEN3_NORTH

png_path = File.join(Koholint::CheckpointSupport::CHECKPOINT_DIR, 'lib_screen3_north.png')
motherboard.ppu.export_framebuffer_png(png_path)
puts "framebuffer: #{png_path}"
puts 'OK: screen3_north reached.'
