require 'digest'
require 'json'
require 'koholint'
require 'koholint/archive'
require 'koholint/dialogues'
require 'koholint/summary'
require 'koholint/trace'

module Koholint
  # What people said to other branches, read only from the archived bundles: each run counts from its fork frame and keeps its first
  # sighting of a text with what the reader held. A run uses the texts read in runs created before its fork point (its parent) and
  # outside its parent's batch of sibling forks; they are souvenirs, never texts the run read.
  module Souvenirs
    DEFAULT_PATH = File.expand_path('../../data/souvenirs.json', __dir__)
    ROOT = File.expand_path('../../runs', __dir__)
    RUN_ID = /\A\d{8}-\d{6}-\h{4}\z/

    module_function

    def build(roots = [ROOT])
      dirs = roots.flat_map { |root| Archive.runs(root) }.uniq { |dir| File.basename(dir) }.sort_by { |dir| File.basename(dir) }
      runs = {}
      texts = {}
      dirs.each do |dir|
        id = File.basename(dir)
        parent = Summary.read_json(File.join(dir, 'manifest.json'))['parent']
        fork = parent.is_a?(Hash) ? parent['frame'].to_i : 0
        talks = Dialogues.from_events(Trace.read(File.join(dir, Archive::TRACE))).select do |talk|
          talk[:frame].to_i >= fork && talk[:place].is_a?(Array) && talk.dig(:source, :entity).is_a?(Integer) && !Dialogues.key(talk[:text]).empty?
        end
        talks.each do |talk|
          text = Dialogues.clean(talk[:text])
          entry = texts[[talk[:place], talk[:source][:entity], Dialogues.key(text)]] ||=
            { 'place' => talk[:place], 'entity' => talk[:source][:entity], 'cell' => talk[:source].values_at(:row, :col), 'text' => text, 'seen' => [] }
          next if entry['seen'].any? { |sighting| sighting['run'] == id }

          entry['seen'] << { 'run' => id, 'frame' => talk[:frame], 'held' => Array(Array(talk[:stamp])[1]) }
          runs[id] = parent.is_a?(Hash) ? [parent['id'], fork] : nil
        end
      end
      { 'runs' => runs.sort.to_h, 'texts' => texts.values.sort_by { |entry| [entry['place'], entry['entity'], entry['text']] } }
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
        valid = entry['place'].is_a?(Array) && entry['place'].size == 2 && entry['entity'].is_a?(Integer) && !entry['text'].to_s.empty? &&
                entry['seen'].is_a?(Array) && !entry['seen'].empty? &&
                entry['seen'].all? { |sighting| sighting['run'].to_s.match?(RUN_ID) && data['runs'].key?(sighting['run']) && sighting['frame'].is_a?(Integer) && sighting['held'].is_a?(Array) }
        raise ArgumentError, "souvenir lacks a place, entity, text or sightings with run, frame and held: #{entry.inspect[0, 200]}" unless valid
      end
      data
    end

    # The texts a run may remember, each with only the sightings it may use: runs created before `before`, outside the batch of forks
    # sharing `batch` (its parent's own parent and fork frame).
    def for_run(data, before:, batch: nil)
      return [] unless before

      data['texts'].filter_map do |entry|
        seen = entry['seen'].select { |sighting| sighting['run'] < before && !(batch && data['runs'][sighting['run']] == batch) }
        entry.merge('seen' => seen) unless seen.empty?
      end
    end

    # Text, place and speaker only: a later sighting or a later bundle never changes a run's digest.
    def digest(entries)
      Digest::SHA256.hexdigest(JSON.generate(entries.map { |entry| entry.values_at('place', 'entity', 'text') }.sort_by(&:inspect)))
    end

    def record(before:, batch: nil, data: load) = { 'before' => before, 'batch' => batch, 'digest' => digest(for_run(data, before:, batch:)) }

    def for_manifest(manifest, data = load)
      recorded = manifest['souvenirs']
      recorded.is_a?(Hash) ? for_run(data, before: recorded['before'], batch: recorded['batch']) : []
    end

    def digest_of(manifest) = manifest['souvenirs'].is_a?(Hash) ? manifest['souvenirs']['digest'] : false

    # Forks compared against each other must remember the same texts.
    def comparable!(manifests)
      digests = manifests.map { |manifest| digest_of(manifest) }.uniq
      raise Error, "runs compared with different souvenirs (digests #{digests.map { |d| d ? d[0, 12] : 'none' }.join(', ')}): fork them alike" if digests.size > 1
    end
  end
end
