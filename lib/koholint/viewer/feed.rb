require 'json'
require 'weakref'
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
      FIELDS = {
        'decision' => %w[frame type decision_point agent choice confidence justification fallback],
        'action' => %w[frame type skill params result],
        'objective' => %w[frame type id status predicate title reason],
        'dialogue' => %w[frame type place text source page]
      }.freeze

      CACHE = {}
      CACHE_LOCK = Mutex.new
      GRID_CACHE = {}
      MAX_RUNS = 4
      GRID_TYPES = %w[screen affordance perception].freeze
      DIRECTIONS = %i[up down left right].freeze

      module_function

      def for(run_dir, follower, limit: 30)
        manifest = read_manifest(run_dir)
        trace = trace_events(run_dir)
        summary = Summary.from_events(trace)
        summary[:health] = 'unknown' if trace.none? { |e| Summary.progress?(e) } && %w[progressing stalled].include?(summary[:health])
        {
          status: summary.merge(run_id: File.basename(run_dir), flow_version: manifest['flow_version'],
                                manifest_status: manifest['status'], budget: manifest['budget'], calls: calls(trace)),
          replay: { frame: follower.frame, journal_frames: follower.journal_frames, lag: follower.lag, sync: follower.sync },
          events: events(trace, limit),
          grid: grid(run_dir, trace, follower.frame)
        }
      end

      def calls(trace)
        trace.count { |e| e['type'] == 'decision' && (e['agent'] == 'claude' || e['cost_usd'].to_f.positive?) }
      end

      def trace_events(run_dir)
        path = File.join(run_dir, 'trace.jsonl')
        stat = File.stat(path)
        signature = [stat.size, stat.mtime]
        CACHE_LOCK.synchronize do
          cached = CACHE[path]
          return remember(CACHE, path, cached).last if cached && cached.first == signature

          Trace.read(path).tap { |parsed| remember(CACHE, path, [signature, parsed]) }
        end
      rescue SystemCallError
        []
      end

      def remember(cache, key, value)
        cache.delete(key)
        cache[key] = value
        cache.shift while cache.size > MAX_RUNS
        value
      end

      def grid(run_dir, trace, frame)
        CACHE_LOCK.synchronize do
          entry = GRID_CACHE[run_dir]
          entry = { source: WeakRef.new(trace), lists: grid_events(trace) } unless entry && same_trace?(entry[:source], trace)
          unless entry[:frame] == frame && entry.key?(:built)
            entry = entry.slice(:source, :lists).merge(frame:, built: build_grid(entry[:lists], frame))
          end
          remember(GRID_CACHE, run_dir, entry)[:built]
        end
      end

      def sound_screen?(event)
        rows = event['grid']
        sprites = event.fetch('static_sprites', [])
        rows.size == Vision::Grid::ROWS && rows.all? { |row| row.is_a?(Array) && row.size == Vision::Grid::COLS } &&
          sprites.is_a?(Array) && sprites.all? { |s| s.is_a?(Hash) && s['x'].is_a?(Integer) && s['y'].is_a?(Integer) }
      end

      def usable_affordance?(event)
        event['action'].is_a?(String) && event.fetch('context', []).is_a?(Array) && %w[yes no].include?(event['result']) &&
          [nil, *DIRECTIONS.map(&:to_s)].include?(event['direction'])
      end

      def same_trace?(ref, trace) = (ref.__getobj__.equal?(trace) rescue false)

      def grid_events(trace)
        usable = trace.select { |e| e.is_a?(Hash) && GRID_TYPES.include?(e['type']) && e['frame'].is_a?(Integer) }
        { screens: usable.select { |e| e['type'] == 'screen' && e['place'].is_a?(Array) && e['grid'].is_a?(Array) && sound_screen?(e) },
          affordances: usable.select { |e| e['type'] == 'affordance' && usable_affordance?(e) },
          perceptions: usable.select { |e| e['type'] == 'perception' } }
      end

      def build_grid(lists, frame)
        screen = lists[:screens].reverse_each.find { |e| e['frame'] <= frame } or return nil
        world = Vision::World.from_events(lists[:screens] + lists[:affordances], at_frame: frame)
        grid = world.grid_for(screen['place'], Vision::Capabilities.new) or return nil
        rows = (0...Vision::Grid::ROWS).to_a
        cols = (0...Vision::Grid::COLS).to_a
        { place: screen['place'], frame: screen['frame'],
          cells: rows.map { |row| cols.map { |col| cell_state(grid, row, col) } },
          appearances: rows.map { |row| cols.map { |col| grid.appearance(row, col) } },
          link: link_cell(lists[:perceptions], frame) }
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

      def link_cell(perceptions, frame)
        state = perceptions.reverse_each.find { |e| e['frame'] <= frame }&.fetch('state', nil)
        return nil unless state.is_a?(Hash) && state['x'].is_a?(Integer) && state['y'].is_a?(Integer)

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
