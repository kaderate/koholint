# frozen_string_literal: true
# Validates Koholint::Navigator against every reachable cell of legacy/'s oracle grids
# (starting_house and front_yard), not just a short chain from spawn: walks the oracle's own
# 'ok' edges breadth-first so a disagreement never truncates coverage, comparing all four edges
# of every visited cell. 'exit' edges (screen transitions) are reported but excluded from the
# agreement tally and never traversed -- Navigator's move!/probe_all only model ok/blocked within
# a single room, and following one would load a different screen mid-walk.
#
# Run: ruby lib/validation/oracle_grid_check.rb
# Needs a gemboy checkout -- path from $GEMBOY_HOME, defaulting to a sibling directory
# (../gemboy relative to this repo's root), per README.md's "Dependency on gemboy".

gemboy_home = ENV.fetch('GEMBOY_HOME', File.expand_path('../../../gemboy', __dir__))
$LOAD_PATH.unshift(File.join(gemboy_home, 'lib'))
$LOAD_PATH.unshift(File.join(gemboy_home, 'profiling'))
require 'motherboard'
require 'utils' # FakeKeys, needed to resolve a marshaled checkpoint's keys object

require_relative '../../legacy/game_agents/zelda/checkpoint'
require_relative '../navigator'
require 'json'

SCREEN_MAPS = File.expand_path('../../legacy/game_agents/zelda/data/screen_maps', __dir__)

def cell_of(mmu) = [mmu.read(0xFF99) / 16, mmu.read(0xFF98) / 16]

def neighbor(row, col, dir)
  case dir.to_sym
  when :up then [row - 1, col]
  when :down then [row + 1, col]
  when :left then [row, col - 1]
  when :right then [row, col + 1]
  end
end

# Breadth-first over the oracle's own 'ok' edges, starting from `motherboard`'s current cell.
# Only ever moves where the oracle itself claims a path exists, so a Navigator disagreement
# ("oracle says ok, Navigator measures blocked") never strands the walk -- it's recorded and the
# walker simply doesn't enqueue that neighbor, same as if the edge didn't exist.
def walk_oracle_graph(motherboard, by_cell, room_name)
  total = 0
  agree = 0
  disagreements = []
  skipped_exit = []
  visited = {}
  start = cell_of(motherboard.mmu)
  queue = [[motherboard.dump, start[0], start[1]]]

  until queue.empty?
    snapshot, row, col = queue.shift
    key = [row, col]
    next if visited[key]

    visited[key] = true
    oracle_edges = by_cell[key] || {}
    edges, = Koholint::Navigator.probe_all(Motherboard.load(snapshot))
    puts format('[%s] cell (%d,%d): oracle=%p predicted=%p', room_name, row, col, oracle_edges, edges)

    oracle_edges.each do |dir, label|
      predicted = edges[dir.to_sym] == :ok ? 'ok' : 'blocked'
      if label == 'exit'
        skipped_exit << { room: room_name, row:, col:, dir:, oracle: label, predicted: }
        next
      end
      total += 1
      if predicted == label
        agree += 1
      else
        disagreements << { room: room_name, row:, col:, dir:, oracle: label, predicted: }
      end
    end

    oracle_edges.each do |dir, label|
      next unless label == 'ok'

      nrow, ncol = neighbor(row, col, dir)
      next if visited[[nrow, ncol]]

      walker = Motherboard.load(snapshot)
      result = Koholint::Navigator.move!(walker, dir.to_sym)
      next unless result == :ok # disagreement already recorded above; don't traverse a blocked edge

      # move! commits at COMMIT_THRESHOLD (half a tile), not a full tile -- cell_of right after a
      # successful move! often still reports the departure cell. Keep tapping the same direction
      # until the cell actually changes, bounded by MAX_TAPS, so the queue advances on real cells.
      arrived = cell_of(walker.mmu)
      extra_taps = 0
      while arrived == [row, col] && extra_taps < Koholint::Navigator::MAX_TAPS
        Koholint::Navigator.tap(walker, dir.to_sym)
        arrived = cell_of(walker.mmu)
        extra_taps += 1
      end
      next if arrived == [row, col] # never actually crossed into a new cell -- not usable for traversal

      queue << [walker.dump, arrived[0], arrived[1]]
    end
  end

  { total:, agree:, disagreements:, skipped_exit:, visited_count: visited.size }
end

def load_legacy_checkpoint(path)
  cpu, ppu, apu, mmu, = Zelda::Checkpoint.load(path)
  motherboard = Motherboard.new(cpu, ppu, apu, mmu, mmu.dma, mmu.model)
  # Checkpointed right after interact() with no settle -- see Navigator.settle!'s comment.
  Koholint::Navigator.settle!(motherboard)
end

def load_navigator_dump(path)
  motherboard = Motherboard.load(File.binread(path))
  Koholint::Navigator.settle!(motherboard) # cheap and idempotent-ish; safety net, not assumed unneeded
end

rooms = {
  'starting_house' => {
    oracle: File.join(SCREEN_MAPS, 'starting_house.json'),
    motherboard: -> { load_legacy_checkpoint('/tmp/zelda_checkpoints/after_shield_interior.marshal') }
  },
  'front_yard' => {
    oracle: File.join(SCREEN_MAPS, 'overworld_front_yard.json'),
    motherboard: -> { load_navigator_dump('/tmp/zelda_checkpoints/front_yard_navigator.dump') }
  }
}

results = rooms.map do |room_name, cfg|
  oracle = JSON.parse(File.read(cfg[:oracle]))
  by_cell = oracle['cells'].to_h { |c| [[c['row'], c['col']], c['edges']] }
  motherboard = cfg[:motherboard].call
  stats = walk_oracle_graph(motherboard, by_cell, room_name)
  [room_name, stats.merge(oracle_cell_count: oracle['cells'].size)]
end

grand_total = results.sum { |_, r| r[:total] }
grand_agree = results.sum { |_, r| r[:agree] }

puts "\n=== per-room summary ==="
results.each do |room_name, r|
  puts format('%s: %d/%d agreement, %d/%d oracle cells visited, %d exit edges skipped',
               room_name, r[:agree], r[:total], r[:visited_count], r[:oracle_cell_count], r[:skipped_exit].size)
end
puts format("\n=== combined: %d/%d agreement ===", grand_agree, grand_total)
results.each do |_, r|
  r[:disagreements].each { |d| puts "  DISAGREE: #{d}" }
end
