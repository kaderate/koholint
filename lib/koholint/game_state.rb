module Koholint
  GameState = Struct.new(:frame, :room_id, :map_id, :x, :y, :direction, :hp, :max_hp, :milestone,
                         :game_mode, :game_submode, :name_length, keyword_init: true) do
    def controllable? = hp.to_i.positive? && x.to_i.positive?
  end
end
