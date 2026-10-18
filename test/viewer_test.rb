require_relative 'test_helper'
require 'stringio'
require 'socket'
require 'koholint/viewer'

class ViewerTest < Minitest::Test
  class FailingFollower
    def step_available(max_frames:) = raise(Koholint::Error, 'replay broke')
  end

  def test_port_in_use_is_reported_before_the_follower_is_built
    listener = TCPServer.new('127.0.0.1', 0)
    port = listener.local_address.ip_port
    error = assert_raises(Koholint::Error) { Koholint::Viewer.watch('/nonexistent/run', port:, out: StringIO.new) }
    assert_match(/already in use/, error.message)
  ensure
    listener&.close
  end

  def test_pump_reports_a_follower_error_in_one_line_and_returns_failure
    err = StringIO.new
    clock = Process.method(:clock_gettime)
    status = Koholint::Viewer.pump(FailingFollower.new, 1.0, -> { false }, clock, err:)
    assert_equal 1, status
    assert_equal "koholint: replay broke\n", err.string
  end

  def test_announce_names_the_loopback_address_by_default
    assert_equal 'watching http://127.0.0.1:8123', Koholint::Viewer.announce('127.0.0.1', 8123)
  end

  def test_announce_warns_when_listening_on_all_interfaces
    line = Koholint::Viewer.announce('0.0.0.0', 8123)
    assert_equal 1, line.lines.size
    assert_match(%r{\Awatching http://0\.0\.0\.0:8123 }, line)
    assert_match(/all network interfaces/, line)
  end
end
