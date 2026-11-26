require_relative 'test_helper'

class DocsTest < Minitest::Test
  ROOT = File.expand_path('..', __dir__)
  ROOTS = %w[lib data docs test bin tools .github].freeze
  DOCS = Dir.chdir(ROOT) do
    (%w[README.md ARCHITECTURE.md AGENTS.md ROADMAP.md] + Dir['docs/*.md', 'tools/*/README.md']).reject do |doc|
      File.read(doc).lines.first(6).any? { |line| line.match?(/\AStatus: (done|superseded|abandoned)/) }
    end
  end.freeze
  FILES = Dir.chdir(ROOT) { Dir.glob("{#{ROOTS.join(',')}}/**/*", File::FNM_DOTMATCH).reject { |path| File.basename(path) == '.' } + Dir['*'] }.freeze

  def read(doc) = File.read(File.join(ROOT, doc))

  def words(doc)
    read(doc).lines.each_with_index.flat_map do |line, index|
      line.scan(/`([^`]+)`/).flatten.flat_map(&:split).map { |word| [index + 1, word.gsub(/\A["'(]+|["',;:.)]+\z/, '').sub(/:\d+\z/, '')] }
    end
  end

  def path_candidate?(word)
    return false if word.match?(/[<>{}$~]|\.\.\.|\Ahttp/)

    (ROOTS.include?(word.split('/').first) && word.include?('/')) || word.match?(/\A[A-Z_]+\.md\z/) || word.match?(%r{\A[\w./-]+\.(rb|html)\z})
  end

  def present?(word)
    path = word.delete_suffix('/')
    if path.include?('*')
      return Dir.glob(File.join(ROOT, path)).any? || FILES.any? { |file| File.fnmatch?("**/#{path}", file, File::FNM_PATHNAME | File::FNM_EXTGLOB) }
    end

    File.exist?(File.join(ROOT, path)) || FILES.any? { |file| file.end_with?("/#{path}") }
  end

  def test_documents_name_only_files_that_exist
    missing = DOCS.flat_map do |doc|
      words(doc).select { |_, word| path_candidate?(word) && !present?(word) }.map { |line, word| "#{doc}:#{line} #{word}" }
    end
    assert_empty missing, 'docs name files that do not exist'
  end

  def test_documents_link_only_files_that_exist
    broken = DOCS.flat_map do |doc|
      base = File.dirname(File.join(ROOT, doc))
      read(doc).scan(/\]\(([^)#\s]+)(?:#[^)]*)?\)/).flatten.reject { |target| target.match?(%r{\A[a-z]+:|\A/}) }
          .reject { |target| File.exist?(File.expand_path(target, base)) }.map { |target| "#{doc} -> #{target}" }
    end
    assert_empty broken
  end

  def test_documents_name_only_commands_flags_and_tasks_that_exist
    cli = read('lib/koholint/cli.rb')
    commands = cli[/USAGE = .*?\n\n/m].gsub(/'\s*\\\n\s*'/, '').scan(/(?:usage: koholint |\|)([a-z][a-z-]*)/).flatten.uniq
    flags = cli.scan(/'(--[a-z-]+)/).flatten.uniq
    tasks = ['test'] + read('Rakefile').scan(/^  task :(\w+)/).flatten.map { |name| "test:#{name}" }
    bad = DOCS.flat_map do |doc|
      text = read(doc)
      found = text.scan(%r{(?:bin/koholint|`koholint) ([a-z][a-z-]*)}).flatten.reject { |word| commands.include?(word) }.map { |word| "koholint #{word}" }
      found += text.lines.select { |line| line.match?(%r{bin/koholint|`koholint }) }.flat_map { |line| line.scan(/ (--[a-z-]+)/).flatten }.reject { |flag| flags.include?(flag) }
      found += text.scan(/\brake (test(?::\w+)?)/).flatten.reject { |task| tasks.include?(task) }.map { |task| "rake #{task}" }
      found.map { |entry| "#{doc} #{entry}" }
    end
    assert_empty bad
  end

  def test_documents_cite_no_flow_beyond_the_current_one
    current = Koholint::FLOW_VERSION[/\d+/].to_i
    ahead = DOCS.flat_map do |doc|
      read(doc).scan(/\bflow-(\d+)/).flatten.map(&:to_i).select { |number| number > current }.map { |number| "#{doc} flow-#{number}" }
    end
    assert_empty ahead
    stated = DOCS.flat_map { |doc| read(doc).scan(/(?:\bcurrently\W{0,3}|FLOW_VERSION\D{0,20}?)(flow-\d+)/).flatten }
    assert_empty stated.reject { |flow| flow == Koholint::FLOW_VERSION }
  end

  def test_battleship_labels_agree_with_the_room_ids_beside_them
    label = ->(room) { "#{('A'.ord + room % 16).chr}#{room / 16 + 1}" }
    wrong = DOCS.flat_map do |doc|
      read(doc).lines.each_with_index.flat_map do |line, index|
        pairs = line.scan(%r{\b([A-P]\d{1,2})\b \(?(\d+)/0\b}) + line.scan(%r{\b(\d+)/0\b \((?:is )?([A-P]\d{1,2})\)}).map(&:reverse)
        pairs.reject { |name, room| label.call(room.to_i) == name }.map { |name, room| "#{doc}:#{index + 1} #{name} beside #{room}/0 (is #{label.call(room.to_i)})" }
      end
    end
    assert_empty wrong
  end
end
