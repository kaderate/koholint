require 'json'
require 'koholint'
require 'koholint/summary'
require 'koholint/trace'
require 'koholint/vision/capabilities'
require 'koholint/vision/grid_builder'
require 'koholint/vision/world'

module Koholint
  module Viewer
    module Feed
      RunDir = Struct.new(:dir)
      FIELDS = { 'decision' => %w[frame type agent choice confidence], 'action' => %w[frame type skill params] }.freeze

      PROGRESS = %w[notable objective].freeze
      CACHE = {}
      CACHE_LOCK = Mutex.new
      GRID_CACHE = {}
      DIRECTIONS = %i[up down left right].freeze

      module_function

      def for(run_dir, follower, limit: 30)
        manifest = read_manifest(run_dir)
        trace = trace_events(run_dir)
        summary = Summary.from_events(trace)
        summary[:health] = 'unknown' if trace.none? { |e| PROGRESS.include?(e['type']) } && %w[progressing stalled].include?(summary[:health])
        {
          status: summary.merge(run_id: File.basename(run_dir), flow_version: manifest['flow_version'],
                                manifest_status: manifest['status'], budget: manifest['budget']),
          replay: { frame: follower.frame, journal_frames: follower.journal_frames, lag: follower.lag, sync: follower.sync },
          events: events(trace, limit),
          grid: grid(run_dir, trace, follower.frame)
        }
      end

      def trace_events(run_dir)
        path = File.join(run_dir, 'trace.jsonl')
        stat = File.stat(path)
        signature = [stat.size, stat.mtime]
        CACHE_LOCK.synchronize do
          cached = CACHE[path]
          return cached.last if cached && cached.first == signature

          Trace.read(path).tap { |parsed| CACHE[path] = [signature, parsed] }
        end
      rescue SystemCallError
        []
      end

      def grid(run_dir, trace, frame)
        CACHE_LOCK.synchronize do
          cached = GRID_CACHE[run_dir]
          return cached[2] if cached && cached[0].equal?(trace) && cached[1] == frame

          build_grid(trace, frame).tap { |built| GRID_CACHE[run_dir] = [trace, frame, built] }
        end
      end

      def build_grid(trace, frame)
        screen = trace.reverse_each.find { |e| e['type'] == 'screen' && e['frame'] <= frame } or return nil
        place = screen['place']
        grid = Vision::World.from_events(trace, at_frame: frame).grid_for(place, Vision::Capabilities.new)
        rows = (0...Vision::Grid::ROWS).to_a
        cols = (0...Vision::Grid::COLS).to_a
        { place:, frame: screen['frame'],
          cells: rows.map { |row| cols.map { |col| cell_state(grid, row, col) } },
          appearances: rows.map { |row| cols.map { |col| grid.appearance(row, col) } },
          link: link_cell(trace, frame) }
      end

      def cell_state(grid, row, col)
        beliefs = DIRECTIONS.map { |direction| grid.passable(row, col, direction) }
        yes = beliefs.include?(:yes)
        no = beliefs.include?(:no)
        return 'mixed' if yes && no
        return 'yes' if yes
        return 'no' if no

        beliefs.include?(:stale) ? 'stale' : 'unknown'
      end

      def link_cell(trace, frame)
        state = trace.reverse_each.find { |e| e['type'] == 'perception' && e['frame'] <= frame }&.fetch('state', nil) or return nil
        return nil unless state['x'].is_a?(Integer) && state['y'].is_a?(Integer)

        row, col = Vision::GridBuilder.link_cell(state['x'], state['y'])
        { row:, col: } if row
      end

      def read_manifest(run_dir)
        manifest = JSON.parse(File.read(File.join(run_dir, 'manifest.json')))
        raise Error, "manifest of run #{File.basename(run_dir)} is not an object" unless manifest.is_a?(Hash)

        manifest
      rescue SystemCallError, JSON::ParserError
        raise Error, "cannot read manifest of run #{File.basename(run_dir)}"
      end

      def events(trace, limit)
        trace.select { |e| FIELDS.key?(e['type']) }.last(limit).map do |event|
          event.slice(*FIELDS[event['type']]).transform_keys(&:to_sym)
        end
      end
    end
  end
end
