require 'digest'
require 'fileutils'
require 'koholint'

module Koholint
  module Viewer
    # Atlas digests kept on disk, one file per run, so a restarted viewer reads them instead of replaying every trace.
    class DigestCache
      SOURCE = Digest::SHA256.file(File.expand_path('../atlas.rb', __dir__)).hexdigest

      def initialize(dir)
        @dir = dir
        @memory = {}
      end

      def [](run_dir)
        @memory.fetch(run_dir) { @memory[run_dir] = load(run_dir) }
      end

      def []=(run_dir, entry)
        @memory[run_dir] = entry
        store(run_dir, entry)
      end

      private

      def path(run_dir) = File.join(@dir, "#{Digest::SHA256.hexdigest(File.expand_path(run_dir))}.bin")

      def load(run_dir)
        data = Marshal.load(File.binread(path(run_dir)))
        data[:entry] if data.is_a?(Hash) && data[:source] == SOURCE && data[:dir] == File.expand_path(run_dir)
      rescue SystemCallError, TypeError, ArgumentError, EOFError
        nil
      end

      def store(run_dir, entry)
        FileUtils.mkdir_p(@dir)
        tmp = "#{path(run_dir)}.#{Process.pid}.tmp"
        File.binwrite(tmp, Marshal.dump({ source: SOURCE, dir: File.expand_path(run_dir), entry: }))
        File.rename(tmp, path(run_dir))
      rescue SystemCallError
        nil
      end
    end
  end
end
