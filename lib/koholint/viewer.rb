require 'koholint'
require 'koholint/viewer/feed'
require 'koholint/viewer/follower'
require 'koholint/viewer/server'

module Koholint
  module Viewer
    FPS = 60
    SLICE = 0.02

    module_function

    def watch(run_dir, port: 0, from: :live, speed: 1.0, out: $stdout, err: $stderr, clock: Process.method(:clock_gettime))
      stopping = false
      previous = %w[INT TERM].to_h { |sig| [sig, Signal.trap(sig) { stopping = true }] }
      server = Server.new(port:)
      server.bind
      follower = Follower.new(run_dir, from: from)
      server.follower = follower
      server.feed = -> { Feed.for(run_dir, follower) }
      out.puts "watching http://127.0.0.1:#{server.start}"
      out.flush
      pump(follower, speed, -> { stopping }, clock, err:)
    ensure
      server&.stop
      previous&.each { |sig, handler| Signal.trap(sig, handler) }
    end

    def pump(follower, speed, stop, clock, err: $stderr)
      now = -> { clock.call(Process::CLOCK_MONOTONIC) }
      last = now.call
      owed = 0.0
      until stop.call
        owed += (now.call - last) * FPS * speed
        last = now.call
        owed = [owed, FPS * speed].min
        stepped = owed >= 1 ? follower.step_available(max_frames: owed.floor) : 0
        owed -= stepped
        sleep SLICE if stepped.zero?
      end
      0
    rescue Error => e
      err.puts "koholint: #{e.message}"
      1
    end
  end
end
