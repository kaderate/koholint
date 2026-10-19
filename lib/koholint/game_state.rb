module Koholint
  # Values and meaning: notes of game_mode and game_submode in data/addresses.json (one boot run, hypotheses).
  PLAY_MODE = 0x0B
  PLAY_SETTLED_SUBMODE = 7

  GameState = Struct.new(:frame, :room_id, :map_id, :x, :y, :direction, :hp, :max_hp, :milestone,
                         :game_mode, :game_submode, :name_length, :dialog_state, keyword_init: true) do
    def controllable? = hp.to_i.positive? && x.to_i.positive?

    def dialog_open? = dialog_state.to_i.positive?

    def loading? = game_mode == PLAY_MODE && game_submode != PLAY_SETTLED_SUBMODE

    def phase
      return :boot unless game_mode == PLAY_MODE
      return :loading if loading?

      dialog_open? ? :dialogue : :playing
    end
  end
end
