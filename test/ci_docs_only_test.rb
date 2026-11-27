require_relative 'test_helper'

class CiDocsOnlyTest < Minitest::Test
  SCRIPT = File.expand_path('../.github/scripts/docs-only.sh', __dir__)

  def docs_only(*paths) = IO.popen(['bash', SCRIPT], 'r+') { |io| io.write(paths.join("\n")); io.close_write; io.read.strip }

  def test_docs_and_markdown_only
    assert_equal 'true', docs_only('docs/OPERATING.md', 'README.md', 'docs/places-montage.png', 'runs/x/suggestions.md')
  end

  def test_any_other_path_runs_everything
    assert_equal 'false', docs_only('docs/OPERATING.md', 'lib/koholint/engine.rb')
    assert_equal 'false', docs_only('README.md', 'Rakefile')
    assert_equal 'false', docs_only('docs/OPERATING.md', '.github/workflows/ci.yml')
    assert_equal 'false', docs_only('tools/gates/README.md')
  end

  def test_empty_list_runs_everything
    assert_equal 'false', docs_only
  end
end
