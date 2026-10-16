module Koholint
  GameState = Struct.new(:frame, :room_id, :map_id, :x, :y, :direction, :hp, :max_hp, :milestone, keyword_init: true)
end
