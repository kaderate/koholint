require_relative 'test_helper'
require 'fileutils'
require 'tmpdir'
require 'koholint/trace'
require 'koholint/viewer/machines'

class MachinesTest < Minitest::Test
  def make_run(root, id, frame)
    dir = File.join(root, id)
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, 'manifest.json'), JSON.generate('flow_version' => 'flow-101'))
    Koholint::Trace.new(File.join(dir, 'trace.jsonl')).emit(:stop, frame:, reason: 'test')
    dir
  end

  def test_koholint_processes_show_their_run_frame_rate_and_resources
    Dir.mktmpdir do |root|
      forked = make_run(root, '20261125-100000-aaaa', 600)
      watched = make_run(root, '20261125-090000-bbbb', 50)
      ps = <<~PS
        101  98.5 204800 01:02:03 ruby --yjit bin/koholint fork #{watched} --at-frame 40 --agent
        102   0.4  10240 2-03:04:05 ruby --yjit bin/koholint watch #{watched} --runs-root #{root} --port 8792
        103   0.0   2208 01:02:03 /bin/bash -lc ruby --yjit bin/koholint fork #{watched}
        104   1.0   4096    00:09 ruby --yjit bin/koholint summary #{watched}
        105   3.0   4096    00:05 ruby -Ilib other.rb
      PS
      clock = [10.0]
      machines = Koholint::Viewer::Machines.new(ps: -> { ps }, lsof: ->(pids) { "p101\nf3\nn#{forked}/run.lock\np102\nn/dev/null\n" }, clock: -> { clock[0] })
      first = machines.list
      assert_equal [[101, 'fork', '20261125-100000-aaaa', 'flow-101', 600, nil, 98.5, 204_800 * 1024, 3723, nil],
                    [102, 'watch', '20261125-090000-bbbb', 'flow-101', 50, nil, 0.4, 10_240 * 1024, 183_845, 8792]],
                   first.map { |row| row.values_at(:pid, :kind, :run, :flow, :frame, :fps, :cpu, :rss, :elapsed, :port) }
      Koholint::Trace.new(File.join(forked, 'trace.jsonl')).emit(:stop, frame: 720, reason: 'test')
      clock[0] = 12.0
      assert_equal [60.0, 0.0], machines.list.map { |row| row[:fps] }
    end
  end
end
