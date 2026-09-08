# frozen_string_literal: true
# Cross-checks Koholint::Terrain (D8: VRAM tilemap reads) against the same oracle grids
# lib/validation/oracle_grid_check.rb uses, with the same breadth-first full-coverage walk. Unlike
# that script (which live-probes all 4 directions of every cell with Navigator), this one predicts
# an edge by reading the neighbor cell's BG tile signature, live-probing only the first time a new
# signature is seen (Terrain::RoomClassifier caches the rest) -- the point is to measure how few
# live probes D8's approach actually needs once seeded, not just its agreement rate.
#
# Run: ruby lib/validation/terrain_predictor_check.rb
# Needs a gemboy checkout -- path from $GEMBOY_HOME, defaulting to a sibling directory.

gemboy_home = ENV.fetch('GEMBOY_HOME', File.expand_path('../../../gemboy', __dir__))
$LOAD_PATH.unshift(File.join(gemboy_home, 'lib'))
$LOAD_PATH.unshift(File.join(gemboy_home, 'profiling'))
require 'motherboard'
require 'utils'

require_relative '../../legacy/game_agents/zelda/checkpoint'
require_relative '../navigator'
require_relative '../terrain'
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

def walk_with_terrain(motherboard, by_cell, room_name)
  total = 0
  agree = 0
  disagreements = []
  skipped_exit = []
  visited = {}
  classifier = Koholint::Terrain::RoomClassifier.new
  start = cell_of(motherboard.mmu)
  queue = [[motherboard.dump, start[0], start[1]]]

  until queue.empty?
    snapshot, row, col = queue.shift
    key = [row, col]
    next if visited[key]

    visited[key] = true
    mb = Motherboard.load(snapshot)
    classifier.verdict_at(mb.mmu, row, col) { :walkable } # Link is standing here right now -- free sample

    oracle_edges = by_cell[key] || {}
    predicted = {}
    oracle_edges.each do |dir, label|
      nrow, ncol = neighbor(row, col, dir)
      verdict = classifier.verdict_at(mb.mmu, nrow, ncol) do
        walker = Motherboard.load(snapshot)
        Koholint::Navigator.move!(walker, dir.to_sym) == :ok ? :walkable : :blocked
      end
      predicted[dir] = verdict == :walkable ? 'ok' : 'blocked'

      if label == 'exit'
        skipped_exit << { room: room_name, row:, col:, dir:, oracle: label, predicted: predicted[dir] }
        next
      end
      total += 1
      if predicted[dir] == label
        agree += 1
      else
        disagreements << { room: room_name, row:, col:, dir:, oracle: label, predicted: predicted[dir] }
      end
    end
    puts format('[%s] cell (%d,%d): oracle=%p predicted=%p', room_name, row, col, oracle_edges, predicted)

    oracle_edges.each do |dir, label|
      next unless label == 'ok'

      nrow, ncol = neighbor(row, col, dir)
      next if visited[[nrow, ncol]]

      walker = Motherboard.load(snapshot)
      result = Koholint::Navigator.move!(walker, dir.to_sym)
      next unless result == :ok

      arrived = cell_of(walker.mmu)
      extra_taps = 0
      while arrived == [row, col] && extra_taps < Koholint::Navigator::MAX_TAPS
        Koholint::Navigator.tap(walker, dir.to_sym)
        arrived = cell_of(walker.mmu)
        extra_taps += 1
      end
      next if arrived == [row, col]

      queue << [walker.dump, arrived[0], arrived[1]]
    end
  end

  { total:, agree:, disagreements:, skipped_exit:, visited_count: visited.size, probes: classifier.probes }
end

def load_legacy_checkpoint(path)
  cpu, ppu, apu, mmu, = Zelda::Checkpoint.load(path)
  motherboard = Motherboard.new(cpu, ppu, apu, mmu, mmu.dma, mmu.model)
  Koholint::Navigator.settle!(motherboard)
end

def load_navigator_dump(path) = Motherboard.load(File.binread(path))

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
  stats = walk_with_terrain(motherboard, by_cell, room_name)
  [room_name, stats.merge(oracle_cell_count: oracle['cells'].size)]
end

grand_total = results.sum { |_, r| r[:total] }
grand_agree = results.sum { |_, r| r[:agree] }
grand_probes = results.sum { |_, r| r[:probes] }

puts "\n=== per-room summary ==="
results.each do |room_name, r|
  puts format('%s: %d/%d agreement, %d/%d oracle cells visited, %d exit edges skipped, %d live probes used',
               room_name, r[:agree], r[:total], r[:visited_count], r[:oracle_cell_count], r[:skipped_exit].size, r[:probes])
end
puts format("\n=== combined: %d/%d agreement, %d total live probes (vs 173 edges x up to 8 taps for the pure live-probe sweep) ===",
             grand_agree, grand_total, grand_probes)
results.each do |_, r|
  r[:disagreements].each { |d| puts "  DISAGREE: #{d}" }
end
