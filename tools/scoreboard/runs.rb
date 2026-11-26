require 'json'
require_relative 'measure'

module Scoreboard
  # The runs on disk: every run folder under the roots (a root may be a glob), the first root winning a duplicated id.
  module Runs
    ROOTS = %w[~/.capy/work/atlas-root ~/.capy/work/runs/*].freeze
    HISTORY = '~/.capy/work/scoreboard/history.jsonl'.freeze

    module_function

    def dirs(roots = ROOTS)
      roots.flat_map { |root| Dir.glob(File.expand_path(root)).select { |dir| File.directory?(dir) }.sort }
           .flat_map { |root| Dir.children(root).sort.map { |name| File.join(root, name) } }
           .select { |dir| File.file?(File.join(dir, 'manifest.json')) }.uniq { |dir| File.basename(dir) }
    end

    # One row per run: its manifest and the dollars its summary records, which for a fork include its parent's (a run's own cost is in Measure).
    def rows(roots = ROOTS)
      dirs(roots).map do |dir|
        { dir:, id: File.basename(dir), manifest: read_json(File.join(dir, 'manifest.json')), total_dollars: read_json(File.join(dir, 'summary.json'))['dollars'] }
      end
    end

    def on_day(rows, day) = rows.select { |row| row[:id].start_with?(day.strftime('%Y%m%d')) }

    def measured(rows) = rows.filter_map { |row| Measure.run(row[:dir]) rescue nil }

    def flow(row) = row[:manifest]['flow_version'].to_s[/\d+/].to_i

    def read_json(path)
      value = JSON.parse(File.read(path))
      value.is_a?(Hash) ? value : {}
    rescue SystemCallError, JSON::ParserError
      {}
    end

    def history(path = HISTORY)
      path = File.expand_path(path)
      File.file?(path) ? File.readlines(path).filter_map { |line| JSON.parse(line) rescue nil } : []
    end
  end
end
