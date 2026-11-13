require 'koholint/addresses'
require 'koholint/game_state'
require 'koholint/items'

module Koholint
  module Perception
    ADDRESSES = Addresses.load.freeze
    HP_PER_HEART = 8
    MILESTONES = %i[none shield sword].freeze

    module_function

    def milestone_for(shield_level, held = [])
      reached = held.filter_map { |id| Items.milestone(id) }
      reached << :shield if shield_level.to_i.positive?
      reached.max_by { |milestone| MILESTONES.index(milestone) || 0 } || :none
    end

    def read(emulator)
      read_byte = ->(name) { emulator.read(ADDRESSES.fetch(name)) }
      first = ADDRESSES.fetch(:inventory_items)
      inventory = Array.new(Items::SLOTS) { |slot| emulator.read(first + slot) }
      buttons = [read_byte.(:inventory_slot_a), read_byte.(:inventory_slot_b)]
      GameState.new(frame: emulator.frame, room_id: read_byte.(:room_id), map_id: read_byte.(:map_id),
                    x: read_byte.(:link_x), y: read_byte.(:link_y), direction: read_byte.(:link_direction),
                    hp: read_byte.(:hp), max_hp: read_byte.(:max_hearts) * HP_PER_HEART,
                    milestone: milestone_for(read_byte.(:shield_level), (buttons + inventory).reject(&:zero?)),
                    game_mode: read_byte.(:game_mode), game_submode: read_byte.(:game_submode),
                    name_length: read_byte.(:name_length), dialog_state: read_byte.(:dialog_state),
                    motion_blocked: read_byte.(:link_motion_blocked), scene_state: read_byte.(:scene_state),
                    link_motion_state: read_byte.(:link_motion_state), game_over_stage: read_byte.(:game_over_stage),
                    inventory_cursor: read_byte.(:inventory_cursor), menu_option: read_byte.(:menu_option),
                    item_a: buttons[0], item_b: buttons[1], inventory:, shield_raised: read_byte.(:shield_raised),
                    room_transition: read_byte.(:room_transition), link_airborne: read_byte.(:link_airborne),
                    link_z: read_byte.(:link_z), link_knockback: read_byte.(:link_knockback),
                    link_frozen: read_byte.(:link_frozen), pending_damage: read_byte.(:pending_damage))
    end
  end
end
