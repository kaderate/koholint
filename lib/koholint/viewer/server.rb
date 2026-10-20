require 'ipaddr'
require 'json'
require 'socket'
require 'uri'
require 'koholint'
require 'koholint/viewer/explorer'
require 'koholint/viewer/registry'

module Koholint
  module Viewer
    class Server
      PAGE_PATH = File.join(__dir__, 'page.html')
      PAGES = { runs: File.join(__dir__, 'runs.html'), compare: File.join(__dir__, 'compare.html') }.freeze
      MAX_LINE = 8192
      MAX_HEADERS = 100
      MAX_BODY = 4096
      READ_TIMEOUT = 5

      attr_reader :listener
      attr_writer :follower, :feed, :explorer

      def initialize(follower: nil, feed: nil, explorer: nil, port: 0, host: '127.0.0.1', read_timeout: READ_TIMEOUT)
        @follower = follower
        @feed = feed
        @explorer = explorer
        @port = port
        @read_timeout = read_timeout
        @host = host
        @connections = []
        @clients = []
        @lock = Mutex.new
      end

      def bind
        @page = File.binread(PAGE_PATH)
        @pages = PAGES.transform_values { |path| File.binread(path) }
        @listener ||= TCPServer.new(@host, @port)
        @listener.local_address.ip_port
      rescue Errno::EADDRINUSE
        raise Error, "port #{@port} is already in use; choose another port with --port"
      end

      def start
        port = bind
        @acceptor = Thread.new { accept_loop }
        port
      end

      def stop
        @listener&.close
        @acceptor&.join(2)
        threads, clients = @lock.synchronize { [@connections.dup, @clients.dup] }
        clients.each { |client| client.close unless client.closed? rescue nil }
        threads.each { |thread| thread.join(1) || thread.kill }
      end

      private

      def accept_loop
        loop do
          socket = @listener.accept
          @lock.synchronize do
            @clients.reject!(&:closed?)
            @clients << socket
          end
          thread = Thread.new(socket) { |client| serve(client) }
          @lock.synchronize do
            @connections.select!(&:alive?)
            @connections << thread
          end
        end
      rescue IOError, Errno::EBADF
        nil
      end

      def serve(client)
        line = read_line(client)
        return unless line

        headers = read_headers(client) or return
        method, target, = line.split(' ')
        path, query = target.to_s.split('?', 2)
        body = method == 'POST' ? read_body(client, headers['content-length']) : ''
        status, type, body, extra = body ? respond(method, path, query.to_s, headers, body) : too_large
        head = "HTTP/1.1 #{status}\r\nContent-Type: #{type}\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n"
        COMMON.merge(type.start_with?('text/html') ? HTML : {}, extra).each { |name, value| head << "#{name}: #{value}\r\n" }
        client.write("#{head}\r\n", body)
      rescue IOError, SystemCallError
        nil
      ensure
        client.close unless client.closed?
      end

      def read_line(client)
        return nil unless client.wait_readable(@read_timeout)

        client.gets("\n", MAX_LINE)
      end

      def read_headers(client)
        headers = {}
        MAX_HEADERS.times do
          header = read_line(client) or return nil
          return headers if header.strip.empty?

          name, value = header.split(':', 2)
          headers[name.strip.downcase] = value.to_s.strip if value
        end
        nil
      end

      def read_body(client, length)
        return nil unless length.to_s.match?(/\A\d{1,5}\z/) && length.to_i <= MAX_BODY

        data = +''
        while data.bytesize < length.to_i
          return nil unless client.wait_readable(@read_timeout)

          data << client.readpartial(length.to_i - data.bytesize)
        end
        data
      end

      def too_large = ['413 Content Too Large', 'text/plain', "request body missing or too large\n", {}]

      def respond(method, path, query, headers, body)
        return post(path, query, headers, body) if method == 'POST'
        return not_allowed('GET') unless method == 'GET'

        get(path, params(query))
      rescue Explorer::NotFound
        ['404 Not Found', 'text/plain', "not found\n", {}]
      rescue Explorer::BadRequest, ArgumentError, EncodingError => e
        ['400 Bad Request', 'application/json', JSON.generate(error: e.message), NO_STORE]
      rescue StandardError => e
        ['500 Internal Server Error', 'application/json', JSON.generate(error: e.message), NO_STORE]
      end

      def get(path, params)
        case path
        when '/' then html(@page)
        when '/frame.png' then ['200 OK', 'image/png', params['run'] ? registry.frame_png(run_dir(params['run'])) : @follower.frame_png, NO_STORE]
        when '/state.json' then json(params['run'] ? registry.state(run_dir(params['run'])) : @feed.call)
        when '/runs' then html(@pages[:runs])
        when '/runs.json' then json(explorer.runs)
        when '/compare.json' then json(explorer.compare(*only(params, %w[a b], required: %w[a b]).values_at('a', 'b')))
        when '/control' then json(control(only(params, %w[run speed pause], required: %w[run])))
        when '/star' then not_allowed('POST')
        when %r{\A/run/([^/]+)\z} then run_dir(segment(::Regexp.last_match(1))) && html(@page)
        when %r{\A/compare/([^/]+)/([^/]+)\z}
          [::Regexp.last_match(1), ::Regexp.last_match(2)].each { |id| run_dir(segment(id)) }
          html(@pages[:compare])
        else ['404 Not Found', 'text/plain', "not found\n", {}]
        end
      end

      def post(path, query, headers, body)
        return not_allowed('GET') unless path == '/star'
        return ['403 Forbidden', 'text/plain', "cross-origin request refused\n", {}] unless same_origin?(headers)

        run = only(params(query), %w[run], required: %w[run])['run']
        why = only(params(body), %w[why], required: %w[why])['why']
        json(explorer.star(run, why))
      end

      def control(params)
        speed = params['speed']
        pause = params['pause']
        raise Explorer::BadRequest, 'give speed or pause' unless speed || pause
        raise Explorer::BadRequest, 'speed must be 1, 4 or 16' unless speed.nil? || Registry::SPEEDS.map(&:to_s).include?(speed)
        raise Explorer::BadRequest, 'pause must be 0 or 1' unless pause.nil? || %w[0 1].include?(pause)

        registry.control(run_dir(params['run']), speed: speed&.to_i, paused: pause && pause == '1')
      end

      def params(query)
        pairs = URI.decode_www_form(query)
        raise Explorer::BadRequest, 'repeated parameter' unless pairs.map(&:first).uniq.size == pairs.size

        pairs.to_h.each_value { |value| raise Explorer::BadRequest, 'invalid encoding' unless value.valid_encoding? }
      end

      def only(params, allowed, required: [])
        raise Explorer::BadRequest, "unknown parameter #{(params.keys - allowed).first.inspect}" unless (params.keys - allowed).empty?
        raise Explorer::BadRequest, "missing parameter #{(required - params.keys).first}" unless (required - params.keys).empty?

        params
      end

      def segment(text)
        decoded = URI.decode_www_form_component(text)
        raise Explorer::NotFound, 'no such run' unless decoded.valid_encoding?

        decoded
      end

      def explorer = @explorer || raise(Explorer::NotFound, 'no runs root')

      def registry = explorer.registry

      def run_dir(id) = explorer.resolve(id)

      def same_origin?(headers)
        host = headers['host'].to_s
        name, port = host.match(/\A(\[[0-9a-fA-F:.]+\]|[^:\[\]]+):(\d{1,5})\z/)&.captures
        return false unless name && port.to_i == @listener.local_address.ip_port && trusted_name?(name.delete('[]'))

        origin = headers['origin']
        origin.nil? || origin == "http://#{host}"
      end

      def trusted_name?(name)
        return true if name == @host
        return true if (LOOPBACK + WILDCARD).include?(@host) && LOOPBACK.include?(name)

        WILDCARD.include?(@host) && ip_literal?(name)
      end

      def ip_literal?(name)
        IPAddr.new(name) && true
      rescue IPAddr::Error
        false
      end

      def html(page) = ['200 OK', 'text/html; charset=utf-8', page, {}]

      def json(value) = ['200 OK', 'application/json', JSON.generate(value), NO_STORE]

      def not_allowed(allow) = ['405 Method Not Allowed', 'text/plain', "method not allowed\n", { 'Allow' => allow }]

      LOOPBACK = %w[127.0.0.1 localhost ::1].freeze
      WILDCARD = %w[0.0.0.0 ::].freeze
      COMMON = { 'X-Content-Type-Options' => 'nosniff' }.freeze
      HTML = { 'Content-Security-Policy' => "default-src 'self'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; " \
                                           "img-src 'self' blob:; frame-ancestors 'none'" }.freeze
      NO_STORE = { 'Cache-Control' => 'no-store' }.freeze
    end
  end
end
