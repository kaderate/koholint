require 'json'
require 'koholint'
require 'koholint/summary'
require 'koholint/trace'

module Koholint
  module Viewer
    module Feed
      RunDir = Struct.new(:dir)
      FIELDS = { 'decision' => %w[frame type agent choice confidence], 'action' => %w[frame type skill params] }.freeze

      PROGRESS = %w[notable objective].freeze
      CACHE = {}
      CACHE_LOCK = Mutex.new

      module_function

      def for(run_dir, follower, limit: 30)
        manifest = read_manifest(run_dir)
        trace = trace_events(run_dir)
        summary = Summary.from_events(trace)
        summary[:health] = 'unknown' if trace.none? { |e| PROGRESS.include?(e['type']) } && %w[progressing stalled].include?(summary[:health])
        {
          status: summary.merge(run_id: File.basename(run_dir), flow_version: manifest['flow_version'],
                                manifest_status: manifest['status'], budget: manifest['budget']),
          replay: { frame: follower.frame, journal_frames: follower.journal_frames, lag: follower.lag, sync: follower.sync },
          events: events(trace, limit)
        }
      end

      def trace_events(run_dir)
        path = File.join(run_dir, 'trace.jsonl')
        stat = File.stat(path)
        signature = [stat.size, stat.mtime]
        CACHE_LOCK.synchronize do
          cached = CACHE[path]
          return cached.last if cached && cached.first == signature

          Trace.read(path).tap { |parsed| CACHE[path] = [signature, parsed] }
        end
      rescue SystemCallError
        []
      end

      def read_manifest(run_dir)
        manifest = JSON.parse(File.read(File.join(run_dir, 'manifest.json')))
        raise Error, "manifest of run #{File.basename(run_dir)} is not an object" unless manifest.is_a?(Hash)

        manifest
      rescue SystemCallError, JSON::ParserError
        raise Error, "cannot read manifest of run #{File.basename(run_dir)}"
      end

      def events(trace, limit)
        trace.select { |e| FIELDS.key?(e['type']) }.last(limit).map do |event|
          event.slice(*FIELDS[event['type']]).transform_keys(&:to_sym)
        end
      end
    end
  end
end
