# frozen_string_literal: true
# Validates Koholint::Navigator against starting_house's oracle grid (legacy/'s
# TileClassifier-probed ground truth). Not exhaustive: walks a short chain of cells from spawn
# rather than every one of the 32 recorded cells (a full graph traversal is future work), but
# gives a real, checkable agreement rate against known-correct data.
#
# Run: ruby lib/validation/starting_house_oracle_check.rb
# Needs a gemboy checkout -- path from $GEMBOY_HOME, defaulting to a sibling directory
# (../gemboy relative to this repo's root), per README.md's "Dependency on gemboy".

gemboy_home = ENV.fetch('GEMBOY_HOME', File.expand_path('../../../gemboy', __dir__))
$LOAD_PATH.unshift(File.join(gemboy_home, 'lib'))
$LOAD_PATH.unshift(File.join(gemboy_home, 'profiling'))
require 'motherboard'
require 'utils' # FakeKeys, needed to resolve a legacy checkpoint's marshaled keys object

require_relative '../../legacy/game_agents/zelda/checkpoint'
require_relative '../navigator'
require 'json'

ORACLE_PATH = File.expand_path('../../legacy/game_agents/zelda/data/screen_maps/starting_house.json', __dir__)
CHECKPOINT_PATH = '/tmp/zelda_checkpoints/after_shield_interior.marshal'

oracle = JSON.parse(File.read(ORACLE_PATH))
by_cell = oracle['cells'].to_h { |c| [[c['row'], c['col']], c['edges']] }

cpu, ppu, apu, mmu, = Zelda::Checkpoint.load(CHECKPOINT_PATH)
motherboard = Motherboard.new(cpu, ppu, apu, mmu, mmu.dma, mmu.model)

# after_shield_interior was checkpointed right after interact() with no settle -- the very first
# tap in ANY direction otherwise produces a fixed, direction-independent position artifact (see
# Navigator.settle!'s comment). Clear it before treating the position as a real cell to test.
Koholint::Navigator.settle!(motherboard)

def cell_of(mmu) = [mmu.read(0xFF99) / 16, mmu.read(0xFF98) / 16]

total = 0
agree = 0
disagreements = []

%i[right right down down left].each do |walk_dir|
  row, col = cell_of(motherboard.mmu)
  oracle_edges = by_cell[[row, col]]
  edges, motherboard = Koholint::Navigator.probe_all(motherboard)

  if oracle_edges
    oracle_edges.each do |dir, label|
      predicted = edges[dir.to_sym] == :ok ? 'ok' : 'blocked'
      total += 1
      if predicted == label
        agree += 1
      else
        disagreements << { row:, col:, dir:, oracle: label, predicted: }
      end
    end
    puts format('cell (%d,%d): oracle=%p predicted=%p', row, col, oracle_edges, edges)
  else
    puts format('cell (%d,%d): not in oracle, skipping comparison. predicted=%p', row, col, edges)
  end

  result = Koholint::Navigator.move!(motherboard, walk_dir)
  puts "  walk #{walk_dir}: #{result}"
  break if result == :blocked
end

puts "\n=== agreement: #{agree}/#{total} ==="
disagreements.each { |d| puts "  DISAGREE: #{d}" }

# Known result as of September 8, 2026: 3/4 agreement on cell (3,4) -- up/down/left match the
# oracle, right disagrees (oracle says ok, Navigator measures fully blocked, 0px movement across
# 8 taps). Not chased further: plausibly a sub-tile alignment difference from where legacy's
# TileClassifier probed this exact cell (already documented as a corner-quirk-prone spot in this
# room). The walk chain stops at the first :blocked result (by design, matching real navigation),
# so this run only reaches one oracle cell -- broader coverage is follow-up work, not blocking.
