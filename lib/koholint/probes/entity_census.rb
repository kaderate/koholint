require 'digest'
require 'json'
require 'koholint/config'
require 'koholint/entities'
require 'koholint/perception'
require 'koholint/probes/mode_census'
require 'koholint/vision/dialogue_shot'
require 'koholint/vision/grid_builder'
require 'koholint/vision/screen_vision'

module Koholint
  module Probes
    module EntityCensus
      OUT_DIR = File.join(Config::ROOT, 'tmp', 'entities')
      SIDES = { up: [0, 16], down: [0, -16], left: [16, 0], right: [-16, 0] }.freeze
      FACE_FRAMES = 6
      PRESS_FRAMES = 4
      RESPONSE_FRAMES = 40
      CONTACT_FRAMES = 90
      IDLE_FRAMES = 120
      SPRITE_DX = 8
      SPRITE_DY = 16
      ADVANCE_FRAMES = 30
      ADVANCE_PRESS = 3
      PAGE_LIMIT = 40
      REOPEN_FRAMES = 10
      SECOND_TALK_GAP = 60
      PHASE_SHIFT = 7
      ADDR = Perception::ADDRESSES

      module_function

      def census(run_dir, frames, out: OUT_DIR)
        frames.map do |frame|
          emulator = ModeCensus.state_at(run_dir, frame)
          write(File.join(out, "#{File.basename(run_dir)}-#{frame}.json"), report(emulator, run: File.basename(run_dir), frame:))
        end
      end

      def report(emulator, run:, frame:)
        state = Perception.read(emulator)
        sprites = Vision::ScreenVision.sprites(emulator, emulator.read(Vision::ScreenVision::LCDC)).reject { |s| Vision::GridBuilder.link_sprite?(s, state) }
        entities = Entities.read(emulator, kinds: {})
        { run:, frame:, place: [state.room_id, state.map_id], link: { x: state.x, y: state.y, cell: state.cell },
          entities: entities.map { |entity| probe(emulator, entity, sprites) },
          free_slots: free_slots(emulator, sprites),
          unmatched_sprites: sprites.reject { |s| entities.any? { |e| sprite_of?(s, e) } }.map { |s| s.slice(:x, :y) } }
      end

      def probe(emulator, entity, sprites)
        talk = SIDES.to_h { |side, offset| [side, { with: talk_opens?(emulator, entity, side, offset), control: talk_opens?(cleared(emulator, entity), entity, side, offset) }] }
        talkable = talk.values.any? { |r| r[:with] && !r[:control] }
        damage = contact_damage(emulator, entity)
        control = contact_damage(cleared(emulator, entity), entity)
        { **entity.except(:kind), sprite: sprites.select { |s| sprite_of?(s, entity) }.map { |s| s.slice(:x, :y) },
          moves: moves?(emulator, entity), talk:, talkable:, contact_hp_delta: damage, control_hp_delta: control,
          hostile: damage.negative? && !control.negative?, conversations: (conversations(emulator, entity, talk) if talkable) }.compact
      end

      def sprite_of?(sprite, entity) = (sprite[:x] - entity[:x]).between?(-SPRITE_DX, SPRITE_DX) && (sprite[:y] - entity[:y]).between?(-SPRITE_DY, SPRITE_DY)

      def free_slots(emulator, sprites)
        (0...Entities::SLOTS).filter_map do |slot|
          next unless emulator.read(ADDR.fetch(:entity_status) + slot).zero?

          x = emulator.read(ADDR.fetch(:entity_x) + slot)
          y = emulator.read(ADDR.fetch(:entity_y) + slot)
          next unless Geometry.cell_for(x, y)

          { slot:, x:, y:, sprite: sprites.any? { |s| sprite_of?(s, { x:, y: }) } }
        end
      end

      def cleared(emulator, entity)
        copy = ModeCensus.copy(emulator)
        ModeCensus.poke(copy, ADDR.fetch(:entity_status) + entity[:slot], 0)
        copy
      end

      def place_link(emulator, x, y)
        ModeCensus.poke(emulator, ADDR.fetch(:link_x), x & 0xFF)
        ModeCensus.poke(emulator, ADDR.fetch(:link_y), y & 0xFF)
      end

      def approach(emulator, entity, side, offset)
        copy = ModeCensus.copy(emulator)
        place_link(copy, entity[:x] + offset[0], entity[:y] + offset[1])
        FACE_FRAMES.times { copy.step([side]) }
        copy
      end

      def talk_opens?(emulator, entity, side, offset)
        copy = approach(emulator, entity, side, offset)
        PRESS_FRAMES.times { copy.step([:a]) }
        RESPONSE_FRAMES.times.any? do
          copy.step([])
          dialog?(copy)
        end || dialog?(copy)
      end

      def dialog?(emulator) = emulator.read(ADDR.fetch(:dialog_state)).positive?

      def contact_damage(emulator, entity)
        copy = ModeCensus.copy(emulator)
        hp = copy.read(ADDR.fetch(:hp))
        CONTACT_FRAMES.times do
          place_link(copy, copy.read(ADDR.fetch(:entity_x) + entity[:slot]), copy.read(ADDR.fetch(:entity_y) + entity[:slot]))
          copy.step([])
        end
        copy.read(ADDR.fetch(:hp)) - hp
      end

      def moves?(emulator, entity)
        copy = ModeCensus.copy(emulator)
        seen = [[entity[:x], entity[:y]]]
        IDLE_FRAMES.times do
          copy.step([])
          seen |= [[copy.read(ADDR.fetch(:entity_x) + entity[:slot]), copy.read(ADDR.fetch(:entity_y) + entity[:slot])]]
        end
        seen.size > 1
      end

      def conversations(emulator, entity, talk)
        side, = talk.find { |_, r| r[:with] && !r[:control] }
        first = approach(emulator, entity, side, SIDES.fetch(side))
        shifted = ModeCensus.copy(emulator)
        PHASE_SHIFT.times { shifted.step([]) }
        shifted = approach(shifted, entity, side, SIDES.fetch(side))
        once = converse(first)
        SECOND_TALK_GAP.times { first.step([]) }
        FACE_FRAMES.times { first.step([side]) }
        { first: once, again: converse(first), shifted: converse(shifted) }
      end

      def converse(emulator)
        PRESS_FRAMES.times do
          break if dialog?(emulator)

          emulator.step([:a])
        end
        RESPONSE_FRAMES.times { dialog?(emulator) ? break : emulator.step([]) }
        rows = []
        while dialog?(emulator) && rows.size < PAGE_LIMIT
          rows << Vision::DialogueShot.text_rows(Vision::DialogueShot.rgb(emulator))
          advance(emulator)
          REOPEN_FRAMES.times { dialog?(emulator) ? break : emulator.step([]) } unless dialog?(emulator)
        end
        page_hashes = rows.map { |page| Digest::SHA256.hexdigest(page.join("\n"))[0, Vision::DialogueShot::HASH_CHARS] }
        { pages: rows.size, page_sequence: Digest::SHA256.hexdigest(page_hashes.join(','))[0, Vision::DialogueShot::HASH_CHARS],
          signature: Vision::DialogueShot.signature(rows) }
      end

      def advance(emulator)
        frames = 0
        until (frames.positive? && !dialog?(emulator)) || frames >= ADVANCE_FRAMES
          emulator.step(frames < ADVANCE_PRESS ? [:a] : [])
          frames += 1
        end
      end

      def write(path, report)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, JSON.pretty_generate(report))
        path
      end
    end
  end
end
