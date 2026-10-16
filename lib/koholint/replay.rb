require 'koholint/emulator'
require 'koholint/keyframes'
require 'koholint/run'

module Koholint
  module Replay
    module_function

    def to(run, frame)
      keyframe = Keyframes.new(File.join(run.dir, 'keyframes')).nearest_at_or_before(frame)
      emulator = keyframe ? Keyframes.load(keyframe.last) : Emulator.boot
      run.inputs.each_frame.with_index do |buttons, index|
        next if index < emulator.frame
        break if emulator.frame >= frame

        emulator.step(buttons)
      end
      emulator
    end

    def verify(run, every: 600)
      expected = []
      Trace.read(File.join(run.dir, 'trace.jsonl')).each do |event|
        next unless event['type'] == 'perception' && event['state_hash']
        next if expected.last && event['frame'] < expected.last['frame'] + every

        expected << event
      end
      emulator = Emulator.boot
      frames = run.inputs.each_frame
      expected.filter_map do |event|
        emulator.step(frames.next) while emulator.frame < event['frame']
        [event['frame'], emulator.state_hash == event['state_hash']]
      rescue StopIteration
        nil
      end
    end
  end
end
