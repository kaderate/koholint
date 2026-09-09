# frozen_string_literal: true
# Regenerates the villager_screen checkpoint lib/-only: continues from overworld_screen2, crosses
# its west edge into 177/0 (data/ram_registry.json's world_topology.front_yard_to_room177 --
# "south then west" holds, its exact legacy tap counts don't -- Navigator.move!'s tile-calibrated
# steps replace them). No legacy/ file required.
#
# Run: ruby lib/validation/checkpoint_villager_screen.rb

require_relative 'checkpoint_support'

include Koholint::CheckpointSupport

VILLAGER_SCREEN = [177, 0].freeze

def build
  motherboard = load_checkpoint('overworld_screen2')
  calls = 0

  room = nil
  3.times do |attempt|
    room, n = cross_until_room_change!(motherboard, :left, max_taps: 20)
    calls += n
    break if room

    # Different vertical offset each retry (anti-patch: vary the approach, not repeat it).
    _, n = nudge_axis!(motherboard, :y, Koholint::Navigator.position(motherboard.mmu)[:y] + ((attempt + 1) * 16), tolerance: 4, max_steps: 4)
    calls += n
  end
  raise "never left overworld_screen2 westward (still at #{room_of(motherboard).inspect})" if room.nil?

  wait_frames(motherboard, 20)
  [motherboard, calls]
end

if File.exist?(Koholint::CheckpointSupport.checkpoint_path('villager_screen'))
  motherboard = load_checkpoint('villager_screen')
  calls = nil
else
  motherboard, calls = build
  save_checkpoint('villager_screen', motherboard)
end

room = room_of(motherboard)
puts "room_id/map_id: #{room.inspect} (expected #{VILLAGER_SCREEN.inspect})"
if calls
  puts "move! calls this build: #{calls} (<= #{calls * Koholint::CheckpointSupport::MOVE_FRAMES_UPPER_BOUND} frames)"
end
raise "room mismatch: expected #{VILLAGER_SCREEN.inspect}, got #{room.inspect}" unless room == VILLAGER_SCREEN

png_path = File.join(Koholint::CheckpointSupport::CHECKPOINT_DIR, 'lib_villager_screen.png')
motherboard.ppu.export_framebuffer_png(png_path)
puts "framebuffer: #{png_path}"
puts 'OK: villager_screen reached.'
