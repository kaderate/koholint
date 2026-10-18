require 'koholint/addresses'
require 'koholint/game_state'

module Koholint
  module Perception
    ADDRESSES = Addresses.load.freeze
    HP_PER_HEART = 8

    module_function

    def read(emulator)
      read_byte = ->(name) { emulator.read(ADDRESSES.fetch(name)) }
      GameState.new(frame: emulator.frame, room_id: read_byte.(:room_id), map_id: read_byte.(:map_id),
                    x: read_byte.(:link_x), y: read_byte.(:link_y), direction: read_byte.(:link_direction),
                    hp: read_byte.(:hp), max_hp: read_byte.(:max_hearts) * HP_PER_HEART, milestone: :none,
                    game_mode: read_byte.(:game_mode), game_submode: read_byte.(:game_submode),
                    name_length: read_byte.(:name_length))
    end
  end
end
