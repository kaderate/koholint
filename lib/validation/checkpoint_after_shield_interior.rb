# frozen_string_literal: true
# Regenerates the after_shield_interior checkpoint lib/-only: boot the ROM, clear the title/file-
# select/naming screens, then exhaust Marin's spontaneous greeting and Tarin's follow-up
# conversation (which ends with the shield) -- still inside starting_house (163/16). No legacy/
# file is required anywhere in this script.
#
# Time is frames throughout (AGENTS.md), never an instruction count; Navigator.tap_button is the
# single-button press-then-settle primitive this checkpoint needed and Navigator didn't have yet
# (PLAN.md Part A).
#
# Two real dialogues happen here, not one, and neither is safe to clear with a fixed tap count
# (see CheckpointSupport.clear_dialogue!'s comment for why -- a fixed count was tried first this
# session and failed both ways, too few and too many). Marin's greeting fires on its own a few
# hundred frames after the file loads, no navigation needed (movement is locked out entirely
# while it's up); a short walk to Tarin then triggers a second conversation that ends with the
# shield and an item-get message. The "6x interact" in this session's own mandate was a rough
# description, not a literal tap count -- reaching the same real end state (shield obtained) is
# what's verified below, visually, the same way this project already reads dialogue state
# (NEXT.md: no reliable memory flag for it).
#
# Run: ruby lib/validation/checkpoint_after_shield_interior.rb

require_relative 'checkpoint_support'

include Koholint::CheckpointSupport

STARTING_HOUSE = [163, 16].freeze
BOOT_WAIT_FRAMES = 4200 # boot logo -> intro cutscene -> idles on the title screen
TARIN_TARGET = { y: 80, x: 112 }.freeze # same approach point this project used before (docs/archive)

def build
  motherboard = boot_fresh
  wait_frames(motherboard, BOOT_WAIT_FRAMES)

  Koholint::Navigator.tap_button(motherboard, :start) # title -> file select
  Koholint::Navigator.tap_button(motherboard, :a)     # empty slot -> name entry
  Koholint::Navigator.tap_button(motherboard, :a)     # pick letter 'A'
  Koholint::Navigator.tap_button(motherboard, :start) # confirm name -> file select, file created
  Koholint::Navigator.tap_button(motherboard, :start) # select the file -> enters starting_house

  clear_dialogue!(motherboard, probe_direction: :down, max_rounds: 40) # Marin's greeting

  nudge_axis!(motherboard, :y, TARIN_TARGET[:y], tolerance: 6, max_steps: 8)
  nudge_axis!(motherboard, :x, TARIN_TARGET[:x], tolerance: 6, max_steps: 8)

  clear_dialogue!(motherboard, probe_direction: :left, max_rounds: 40) # Tarin -> the shield

  motherboard
end

if File.exist?(Koholint::CheckpointSupport.checkpoint_path('after_shield_interior'))
  motherboard = load_checkpoint('after_shield_interior')
else
  motherboard = build
  save_checkpoint('after_shield_interior', motherboard)
end

room = room_of(motherboard)
puts "room_id/map_id: #{room.inspect} (expected #{STARTING_HOUSE.inspect})"
raise "room mismatch: expected #{STARTING_HOUSE.inspect}, got #{room.inspect}" unless room == STARTING_HOUSE

png_path = File.join(Koholint::CheckpointSupport::CHECKPOINT_DIR, 'lib_after_shield_interior.png')
motherboard.ppu.export_framebuffer_png(png_path)
puts "framebuffer: #{png_path}"
puts 'OK: still in starting_house. Shield ownership has no known HRAM address (not in ' \
     'data/ram_registry.json) -- confirm visually from the PNG above: the B-button HUD slot ' \
     '(bottom-left) should show the shield icon, matching this session\'s own recon screenshots.'
