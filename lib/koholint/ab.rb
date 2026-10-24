require 'fileutils'
require 'json'
require 'shellwords'
require 'koholint/game_state'
require 'koholint/summary'
require 'koholint/trace'

module Koholint
  module AB
    ARMS = { 'autopilot' => 'on', 'off' => 'off' }.freeze
    BIN = File.expand_path('../../bin/koholint', __dir__)
    COST_SHARE = 0.5
    PLACES_SHARE = 0.9

    module_function

    def plan(parent:, at_frame:, arms: ARMS.keys, forks: 3, dollars: 0.8, frames: 3000, tag: 'ab', root: 'tmp/ab/runs', model: nil, out_dir: 'tmp/ab')
      unknown = arms - ARMS.keys
      raise Error, "unknown arms #{unknown.join(', ')} (known: #{ARMS.keys.join(', ')})" unless unknown.empty?

      runs = (1..forks).flat_map do |k|
        arms.map do |arm|
          name = "#{tag}-#{arm}-#{k}"
          mode = ARMS.fetch(arm)
          { arm:, k:, tag: name,
            fork: ['fork', parent, '--at-frame', at_frame.to_s, '--root', root, '--tag', name, '--autopilot', mode],
            resume: ['resume', '$child', '--agent', '--autopilot', mode, '--max-dollars', dollars.to_s, '--frames', frames.to_s,
                     *(model ? ['--model', model] : [])] }
        end
      end
      record = { parent:, at_frame:, arms:, forks:, max_dollars: dollars, frames:, tag:, root:, runs:,
                 report: ['ab-report', tag, '--root', root] }
      FileUtils.mkdir_p(out_dir)
      File.write(File.join(out_dir, 'plan.json'), "#{JSON.pretty_generate(record)}\n")
      script = File.join(out_dir, 'run.sh')
      File.write(script, script_for(record))
      File.chmod(0o755, script)
      [record, script]
    end

    def script_for(record)
      lines = ['#!/bin/sh', 'set -e']
      record[:runs].each do |run|
        lines << "child=$(#{command(run[:fork])} | sed -n 's/^run //p')"
        lines << command(run[:resume]).sub("'$child'", '"$child"').sub('\\$child', '"$child"')
      end
      lines << command(record[:report])
      "#{lines.join("\n")}\n"
    end

    def command(argv) = ([BIN] + argv).shelljoin

    def report(prefix:, root: 'runs')
      pattern = /\A#{Regexp.escape(prefix)}-(.+)-(\d+)\z/
      measured = Dir.glob(File.join(root, '*', 'manifest.json')).sort.filter_map do |path|
        manifest = Summary.read_json(path)
        arm = manifest['tag'].to_s[pattern, 1] or next
        measure(File.dirname(path), manifest).merge(arm:)
      end
      arms = measured.group_by { |run| run[:arm] }.sort.to_h { |arm, runs| [arm, pooled(runs)] }
      { prefix:, root:, arms:, criterion: criterion(arms) }
    end

    def measure(dir, manifest)
      start = manifest.dig('parent', 'frame').to_i
      events = Trace.read(File.join(dir, 'trace.jsonl'))
      before, after = events.partition { |event| event['frame'] < start }
      frames = [(after.map { |event| event['frame'] }.max || start) - start, 0].max
      decisions = after.select { |event| event['type'] == 'decision' }
      { run: File.basename(dir), frames:, usd: decisions.sum { |event| event['cost_usd'].to_f }, calls: after.count { |event| Summary.model_call?(event) },
        autopilot: decisions.count { |event| event['autopilot'] },
        places: (Summary.visited_places(after) - Summary.visited_places(before)).size, cells: (cells(after) - cells(before)).size,
        stalls: after.count { |event| stall?(event) } }
    end

    def cells(events)
      events.filter_map do |event|
        place = Summary.perceived_place(event) or next
        cell = GameState.cell_at(event['state']['x'].to_i, event['state']['y'].to_i) or next
        [*place, *cell]
      end.uniq
    end

    def stall?(event)
      case event['type']
      when 'action' then event['skill'] == 'explore' && event.dig('result', 'stopped_by').to_s == 'stalled'
      when 'objective' then event['status'] == 'abandoned' && %w[stall loop].include?(event['reason'])
      else false
      end
    end

    def pooled(runs)
      frames = runs.sum { |run| run[:frames] }
      rate = ->(key) { Summary.per_1000(runs.sum { |run| run[key] }, frames) }
      { runs: runs.size, frames:, usd: runs.sum { |run| run[:usd] }.round(6), usd_per_1000f: rate.(:usd), calls_per_1000f: rate.(:calls),
        places_per_1000f: rate.(:places), cells_per_1000f: rate.(:cells), stalls: runs.sum { |run| run[:stalls] },
        autopilot_decisions: runs.sum { |run| run[:autopilot] }, detail: runs }
    end

    def criterion(arms)
      on = arms['autopilot']
      off = arms['off']
      return { verdict: 'incomplete', rule: rule } unless on && off && on[:usd_per_1000f] && off[:usd_per_1000f]

      cost = off[:usd_per_1000f].positive? ? on[:usd_per_1000f] / off[:usd_per_1000f] : nil
      places = off[:places_per_1000f].to_f.positive? ? on[:places_per_1000f].to_f / off[:places_per_1000f] : nil
      pass = (cost.nil? || cost <= COST_SHARE) && (places.nil? || places >= PLACES_SHARE)
      { verdict: pass ? 'pass' : 'fail', rule:, cost_ratio: cost&.round(3), places_ratio: places&.round(3) }
    end

    def rule = "autopilot cost per 1000 frames <= #{(COST_SHARE * 100).round} % of off and places per 1000 frames >= #{(PLACES_SHARE * 100).round} % of off"

    COLUMNS = %i[runs frames usd usd_per_1000f calls_per_1000f places_per_1000f cells_per_1000f stalls autopilot_decisions].freeze

    def markdown(result)
      lines = ["A/B #{result[:prefix]} (#{result[:root]})", '', "| arm | #{COLUMNS.join(' | ')} |", "|---|#{COLUMNS.map { '---' }.join('|')}|"]
      result[:arms].each { |arm, row| lines << "| #{arm} | #{COLUMNS.map { |key| row[key].nil? ? '-' : row[key] }.join(' | ')} |" }
      verdict = result[:criterion]
      ratios = verdict.slice(:cost_ratio, :places_ratio).map { |key, value| "#{key} #{value.nil? ? '-' : value}" }.join(', ')
      lines << '' << "Criterion (#{verdict[:rule]}): #{verdict[:verdict]}#{ratios.empty? ? '' : " (#{ratios})"}"
      "#{lines.join("\n")}\n"
    end
  end
end
