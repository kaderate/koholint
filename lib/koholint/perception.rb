require 'koholint/addresses'
require 'koholint/game_state'

module Koholint
  module Perception
    ADDRESSES = Addresses.load.freeze
    HP_PER_HEART = 8
    MILESTONES = %i[none shield].freeze

    module_function

    def milestone_for(shield_level) = shield_level.to_i.positive? ? :shield : :none

    def read(emulator)
      read_byte = ->(name) { emulator.read(ADDRESSES.fetch(name)) }
      GameState.new(frame: emulator.frame, room_id: read_byte.(:room_id), map_id: read_byte.(:map_id),
                    x: read_byte.(:link_x), y: read_byte.(:link_y), direction: read_byte.(:link_direction),
                    hp: read_byte.(:hp), max_hp: read_byte.(:max_hearts) * HP_PER_HEART,
                    milestone: milestone_for(read_byte.(:shield_level)),
                    game_mode: read_byte.(:game_mode), game_submode: read_byte.(:game_submode),
                    name_length: read_byte.(:name_length), dialog_state: read_byte.(:dialog_state),
                    motion_blocked: read_byte.(:link_motion_blocked), scene_state: read_byte.(:scene_state),
                    link_motion_state: read_byte.(:link_motion_state), game_over_stage: read_byte.(:game_over_stage),
                    inventory_cursor: read_byte.(:inventory_cursor), menu_option: read_byte.(:menu_option),
                    item_a: read_byte.(:inventory_slot_a), item_b: read_byte.(:inventory_slot_b))
    end
  end
end
