require 'digest'
require 'fileutils'
require 'json'
require 'koholint'

module Koholint
  module Viewer
    # Atlas digests kept on disk, one file per run, so a restarted viewer reads them instead of replaying every trace.
    class DigestCache
      ROOT = File.expand_path('../../..', __dir__)

      # Everything a digest or the island is computed from: the library and the data files.
      def self.identity
        @identity ||= Digest::SHA256.hexdigest(Dir.glob(File.join(ROOT, '{lib/koholint/**/*.rb,data/*.json}')).sort.map { |path| "#{path}:#{Digest::SHA256.file(path).hexdigest}" }.join("\n"))
      end

      def self.encode(value)
        case value
        when Hash then { '$h' => value.map { |key, item| [encode(key), encode(item)] } }
        when Array then value.map { |item| encode(item) }
        when Symbol then { '$s' => value.to_s }
        else value
        end
      end

      def self.decode(value)
        case value
        when Array then value.map { |item| decode(item) }
        when Hash then value.key?('$s') ? value['$s'].to_sym : value['$h'].to_h { |key, item| [decode(key), decode(item)] }
        else value
        end
      end

      def initialize(dir, identity: self.class.identity)
        @dir = dir
        @identity = identity
        @memory = {}
      end

      def [](run_dir)
        @memory.fetch(run_dir) { @memory[run_dir] = load(run_dir) }
      end

      def []=(run_dir, entry)
        @memory[run_dir] = entry
        store(run_dir, entry)
      end

      def prune(run_dirs)
        kept = run_dirs.to_set { |run_dir| path(run_dir) }
        Dir.glob(File.join(@dir, '*.json')).each { |file| File.delete(file) unless kept.include?(file) }
      rescue SystemCallError
        nil
      end

      private

      def path(run_dir) = File.join(@dir, "#{Digest::SHA256.hexdigest(File.expand_path(run_dir))}.json")

      def load(run_dir)
        data = JSON.parse(File.read(path(run_dir)))
        self.class.decode(data['entry']) if data['identity'] == @identity && data['dir'] == File.expand_path(run_dir)
      rescue SystemCallError, JSON::ParserError, NoMethodError, TypeError
        nil
      end

      def store(run_dir, entry)
        FileUtils.mkdir_p(@dir)
        tmp = "#{path(run_dir)}.#{Process.pid}.tmp"
        File.write(tmp, JSON.generate({ identity: @identity, dir: File.expand_path(run_dir), entry: self.class.encode(entry) }))
        File.rename(tmp, path(run_dir))
      rescue SystemCallError
        nil
      end
    end
  end
end
