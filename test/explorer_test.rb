require_relative 'test_helper'
require 'net/http'
require 'socket'
require 'stringio'
require 'tmpdir'
require 'json'
require 'koholint/viewer'

class ExplorerTest < Minitest::Test
  PLAYING = { 'hp' => 24, 'max_hp' => 24, 'milestone' => 'none', 'room_id' => 3, 'map_id' => 1, 'game_mode' => 0x0B, 'game_submode' => 7 }.freeze
  A = '20261019-092839-1af5'.freeze
  B = '20261020-085011-8330'.freeze
  XSS = '<script>alert(1)</script>'.freeze

  class StubFollower
    def frame = 0
    def journal_frames = 100
    def lag = 100
    def sync = :unknown
    def frame_png = "\x89PNG\r\n\x1a\nstub".b
    def step_available(max_frames:) = 0
  end

  def make_run(root, id, summary: {}, milestone: 'none', star: nil)
    dir = File.join(root, id)
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, 'manifest.json'), JSON.generate('flow_version' => 'flow-3', 'status' => 'stopped'))
    trace = Koholint::Trace.new(File.join(dir, 'trace.jsonl'))
    trace.emit(:perception, frame: 5, state: PLAYING, state_hash: 'h')
    trace.emit(:perception, frame: 40, state: PLAYING.merge('milestone' => milestone, 'room_id' => 4), state_hash: 'h')
    File.write(File.join(dir, 'summary.json'), JSON.generate({ 'run_id' => id, 'frames' => 40, 'highest_milestone' => milestone }.merge(summary))) if summary
    File.write(File.join(dir, 'star.json'), JSON.generate(star)) if star
    dir
  end

  def with_root
    Dir.mktmpdir do |root|
      make_run(root, A, summary: { 'tag' => XSS, 'dollars' => 0.5 }, star: { 'starred' => true, 'why' => 'first <b>exit</b>' })
      make_run(root, B, summary: { 'tag' => 'agent', 'dollars' => 1.1 }, milestone: 'shield')
      yield root
    end
  end

  def with_server(root, host: '127.0.0.1')
    built = []
    registry = Koholint::Viewer::Registry.new(factory: ->(dir) { built << dir && StubFollower.new }, err: StringIO.new)
    explorer = Koholint::Viewer::Explorer.new(root:, registry:)
    server = Koholint::Viewer::Server.new(follower: StubFollower.new, feed: -> { {} }, explorer:, host:)
    port = server.start
    yield port, built
  ensure
    server&.stop
  end

  def get(port, path) = Net::HTTP.get_response(URI("http://127.0.0.1:#{port}#{path}"))

  def code(port, path) = raw(port, "GET #{path} HTTP/1.1\r\nHost: x\r\n\r\n").first

  def raw(port, request)
    socket = TCPSocket.new('127.0.0.1', port)
    socket.write(request)
    response = socket.read
    socket.close
    status = response[%r{\AHTTP/1.1 (\d+)}, 1]
    [status, response.split("\r\n\r\n", 2).last]
  end

  def post_star(port, run, why, host: "127.0.0.1:#{port}", origin: nil, length: nil)
    body = URI.encode_www_form(why:)
    headers = ["Host: #{host}", "Content-Type: application/x-www-form-urlencoded", "Content-Length: #{length || body.bytesize}"]
    headers << "Origin: #{origin}" if origin
    raw(port, "POST /star?run=#{URI.encode_www_form_component(run)} HTTP/1.1\r\n#{headers.join("\r\n")}\r\n\r\n#{body}")
  end

  def test_runs_json_lists_runs_with_a_summary_newest_first
    with_root do |root|
      make_run(root, '20261021-000000-0000', summary: nil)
      FileUtils.mkdir_p(File.join(root, 'notes'))
      with_server(root) do |port, _|
        response = get(port, '/runs.json')
        assert_equal 'application/json', response['Content-Type']
        assert_equal 'nosniff', response['X-Content-Type-Options']
        runs = JSON.parse(response.body)
        assert_equal [B, A], runs.map { |run| run['run_id'] }
        assert_equal [1, 0], runs.map { |run| run['milestone_rank'] }
        assert_equal [false, true], runs.map { |run| run['starred'] }
        assert_equal [nil, 'first <b>exit</b>'], runs.map { |run| run['why'] }
        assert_equal XSS, runs.last['tag']
        assert_equal %w[run_id tag flow_version frames dollars calls usd_per_1000f highest_milestone places_seen stop_reason milestone_rank starred why],
                     runs.first.keys
      end
    end
  end

  def test_html_pages_are_static_and_never_echo_run_data
    with_root do |root|
      with_server(root) do |port, _|
        page = File.binread(File.expand_path('../lib/koholint/viewer/page.html', __dir__))
        assert_equal page, get(port, "/run/#{A}").body.b
        runs = get(port, '/runs')
        assert_match %r{\Atext/html}, runs['Content-Type']
        assert_match(/frame-ancestors 'none'/, runs['Content-Security-Policy'])
        assert_equal File.binread(File.expand_path('../lib/koholint/viewer/runs.html', __dir__)), runs.body.b
        compare = get(port, "/compare/#{A}/#{B}").body
        assert_equal File.binread(File.expand_path('../lib/koholint/viewer/compare.html', __dir__)), compare.b
        [runs.body, compare].each { |body| refute_includes body, 'alert(1)' }
      end
    end
  end

  def test_pages_insert_data_with_text_only
    %w[runs.html compare.html page.html].each do |name|
      html = File.read(File.expand_path("../lib/koholint/viewer/#{name}", __dir__))
      %w[innerHTML outerHTML insertAdjacentHTML document.write].each { |sink| refute_includes html, sink, "#{name} uses #{sink}" }
      refute_match %r{https?://}, html
    end
  end

  def test_a_past_run_frame_and_state_come_from_its_own_replay
    with_root do |root|
      with_server(root) do |port, built|
        frame = get(port, "/frame.png?t=1&run=#{A}")
        assert_equal '200', frame.code
        assert_equal 'image/png', frame['Content-Type']
        state = JSON.parse(get(port, "/state.json?run=#{A}").body)
        assert_equal A, state.dig('status', 'run_id')
        assert_equal({ 'speed' => 1, 'paused' => false }, state['replay'].slice('speed', 'paused'))
        assert_equal [File.join(root, A)], built
        assert_equal({}, JSON.parse(get(port, '/state.json').body))
      end
    end
  end

  TRAVERSALS = ['..', '%2e%2e', '%2E%2E', '.hidden', '%00', "#{A}%00", '%2Fetc', '%2Fetc%2Fpasswd', 'a..b', '..%2F..%2Fetc',
                '%C0%AE%C0%AE', 'nope', '%ZZ'].freeze

  def test_run_ids_cannot_escape_the_runs_root
    with_root do |root|
      outside = make_run(File.dirname(root), "outside-#{File.basename(root)}")
      File.symlink(outside, File.join(root, 'linked'))
      with_server(root) do |port, built|
        (TRAVERSALS + ['linked', root.delete_prefix('/'), URI.encode_www_form_component(outside)]).each do |id|
          assert_includes %w[400 404], code(port, "/run/#{id}"), "/run/#{id}"
          assert_includes %w[400 404], code(port, "/frame.png?run=#{id}"), "frame #{id}"
          assert_includes %w[400 404], code(port, "/state.json?run=#{id}"), "state #{id}"
          assert_includes %w[400 404], code(port, "/compare.json?a=#{A}&b=#{id}"), "compare #{id}"
        end
        ["/run/../#{A}", '/run/../../etc/passwd', "/run//#{A}", "/compare/#{A}/../#{B}"].each do |path|
          assert_equal '404', code(port, path), path
        end
        assert_empty built
      ensure
        FileUtils.rm_rf(outside)
      end
    end
  end

  def test_controls_are_validated_strictly
    with_root do |root|
      with_server(root) do |port, _|
        assert_equal({ 'speed' => 4, 'paused' => false }, JSON.parse(get(port, "/control?run=#{A}&speed=4").body))
        assert_equal({ 'speed' => 4, 'paused' => true }, JSON.parse(get(port, "/control?run=#{A}&pause=1").body))
        assert_equal({ 'speed' => 16, 'paused' => false }, JSON.parse(get(port, "/control?run=#{A}&pause=0&speed=16").body))
        ["/control?run=#{A}", "/control?run=#{A}&speed=2", "/control?run=#{A}&speed=4.0", "/control?run=#{A}&pause=yes",
         "/control?run=#{A}&speed=4&x=1", "/control?run=#{A}&speed=4&speed=16", '/control?speed=4'].each do |path|
          assert_equal '400', code(port, path), path
        end
        assert_equal '404', get(port, '/control?run=nope&speed=4').code
        assert_equal '404', code(port, '/control?run=%ZZ&speed=4')
      end
    end
  end

  def test_compare_json_diffs_two_runs
    with_root do |root|
      with_server(root) do |port, _|
        data = JSON.parse(get(port, "/compare.json?a=#{A}&b=#{B}").body)
        assert_equal [A, B], [data.dig('a', 'run_id'), data.dig('b', 'run_id')]
        assert_equal %w[tag dollars highest_milestone], data['differences']
        assert_equal [{ 'milestone' => 'shield', 'a' => nil, 'b' => 40 }], data['milestones']
        assert_equal [[3, 1], [4, 1]], data['places'].map { |place| place['place'] }
        assert_equal '400', get(port, "/compare.json?a=#{A}").code
        assert_equal '404', get(port, "/compare/#{A}/nope").code
      end
    end
  end

  def test_star_is_a_same_origin_post_reusing_the_star_command
    with_root do |root|
      with_server(root) do |port, _|
        assert_equal '405', get(port, "/star?run=#{B}&why=x").code
        refute File.exist?(File.join(root, B, 'star.json'))
        status, body = post_star(port, B, 'reached <b>shield</b>', origin: "http://127.0.0.1:#{port}")
        assert_equal '200', status
        assert_equal({ 'run_id' => B, 'starred' => true, 'why' => 'reached <b>shield</b>' }, JSON.parse(body))
        assert_equal 'reached <b>shield</b>', JSON.parse(File.read(File.join(root, B, 'star.json')))['why']
        assert_equal true, JSON.parse(File.read(File.join(root, B, 'summary.json')))['starred']
        assert_equal '200', post_star(port, A, 'again', host: "localhost:#{port}").first
      end
    end
  end

  def test_star_refuses_cross_origin_and_bad_input
    with_root do |root|
      with_server(root) do |port, _|
        assert_equal '403', post_star(port, B, 'x', host: "evil.example:#{port}").first
        assert_equal '403', post_star(port, B, 'x', host: "127.0.0.1:#{port + 1}").first
        assert_equal '403', post_star(port, B, 'x', host: '127.0.0.1').first
        assert_equal '403', post_star(port, B, 'x', origin: 'http://evil.example').first
        assert_equal '400', post_star(port, B, '  ').first
        assert_equal '400', post_star(port, B, 'x' * 501).first
        assert_equal '400', post_star(port, B, "a\nb").first
        assert_equal '404', post_star(port, '../x', 'x').first
        assert_equal '413', post_star(port, B, 'x', length: 100_000).first
        refute File.exist?(File.join(root, B, 'star.json'))
      end
    end
  end

  def test_a_wildcard_server_trusts_ip_literals_but_not_names
    with_root do |root|
      with_server(root, host: '0.0.0.0') do |port, _|
        assert_equal '403', post_star(port, B, 'x', host: "evil.example:#{port}").first
        assert_equal '200', post_star(port, B, 'x', host: "192.168.1.20:#{port}").first
      end
    end
  end

  def test_a_server_without_a_runs_root_has_no_explorer_routes
    server = Koholint::Viewer::Server.new(follower: StubFollower.new, feed: -> { {} })
    port = server.start
    assert_equal '404', get(port, '/runs.json').code
    assert_equal '404', get(port, "/frame.png?run=#{A}").code
    assert_equal '200', get(port, '/frame.png').code
  ensure
    server&.stop
  end

  def test_default_root_is_the_parent_when_it_holds_other_runs
    with_root do |root|
      assert_equal root, Koholint::Viewer::Explorer.default_root(File.join(root, A))
      Dir.mktmpdir do |lonely|
        assert_equal 'runs', Koholint::Viewer::Explorer.default_root(make_run(lonely, A))
      end
    end
  end
end
