require 'koholint/geometry'

module Koholint
  GRID_ROWS = 8
  GRID_COLS = 10

  # Values and meaning: notes of game_mode and game_submode in data/addresses.json (one boot run, hypotheses).
  PLAY_MODE = 0x0B
  PLAY_SETTLED_SUBMODE = 7
  # Values and meaning: notes of link_motion_blocked and scene_state in data/addresses.json.
  SCENE_LOCKED = 1

  GameState = Struct.new(:frame, :room_id, :map_id, :x, :y, :direction, :hp, :max_hp, :milestone,
                         :game_mode, :game_submode, :name_length, :dialog_state, :motion_blocked, :scene_state, keyword_init: true) do
    # Link's sprites cover x - 8...x + 8 and y - 16...y; nil when his center is outside the 8x10 grid.
    def self.cell_at(x, y) = Geometry.cell_for(x, y)

    def cell = self.class.cell_at(x, y)

    def controllable? = hp.to_i.positive? && x.to_i.positive?

    def dialog_open? = dialog_state.to_i.positive?

    def loading? = game_mode == PLAY_MODE && game_submode != PLAY_SETTLED_SUBMODE

    def locked? = motion_blocked.to_i.positive? || scene_state == SCENE_LOCKED

    def phase
      return :boot unless game_mode == PLAY_MODE
      return :loading if loading?

      return :dialogue if dialog_open?

      locked? ? :locked : :playing
    end
  end
end
