require 'json'
require 'set'
require 'koholint/items'
require 'koholint/trace'

module Koholint
  # An item gain measures where an item comes from. `check-pickups` lists every gained item with the runs, places and held sets that
  # carry it and the lineage each run measures from, then says which confidence data/items.json may claim: observed inside one
  # lineage, verified from two, since two runs of one parent measure the same thing once.
  module PickupCheck
    module_function

    def check(dirs, out:, data: Items::DEFAULT_PATH)
      gains = dirs.flat_map { |dir| gains_of(dir) }
      claims = claims(data)
      wrong = 0
      gains.group_by { |gain| gain[:item] }.sort.each do |item, found|
        found.each { |gain| out.puts line(gain, item) }
        lineages = found.map { |gain| gain[:lineage] }.uniq
        status = status_of(found)
        out.puts "item #{item} (#{Items.name(item)}): #{found.size} gain(s) in #{found.map { |gain| gain[:run] }.uniq.size} run(s), " \
                 "#{lineages.size} lineage(s) (#{lineages.sort.join(', ')}) holding #{found.map { |gain| gain[:held] }.uniq.inspect}, " \
                 "so the data may claim #{status} with verified_count #{lineages.size}"
        claim = claims[item] or next
        next unless overstated?(claim, status:, checks: lineages.size)

        wrong += 1
        out.puts "MISMATCH item #{item}: data claims #{claim['confidence']} with verified_count #{claim['verified_count']}, these runs measure #{status} from #{lineages.size} lineage(s)"
      end
      out.puts "#{gains.map { |gain| gain[:item] }.uniq.size} item(s) gained across #{dirs.size} run(s)"
      wrong.zero? ? 0 : 1
    end

    def line(gain, item)
      "#{gain[:run]} (tag #{gain[:tag]}) place #{Array(gain[:place]).join('-')} frame #{gain[:frame]}: item #{item} #{Items.name(item)} held #{gain[:held].inspect}"
    end

    def gains_of(dir)
      manifest = JSON.parse(File.read(File.join(dir, 'manifest.json')))
      lineage = lineage_of(dir, manifest.dig('parent', 'id'))
      Trace.read(File.join(dir, 'trace.jsonl')).select { |event| event['type'] == 'item_gained' }.map do |event|
        { run: File.basename(dir), tag: manifest['tag'], item: event['item'], place: event['place'], frame: event['frame'], held: event['held'], lineage: }
      end
    end

    # The oldest run this one measures from: a fork's parent run, a resumed run's checkpoint, else the run itself.
    def lineage_of(dir, id)
      return File.basename(File.expand_path(dir)) unless id

      root = File.dirname(File.expand_path(dir))
      seen = Set.new
      while id && seen.add?(id)
        path = Dir.glob(File.join(root, '**', id, 'manifest.json')).first or return id
        parent = JSON.parse(File.read(path)).dig('parent', 'id') or return id
        id = parent
      end
      id
    end

    def status_of(found) = found.map { |gain| gain[:lineage] }.uniq.size >= 2 && found.map { |gain| gain[:held] }.uniq.size == 1 ? 'verified' : 'observed'

    def claims(data) = Items.catalogue(data).filter_map { |id, entry| [id, entry['pickups']] if entry['pickups'] }.to_h

    def overstated?(claim, status:, checks:)
      (claim['confidence'] == 'verified' && status != 'verified') || claim['verified_count'].to_i > checks
    end
  end
end
