require 'koholint'
require 'koholint/viewer/feed'
require 'koholint/viewer/follower'

module Koholint
  module Viewer
    class Registry
      IDLE_SECONDS = 300
      MAX_REPLAYS = 3
      SPEEDS = [1, 4, 16].freeze
      STEP_CHUNK = 60
      SLICE = 0.02
      MAX_EXPIRED = 100

      class Expired < Error; end

      Entry = Struct.new(:dir, :follower, :speed, :paused, :used_at, :ticked_at, :owed)

      def initialize(factory: ->(dir) { Follower.new(dir, from: :start, max_lag_frames: Float::INFINITY) }, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) },
                     idle: IDLE_SECONDS, max: MAX_REPLAYS, err: $stderr)
        @factory = factory
        @clock = clock
        @idle = idle
        @max = max
        @err = err
        @entries = {}
        @expired = {}
        @lock = Mutex.new
      end

      def open(dir) = @lock.synchronize { @expired.delete(dir) }

      def fetch(dir)
        touch(dir) || insert(dir, @factory.call(dir))
      end

      def dirs = @lock.synchronize { @entries.keys }

      def frame_png(dir) = fetch(dir).follower.frame_png

      def state(dir)
        entry = fetch(dir)
        feed = Feed.for(dir, entry.follower, upto: entry.follower.frame)
        feed.merge(replay: feed[:replay].merge(controls(entry)))
      end

      def insight(dir, kind)
        entry = fetch(dir)
        Feed.insight(kind, dir, entry.follower, upto: entry.follower.frame)
      end

      def control(dir, speed: nil, paused: nil, seek: nil)
        raise ArgumentError, "speed must be one of #{SPEEDS.join(', ')}" unless speed.nil? || SPEEDS.include?(speed)

        entry = fetch(dir)
        if seek
          entry.follower.seek(seek)
          @lock.synchronize do
            entry.owed = 0.0
            entry.ticked_at = @clock.call
          end
        end
        @lock.synchronize do
          entry.speed = speed if speed
          entry.paused = paused unless paused.nil?
          controls(entry)
        end
      end

      def tick
        now = @clock.call
        active = @lock.synchronize do
          @entries.select { |_, entry| now - entry.used_at > @idle }.each_key { |dir| expire(dir) }
          @entries.values.each { |entry| owe(entry, now) }
        end
        active.each { |entry| advance(entry) }
      end

      def start
        @pump ||= Thread.new do
          until @stopping
            tick
            sleep SLICE
          end
        end
        self
      end

      def stop
        @stopping = true
        @pump&.join(2) || @pump&.kill
      end

      private

      def touch(dir)
        @lock.synchronize do
          raise Expired, 'replay expired: reload the page' if @expired.key?(dir)

          entry = @entries.delete(dir) or next nil
          entry.used_at = @clock.call
          @entries[dir] = entry
        end
      end

      def insert(dir, follower)
        @lock.synchronize do
          now = @clock.call
          entry = @entries.delete(dir) || Entry.new(dir, follower, 1, false, now, now, 0.0)
          entry.used_at = now
          @entries[dir] = entry
          expire(@entries.first.first) while @entries.size > @max
          entry
        end
      end

      def expire(dir)
        @entries.delete(dir)
        @expired[dir] = true
        @expired.shift while @expired.size > MAX_EXPIRED
      end

      def controls(entry) = { speed: entry.speed, paused: entry.paused, frame: entry.follower.frame }

      def owe(entry, now)
        elapsed = now - entry.ticked_at
        entry.ticked_at = now
        entry.owed = entry.paused ? 0.0 : [entry.owed + (elapsed * FPS * entry.speed), FPS * entry.speed].min
      end

      def advance(entry)
        while entry.owed >= 1
          stepped = entry.follower.step_available(max_frames: [entry.owed.floor, STEP_CHUNK].min)
          break entry.owed = 0.0 if stepped.zero?

          entry.owed -= stepped
        end
      rescue StandardError => e
        @err.puts "koholint: replay of #{File.basename(entry.dir)}: #{e.message}"
        @lock.synchronize { @entries.delete(entry.dir) if @entries[entry.dir].equal?(entry) }
      end
    end
  end
end
