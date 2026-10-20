require 'json'
require 'stringio'
require 'koholint'
require 'koholint/archive'
require 'koholint/perception'
require 'koholint/run_compare'
require 'koholint/summary'

module Koholint
  module Viewer
    class Explorer
      class NotFound < Error; end
      class BadRequest < Error; end

      RUN_ID = /\A(?!\.)(?!.*\.\.)[\w.-]{1,100}\z/
      MAX_WHY = 500
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

      def runs
        Archive.runs(@root).filter_map { |dir| row(dir) if File.basename(dir).match?(RUN_ID) }.sort_by { |row| row['run_id'] }.reverse
      end

      def compare(a, b) = RunCompare.compare(resolve(a), resolve(b))

      def star(id, why)
        why = why.to_s.strip
        raise BadRequest, 'why is required' if why.empty?
        raise BadRequest, "why is longer than #{MAX_WHY} characters" if why.length > MAX_WHY
        raise BadRequest, 'why must not contain control characters' if why.match?(/[[:cntrl:]]/)

        Archive.star(resolve(id), why, out: StringIO.new)
        { run_id: id, starred: true, why: }
      end

      private

      def row(dir)
        summary = Summary.read_json(File.join(dir, Summary::FILE))
        return nil if summary.empty?

        star = Summary.read_json(File.join(dir, 'star.json'))
        milestone = summary['highest_milestone']
        FIELDS.to_h { |key| [key, summary[key]] }.merge(
          'run_id' => File.basename(dir), 'milestone_rank' => Perception::MILESTONES.index(milestone.to_s.to_sym),
          'starred' => !star.empty? || summary['starred'] == true, 'why' => star['why']
        )
      end
    end
  end
end
