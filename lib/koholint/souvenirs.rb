require 'digest'
require 'json'
require 'koholint'
require 'koholint/archive'
require 'koholint/dialogues'
require 'koholint/summary'
require 'koholint/trace'

module Koholint
  # Souvenirs are read only from sealed bundles, so the committed file is a pure function of runs/.
  module Souvenirs
    DEFAULT_PATH = File.expand_path('../../data/souvenirs.json', __dir__)
    ROOT = File.expand_path('../../runs', __dir__)
    RUN_ID = /\A\d{8}-\d{6}-\h{4}\z/

    module_function

    def build(roots = [ROOT])
      dirs = roots.flat_map { |root| Archive.runs(root) }.select { |dir| Archive.sealed?(dir) }.uniq { |dir| File.basename(dir) }.sort_by { |dir| File.basename(dir) }
      runs = {}
      texts = {}
      dirs.each do |dir|
        id = File.basename(dir)
        parent = Summary.read_json(File.join(dir, 'manifest.json'))['parent']
        fork = parent.is_a?(Hash) ? parent['frame'].to_i : 0
        runs[id] = parent.is_a?(Hash) ? [parent['id'], fork] : nil
        talks = Dialogues.from_events(Trace.read(File.join(dir, Archive::TRACE))).select do |talk|
          talk[:frame].to_i >= fork && talk[:place].is_a?(Array) && talk.dig(:source, :entity).is_a?(Integer) && !Dialogues.key(talk[:text]).empty?
        end
        talks.each do |talk|
          text = Dialogues.clean(talk[:text])
          entry = texts[[talk[:place], talk[:source][:entity], Dialogues.key(text)]] ||= { 'place' => talk[:place], 'entity' => talk[:source][:entity], 'seen' => [] }
          next if entry['seen'].any? { |sighting| sighting['run'] == id }

          entry['seen'] << { 'run' => id, 'frame' => talk[:frame], 'held' => Array(Array(talk[:stamp])[1]), 'cell' => talk[:source].values_at(:row, :col), 'text' => text }
        end
      end
      { 'runs' => runs.sort.to_h, 'texts' => texts.values.sort_by { |entry| [entry['place'], entry['entity'], entry['seen'].first['text']] } }
    end

    def load(path = DEFAULT_PATH) = File.exist?(path) ? validate!(JSON.parse(File.read(path))) : { 'runs' => {}, 'texts' => [] }

    def write(data, path = DEFAULT_PATH)
      validate!(data)
      File.write("#{path}.tmp", "#{JSON.pretty_generate(data)}\n")
      File.rename("#{path}.tmp", path)
    end

    def validate!(data)
      raise ArgumentError, 'souvenirs need runs and texts' unless data['runs'].is_a?(Hash) && data['texts'].is_a?(Array)

      data['texts'].each do |entry|
        valid = entry['place'].is_a?(Array) && entry['place'].size == 2 && entry['entity'].is_a?(Integer) && entry['seen'].is_a?(Array) && !entry['seen'].empty? &&
                entry['seen'].all? do |sighting|
                  sighting['run'].to_s.match?(RUN_ID) && data['runs'].key?(sighting['run']) && sighting['frame'].is_a?(Integer) && sighting['held'].is_a?(Array) &&
                    !sighting['text'].to_s.empty?
                end
        raise ArgumentError, "souvenir lacks a place, entity or sightings with run, frame, held and text: #{entry.inspect[0, 200]}" unless valid
      end
      data
    end

    # A sibling arm of the parent, or any fork of one, is the same experiment: never a souvenir.
    def for_run(data, before:, batch: nil)
      return [] unless before

      data['texts'].filter_map do |entry|
        seen = entry['seen'].select { |sighting| sighting['run'] < before && !(batch && descends?(data['runs'], sighting['run'], batch)) }
        entry.merge('seen' => seen, 'text' => seen.first['text'], 'cell' => seen.first['cell']) unless seen.empty?
      end
    end

    def descends?(runs, run, (root, frame))
      seen = []
      while (link = runs[run]) && !seen.include?(run)
        seen << run
        return true if link[0] == root && link[1] >= frame

        run = link[0]
      end
      false
    end

    # Hashes what play reads (text, cell, items every reader held), never run ids or frames, so bundles archived later leave it alone.
    def digest(entries)
      used = entries.map { |entry| [*entry.values_at('place', 'entity', 'text', 'cell'), entry['seen'].map { |sighting| sighting['held'] }.reduce(:&).sort] }
      Digest::SHA256.hexdigest(JSON.generate(used.sort_by(&:inspect)))
    end

    def record(before:, batch: nil, data: load) = { 'before' => before, 'batch' => batch, 'digest' => digest(for_run(data, before:, batch:)) }

    def for_manifest(manifest, data = load)
      recorded = manifest['souvenirs']
      recorded.is_a?(Hash) ? for_run(data, before: recorded['before'], batch: recorded['batch']) : []
    end

    def digest_of(manifest) = manifest['souvenirs'].is_a?(Hash) ? manifest['souvenirs']['digest'] : false

    def comparable!(manifests)
      digests = manifests.map { |manifest| digest_of(manifest) }.uniq
      raise Error, "runs compared with different souvenirs (digests #{digests.map { |d| d ? d[0, 12] : 'none' }.join(', ')}): fork them alike" if digests.size > 1
    end
  end
end
