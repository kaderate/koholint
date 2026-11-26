require 'open3'
require_relative 'measure'
require_relative 'runs'

module Scoreboard
  # The pit index: whether the decision layer's rules pile up faster than the game advances. Read-only: git and the runs on disk.
  module Debt
    DECISION = %r{policies/|autopilot|candidates|objectives|healers|revisit|leads|loop_watch|zero_watch|souvenirs}
    BRANCH = /\b(if|unless|elsif|when|while|until)\b|&&|\|\||\? /
    FLOW = /FLOW_VERSION = 'flow-(\d+)'/
    GROWTH_ALARM = 20.0

    module_function

    def git(repo, *args) = Open3.capture3('git', '-C', repo, *args).first.scrub

    def flow_at(repo, sha) = git(repo, 'show', "#{sha}:lib/koholint.rb")[FLOW, 1].to_i

    def harness?(path) = path.start_with?('lib/') && path.end_with?('.rb') && !path.include?('viewer')

    def branches(repo, sha)
      files = git(repo, 'ls-tree', '-r', '--name-only', sha, 'lib').split.select { |file| harness?(file) && DECISION.match?(file) }
      files.sum { |file| git(repo, 'show', "#{sha}:#{file}").scan(BRANCH).size }
    end

    # The first-parent commits from the one `window` flow versions before the tip to the tip, oldest first.
    def span(repo, ref, window)
      commits = git(repo, 'log', ref, '--first-parent', '--format=%H').split
      tip = flow_at(repo, commits.first)
      base = commits.find { |sha| flow_at(repo, sha) <= tip - window } || commits.last
      [tip, commits[0..commits.index(base)].reverse]
    end

    # Share of the functions edited by a flow of the window that an earlier flow of the window had edited, by the enclosing def of each changed line.
    def rework(repo, commits)
      touched = Hash.new { |hash, key| hash[key] = [] }
      commits.each_cons(2) do |prev, sha|
        flow = flow_at(repo, sha)
        path = nil
        defs = []
        git(repo, 'diff', '-U0', prev, sha, '--', 'lib').each_line do |line|
          if line.start_with?('+++ ')
            path = line[6..].chomp
            path = nil unless harness?(path)
            defs = path ? git(repo, 'show', "#{sha}:#{path}").lines.map { |text| text[/^\s*def\s+(?:self\.)?([\w?!=]+)/, 1] } : []
          elsif path && (hunk = line.match(/^@@ -\S+ \+(\d+)(?:,(\d+))? @@/))
            first = hunk[1].to_i
            (first..(first + [(hunk[2] || '1').to_i, 1].max - 1)).each do |number|
              name = defs[0, number].compact.last or next
              touched["#{File.basename(path, '.rb')}##{name}"] |= [flow]
            end
          end
        end
      end
      edits = touched.values.sum(&:size)
      again = touched.values.sum { |flows| flows.size - 1 }
      edits.zero? ? nil : (100.0 * again / edits).round(1)
    end

    def report(repo:, ref: 'origin/main', window: 10, roots: Runs::ROOTS, history: Runs.history, last: 5)
      tip, commits = span(repo, ref, window)
      now = branches(repo, commits.last)
      then_ = branches(repo, commits.first)
      rows = Runs.rows(roots)
      recent = Runs.measured(rows.select { |row| Runs.flow(row) > tip - window }).select { |result| result[:cost][:usd].positive? }
      gains = recent.flat_map { |result| result[:items_gained] }.uniq.sort
      usd = recent.sum { |result| result[:cost][:usd] }
      new_places = recent.sum { |result| result[:new_places] }
      from_boot = rows.select { |row| row[:manifest]['parent'].nil? && row[:total_dollars].to_f.positive? }.map { |row| Runs.flow(row) }.max || 0
      fired = history.last(last).flat_map { |entry| entry['runs'].to_a.flat_map { |run| run['rules'].to_h.keys } }.uniq
      growth = then_.zero? ? 0.0 : (100.0 * (now - then_) / then_).round(1)
      { tip:, window:, branches: now, branches_before: then_, branch_growth_pct: growth, gains:,
        branches_per_gain: gains.empty? ? nil : ((now - then_).to_f / gains.size).round(1),
        flows_since_paid_boot_run: tip - from_boot, paid_fork_points: recent.map { |result| result[:parent].values }.uniq.size, paid_runs: recent.size,
        new_places_per_usd: usd.positive? ? (new_places / usd).round(2) : nil, usd: usd.round(2), rework_pct: rework(repo, commits),
        rules_never_fired: history.empty? ? nil : Measure.rule_names - fired, scoreboard_runs_read: history.last(last).size,
        alarm: growth > GROWTH_ALARM && gains.empty? }
    end

    def text(r)
      never = r[:rules_never_fired] ? "#{r[:rules_never_fired].size} (#{r[:rules_never_fired].join(', ')})" : 'no scoreboard run yet'
      ["tip flow-#{r[:tip]}, window: the last #{r[:window]} flow versions",
       "1 decision-layer branch conditions: #{r[:branches]} (#{r[:branches] - r[:branches_before]} over the window, #{r[:branch_growth_pct]}%)",
       "2 first gains in the paid runs of the window: #{r[:gains].empty? ? 'none' : r[:gains].join(', ')}; branch conditions added per gain: #{r[:branches_per_gain] || 'no gain'}",
       "3 flow versions since the last paid run from boot: #{r[:flows_since_paid_boot_run]}",
       "4 distinct fork points among the #{r[:paid_runs]} paid runs of the window: #{r[:paid_fork_points]}",
       "5 new places per paid dollar in the window: #{r[:new_places_per_usd] || 'no paid run'} ($#{r[:usd]})",
       "6 rework: #{r[:rework_pct] || 'no edit'}% of the function edits of the window follow an earlier edit of the window",
       "7 rules that fired in none of the last #{r[:scoreboard_runs_read]} scoreboard runs: #{never}",
       "alarm (branch conditions +#{GROWTH_ALARM.to_i}% with no gain): #{r[:alarm] ? 'YES' : 'no'}"].join("\n")
    end
  end
end
