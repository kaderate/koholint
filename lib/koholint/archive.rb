require 'fileutils'
require 'json'
require 'open3'
require 'pathname'
require 'time'
require 'zlib'
require 'koholint'
require 'koholint/summary'
require 'koholint/trace'

module Koholint
  module Archive
    LIGHT = %w[manifest.json inputs.log world.json suggestions.md summary.json star.json notes.md trace.jsonl.gz].freeze
    HEAVY = %w[prompts keyframes].freeze
    TRACE = 'trace.jsonl'.freeze
    INDEX = File.join('docs', 'runs', 'index.md')

    module_function

    def archive(root:, from: root, commit: false, full: false, out: $stdout)
      FileUtils.mkdir_p(root)
      bundles = runs(from).filter_map do |source|
        dest = File.join(root, File.basename(source))
        in_place = File.expand_path(source) == File.expand_path(dest)
        next dest if in_place && sealed?(dest) && current?(dest)

        reason = unfinished(source)
        next out.puts("skip #{File.basename(source)}: #{reason}") if reason

        changed = in_place ? seal(dest) : import(source, dest, full:)
        out.puts "archived #{File.basename(dest)}" if changed
        dest
      end
      index = write_index(root)
      commit!(root, bundles, index, full:, out:) if commit
      0
    end

    def star(dir, why, out: $stdout)
      raise Error, "no run at #{dir}" unless File.file?(File.join(dir, 'manifest.json'))

      write_json(File.join(dir, 'star.json'), { starred: true, why:, at: Time.now.utc.iso8601 })
      summary = File.join(dir, Summary::FILE)
      write_json(summary, Summary.read_json(summary).merge('starred' => true)) if File.file?(summary)
      out.puts "starred #{File.basename(dir)}"
      0
    end

    def prune_heavy(root:, keep: 5, yes: false, out: $stdout)
      all = runs(root)
      old = keep.positive? ? all[0...-keep] || [] : all
      paths = old.reject { |dir| File.exist?(File.join(dir, 'star.json')) || locked?(dir) }
                 .flat_map { |dir| HEAVY.map { |name| File.join(dir, name) } }.select { |path| File.directory?(path) }
      paths.each do |path|
        out.puts "#{yes ? 'deleted' : 'would delete'} #{path}"
        FileUtils.rm_rf(path) if yes
      end
      out.puts "#{paths.size} directories #{yes ? 'deleted' : 'to delete (pass --yes)'}"
      0
    end

    def runs(dir)
      return [] unless File.directory?(dir)

      Dir.children(dir).sort.map { |name| File.join(dir, name) }.select { |path| File.file?(File.join(path, 'manifest.json')) }
    end

    def unfinished(dir)
      return 'in use' if locked?(dir)
      return 'corrupt trace' unless Trace.intact?(File.join(dir, TRACE))

      'no stop event' unless Trace.read(File.join(dir, TRACE)).last&.fetch('type', nil) == 'stop'
    end

    def locked?(dir)
      path = File.join(dir, 'run.lock')
      return false unless File.file?(path)

      File.open(path, File::RDONLY) { |file| !file.flock(File::LOCK_SH | File::LOCK_NB) }
    end

    def sealed?(dir)
      File.file?(File.join(dir, "#{TRACE}.gz")) && !File.exist?(File.join(dir, TRACE)) && File.file?(File.join(dir, Summary::FILE))
    end

    def import(source, dest, full:)
      FileUtils.mkdir_p(dest)
      fresh = current?(source)
      changed = (LIGHT - ["#{TRACE}.gz", *(Summary::FILE unless fresh)]).select { |name| refresh(File.join(source, name), File.join(dest, name)) }
      trace = Trace.raw(File.join(source, TRACE))
      unless trace == archived_trace(dest)
        Trace.write_archive(trace, File.join(dest, "#{TRACE}.gz"))
        changed << TRACE
      end
      changed.concat(prompts(source, dest)) if full
      stale = !fresh && (changed.any? || !current?(dest))
      Summary.write(dest) if stale
      changed.any? || stale
    end

    def refresh(from, to)
      return false unless File.file?(from) && !(File.file?(to) && FileUtils.identical?(from, to))

      FileUtils.cp(from, to)
      true
    end

    def archived_trace(dir)
      path = File.join(dir, "#{TRACE}.gz")
      File.file?(path) ? Zlib::GzipReader.open(path, &:read) : nil
    rescue Zlib::Error, EOFError
      nil
    end

    def prompts(source, dest)
      dir = File.join(source, 'prompts')
      return [] unless File.directory?(dir)

      FileUtils.mkdir_p(File.join(dest, 'prompts'))
      Dir.children(dir).sort.select { |name| refresh(File.join(dir, name), File.join(dest, 'prompts', name)) }
    end

    def seal(dir)
      plain = File.join(dir, TRACE)
      changed = File.file?(plain)
      if changed
        Trace.compress(plain)
        File.delete(plain)
      end
      return changed if current?(dir)

      Summary.write(dir)
      true
    end

    def current?(dir) = Summary.read_json(File.join(dir, Summary::FILE))['v'].to_i >= Summary::VERSION

    def index_path(root)
      top, _err, status = Open3.capture3('git', 'rev-parse', '--show-toplevel', chdir: root)
      File.join(status.success? ? top.strip : File.dirname(File.expand_path(root)), INDEX)
    rescue SystemCallError
      File.join(File.dirname(File.expand_path(root)), INDEX)
    end

    def write_index(root)
      path = index_path(root)
      FileUtils.mkdir_p(File.dirname(path))
      link = Pathname(File.realpath(root)).relative_path_from(Pathname(File.realpath(File.dirname(path)))).to_s
      rows = runs(root).select { |dir| sealed?(dir) }.map { |dir| row(dir, Summary.read_json(File.join(dir, Summary::FILE)), link) }
      text = ["# Runs\n", 'One row per archived run; regenerated by `bin/koholint archive`.', '',
              '| run | tag | flow | frames | dollars | calls | usd/1000f | milestone | places | stop | ★ |',
              '|---|---|---|---:|---:|---:|---:|---|---:|---|---|', *rows].join("\n") << "\n"
      File.write(path, text) unless File.file?(path) && File.read(path) == text
      path
    end

    def row(dir, summary, link)
      id = File.basename(dir)
      cells = [summary['tag'], summary['flow_version'], summary['frames'], money(summary['dollars']), summary['calls'],
               money(summary['usd_per_1000f']), summary['highest_milestone'], summary['places_seen'], summary['stop_reason'],
               summary['starred'] ? '★' : '']
      "| [#{id}](#{link}/#{id}/) | #{cells.map { |cell| cell.to_s.gsub('|', '\|') }.join(' | ')} |"
    end

    def money(value) = value.is_a?(Numeric) ? format('%.4f', value) : nil

    def commit!(root, bundles, index, full:, out:)
      root = File.realpath(root)
      top = git(root, 'rev-parse', '--show-toplevel').strip
      paths = [*bundles.map { |dir| File.basename(dir) }, File.realpath(index)]
      git(root, 'add', '-A', '--', *paths)
      prompts = full ? bundles.map { |dir| File.join(File.basename(dir), 'prompts') }.select { |p| File.directory?(File.join(root, p)) } : []
      git(root, 'add', '-f', '--', *prompts) unless prompts.empty?
      changed = git(root, 'diff', '--cached', '--name-only', '--', *paths).lines.map(&:strip)
      return out.puts('nothing to commit') if changed.empty?

      prefix = root == top ? '' : "#{root.delete_prefix("#{top}/")}/"
      ids = changed.filter_map { |path| path.delete_prefix(prefix).split('/').first if path.start_with?(prefix) && path != INDEX }.uniq.sort
      message = case ids.size
                when 0 then 'Update the run index'
                when 1 then "Archive run #{ids.first}"
                else "Archive runs #{ids.first}..#{ids.last}"
                end
      message += ' (with prompts)' if changed.any? { |path| path.match?(%r{/prompts/}) }
      git(root, 'commit', '-q', '-m', message, '--', *changed.map { |path| File.join(top, path) })
      out.puts "committed: #{message}"
    end

    def git(dir, *args)
      output, error, status = Open3.capture3('git', *args, chdir: dir)
      raise Error, "git #{args.first} failed: #{error.lines.first&.strip}" unless status.success?

      output
    end

    def write_json(path, value)
      File.write("#{path}.tmp", "#{JSON.pretty_generate(value)}\n")
      File.rename("#{path}.tmp", path)
    end
  end
end
