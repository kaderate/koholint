require 'json'
require 'monitor'
require 'koholint'
require 'koholint/emulator'
require 'koholint/input_log'
require 'koholint/keyframes'
require 'koholint/trace'

module Koholint
  module Viewer
    class Follower
      def initialize(run_dir, from: :live, max_lag_frames: 1800)
        @lock = Monitor.new
        @dir = run_dir
        @max_lag = max_lag_frames
        @journal_path = File.join(run_dir, 'inputs.log')
        @trace_path = File.join(run_dir, 'trace.jsonl')
        @keyframes_dir = File.join(run_dir, 'keyframes')
        @entries = []
        @total = 0
        @expected = {}
        @captured = {}
        @trace_offset = 0
        open_journal
        refresh_trace
        start(from)
      end

      def frame = synchronize { @frame }

      def journal_frames = synchronize { refresh_journal && @total }

      def lag = synchronize { journal_frames - @frame }

      def frame_png = synchronize { @emulator.frame_png }

      def state_hash = synchronize { @emulator.state_hash }

      def compared_frames = synchronize { @captured.size }

      def step_available(max_frames: 60)
        synchronize do
          refresh_trace
          jump_if_lagging
          capture
          count = [max_frames, lag].min
          count.times do
            @emulator.step(buttons_at_cursor)
            advance_cursor(1)
            @frame = @emulator.frame
            capture
          end
          [count, 0].max
        end
      end

      def sync
        synchronize do
          refresh_trace
          capture
          next :unknown if @captured.empty?

          @captured.all? { |frame, hash| @expected[frame] == hash } ? :in_sync : :diverged
        end
      end

      private

      def synchronize(&) = @lock.synchronize(&)

      def open_journal
        raise Error, "no run at #{@dir}" unless File.file?(File.join(@dir, 'manifest.json'))

        JSON.parse(File.read(File.join(@dir, 'manifest.json')))
        raise Error, "no input journal at #{@dir}" unless File.file?(@journal_path)

        @version = File.binread(@journal_path, 1)&.getbyte(0)
        case @version
        when InputLog::FORMAT_VERSION
          @offset = 1
          refresh_journal
        when InputLog::LEGACY_VERSION
          load_legacy
        else raise Error, "unsupported input journal version #{@version.inspect} at #{@dir}"
        end
      rescue JSON::ParserError
        raise Error, "garbled manifest at #{@dir}"
      end

      def refresh_journal
        return true unless @version == InputLog::FORMAT_VERSION

        fresh, @offset = InputLog.read_from(@journal_path, @offset)
        @entries.concat(fresh)
        @total += fresh.sum(&:last)
        true
      end

      def load_legacy
        masks = InputLog.load(@journal_path).each_frame.map { |buttons| buttons.sum { |b| 1 << InputLog::BUTTONS.index(b) } }
        @entries = masks.chunk_while { |a, b| a == b }.map { |run| [run.first, run.size] }
        @total = masks.size
      end

      def start(from)
        @emulator = Emulator.boot
        @frame = 0
        @entry = 0
        @used = 0
        restore_keyframe_at_or_before(@total) if from == :live
        capture
      end

      def restore_keyframe_at_or_before(target)
        best = keyframe_frames.select { |f| f <= target }.max
        return unless best && best > @frame

        @emulator = Keyframes.load(File.join(@keyframes_dir, format('kf-%09d.zlib', best)))
        @frame = @emulator.frame
        @entry = 0
        @used = 0
        advance_cursor(@frame)
        capture
      end

      def keyframe_frames
        return [] unless File.directory?(@keyframes_dir)

        Dir.children(@keyframes_dir).filter_map { |name| name[/\Akf-(\d+)\.zlib\z/, 1]&.to_i }
      end

      def jump_if_lagging
        restore_keyframe_at_or_before(@total) if lag > @max_lag
      end

      def advance_cursor(frames)
        while frames.positive? && @entry < @entries.size
          take = [frames, @entries[@entry].last - @used].min
          @used += take
          frames -= take
          next unless @used == @entries[@entry].last

          @entry += 1
          @used = 0
        end
      end

      def buttons_at_cursor
        mask = @entries[@entry].first
        InputLog::BUTTONS.each_index.select { |i| mask[i] == 1 }.map { |i| InputLog::BUTTONS[i] }
      end

      def refresh_trace
        size = File.exist?(@trace_path) ? File.size(@trace_path) : 0
        if size < @trace_offset
          @trace_offset = 0
          @expected.clear
        end
        return if size == @trace_offset

        chunk = File.open(@trace_path, 'rb') { |file| file.seek(@trace_offset) && file.read } || ''
        complete = chunk[0..(chunk.rindex("\n") || -1)]
        complete = '' unless complete.end_with?("\n")
        @trace_offset += complete.bytesize
        complete.each_line { |line| record(line) }
      end

      def record(line)
        event = JSON.parse(line)
        @expected[event['frame']] = event['state_hash'] if event['type'] == 'perception' && event['state_hash']
      rescue JSON::ParserError
        nil
      end

      def capture
        @captured[@frame] = @emulator.state_hash if @expected.key?(@frame) && !@captured.key?(@frame)
      end
    end
  end
end
