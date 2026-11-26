require 'json'
require 'open3'
require 'koholint'
require 'koholint/summary'

module Koholint
  module Viewer
    # The koholint processes running on this computer, read from ps, lsof and their run folders; read-only.
    class Machines
      COMMANDS = %w[run resume fork branch watch].freeze
      ARGV_DIR = %w[resume watch].freeze
      TAIL = 16_384
      LOCK = 'run.lock'.freeze

      def initialize(ps: -> { Open3.capture2('ps', '-axww', '-o', 'pid=,pcpu=,rss=,etime=,command=').first },
                     lsof: ->(pids) { Open3.capture2('lsof', '-a', '-p', pids.join(','), '-Fpn').first },
                     clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
        @ps = ps
        @lsof = lsof
        @clock = clock
        @samples = {}
        @lock = Mutex.new
      end

      def list
        processes = @ps.call.each_line.filter_map { |line| process(line) }
        locks = processes.empty? ? {} : locked_dirs(@lsof.call(processes.map { |found| found[:pid] }))
        now = @clock.call
        rows = processes.map { |found| row(found, locks[found[:pid]] || (found[:dir] if ARGV_DIR.include?(found[:kind])), now) }
        @lock.synchronize { @samples.select! { |pid, _| rows.any? { |row| row[:pid] == pid } } }
        rows
      end

      def self.seconds(etime)
        days, clock = etime.include?('-') ? etime.split('-', 2) : [0, etime]
        clock.split(':').map(&:to_i).reverse.each_with_index.sum { |part, index| part * (60**index) } + (days.to_i * 86_400)
      end

      private

      def process(line)
        pid, cpu, rss, etime, command = line.strip.split(/\s+/, 5)
        words = command.to_s.split
        return nil unless File.basename(words.first.to_s).start_with?('ruby')

        at = words.index { |word| File.basename(word) == 'koholint' } or return nil
        kind = words[at + 1]
        return nil unless COMMANDS.include?(kind)

        args = words[(at + 2)..]
        { pid: pid.to_i, cpu: cpu.to_f, rss: rss.to_i, elapsed: self.class.seconds(etime.to_s), kind:,
          dir: args.find { |word| !word.start_with?('-') && File.directory?(word) }, port: flag(args, '--port')&.to_i }
      end

      def flag(args, name)
        args.each_cons(2) { |key, value| return value if key == name }
        args.find { |word| word.start_with?("#{name}=") }&.split('=', 2)&.last
      end

      def locked_dirs(output)
        pid = nil
        output.each_line.with_object({}) do |line, dirs|
          pid = line[1..].to_i if line.start_with?('p')
          dirs[pid] ||= File.dirname(line[1..].chomp) if line.start_with?('n') && File.basename(line.chomp) == LOCK
        end
      end

      def row(found, dir, now)
        frame = dir && last_frame(File.join(dir, 'trace.jsonl'))
        { pid: found[:pid], kind: found[:kind], run: dir && File.basename(dir), dir:, flow: dir && Summary.read_json(File.join(dir, 'manifest.json'))['flow_version'],
          frame:, fps: fps(found[:pid], frame, now), cpu: found[:cpu], rss: found[:rss] * 1024, elapsed: found[:elapsed], port: found[:kind] == 'watch' ? found[:port] : nil }
      end

      def fps(pid, frame, now)
        @lock.synchronize do
          before = @samples[pid]
          @samples[pid] = [frame, now] if frame && (before.nil? || before[0] != frame || now - before[1] > 10)
          next nil unless frame && before && now > before[1]

          before[0] == frame ? 0.0 : ((frame - before[0]) / (now - before[1])).round(1)
        end
      end

      def last_frame(trace)
        File.open(trace, 'rb') do |file|
          file.seek([file.size - TAIL, 0].max)
          file.read.to_s.split("\n").reverse_each do |line|
            frame = JSON.parse(line)['frame']
            return frame if frame.is_a?(Integer)
          rescue JSON::ParserError, EncodingError
            next
          end
        end
        nil
      rescue SystemCallError
        nil
      end
    end
  end
end
