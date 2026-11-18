require 'koholint/budget'
require 'koholint/config'
require 'koholint/decision'
require 'koholint/dialogues'
require 'koholint/engine'
require 'koholint/exits'
require 'koholint/geometry'
require 'koholint/run'
require 'koholint/skills/registry'
require 'koholint/summary'
require 'koholint/trace'

module Koholint
  # Offline exit bench: from keyframes of a run in a puzzle's place, each way out (the four sides and the doors the place cards list) is tried
  # in a throwaway fork by existing skills only, with no model call; the arrival and the way back are recorded as exit edges with their context.
  module Bench
    ROOT = File.join(Config::ROOT, 'tmp', 'bench', 'runs')
    SIDES = %i[up down left right].freeze
    OPPOSITE = { up: :down, down: :up, left: :right, right: :left }.freeze
    STANDS = 10
    CROSS_CELLS = 2
    TRIAL_FRAMES = 3000
    VISITS = 2
    SETTLE_FRAMES = 10

    # Walks to the nearest border cell of a side that goto reaches, walks out, then walks back the opposite way from the landing.
    class ExitTrial
      attr_reader :arrival, :back, :outcome

      def initialize(registry:, place:, stands:, direction:, budget:)
        @place = place
        @point = DecisionPoint.choose_skill(registry)
        @stands = stands.dup
        @direction = direction
        @budget = budget
        @phase = :approach
        @outcome = :unreached
      end

      def decision_point_for(_state) = @point

      def decide(_decision_point, state, _context)
        return answer({ skill: 'advance_dialogue', params: {} }) if state.dialog_open?
        return answer({ skill: 'wait', params: { frames: SETTLE_FRAMES } }) unless state.phase(booted: true) == :playing

        place = [state.room_id, state.map_id]
        @origin ||= place
        return answer(stop(:wrong_start)) unless @origin == @place

        answer(next_choice(place, state))
      end

      def answer(choice) = { choice:, justification: 'exit bench', confidence: 1.0, agent: 'learner', latency_ms: 0, cost_usd: 0.0 }

      def after_action(choice:, outcome:, state:, **)
        return unless @origin && %w[goto walk].include?(choice[:skill].to_s)

        place = [state.room_id, state.map_id]
        @phase = case @phase
                 when :approach then place == @origin && outcome[:stopped_by].to_s == 'done' ? :cross : :approach
                 when :cross then place == @origin ? :approach : :landed
                 when :back then :returned
                 else @phase
                 end
      end

      private

      def next_choice(place, state)
        case @phase
        when :approach then approach
        when :cross then { skill: 'walk', params: { direction: @direction.to_s, cells: CROSS_CELLS } }
        when :landed
          @arrival = { to: place, landing: state.cell }
          @phase = :back
          { skill: 'walk', params: { direction: OPPOSITE.fetch(@direction).to_s, cells: CROSS_CELLS } }
        else finish(place, state)
        end
      end

      def approach
        stand = @stands.shift
        return stop(:unreached) unless stand

        { skill: 'goto', params: { row: stand[0], col: stand[1] } }
      end

      def finish(place, state)
        @back = { to: place, landing: state.cell }
        @outcome = :left
        stop(:left)
      end

      def stop(outcome)
        @outcome = outcome
        @budget.stop!(:trial_done)
        { skill: 'wait', params: { frames: 1 } }
      end
    end

    module_function

    # Runs every way of each puzzle place of the run (or of place:), from up to two visits (or the keyframe at:), and writes the edges and the bench record.
    def exits(run, place: nil, at: nil, root: ROOT, path: Exits::DEFAULT_PATH, out: $stdout)
      events = Trace.read(File.join(run.dir, 'trace.jsonl'))
      data = Exits.load(path)
      places = place ? [place] : events.select { |event| event['type'] == 'puzzle' }.map { |event| event['place'] }.uniq
      out.puts 'no puzzle in this run' if places.empty?
      places.each do |where|
        starts = at ? [{ frame: at, visit: at }] : keyframes(events, where).last(VISITS)
        out.puts "#{where.join('-')}: no keyframe in this place" if starts.empty?
        starts.each { |start| bench_place(run, events, data, where, start, root:, out:) }
        Exits.write(data, path)
      end
      0
    end

    def bench_place(run, events, data, place, start, root:, out:)
      state = state_at(events, start[:frame])
      context = Exits.context(state)
      link = Geometry.cell_for(state['x'], state['y']) || [3, 4]
      ways = SIDES.map { |side| [side, border(side, link)] } + doors(events, place, start[:frame]).map { |door| [door, [[door[0] + 1, door[1]]]] }
      results = ways.to_h do |way, stands|
        trial = trial(run, start[:frame], place, way.is_a?(Array) ? :up : way, stands, root:)
        record(data, place, way, context, start, trial, run)
        out.puts "  #{place.join('-')} #{way.inspect} from #{start[:frame]}: #{trial[:outcome]} #{trial.dig(:arrival, :to)&.join('-')} back #{trial.dig(:back, :to)&.join('-')} (#{trial[:run]})"
        [way.is_a?(Array) ? way.join('-') : way.to_s, trial.dig(:arrival, :to)]
      end
      note_bench(data, events, place, context, start, results, run)
    end

    def trial(run, frame, place, direction, stands, root:)
      budget = Budget.new(frames: TRIAL_FRAMES)
      child = run.fork(at_frame: frame, flow_version: FLOW_VERSION, root:, tag: 'bench-exit')
      policy = ExitTrial.new(registry: Skills::Registry.default, place:, stands:, direction:, budget:)
      Engine.resume(child.dir, policy:, budget:, grid: true).run
      { outcome: policy.outcome, arrival: policy.arrival, back: policy.back, run: child.id }
    end

    def record(data, place, way, context, start, trial, run)
      key = way.is_a?(Array) ? way : way.to_s
      source = { 'run' => trial[:run], 'parent' => run.id, 'frame' => start[:frame], 'visit' => start[:visit] }
      arrival = trial[:arrival]
      unless arrival
        Exits.record(data, place:, way: key, context:, trial: source.merge('to' => nil, 'outcome' => trial[:outcome].to_s))
        return
      end

      neighbour = Geometry.neighbour(place, way) unless way.is_a?(Array)
      refutes = { 'to' => neighbour, 'source' => 'neighbour' } if neighbour && neighbour != arrival[:to]
      Exits.record(data, place:, way: key, context:, trial: source.merge('to' => arrival[:to], 'landing' => arrival[:landing]), refutes:)
      back = trial[:back] or return

      reverse = way.is_a?(Array) ? 'down' : OPPOSITE.fetch(way).to_s
      refuted = { 'to' => place, 'source' => 'reverse' } if back[:to] != place
      Exits.record(data, place: arrival[:to], way: reverse, context:, trial: source.merge('to' => back[:to], 'landing' => back[:landing], 'from_landing' => arrival[:landing]),
                         refutes: refuted)
    end

    # What the bench found for the place in this context: a way to a place the run never saw leads on; none means the outcome depends on context,
    # and the texts read there are kept as hypotheses, by lead id or dialogue frame, without a guess.
    def note_bench(data, events, place, context, start, results, run)
      seen = Summary.visited_places(events)
      fresh = results.values.compact.uniq.reject { |to| seen.include?(to) }
      texts = events.select { |event| event['place'] == place && event['frame'] <= start[:frame] && %w[lead dialogue].include?(event['type']) }
      leads = texts.select { |event| event['type'] == 'lead' }.map { |event| { 'type' => 'lead', 'id' => event['id'], 'frame' => event['frame'], 'quote' => event['quote'] } }
      dialogues = texts.select { |event| event['type'] == 'dialogue' }.group_by { |event| event['frame'] }
                       .map { |frame, pages| { 'type' => 'dialogue', 'frame' => frame, 'text' => Dialogues.text(pages.map { |page| page['text'] }) } }
      hypotheses = (leads + dialogues).uniq { |hypothesis| hypothesis['id'] || hypothesis['frame'] }.sort_by { |hypothesis| hypothesis['frame'] }
      bench = data['benches'].find { |known| known['place'] == place && known['context'] == context }
      bench ||= { 'place' => place, 'context' => context, 'runs' => [] }.tap { |fresh_bench| data['benches'] << fresh_bench }
      bench['runs'] |= [{ 'parent' => run.id, 'frame' => start[:frame] }]
      bench['ways'] = (bench['ways'] || {}).merge(results.transform_values { |to| to || 'unreached' })
      bench['new_places'] = ((bench['new_places'] || []) | fresh)
      bench['status'] = bench['new_places'].empty? ? 'depends_on_context' : 'leads_on'
      bench['hypotheses'] = bench['new_places'].empty? ? (Array(bench['hypotheses']) | hypotheses).sort_by { |hypothesis| hypothesis['frame'] } : []
    end

    # The first keyframe of each visit to the place, with the visit's first frame (the last one of a visit can catch Link already leaving).
    def keyframes(events, place)
      visit = nil
      found = {}
      events.each do |event|
        case event['type']
        when 'perception'
          here = [event.dig('state', 'room_id'), event.dig('state', 'map_id')]
          visit = here == place ? visit || event['frame'] : nil
        when 'keyframe'
          found[visit] ||= { frame: event['frame'], visit: } if visit
        end
      end
      found.values
    end

    def state_at(events, frame) = events.reverse_each.find { |event| event['type'] == 'perception' && event['frame'] <= frame }&.dig('state') || {}

    def border(side, link)
      cells = case side
              when :up then Geometry::COLS.times.map { |col| [0, col] }
              when :down then Geometry::COLS.times.map { |col| [Geometry::ROWS - 1, col] }
              when :left then Geometry::ROWS.times.map { |row| [row, 0] }
              else Geometry::ROWS.times.map { |row| [row, Geometry::COLS - 1] }
              end
      cells.sort_by { |cell| [(cell[0] - link[0]).abs + (cell[1] - link[1]).abs, cell] }.first(STANDS)
    end

    def doors(events, place, frame)
      card = events.reverse_each.find { |event| event['type'] == 'place_card' && event['place'] == place && event['frame'] <= frame }
      Array(card && card['doors']).filter_map { |door| door['cell'] if door.is_a?(Hash) }
    end
  end
end
