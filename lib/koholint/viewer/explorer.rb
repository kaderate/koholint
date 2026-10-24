require 'fileutils'
require 'json'
require 'stringio'
require 'koholint'
require 'koholint/archive'
require 'koholint/perception'
require 'koholint/run_compare'
require 'koholint/summary'
require 'koholint/trace'
require 'koholint/viewer/insights'
require 'koholint/viewer/registry'
require 'zlib'

module Koholint
  module Viewer
    class Explorer
      class NotFound < Error; end
      class BadRequest < Error; end
      class Unreadable < Error; end

      RUN_ID = /\A(?!\.)(?!.*\.\.)[\w.-]{1,100}\z/
      MAX_WHY = 500
      MAX_NOTES = 8192
      NOTES = 'notes.md'.freeze
      HEADER = %w[run_id tag flow_version model harness_sha highest_milestone places_seen frames dollars stop_reason].freeze
      FIELDS = %w[run_id tag flow_version frames dollars calls usd_per_1000f highest_milestone places_seen stop_reason].freeze

      attr_reader :root, :registry

      def initialize(root:, registry:)
        @root = root
        @registry = registry
      end

      def self.default_root(run_dir)
        parent = File.dirname(File.expand_path(run_dir))
        siblings = Archive.runs(parent).reject { |dir| File.expand_path(dir) == File.expand_path(run_dir) }
        siblings.empty? ? 'runs' : parent
      end

      def resolve(id)
        raise NotFound, 'no such run' unless id.is_a?(String) && id.match?(RUN_ID)

        dir = File.join(@root, id)
        raise NotFound, 'no such run' unless File.directory?(dir) && File.file?(File.join(dir, 'manifest.json'))
        raise NotFound, 'no such run' unless File.dirname(File.realpath(dir)) == File.realpath(@root)

        dir
      rescue SystemCallError
        raise NotFound, 'no such run'
      end

      def replay_dir(id)
        dir = resolve(id)
        raise NotFound, 'no replay for this run' unless File.file?(File.join(dir, 'inputs.log'))

        dir
      end

      def open(id) = registry.open(replay_dir(id))

      def frame_png(id) = readable(id) { registry.frame_png(replay_dir(id)) }

      def state(id) = readable(id) { registry.state(replay_dir(id)) }

      def control(id, **controls) = readable(id) { registry.control(replay_dir(id), **controls) }

      def insight(id, kind) = readable(id) { registry.insight(replay_dir(id), kind) }

      def header(id) = readable(id) { self.class.header(resolve(id), notes_run: id) }

      def notes_run(dir)
        id = File.basename(dir)
        id if File.realpath(resolve(id)) == File.realpath(dir)
      rescue NotFound, SystemCallError
        nil
      end

      def self.header(dir, notes_run: nil)
        summary = Summary.read_json(File.join(dir, Summary::FILE))
        summary = recorded(dir).merge(summary) unless summary['v'].to_i >= Summary::VERSION
        notes = File.file?(File.join(dir, NOTES)) ? File.read(File.join(dir, NOTES), MAX_NOTES).to_s : ''
        HEADER.to_h { |key| [key, summary[key]] }.merge('run_id' => File.basename(dir), 'notes' => notes.scrub, 'notes_run' => notes_run)
      end

      def self.recorded(dir)
        JSON.parse(JSON.generate(Summary.record(dir)))
      rescue StandardError
        {}
      end

      def save_notes(id, text)
        raise BadRequest, "notes are longer than #{MAX_NOTES} bytes" if text.bytesize > MAX_NOTES
        raise BadRequest, 'notes must not contain control characters' if text.match?(/[^\P{Cntrl}\n\r\t]/)

        readable(id) do
          path = File.join(resolve(id), NOTES)
          if text.strip.empty?
            FileUtils.rm_f(path)
          else
            File.write("#{path}.tmp", text)
            File.rename("#{path}.tmp", path)
          end
        end
        { run_id: id, saved: true, bytes: text.bytesize }
      end

      REFERENCE_CACHE = {}
      REFERENCE_LOCK = Mutex.new

      def reference(dir)
        others = Archive.runs(@root).reject { |other| File.expand_path(other) == File.expand_path(dir) }
                                    .select { |other| File.basename(other).match?(RUN_ID) }
        before = others.select { |other| File.basename(other) < File.basename(dir) }
        other = (before.empty? ? others : before).last or return nil
        path = Trace.located(File.join(other, 'trace.jsonl'))
        stat = File.stat(path)
        key = [path, stat.size, stat.mtime]
        REFERENCE_LOCK.synchronize do
          REFERENCE_CACHE.clear unless REFERENCE_CACHE.key?(key)
          REFERENCE_CACHE[key] ||= begin
            trace = Trace.read(File.join(other, 'trace.jsonl'))
            { run_id: File.basename(other), series: Insights.cost(trace)[:series], frames: trace.last&.fetch('frame', 0).to_i }
          end
        end
      rescue Error, SystemCallError, Zlib::Error, JSON::ParserError
        nil
      end

      def runs
        Archive.runs(@root).filter_map { |dir| row(dir) if File.basename(dir).match?(RUN_ID) }.sort_by { |row| row['run_id'] }.reverse
      end

      def compare(a, b) = readable("#{a} or #{b}") { RunCompare.compare(resolve(a), resolve(b)) }

      def star(id, why)
        why = why.to_s.strip
        raise BadRequest, 'why is required' if why.empty?
        raise BadRequest, "why is longer than #{MAX_WHY} characters" if why.length > MAX_WHY
        raise BadRequest, 'why must not contain control characters' if why.match?(/[[:cntrl:]]/)

        readable(id) { Archive.star(resolve(id), why, out: StringIO.new) }
        { run_id: id, starred: true, why: }
      end

      private

      def readable(id)
        yield
      rescue NotFound, BadRequest, Registry::Expired
        raise
      rescue Error, SystemCallError, Zlib::Error, JSON::ParserError
        raise Unreadable, "run #{id} cannot be read"
      end

      def row(dir)
        row!(dir)
      rescue Error, SystemCallError
        nil
      end

      def row!(dir)
        summary = Summary.read_json(File.join(dir, Summary::FILE))
        return nil if summary.empty?

        star = Summary.read_json(File.join(dir, 'star.json'))
        milestone = summary['highest_milestone']
        calls = summary['calls']
        agents = summary['decisions_by_agent']
        FIELDS.to_h { |key| [key, summary[key]] }.merge(
          'usd_per_call' => calls.is_a?(Integer) && calls.positive? && summary['dollars'].is_a?(Numeric) ? (summary['dollars'] / calls).round(6) : nil,
          'free_decisions' => agents.is_a?(Hash) ? agents.except('claude').values.grep(Integer).sum : nil,
          'run_id' => File.basename(dir), 'milestone_rank' => Perception::MILESTONES.index(milestone.to_s.to_sym),
          'starred' => !star.empty? || summary['starred'] == true, 'why' => star['why']
        )
      end
    end
  end
end
