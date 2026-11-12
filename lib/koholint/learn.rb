require 'koholint/budget'
require 'koholint/capabilities'
require 'koholint/config'
require 'koholint/decision'
require 'koholint/engine'
require 'koholint/entities'
require 'koholint/game_state'
require 'koholint/items'
require 'koholint/replay'
require 'koholint/run'
require 'koholint/skills/registry'
require 'koholint/trace'

module Koholint
  # Offline capability learning: an item first held in a run suggests using it facing the uncatalogued objects seen after the gain;
  # each suggestion is tried in throwaway forks of the run through existing skills only, then judged from the trials.
  module Learn
    LIMIT = 3
    PLACES = 3
    CELLS = 2
    TRIALS = 12
    REACHED_TO_REJECT = 4
    SETTLE_FRAMES = 20
    # A blocked walk recentres Link and turns him away from the obstacle; a blocked step leaves him facing it.
    FACE_PIXELS = 16
    STRIKE_FRAMES = 3
    PLAY_MODE = 0x0B
    ROOT = File.join(Config::ROOT, 'tmp', 'learn', 'runs')
    EFFECT = "walking into the target cell is blocked before the item is used and enters it after, and the cell's object id changes"

    # Runs the composite once, reading the target cell's object id before and after it, then stops the engine.
    class Trial
      attr_reader :before, :after, :outcome

      def initialize(registry:, choice:, target:, budget:)
        @point = DecisionPoint.choose_skill(registry)
        @choice = choice
        @target = target
        @budget = budget
      end

      def decision_point_for(_state) = @point

      def prepare(context) = @room_objects ||= context[:room_objects]

      def decide(_decision_point, _state, context)
        prepare(context)
        @before = id_at_target
        { choice: @choice, justification: 'capability trial', confidence: 1.0, agent: 'learner', latency_ms: 0, cost_usd: 0.0 }
      end

      def after_action(outcome:, **)
        @outcome = outcome
        @after = id_at_target
        @budget.stop!(:trial_done)
      end

      private

      def id_at_target = @room_objects.call.dig(*@target)
    end

    module_function

    def learn(run, limit: LIMIT, object: nil, path: Capabilities::DEFAULT_PATH, root: ROOT, out: $stdout)
      events = Trace.read(File.join(run.dir, 'trace.jsonl'))
      entries = Capabilities.load(path)
      triggers(events, since: run.manifest.dig('parent', 'frame').to_i).each do |gain|
        sightings = sightings(run, first_frames(events, gain[:frame]))
        candidates(gain:, sightings:, stood: stood(events), known: entries, limit:, object:).each do |candidate|
          entry = hypothesis(gain:, object: candidate[:object], run: run.id, selected: !object.nil?)
          out.puts "#{entry['id']}: #{candidate[:places].size} places"
          evidence = try(run, entry, candidate[:places], root:, out:)
          status = judge(evidence)
          entries += [Capabilities.transition(entry, status, verdict(evidence, status), evidence:)]
          Capabilities.write(entries, path)
          out.puts "#{entry['id']}: #{status} (#{verdict(evidence, status)})"
        end
      end
      0
    end

    # Items first held at or after the run's own first frame; read from perceptions, since a fork drops the item_gained of its fork frame.
    def triggers(events, since: 0)
      seen = {}
      events.each do |event|
        next unless event['type'] == 'perception' && event.dig('state', 'game_mode') == PLAY_MODE

        state = event['state']
        [state['item_a'], state['item_b'], *Array(state['inventory']).first(Items::SLOTS)].map(&:to_i).reject(&:zero?).each { |id| seen[id] ||= event['frame'] }
      end
      seen.filter_map { |id, frame| { item: id, name: Items.name(id), frame: } if frame >= since }
    end

    def first_frames(events, since)
      events.each_with_object({}) do |event, firsts|
        next unless event['type'] == 'perception' && event['frame'] >= since && event.dig('state', 'game_mode') == PLAY_MODE

        state = event['state']
        firsts[[state['room_id'], state['map_id']]] ||= { frame: event['frame'], arrival: GameState.cell_at(state['x'].to_i, state['y'].to_i) }
      end
    end

    def stood(events)
      events.each_with_object(Hash.new { |hash, key| hash[key] = Set.new }) do |event, cells|
        next unless event['type'] == 'perception' && event.dig('state', 'game_mode') == PLAY_MODE

        state = event['state']
        cell = GameState.cell_at(state['x'].to_i, state['y'].to_i) or next
        cells[[state['room_id'], state['map_id']]] << cell
      end
    end

    def sightings(run, firsts)
      firsts.to_h { |place, first| [place, first.merge(grid: Entities.room_objects(Replay.to(run, first[:frame])))] }
    end

    # Uncatalogued object ids Link never stood on, most widespread first; an (item, object) pair already in the file is never retried.
    def candidates(gain:, sightings:, stood:, known:, limit: LIMIT, object: nil)
      stood_ids = stood.flat_map { |place, cells| (grid = sightings.dig(place, :grid)) ? cells.map { |row, col| grid[row][col] } : [] }.to_set
      tried = known.filter_map { |entry| entry['target']['object'] if entry['trigger']['item'] == gain[:item] }
      places = Hash.new { |hash, key| hash[key] = [] }
      sightings.each do |place, sighting|
        cells = Hash.new { |hash, key| hash[key] = [] }
        sighting[:grid].each_with_index { |row, r| row.each_with_index { |id, c| cells[id] << [r, c] } }
        cells.each { |id, at| places[id] << { place:, frame: sighting[:frame], arrival: sighting[:arrival], grid: sighting[:grid], cells: at } }
      end
      catalogued = Entities.object_catalogue.keys
      ids = places.keys.reject { |id| catalogued.include?(id) || stood_ids.include?(id) || tried.include?(id) }
      ids = ids.select { |id| id == object } if object
      ids.sort_by { |id| [-places[id].size, id] }.first(limit).map { |id| { object: id, places: places[id] } }
    end

    def hypothesis(gain:, object:, run:, selected: false)
      item = Items.name(gain[:item]).to_s.delete('?').strip
      slug = item.downcase.gsub(/[^a-z0-9]+/, '_').gsub(/\A_|_\z/, '')
      { 'id' => "#{slug.tr('_', '-')}-on-object-#{object}", 'name' => "#{slug}_on_object_#{object}", 'version' => 1, 'status' => 'hypothesis',
        'trigger' => { 'run' => run, 'frame' => gain[:frame], 'item' => gain[:item] }, 'target' => { 'object' => object },
        'steps' => steps(item), 'effect' => EFFECT, 'evidence' => [],
        'source' => "koholint learn: item #{gain[:item]} gained at frame #{gain[:frame]} of run #{run}; object #{object} seen after it and never stood on#{'; the object id was selected by --object (manual override of the ranking)' if selected}",
        'history' => [{ 'version' => 1, 'status' => 'hypothesis', 'reason' => "item #{gain[:item]} gained in run #{run}" }] }
    end

    def steps(item)
      [{ 'skill' => 'goto', 'params' => { 'row' => '$row', 'col' => '$col' }, 'accept' => %w[done] },
       { 'skill' => 'step', 'params' => { 'direction' => '$direction', 'pixels' => FACE_PIXELS }, 'accept' => %w[blocked] },
       { 'skill' => 'use_item', 'params' => { 'item' => item, 'frames' => STRIKE_FRAMES }, 'accept' => %w[done] },
       { 'skill' => 'wait', 'params' => { 'frames' => SETTLE_FRAMES }, 'accept' => %w[done] },
       { 'skill' => 'walk', 'params' => { 'direction' => '$direction', 'cells' => 1 }, 'accept' => %w[done] }]
    end

    # Per place (up to PLACES) and target cell (up to CELLS, nearest the arrival first), standing sides nearest first until one is reached.
    def try(run, entry, places, root:, out:)
      evidence = []
      places.first(PLACES).each do |sighting|
        nearest(sighting[:cells], sighting[:arrival]).first(CELLS).each do |cell|
          stands(cell, sighting).each do |stand, direction|
            break if evidence.count { |trial| trial['outcome'] != 'unreached' } >= TRIALS

            trial = trial(run, entry, sighting, cell, stand, direction, root:)
            out.puts "  #{sighting[:place].join('-')} #{cell.inspect} from #{stand.inspect} #{direction}: #{trial['outcome']}"
            evidence << trial
            break unless trial['outcome'] == 'unreached'
          end
          return evidence if judge(evidence) == 'validated'
        end
      end
      evidence
    end

    def stands(cell, sighting)
      Skills::Composite::DELTAS.filter_map do |direction, (dr, dc)|
        stand = [cell[0] - dr, cell[1] - dc]
        next unless stand[0].between?(0, Geometry::ROWS - 1) && stand[1].between?(0, Geometry::COLS - 1)
        next if sighting[:grid][stand[0]][stand[1]] == sighting[:grid][cell[0]][cell[1]]

        [stand, direction]
      end.then { |options| nearest(options, sighting[:arrival]) { |option| option.first } }
    end

    def nearest(items, from, &key)
      return items unless from

      key ||= ->(item) { item }
      items.sort_by { |item| key.(item).zip(from).sum { |a, b| (a - b).abs } }
    end

    def trial(run, entry, sighting, cell, stand, direction, root:)
      composite = Skills::Composite.new(entry)
      registry = Skills::Registry.default(extra: [composite])
      budget = Budget.new(frames: composite.max_frames + Engine::NOT_READY_STUCK_FRAMES)
      child = run.fork(at_frame: sighting[:frame], flow_version: FLOW_VERSION, root:, tag: "learn-#{entry['id']}")
      policy = Trial.new(registry:, choice: { skill: composite.name, params: { row: stand[0], col: stand[1], direction: direction.to_s } }, target: cell, budget:)
      Engine.resume(child.dir, policy:, budget:, grid: true).run
      outcome(policy, entry).merge('run' => child.id, 'parent' => run.id, 'frame' => sighting[:frame], 'place' => sighting[:place],
                                   'cell' => cell, 'stand' => stand, 'direction' => direction.to_s)
    end

    def outcome(policy, entry)
      result = policy.outcome || {}
      steps = Array(result[:steps]).map { |step| step[:stopped_by].to_s }
      object = entry['target']['object']
      label = if steps.first != 'done' then 'unreached'
              elsif steps[1] != 'blocked' then 'not_solid'
              elsif result[:effect] && policy.before == object && policy.after != object then 'success'
              else 'failure'
              end
      { 'outcome' => label, 'steps' => steps, 'before' => policy.before, 'after' => policy.after, 'frames' => result[:frames].to_i }
    end

    def judge(evidence)
      reached = evidence.reject { |trial| trial['outcome'] == 'unreached' }
      successes = reached.select { |trial| trial['outcome'] == 'success' }
      return 'validated' if successes.map { |trial| trial['place'] }.uniq.size >= Capabilities::PLACES_TO_VALIDATE
      return 'rejected' if successes.empty? && reached.size >= REACHED_TO_REJECT && reached.map { |trial| trial['place'] }.uniq.size >= 2

      'inconclusive'
    end

    def verdict(evidence, status)
      counts = evidence.group_by { |trial| trial['outcome'] }.transform_values(&:size).sort.map { |label, n| "#{n} #{label}" }.join(', ')
      places = evidence.select { |trial| trial['outcome'] == 'success' }.map { |trial| trial['place'].join('-') }.uniq
      "#{status} by koholint learn: #{counts.empty? ? 'no trial' : counts}#{places.empty? ? '' : "; successes in #{places.join(', ')}"}"
    end
  end
end
