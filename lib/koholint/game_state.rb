require 'koholint/geometry'
require 'koholint/modes'

module Koholint
  GRID_ROWS = 8
  GRID_COLS = 10

  # Values and meaning: notes of game_mode and game_submode in data/addresses.json and the catalogue data/modes.json.
  PLAY_MODE = 0x0B
  PLAY_SETTLED_SUBMODE = 7
  # link_motion_state while a door walks Link in: he holds still about 18 frames, then the next place loads (run 20261112-103604-0c64, frames 71971-71990).
  DOOR_WALK_IN = 3

  GameState = Struct.new(:frame, :room_id, :map_id, :x, :y, :direction, :hp, :max_hp, :milestone,
                         :game_mode, :game_submode, :name_length, :dialog_state, :motion_blocked, :scene_state,
                         :link_motion_state, :game_over_stage, :inventory_cursor, :menu_option, :item_a, :item_b,
                         :room_transition, :link_airborne, :link_z, :link_knockback, :inventory, :shield_raised, :link_frozen, :pending_damage,
                         keyword_init: true) do
    # Link's sprites cover x - 8...x + 8 and y - 16...y; nil when his center is outside the 8x10 grid.
    def self.cell_at(x, y) = Geometry.cell_for(x, y)

    def cell = self.class.cell_at(x, y)

    def controllable? = hp.to_i.positive? && x.to_i.positive?

    # Health once the pending damage has drained: the game lowers hp by one unit every 2 frames after a hit (data/addresses.json, pending_damage).
    def health = hp.to_i - pending_damage.to_i

    def low_health? = max_hp.to_i.positive? && hp.to_i.positive? && hp.to_i * 3 <= max_hp.to_i

    def dialog_open? = dialog_state.to_i.positive?

    def loading? = game_mode == PLAY_MODE && game_submode != PLAY_SETTLED_SUBMODE

    def door_walk_in? = link_motion_state.to_i == DOOR_WALK_IN

    def locked? = motion_blocked.to_i.positive?

    # link_frozen 1 alone was seen for a few frames outside any scene (data/addresses.json).
    def scene? = link_frozen.to_i > 1

    def self.played?(events) = events.any? { |event| event['type'] == 'perception' && event.dig('state', 'game_mode') == PLAY_MODE }

    def mode = Modes.for(self)

    def phase(booted: false) = Modes.phase(self, booted:)
  end
end
