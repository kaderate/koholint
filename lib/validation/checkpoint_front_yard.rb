# frozen_string_literal: true
# Regenerates the front_yard checkpoint lib/-only: continues from after_shield_interior, exits
# starting_house's south door into the front yard (162/0). No legacy/ file required.
#
# Door approach coordinate (x=72) is a known tuning constant from this project's own prior
# exploration (docs/archive/EXPLORATION_LOG.md), not a dependency on legacy/ code -- same status
# as any other empirically-established constant already in Navigator/Terrain.
#
# Run: ruby lib/validation/checkpoint_front_yard.rb

require_relative 'checkpoint_support'

include Koholint::CheckpointSupport

STARTING_HOUSE = [163, 16].freeze
FRONT_YARD = [162, 0].freeze
DOOR_X = 72

def build
  motherboard = load_checkpoint('after_shield_interior')
  calls = 0

  _, n = nudge_axis!(motherboard, :x, DOOR_X, tolerance: 8, max_steps: 15)
  calls += n

  room = nil
  3.times do |attempt|
    room, n = cross_until_room_change!(motherboard, :down, max_taps: 20)
    calls += n
    break if room

    # Anti-patch discipline: a different lateral offset each retry, not the same push again.
    _, n = nudge_axis!(motherboard, :x, DOOR_X + ((attempt + 1) * (attempt.even? ? 8 : -16)), tolerance: 4, max_steps: 6)
    calls += n
  end
  raise "never crossed out of starting_house toward the south door (still at #{room_of(motherboard).inspect})" if room.nil?

  wait_frames(motherboard, 20)
  [motherboard, calls]
end

if File.exist?(Koholint::CheckpointSupport.checkpoint_path('front_yard'))
  motherboard = load_checkpoint('front_yard')
  calls = nil
else
  motherboard, calls = build
  save_checkpoint('front_yard', motherboard)
end

room = room_of(motherboard)
puts "room_id/map_id: #{room.inspect} (expected #{FRONT_YARD.inspect})"
if calls
  puts "move! calls this build: #{calls} (<= #{calls * Koholint::CheckpointSupport::MOVE_FRAMES_UPPER_BOUND} frames)"
end
raise "room mismatch: expected #{FRONT_YARD.inspect}, got #{room.inspect}" unless room == FRONT_YARD

png_path = File.join(Koholint::CheckpointSupport::CHECKPOINT_DIR, 'lib_front_yard.png')
motherboard.ppu.export_framebuffer_png(png_path)
puts "framebuffer: #{png_path}"
puts 'OK: front_yard reached.'
