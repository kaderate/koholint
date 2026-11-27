require 'koholint/entities'
require 'koholint/footing'
require 'koholint/geometry'
require 'koholint/items'
require 'koholint/perception'
require 'koholint/skills/clearing'

module Koholint
  module Skills
    class Execution
      HARD_CAP = 400
      CENTRING_FRAMES = 16
      CENTRING_STILL = 3
      EDGE_FRAMES = 120
      PUSH_MARGIN = 8
      PUSH_SETTLE = 48
      GIVE_WAY_SLACK = 8
      STEP_OFF_PIXELS = 24
      STILL_STEPS = 2
      HOLE_LOOK = 2

      attr_reader :frames, :stopped_by
      attr_writer :triggers, :footing, :footing_grid

      def initialize(skill:, params:, state:)
        @skill = skill
        @params = params
        @start = state
        @last = state
        @frames = 0
        @stopped_by = nil
        @centring = nil
        @blocked_at = nil
        @triggers = nil
        @last_input = nil
        @trigger_input = nil
        @exit = nil
        @walked_in = false
        @room_objects = nil
        @push = nil
        @pushed = nil
        @stepping = nil
        @walled_off = []
      end

      def next_input(state)
        @last = state
        @trigger_input = @last_input if state.dialog_open? && !@start.dialog_open? && @trigger_input.nil?
        return nil if @stopped_by

        @walked_in ||= state.door_walk_in?
        landed_push
        buttons = if @frames >= hard_cap then finish(:frame_cap)
                  elsif state.scene? && !@start.scene? then finish(:scene)
                  elsif @pushed then settle_push
                  elsif waits_through_doors? && door_walk?(state) then []
                  elsif (off = floor_step(state)) then off
                  elsif @centring then centre(state)
                  else input_for(state)
                  end
        buttons = finish(:hole) if buttons && !off && walking?(state) && into_hole?(state, buttons)
        watch_push(state, buttons)
        note_exit(state, buttons)
        @frames += 1 if buttons
        @last_input = buttons if buttons
        buttons
      end

      def abort(reason)
        @frames -= 1
        @stopped_by = reason
      end

      def result(state = @last)
        aligned, offset = alignment(state)
        { skill: @skill, params: @params, frames: @frames, from: place(@start), to: place(state),
          moved_cells: moved_cells(state), room_changed: @start.place != state.place, hp_delta: state.health - @start.health,
          dialog_before: @start.dialog_open?, dialog_after: state.dialog_open?, stopped_by: @stopped_by,
          aligned:, offset:, blocked_at: @blocked_at, trigger_input: trigger_input }.tap do |r|
          r[:exit] = @walked_in ? @exit.merge(walk_in: true) : @exit if r[:room_changed] && @exit
          r[:pushed] = @pushed.slice(:row, :col, :direction) if @pushed
        end
      end

      private

      # Link stands still while a door walks him in and the next place loads; a moving skill waits through it instead of reading it as blocked.
      def door_walk?(state) = state.loading? || state.door_walk_in?

      def waits_through_doors? = false

      def note_exit(state, buttons)
        direction = (Array(buttons) & Geometry::DIRECTIONS).first
        row, col = state.cell
        @exit = { row:, col:, direction: } if direction && row && state.place == @start.place
      end

      # Stationary enemies the raised shield pushes aside (sea urchins) sit on cells their sprites make look like objects; only with the shield held.
      # Cells of objects a published capability clears are passable at the same last-resort cost, and so is a stone entered in a direction it slides.
      def pushable_of(context, stones: true)
        shield = Array(context[:held]).include?(Items::SHIELD)
        urchins = context[:entities] && shield ? -> { Array(context[:entities].call).select { |e| e[:kind].to_s == 'enemy' && e[:moves] == false && e[:cell] }.map { |e| e[:cell] } } : nil
        stones = context[:room_objects] && context[:grid] && stones ? -> { stone_pushes(context[:room_objects].call, context[:grid]) } : nil
        clearing = Clearing.of(context)
        sources = [urchins, stones, (-> { clearing.cells.keys } if clearing)].compact
        -> { sources.flat_map(&:call).uniq } if sources.any?
      end

      # [stone cell, direction] for each catalogued stone and each direction whose far cell is floor.
      def stone_pushes(objects, grid)
        catalogue = Entities.object_catalogue
        objects.each_with_index.flat_map do |row, r|
          row.each_index.select { |c| catalogue.dig(row[c], :push) }.flat_map do |c|
            Geometry::DIRECTIONS.filter_map do |direction|
              far = ahead_of([r, c], direction)
              [[r, c], direction] if far && lands?(objects, grid, far, direction)
            end
          end
        end
      end

      def lands?(objects, grid, cell, direction) = !Entities.object_catalogue.key?(objects.dig(*cell)) && !grid.static_sprite(*cell) && grid.passable(*cell, direction) == :yes

      def ahead_of(cell, direction) = cell && Geometry.step(cell, direction)

      # A stone ahead slides only after a measured hold, so a moving skill keeps pressing that long before it reads blocked.
      def still_limit(state, direction, base)
        ahead = @room_objects && ahead_of(state.cell, direction) or return base
        hold = Entities.object_catalogue.dig(@room_objects.call.dig(*ahead), :push)
        hold ? [base, hold + PUSH_MARGIN].max : base
      end

      # A stone pressed on the last frame that has left its cell is sliding: Link waits for it to land, then the skill stops so the next one reads the changed screen.
      def landed_push
        return unless @push && !@pushed

        objects = @room_objects.call
        return if objects.dig(*@push[:cell]) == @push[:object]

        far = ahead_of(@push[:cell], @push[:direction])
        @pushed = { row: @push[:cell][0], col: @push[:cell][1], direction: @push[:direction], far:, before: far && objects.dig(*far), frames: 0 }
      end

      def watch_push(state, buttons)
        return if @pushed || !@room_objects

        direction = (Array(buttons) & Geometry::DIRECTIONS).first
        ahead = direction && ahead_of(state.cell, direction)
        object = ahead && @room_objects.call.dig(*ahead)
        @push = Entities.object_catalogue.dig(object, :push) ? { cell: ahead, object:, direction: } : nil
      end

      def settle_push
        @pushed[:frames] += 1
        landed = @pushed[:far].nil? || @room_objects.call.dig(*@pushed[:far]) != @pushed[:before]
        return [] unless landed || @pushed[:frames] >= PUSH_SETTLE

        @stopped_by = :pushed
        nil
      end

      # Floor reflexes act only while directions walk Link, and never on a skill's first frame, which some skills set themselves up on.
      def walking?(state) = state.phase(booted: true) == :playing

      def floor_step(state) = @frames.positive? && walking?(state) && step_off(state)

      # No skill keeps Link on floor that gives way: when the shortest step that takes his foot point onto another floor cell, where the game's
      # count starts over, would just fit in the frames left, he takes it to the end.
      def step_off(state)
        under = @footing&.under(state) or return
        if under.empty?
          @stepping = nil
          @walled_off = []
          return
        end
        return [@stepping[:direction]] if stepping_on?(state)

        cells = under.map { |at| at[:cell] }
        best = (Geometry::DIRECTIONS - @walled_off).filter_map { |d| (pixels = clearance(state, cells, d)) && [pixels, d] }.min_by(&:first)
        return unless best && under.any? { |at| at[:left] <= best[0] + GIVE_WAY_SLACK }

        @stepping = { direction: best[1], cells:, frames: 0, at: [state.x, state.y], still: 0 }
        [best[1]]
      end

      # A step off that leaves Link where he was for STILL_STEPS frames runs into something the grid did not show; another way is tried.
      def stepping_on?(state)
        return @stepping = false unless @stepping && Footing.feet(state.x, state.y).intersect?(@stepping[:cells]) && (@stepping[:frames] += 1) <= STEP_OFF_PIXELS

        @stepping[:still] = [state.x, state.y] == @stepping[:at] ? @stepping[:still] + 1 : 0
        @stepping[:at] = [state.x, state.y]
        return true if @stepping[:still] < STILL_STEPS

        @walled_off = @walled_off | [@stepping[:direction]]
        @stepping = nil
        false
      end

      def clearance(state, cells, direction)
        dr, dc = Geometry::DELTAS.fetch(direction)
        (1..STEP_OFF_PIXELS).each do |pixels|
          feet = Footing.feet(state.x + (dc * pixels), state.y + (dr * pixels))
          next if feet.intersect?(cells)

          return feet.all? { |cell| safe_floor?(state, cell) } ? pixels : nil
        end
        nil
      end

      # A hole that opened after the skill planned is missing from its grid: the step that would put Link's foot point in it ends the skill.
      def into_hole?(state, buttons)
        direction = (buttons & Geometry::DIRECTIONS).first
        return false unless @footing && direction && state.x

        dr, dc = Geometry::DELTAS.fetch(direction)
        (Footing.feet(state.x + (dc * HOLE_LOOK), state.y + (dr * HOLE_LOOK)) - Footing.feet(state.x, state.y)).any? { |cell| @footing.hole?(state, cell) }
      end

      def safe_floor?(state, cell)
        return false unless @footing_grid

        Geometry::DIRECTIONS.any? { |way| @footing_grid.passable(*cell, way) == :yes } && !@footing.hole?(state, cell) && !(@footing_grid.respond_to?(:hole?) && @footing_grid.hole?(*cell))
      end

      # At one heart or less, every enemy contact zone grows by a cell and is never crossed, until the policy lifts it (context[:unguarded]).
      def low_health?(context) = !context[:unguarded] && @start.health.to_i <= Perception::HP_PER_HEART

      def danger_of(context)
        margin = Entities::DANGER_MARGIN + (low_health?(context) ? Geometry::CELL : 0)
        context[:entities] && -> { Entities.danger_cells(Array(context[:entities].call), margin:) }
      end

      def contact_of(context) = low_health?(context) && context[:entities] ? -> { Entities.danger_cells(Array(context[:entities].call)) } : nil

      # A step heads away when no enemy within a cell of its touch lies ahead of it, measured from where Link stands when the step starts in his cell.
      def away_of(context)
        context[:entities] && lambda do |cell, target|
          x, y = cell == @last.cell ? [@last.x, @last.y] : Geometry.center_of(*cell)
          dr = target[0] - cell[0]
          dc = target[1] - cell[1]
          Navigation::Threat.of(Array(context[:entities].call)).none? do |threat|
            Navigation::Threat.distance(threat, x, y) <= threat[:reach] + Geometry::CELL && ((threat[:x] - x) * dc) + ((threat[:y] - y) * dr) > 0
          end
        end
      end

      def trigger_input
        return nil unless @stopped_by == :dialogue && !@start.dialog_open?

        directions = Array(@trigger_input) & Geometry::DIRECTIONS
        directions.empty? ? nil : directions
      end

      def forbidden_at(state)
        return [] unless @triggers && state.cell

        @triggers.forbidden(state.place, state.cell)
      end

      def finish(reason)
        @blocked_at = blocked_at_for(@last) if reason == :blocked
        return centre_after(reason) if centres? && %i[done blocked].include?(reason)

        @stopped_by = reason
        nil
      end

      def centres? = false

      def hard_cap = HARD_CAP

      def blocked_direction = nil

      def blocked_at_for(state)
        row, col = state.cell
        return nil unless row && blocked_direction

        { row:, col:, direction: blocked_direction }
      end

      def centre_after(reason)
        @centring = { reason:, frames: 0 }
        centre(@last)
      end

      def centre(state)
        reason = @centring[:reason]
        event = if state.place != @start.place then :room_change
                elsif state.health < @start.health then :damage
                elsif state.dialog_open? && !@start.dialog_open? then :dialogue
                end
        # Off the grid is a border crossing whose room id changes only after the scroll.
        return [] if !event && state.cell.nil? && (@centring[:edge] = @centring[:edge].to_i + 1) <= EDGE_FRAMES

        position = [state.x, state.y]
        @centring[:still] = position == @centring[:position] ? @centring[:still].to_i + 1 : 0
        @centring[:position] = position
        stuck = @centring[:frames] >= CENTRING_FRAMES || @centring[:still] >= CENTRING_STILL
        buttons = toward_centre(state, avoid: (blocked_direction if reason == :blocked)) unless event || stuck
        @centring[:frames] += 1 if buttons
        return buttons if buttons

        @centring = nil
        @stopped_by = event || reason
        nil
      end

      def toward_centre(state, avoid:)
        return nil unless state.cell

        dx, dy = Geometry.offset(state.x, state.y, state.cell)
        wanted = []
        wanted << (dx.positive? ? :left : :right) unless Geometry.x_aligned?(dx)
        wanted << (dy.positive? ? :up : :down) if dy.abs > Geometry::ALIGN_TOLERANCE
        blocked = forbidden_at(state)
        direction = wanted.find { |d| d != avoid && !blocked.include?(d) }
        [direction] if direction
      end

      def alignment(state)
        cell = state.cell
        return [false, { dx: nil, dy: nil }] unless cell

        dx, dy = Geometry.offset(state.x, state.y, cell)
        [Geometry.aligned?(state.x, state.y, cell), { dx:, dy: }]
      end


      def moved_cells(state)
        from = @start.cell
        to = state.cell
        return from.zip(to).sum { |a, b| (a - b).abs } if from && to
        return 0 unless @start.x && @start.y && state.x && state.y

        ((@start.x - state.x).abs + (@start.y - state.y).abs + 8) / 16
      end

      def place(state)
        row, col = state.cell
        { room: state.room_id, map: state.map_id, x: state.x, y: state.y, row:, col: }
      end
    end
  end
end
