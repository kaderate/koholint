# frozen_string_literal: true
# Replaces the guessed-column WIP (4 abandoned attempts, all on stale pre-SCX/SCY-fix terrain
# reads -- see git history) with a real walkability map of villager_screen (177/0), built via
# Terrain::RoomClassifier (D8): a genuinely new BG-tile signature costs one live probe, cached
# afterwards. Room identity is checked after every real move regardless of its :ok/:blocked
# verdict -- not just on a classifier cache miss -- because a shared signature can otherwise mask
# a door behind an already-cached "blocked" wall (confirmed live this session: the room's real
# east exit to 178/0 was missed by a cache-respecting sweep alone, only surfacing once every edge's
# real outcome was checked; see NEXT.md).
#
# Session 4 (PLAN.md) re-confirmation, September 9 2026: REFUTED, not inconclusive. Full sweep of
# the 83 cells reachable from villager_screen's spawn (52 walkable, 31 blocked, every edge's real
# move outcome checked) finds only the two already-known exits -- north to 161/0, east to 178/0 --
# and no third door into the building. See data/ram_registry.json's world_topology.room177_exits
# for the finding and NEXT.md's anti-patch note for what this rules out. Kept runnable as a
# diagnostic: it raises on completion instead of silently reporting success.
#
# Run: ruby lib/validation/checkpoint_house2_interior.rb

require_relative 'checkpoint_support'

include Koholint::CheckpointSupport

VILLAGER_SCREEN = [177, 0].freeze
KNOWN_EXITS = [[161, 0], [178, 0]].freeze
MAX_VISITED = 300 # safety net, well above the ~83 cells this room actually has

def neighbor(row, col, dir)
  case dir
  when :up then [row - 1, col]
  when :down then [row + 1, col]
  when :left then [row, col - 1]
  when :right then [row, col + 1]
  end
end

def cell_of(mmu) = [mmu.read(0xFF99) / 16, mmu.read(0xFF98) / 16]

# Flood-fills the room from `motherboard`'s current cell. Returns [visited, blocked, doors]:
# visited/blocked are cell => snapshot-dump-or-true; doors is every (row, col, dir) whose real
# move landed in a room other than `start_room`, whatever its :ok/:blocked verdict said.
def map_room(motherboard, start_room)
  classifier = Koholint::Terrain::RoomClassifier.new
  visited = {}
  blocked = {}
  doors = []
  queue = [[motherboard.dump, *cell_of(motherboard.mmu)]]

  until queue.empty? || visited.size >= MAX_VISITED
    snapshot, row, col = queue.shift
    key = [row, col]
    next if visited[key]

    visited[key] = snapshot
    mb = Motherboard.load(snapshot)
    classifier.verdict_at(mb.mmu, row, col) { :walkable } # Link stands here for real -- free sample

    %i[up down left right].each do |dir|
      nkey = neighbor(row, col, dir)
      next if visited[nkey] || blocked[nkey]

      classifier.verdict_at(mb.mmu, *nkey) do
        walker = Motherboard.load(snapshot)
        result = Koholint::Navigator.move!(walker, dir)
        room = room_of(walker)
        doors << { row:, col:, dir:, room:, dump: walker.dump } if room != start_room
        result == :ok ? :walkable : :blocked
      end

      # Confirm for real regardless of the (possibly cached) verdict above: a signature seen as
      # "blocked" elsewhere in the room isn't a per-cell guarantee, and this is the only way to
      # find a door hidden behind a wall's own tile signature.
      walker = Motherboard.load(snapshot)
      result = Koholint::Navigator.move!(walker, dir)
      room = room_of(walker)
      if room != start_room
        doors << { row:, col:, dir:, room:, dump: walker.dump }
        next
      end

      unless result == :ok
        blocked[nkey] = true
        next
      end

      arrived = cell_of(walker.mmu)
      extra_taps = 0
      while arrived == key && extra_taps < Koholint::Navigator::MAX_TAPS
        Koholint::Navigator.tap(walker, dir)
        arrived = cell_of(walker.mmu)
        extra_taps += 1
      end
      if arrived == key
        blocked[nkey] = true
        next
      end

      room = room_of(walker)
      if room != start_room
        doors << { row:, col:, dir:, room:, dump: walker.dump }
        next
      end

      queue << [walker.dump, *arrived] unless visited[arrived]
    end
  end

  [visited, blocked, doors]
end

if File.exist?(Koholint::CheckpointSupport.checkpoint_path('house2_interior'))
  motherboard = load_checkpoint('house2_interior')
else
  motherboard = load_checkpoint('villager_screen')
  start_room = room_of(motherboard)
  raise "expected to start in villager_screen #{VILLAGER_SCREEN.inspect}, got #{start_room.inspect}" unless start_room == VILLAGER_SCREEN

  visited, blocked, doors = map_room(motherboard, start_room)
  puts "walkability map: #{visited.size} walkable cells, #{blocked.size} blocked cells"
  doors.each { |d| puts "  door: (#{d[:row]},#{d[:col]}) #{d[:dir]} -> #{d[:room].inspect}" }

  new_room_doors = doors.reject { |d| KNOWN_EXITS.include?(d[:room]) }
  if new_room_doors.empty?
    raise "no house2_interior door found -- #{visited.size} walkable / #{blocked.size} blocked cells mapped, " \
          "only the known exits (#{KNOWN_EXITS.map(&:inspect).join(', ')}) reached. " \
          'See data/ram_registry.json world_topology.room177_exits and NEXT.md.'
  end

  door = new_room_doors.first
  motherboard = Motherboard.load(door[:dump])
  wait_frames(motherboard, 20)
  save_checkpoint('house2_interior', motherboard)
end

room = room_of(motherboard)
puts "room_id/map_id: #{room.inspect}"
raise "still in villager_screen -- door never triggered" if room == VILLAGER_SCREEN

png_path = File.join(Koholint::CheckpointSupport::CHECKPOINT_DIR, 'lib_house2_interior.png')
motherboard.ppu.export_framebuffer_png(png_path)
puts "framebuffer: #{png_path}"
puts 'OK: house2_interior reached.'
