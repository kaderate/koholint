require 'socket'
require 'json'
require 'koholint'

module Koholint
  module Viewer
    class Server
      PAGE_PATH = File.join(__dir__, 'page.html')
      MAX_LINE = 8192

      attr_reader :listener

      def initialize(follower:, feed:, port: 0, host: '127.0.0.1')
        @follower = follower
        @feed = feed
        @port = port
        @host = host
        @connections = []
        @lock = Mutex.new
      end

      def start
        @page = File.binread(PAGE_PATH)
        @listener = TCPServer.new(@host, @port)
        @acceptor = Thread.new { accept_loop }
        @listener.local_address.ip_port
      rescue Errno::EADDRINUSE
        raise Error, "port #{@port} is already in use"
      end

      def stop
        @listener&.close
        @acceptor&.join(2)
        threads = @lock.synchronize { @connections.dup }
        threads.each { |thread| thread.join(1) || thread.kill }
      end

      private

      def accept_loop
        loop do
          socket = @listener.accept
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
        line = client.gets("\n", MAX_LINE)
        return unless line

        while (header = client.gets("\n", MAX_LINE)) && header.strip != ''; end
        method, target, = line.split(' ')
        status, type, body, extra = respond(method, target.to_s.split('?').first)
        head = "HTTP/1.1 #{status}\r\nContent-Type: #{type}\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n"
        extra.each { |name, value| head << "#{name}: #{value}\r\n" }
        client.write("#{head}\r\n", body)
      rescue IOError, SystemCallError
        nil
      ensure
        client.close unless client.closed?
      end

      def respond(method, path)
        return ['405 Method Not Allowed', 'text/plain', "method not allowed\n", { 'Allow' => 'GET' }] unless method == 'GET'

        case path
        when '/' then ['200 OK', 'text/html; charset=utf-8', @page, {}]
        when '/frame.png' then ['200 OK', 'image/png', @follower.frame_png, NO_STORE]
        when '/state.json' then ['200 OK', 'application/json', JSON.generate(@feed.call), NO_STORE]
        else ['404 Not Found', 'text/plain', "not found\n", {}]
        end
      rescue StandardError => e
        ['500 Internal Server Error', 'application/json', JSON.generate(error: e.message), NO_STORE]
      end

      NO_STORE = { 'Cache-Control' => 'no-store' }.freeze
    end
  end
end
