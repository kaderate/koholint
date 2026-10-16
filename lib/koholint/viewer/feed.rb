require 'json'
require 'koholint'
require 'koholint/summary'
require 'koholint/trace'

module Koholint
  module Viewer
    module Feed
      RunDir = Struct.new(:dir)
      FIELDS = { 'decision' => %w[frame type agent choice confidence], 'action' => %w[frame type skill params] }.freeze

      module_function

      def for(run_dir, follower, limit: 30)
        manifest = read_manifest(run_dir)
        {
          status: Summary.for(RunDir.new(run_dir)).merge(run_id: File.basename(run_dir), flow_version: manifest['flow_version'],
                                                         manifest_status: manifest['status'], budget: manifest['budget']),
          replay: { frame: follower.frame, journal_frames: follower.journal_frames, lag: follower.lag, sync: follower.sync },
          events: events(run_dir, limit)
        }
      end

      def read_manifest(run_dir)
        manifest = JSON.parse(File.read(File.join(run_dir, 'manifest.json')))
        raise Error, "manifest of run #{File.basename(run_dir)} is not an object" unless manifest.is_a?(Hash)

        manifest
      rescue SystemCallError, JSON::ParserError
        raise Error, "cannot read manifest of run #{File.basename(run_dir)}"
      end

      def events(run_dir, limit)
        Trace.read(File.join(run_dir, 'trace.jsonl')).select { |e| FIELDS.key?(e['type']) }.last(limit).map do |event|
          event.slice(*FIELDS[event['type']]).transform_keys(&:to_sym)
        end
      end
    end
  end
end
