require 'json'
require 'koholint/config'
require 'koholint/entities'
require 'koholint/items'
require 'koholint/perception'
require 'koholint/probes/entity_census'
require 'koholint/probes/mode_census'

module Koholint
  module Probes
    # Sword strikes on the enemies of a state, in throwaway copies: reach per facing, lateral tolerance, hits to kill,
    # health lost per hit, knockback, and whether a charged release (spin) hits behind Link.
    module SwordCensus
      OUT_DIR = File.join(Config::ROOT, 'tmp', 'sword')
      GAPS = (8..40).step(2).to_a.freeze
      LATERAL = (-16..16).step(2).to_a.freeze
      LATERAL_GAP = 16
      STRIKE_FRAMES = 3
      WATCH_FRAMES = 20
      FACE_FRAMES = 2
      MAX_STRIKES = 8
      RECOVER_FRAMES = 60
      KNOCKBACK_FRAMES = 16
      CHARGES = [50, 52, 54, 56, 58, 60].freeze
      SCREEN = { x: 0..159, y: 0..143 }.freeze
      SPIN_WATCH = 40
      ALIVE = 5
      ADDR = Perception::ADDRESSES
      EC = EntityCensus

      module_function

      def census(run_dir, frames, out: OUT_DIR)
        frames.map do |frame|
          emulator = ModeCensus.state_at(run_dir, frame)
          EC.write(File.join(out, "#{File.basename(run_dir)}-#{frame}.json"), report(emulator, run: File.basename(run_dir), frame:))
        end
      end

      def report(emulator, run:, frame:)
        state = Perception.read(emulator)
        enemies = Entities.read(emulator).select { |entity| entity[:kind].to_s == 'enemy' }
        { run:, frame:, place: [state.room_id, state.map_id], link: { x: state.x, y: state.y, hp: state.hp },
          sword: Items.button_of(state, Items::SWORD), enemies: enemies.map { |entity| probe(emulator, entity) } }
      end

      def probe(emulator, entity)
        reach = EC::VECTORS.keys.to_h { |face| [face, GAPS.select { |gap| on_screen?(entity, face, gap) && strike(emulator, entity, face, gap)[:hit] }] }
        { **entity.slice(:slot, :type, :x, :y), health: slot(emulator, entity, :entity_health), reach:,
          lateral: LATERAL.select { |offset| strike(emulator, entity, :left, LATERAL_GAP, lateral: offset)[:hit] },
          kill: kill(emulator, entity, gap_for(reach)), spin: CHARGES.to_h { |charge| [charge, spin(emulator, entity, charge)] },
          tap_behind: strike(emulator, entity, :left, LATERAL_GAP, behind: true)[:hit] }
      end

      def gap_for(reach) = reach.values.flatten.then { |gaps| gaps.empty? ? LATERAL_GAP : gaps.sort[gaps.size / 2] }

      def slot(emulator, entity, name) = emulator.read(ADDR.fetch(name) + entity[:slot])

      def hit?(emulator, entity, before) = slot(emulator, entity, :entity_status) != ALIVE || slot(emulator, entity, :entity_health) < before

      # Link at gap pixels from the entity on the side he faces it from (or with his back to it), offset sideways by lateral.
      def place(copy, entity, face, gap, lateral: 0, behind: false)
        ex = slot(copy, entity, :entity_x)
        ey = slot(copy, entity, :entity_y)
        EC.place_link(copy, *spot(ex, ey, face, gap, lateral:, behind:))
      end

      def spot(ex, ey, face, gap, lateral: 0, behind: false)
        dx, dy = EC::VECTORS.fetch(face)
        sign = behind ? -1 : 1
        [ex - (sign * dx * gap) + (dy.abs * lateral), ey - (sign * dy * gap) + (dx.abs * lateral)]
      end

      def on_screen?(entity, face, gap, **opts) = spot(entity[:x], entity[:y], face, gap, **opts).then { |x, y| SCREEN[:x].cover?(x) && SCREEN[:y].cover?(y) }

      def face(copy, entity, face, gap, **opts)
        FACE_FRAMES.times do
          place(copy, entity, face, gap, **opts)
          copy.step([face])
        end
        place(copy, entity, face, gap, **opts)
      end

      def strike(emulator, entity, face, gap, lateral: 0, behind: false)
        copy = ModeCensus.copy(emulator)
        face(copy, entity, face, gap, lateral:, behind:)
        before = slot(copy, entity, :entity_health)
        first = WATCH_FRAMES.times.find do |n|
          copy.step(n < STRIKE_FRAMES ? [:a] : [])
          hit?(copy, entity, before)
        end
        { hit: !first.nil?, frame: first }
      end

      def kill(emulator, entity, gap)
        copy = ModeCensus.copy(emulator)
        health = [slot(copy, entity, :entity_health)]
        knockback = []
        strikes = 0
        while strikes < MAX_STRIKES && slot(copy, entity, :entity_status) == ALIVE
          strikes += 1
          face(copy, entity, :left, gap)
          before = slot(copy, entity, :entity_health)
          from = [slot(copy, entity, :entity_x), slot(copy, entity, :entity_y)]
          landed = RECOVER_FRAMES.times.find do |n|
            copy.step(n < STRIKE_FRAMES ? [:a] : [])
            hit?(copy, entity, before)
          end
          next RECOVER_FRAMES.times { copy.step([]) } unless landed

          health << slot(copy, entity, :entity_health)
          KNOCKBACK_FRAMES.times { copy.step([]) }
          knockback << [slot(copy, entity, :entity_x) - from[0], slot(copy, entity, :entity_y) - from[1]] if slot(copy, entity, :entity_status) == ALIVE
          RECOVER_FRAMES.times { copy.step([]) }
        end
        { gap:, strikes:, hits: health.size - 1, health:, killed: slot(copy, entity, :entity_status) != ALIVE, knockback: }
      end

      def spin(emulator, entity, charge)
        copy = ModeCensus.copy(emulator)
        face(copy, entity, :left, LATERAL_GAP, behind: true)
        charge.times do
          place(copy, entity, :left, LATERAL_GAP, behind: true)
          copy.step([:a])
        end
        before = slot(copy, entity, :entity_health)
        !SPIN_WATCH.times.find do
          place(copy, entity, :left, LATERAL_GAP, behind: true)
          copy.step([])
          hit?(copy, entity, before)
        end.nil?
      end
    end
  end
end
