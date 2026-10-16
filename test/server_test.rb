require_relative 'test_helper'
require 'net/http'
require 'json'
require 'koholint/viewer/server'

class ServerTest < Minitest::Test
  PNG_SIGNATURE = "\x89PNG\r\n\x1a\n".b

  class StubFollower
    def frame_png = PNG_SIGNATURE + 'stub'.b
  end

  class BrokenFollower
    def frame_png = raise('no frame')
  end

  STATE = { status: { run_id: 'r1', health: 'ok' }, replay: { frame: 1, sync: 'in_sync' }, events: [] }.freeze

  def with_server(follower: StubFollower.new, feed: -> { STATE })
    server = Koholint::Viewer::Server.new(follower:, feed:)
    port = server.start
    yield server, port
  ensure
    server&.stop
  end

  def get(port, path)
    Net::HTTP.get_response(URI("http://127.0.0.1:#{port}#{path}"))
  end

  def test_root_serves_the_page
    with_server do |_, port|
      response = get(port, '/')
      assert_equal '200', response.code
      assert_match %r{\Atext/html}, response['Content-Type']
      assert_includes response.body, 'frame.png'
      assert_includes response.body, 'state.json'
    end
  end

  def test_frame_png
    with_server do |_, port|
      response = get(port, '/frame.png?t=3')
      assert_equal '200', response.code
      assert_equal 'image/png', response['Content-Type']
      assert_equal 'no-store', response['Cache-Control']
      assert_equal PNG_SIGNATURE, response.body.b[0, 8]
    end
  end

  def test_state_json
    with_server do |_, port|
      response = get(port, '/state.json')
      assert_equal 'application/json', response['Content-Type']
      assert_equal 'no-store', response['Cache-Control']
      assert_equal 'r1', JSON.parse(response.body).dig('status', 'run_id')
    end
  end

  def test_unknown_path_is_404
    with_server { |_, port| assert_equal '404', get(port, '/nope').code }
  end

  def test_non_get_is_405
    with_server do |_, port|
      response = Net::HTTP.post(URI("http://127.0.0.1:#{port}/"), 'x')
      assert_equal '405', response.code
      assert_equal 'GET', response['Allow']
    end
  end

  def test_two_simultaneous_connections
    with_server do |_, port|
      slow = TCPSocket.new('127.0.0.1', port)
      slow.write("GET /state.json HTTP/1.1\r\nHost: x\r\n")
      assert_equal '200', get(port, '/state.json').code
      slow.write("\r\n")
      assert_match %r{\AHTTP/1.1 200}, slow.gets
      slow.close
    end
  end

  def test_second_server_on_the_same_port_raises
    with_server do |_, port|
      other = Koholint::Viewer::Server.new(follower: StubFollower.new, feed: -> { STATE }, port:)
      error = assert_raises(Koholint::Error) { other.start }
      refute_includes error.message, "\n"
      assert_match(/choose another port with --port\z/, error.message)
    end
  end

  def test_slow_feed_does_not_block_frame_png
    entered = Queue.new
    release = Queue.new
    feed = -> { entered << true; release.pop; STATE }
    with_server(feed:) do |_, port|
      slow = Thread.new { get(port, '/state.json').code }
      entered.pop
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      assert_equal '200', get(port, '/frame.png').code
      assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 1
      release << true
      assert_equal '200', slow.value
    end
  end

  def test_simultaneous_requests_all_succeed
    with_server do |_, port|
      codes = %w[/frame.png /state.json /frame.png /state.json /frame.png /state.json].map do |path|
        Thread.new { get(port, path).code }
      end.map(&:value)
      assert_equal ['200'] * 6, codes
    end
  end

  def test_stop_returns_promptly_with_a_silent_connection
    server = Koholint::Viewer::Server.new(follower: StubFollower.new, feed: -> { STATE })
    port = server.start
    silent = TCPSocket.new('127.0.0.1', port)
    sleep 0.1
    threads = server.instance_variable_get(:@connections).dup
    refute_empty threads
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    server.stop
    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 1
    assert threads.none?(&:alive?)
    silent.close
  end

  def test_idle_connection_is_dropped_after_the_read_timeout
    server = Koholint::Viewer::Server.new(follower: StubFollower.new, feed: -> { STATE }, read_timeout: 0.2)
    port = server.start
    silent = TCPSocket.new('127.0.0.1', port)
    assert_nil silent.read(1)
    silent.close
  ensure
    server&.stop
  end

  def test_binds_loopback_only
    with_server do |server, _|
      assert_equal '127.0.0.1', server.listener.local_address.ip_address
    end
  end

  def test_feed_failure_is_a_500_and_server_survives
    calls = 0
    feed = -> { (calls += 1) == 1 ? raise('boom') : STATE }
    with_server(feed:) do |_, port|
      response = get(port, '/state.json')
      assert_equal '500', response.code
      assert_equal 'application/json', response['Content-Type']
      assert JSON.parse(response.body).key?('error')
      assert_equal '200', get(port, '/state.json').code
    end
  end

  def test_follower_failure_is_a_500
    with_server(follower: BrokenFollower.new) do |_, port|
      assert_equal '500', get(port, '/frame.png').code
      assert_equal '200', get(port, '/').code
    end
  end

  def test_page_has_no_innerhtml_and_no_external_url
    page = File.read(File.expand_path('../lib/koholint/viewer/page.html', __dir__))
    refute_includes page, 'innerHTML'
    refute_match %r{https?://}, page
  end
end
