require 'koholint/budget'
require 'koholint/capabilities'
require 'koholint/config'
require 'koholint/decision'
require 'koholint/engine'
require 'koholint/entities'
require 'koholint/game_state'
require 'koholint/items'
require 'koholint/ledger'
require 'koholint/navigation/planner'
require 'koholint/replay'
require 'koholint/run'
require 'koholint/skills/registry'
require 'koholint/trace'
require 'koholint/vision/capabilities'
require 'koholint/vision/world'

module Koholint
  # Offline capability learning: an item first held in a run suggests using it facing the uncatalogued objects seen after the gain;
  # each suggestion is tried in throwaway forks of the run through existing skills only, then judged from the trials.
  module Learn
    LIMIT = 10
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

      def initialize(registry:, choice:, target:, budget:, place: nil, walls: [])
        @place = place
        @walls = walls
        @point = DecisionPoint.choose_skill(registry)
        @choice = choice
        @target = target
        @budget = budget
      end

      def decision_point_for(_state) = @point

      def prepare(context)
        @ledger ||= Learn.ledger(@place, @walls, context[:ledger] || Ledger.new)
        context[:ledger] = @ledger
        @room_objects ||= context[:room_objects]
      end

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
      blocked = lineage_blocks(run)
      walls = walls(entries)
      triggers(events, since: run.manifest.dig('parent', 'frame').to_i).each do |gain|
        sightings = sightings(run, first_frames(events, gain[:frame]), events)
        candidates(gain:, sightings:, stood: stood(events), blocked:, known: entries, limit:, object:).each do |candidate|
          entry = known(entries, gain[:item], candidate[:object]) || hypothesis(gain:, object: candidate[:object], run: run.id, selected: !object.nil?)
          out.puts "#{entry['id']}: #{candidate[:blocks]} blocks in the lineage, #{candidate[:places].size} places"
          evidence = entry['evidence'] + try(run, entry, candidate[:places], root:, out:, walls:)
          status = judge(evidence)
          entries = entries.reject { |other| other['id'] == entry['id'] } + [Capabilities.transition(entry, status, verdict(evidence, status), evidence:)]
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

    # A cell entered only after a capability changed its object says nothing about that object being walkable.
    def stood(events)
      cleared = cleared(events)
      events.each_with_object(Hash.new { |hash, key| hash[key] = Set.new }) do |event, cells|
        next unless event['type'] == 'perception' && event.dig('state', 'game_mode') == PLAY_MODE

        state = event['state']
        place = [state['room_id'], state['map_id']]
        cell = GameState.cell_at(state['x'].to_i, state['y'].to_i) or next
        cells[place] << cell unless cleared[place].include?(cell)
      end
    end

    def cleared(events)
      events.each_with_object(Hash.new { |hash, key| hash[key] = Set.new }) do |event, cells|
        result = event['result'] if event['type'] == 'action'
        place = result.is_a?(Hash) && Ledger.place_of(result['from']) or next
        [*Array(result['clears']), (result if result['capability'])].compact.each do |use|
          next unless use['target'].is_a?(Hash) && use['object_before'] != use['object_after']

          cells[place] << [use['target']['row'].to_i, use['target']['col'].to_i]
        end
      end
    end

    # Cells that stopped Link, per place: a blocked move or edge (the cell ahead of it), the walls an explore found and the target of a
    # capability use whose step into it was blocked.
    def blocks(events)
      events.each_with_object(Hash.new { |hash, key| hash[key] = Set.new }) do |event, cells|
        result = event['result'] if event['type'] == 'action'
        place = result.is_a?(Hash) && Ledger.place_of(result['from']) or next
        ahead = [*Array(result['blocked_edges']), result['blocked_at']].compact.filter_map do |edge|
          delta = Skills::Composite::DELTAS[edge['direction'].to_s.to_sym] or next
          [edge['row'].to_i + delta[0], edge['col'].to_i + delta[1]]
        end
        uses = [*Array(result['clears']), (result if result['capability'])].compact
        faced = uses.filter_map do |use|
          [use['target']['row'].to_i, use['target']['col'].to_i] if use['target'].is_a?(Hash) && Array(use['steps']).any? { |step| step['skill'] == 'step' && step['stopped_by'] == 'blocked' }
        end
        (ahead + faced + Array(result['walls']).map { |wall| [wall['row'].to_i, wall['col'].to_i] }).each do |row, col|
          cells[place] << [row, col] if row.between?(0, Geometry::ROWS - 1) && col.between?(0, Geometry::COLS - 1)
        end
      end
    end

    # The run's tree under its root directory: its oldest ancestor there and every run descending from it. Blocks are sets, so the
    # trace prefix a fork copies from its parent counts once.
    def lineage(run)
      root = File.dirname(run.dir)
      parents = Dir.glob(File.join(root, '*', 'manifest.json')).to_h { |path| [File.basename(File.dirname(path)), JSON.parse(File.read(path)).dig('parent', 'id')] }
      origin = ->(id) { parents.key?(parents[id]) ? origin.(parents[id]) : id }
      top = origin.(run.id)
      parents.keys.select { |id| origin.(id) == top }.sort.map { |id| File.join(root, id) } | [run.dir]
    end

    def lineage_blocks(run)
      lineage(run).each_with_object(Hash.new { |hash, key| hash[key] = Set.new }) do |dir, all|
        blocks(Trace.read(File.join(dir, 'trace.jsonl'))).each { |place, cells| all[place].merge(cells) }
      end
    end

    # The entry already tried for an (item, object) pair; it is retried while inconclusive and some (place, cell, stand) is still untried.
    def known(entries, item, object) = entries.find { |entry| entry['trigger']['item'] == item && entry['target']['object'] == object }

    def retryable?(entry, places)
      done = tried(entry)
      entry['status'] == 'inconclusive' && triples(places).any? { |sighting, cell, stand| !done.include?([sighting[:place], cell, stand]) }
    end

    def tried(entry) = entry['evidence'].to_set { |trial| [trial['place'], trial['cell'], trial['stand']] }

    def triples(places)
      places.first(PLACES).flat_map do |sighting|
        nearest(sighting[:cells], sighting[:arrival]).first(CELLS).flat_map { |cell| stands(cell, sighting).map { |stand, direction| [sighting, cell, stand, direction] } }
      end
    end

    def sightings(run, firsts, events)
      firsts.to_h do |place, first|
        walk = Vision::World.from_events(events, at_frame: first[:frame]).grid_for(place, Vision::Capabilities.new)
        [place, first.merge(grid: Entities.room_objects(Replay.to(run, first[:frame])), walk:)]
      end
    end

    # Edges that stopped the walk to a standing cell, per place, with the trial runs that hit each.
    def walls(entries)
      walls = Hash.new { |hash, place| hash[place] = Hash.new { |edges, edge| edges[edge] = Set.new } }
      entries.each { |entry| entry['evidence'].each { |trial| note_walls(walls, trial) } }
      walls
    end

    def note_walls(walls, trial)
      Array(trial['blocked_edges']).each { |edge| walls[trial['place']][edge] << trial['run'] }
    end

    # A wall counts once trials in 2 different runs hit it, like a fact checked twice; one blocked trial may be a passing enemy.
    def confirmed(walls, place) = walls.key?(place) ? walls[place].select { |_, runs| runs.size >= Ledger::DOUBT_AT }.keys : []

    # Confirmed walls as doubtful edges, so the trial's goto plans around them like a run that was blocked there twice.
    def ledger(place, walls, ledger = Ledger.new)
      walls.each { |row, col, direction| Ledger::DOUBT_AT.times { ledger.record(place:, blocked_at: { row:, col:, direction: }) } }
      ledger
    end

    # The planner goto uses, over the place's grid at the sighting, finds a way from the arrival that avoids the known walls.
    def reachable?(sighting, stand, walls)
      return true unless sighting[:walk] && sighting[:arrival]

      planner = Navigation::Planner.new(grid: sighting[:walk], ledger: nil, place: sighting[:place])
      confirmed(walls, sighting[:place]).each { |row, col, direction| planner.avoid([row, col], direction.to_sym) }
      !planner.path(from: sighting[:arrival], to: stand).nil?
    end

    # Uncatalogued object ids Link never stood on, the ones that stopped him most often first, then the most widespread; an (item, object)
    # pair already in the file is retried only while retryable?.
    def candidates(gain:, sightings:, stood:, known:, blocked: {}, limit: LIMIT, object: nil)
      stood_ids = stood.flat_map { |place, cells| (grid = sightings.dig(place, :grid)) ? cells.map { |row, col| grid[row][col] } : [] }.to_set
      places = Hash.new { |hash, key| hash[key] = [] }
      sightings.each do |place, sighting|
        cells = Hash.new { |hash, key| hash[key] = [] }
        sighting[:grid].each_with_index { |row, r| row.each_with_index { |id, c| cells[id] << [r, c] } }
        cells.each { |id, at| places[id] << { place:, frame: sighting[:frame], arrival: sighting[:arrival], grid: sighting[:grid], walk: sighting[:walk], cells: at } }
      end
      catalogued = Entities.object_catalogue.keys
      ids = places.keys.reject do |id|
        entry = known(known, gain[:item], id)
        catalogued.include?(id) || stood_ids.include?(id) || (entry && !retryable?(entry, places[id]))
      end
      ids = ids.select { |id| id == object } if object
      hits = blocked.sum([]) { |place, cells| (grid = sightings.dig(place, :grid)) ? cells.map { |row, col| grid[row][col] } : [] }.tally
      ids.sort_by { |id| [-hits[id].to_i, -places[id].size, id] }.first(limit).map { |id| { object: id, places: places[id], blocks: hits[id].to_i } }
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

    # Per place (up to PLACES) and target cell (up to CELLS, nearest the arrival first), standing sides nearest first until one is reached;
    # a (place, cell, stand) already in the entry's evidence is never tried again, nor one the planner cannot reach past the known walls.
    def try(run, entry, places, root:, out:, walls: Learn.walls([]))
      done = tried(entry)
      reached = Set.new
      evidence = []
      triples(places).each do |sighting, cell, stand, direction|
        next if done.include?([sighting[:place], cell, stand]) || reached.include?([sighting[:place], cell])
        break if evidence.count { |trial| trial['outcome'] != 'unreached' } >= TRIALS

        unless reachable?(sighting, stand, walls)
          out.puts "  #{sighting[:place].join('-')} #{cell.inspect} from #{stand.inspect} #{direction}: skipped, no path"
          next
        end

        trial = trial(run, entry, sighting, cell, stand, direction, root:, walls: confirmed(walls, sighting[:place]))
        note_walls(walls, trial)
        out.puts "  #{sighting[:place].join('-')} #{cell.inspect} from #{stand.inspect} #{direction}: #{trial['outcome']}"
        evidence << trial
        reached << [sighting[:place], cell] unless trial['outcome'] == 'unreached'
        return evidence if judge(entry['evidence'] + evidence) == 'validated'
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

    def trial(run, entry, sighting, cell, stand, direction, root:, walls: [])
      composite = Skills::Composite.new(entry)
      registry = Skills::Registry.default(extra: [composite])
      budget = Budget.new(frames: composite.max_frames + Engine::NOT_READY_STUCK_FRAMES)
      child = run.fork(at_frame: sighting[:frame], flow_version: FLOW_VERSION, root:, tag: "learn-#{entry['id']}")
      policy = Trial.new(registry:, choice: { skill: composite.name, params: { row: stand[0], col: stand[1], direction: direction.to_s } }, target: cell, budget:,
                         place: sighting[:place], walls:)
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
      edges = label == 'unreached' ? Ledger.edges_of(Array(result[:steps]).first || {}) : []
      { 'outcome' => label, 'steps' => steps, 'before' => policy.before, 'after' => policy.after, 'frames' => result[:frames].to_i,
        'blocked_edges' => edges.map { |edge| [edge[:row], edge[:col], edge[:direction].to_s] }.uniq.then { |list| list unless list.empty? } }.compact
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
