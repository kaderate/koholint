# frozen_string_literal: true
# Regenerates the overworld_screen2 checkpoint lib/-only: continues from front_yard, crosses its
# south edge into 178/0 (data/ram_registry.json's world_topology.front_yard_adjacent_rooms,
# independently re-confirmed here by this session's own run -- see AGENTS.md's 2-independent-
# checks provenance rule). No legacy/ file required.
#
# Run: ruby lib/validation/checkpoint_overworld_screen2.rb

require_relative 'checkpoint_support'

include Koholint::CheckpointSupport

OVERWORLD_SCREEN2 = [178, 0].freeze

def build
  motherboard = load_checkpoint('front_yard')
  room, calls = cross_until_room_change!(motherboard, :down, max_taps: 25)
  raise "never left front_yard southward (still at #{room_of(motherboard).inspect})" if room.nil?

  wait_frames(motherboard, 20) # let any in-flight scroll settle before checkpointing
  [motherboard, calls]
end

if File.exist?(Koholint::CheckpointSupport.checkpoint_path('overworld_screen2'))
  motherboard = load_checkpoint('overworld_screen2')
  calls = nil
else
  motherboard, calls = build
  save_checkpoint('overworld_screen2', motherboard)
end

room = room_of(motherboard)
puts "room_id/map_id: #{room.inspect} (expected #{OVERWORLD_SCREEN2.inspect})"
if calls
  puts "move! calls this build: #{calls} (<= #{calls * Koholint::CheckpointSupport::MOVE_FRAMES_UPPER_BOUND} frames)"
end
raise "room mismatch: expected #{OVERWORLD_SCREEN2.inspect}, got #{room.inspect}" unless room == OVERWORLD_SCREEN2

png_path = File.join(Koholint::CheckpointSupport::CHECKPOINT_DIR, 'lib_overworld_screen2.png')
motherboard.ppu.export_framebuffer_png(png_path)
puts "framebuffer: #{png_path}"
puts 'OK: overworld_screen2 reached.'
