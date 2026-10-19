require_relative 'test_helper'
require 'json'
require 'tmpdir'
require 'koholint/agents/claude_cli'

class ClaudeCliTest < Minitest::Test
  FAKE = File.expand_path('fixtures/fake_claude', __dir__)
  SCHEMA = { type: 'object', properties: { answer: { type: 'string' } }, required: ['answer'] }.freeze

  def setup
    @log = File.join(Dir.mktmpdir('fake-claude-log'), 'log.json')
  end

  def teardown = FileUtils.rm_rf(File.dirname(@log))

  def run_call(mode = 'success', image: nil, **options)
    ENV['FAKE_CLAUDE_LOG'] = @log
    ENV['FAKE_CLAUDE_MODE'] = mode
    client = Koholint::Agents::ClaudeCli.new(command: FAKE, **options)
    client.call(system: 'be brief', prompt: 'hello there', schema: SCHEMA, image:)
  ensure
    ENV.delete('FAKE_CLAUDE_LOG')
    ENV.delete('FAKE_CLAUDE_MODE')
  end

  def events = File.readlines(@log).map { |line| JSON.parse(line) }
  def recorded = events.first

  def alive?(pid)
    Process.kill(0, pid)
    true
  rescue Errno::ESRCH
    false
  end

  def wait_gone(*pids)
    100.times do
      return true if pids.none? { |pid| alive?(pid) }

      sleep 0.1
    end
    false
  end

  def test_success_returns_output_cost_latency_tokens
    reply = run_call
    assert_equal({ 'answer' => 'ok' }, reply.output)
    assert_nil reply.error
    assert_in_delta 0.0123, reply.cost_usd
    assert_equal 321, reply.latency_ms
    assert_equal({ 'input_tokens' => 10, 'output_tokens' => 5 }, reply.tokens)
  end

  def test_argv_is_exactly_the_isolation_flags
    run_call(model: 'haiku', max_call_usd: 0.1)
    expected = ['-p', '--model', 'haiku', '--tools', '', '--no-session-persistence', '--setting-sources', '',
                '--output-format', 'json', '--json-schema', SCHEMA.to_json, '--system-prompt', 'be brief',
                '--max-budget-usd', '0.1']
    assert_equal expected, recorded['argv']
  end

  def test_prompt_goes_on_stdin
    run_call
    assert_equal 'hello there', recorded['stdin']
  end

  def test_runs_in_an_empty_temporary_directory_removed_afterwards
    run_call
    data = recorded
    assert_empty data['entries']
    refute_equal Dir.pwd, data['cwd']
    refute_path_exists data['cwd']
  end

  def test_invalid_json_gives_an_error
    reply = run_call('invalid_json')
    assert_nil reply.output
    assert_match(/json/i, reply.error)
  end

  def test_is_error_gives_an_error_and_keeps_the_cost
    reply = run_call('is_error')
    assert_nil reply.output
    assert reply.error
    assert_in_delta 0.0123, reply.cost_usd
  end

  def test_missing_structured_output_gives_an_error
    reply = run_call('no_structured')
    assert_nil reply.output
    assert_match(/structured_output/, reply.error)
    assert_in_delta 0.0123, reply.cost_usd
  end

  def test_schema_invalid_output_gives_an_error_without_retry
    reply = run_call('schema_invalid', retries: 2)
    assert_nil reply.output
    assert_match(/schema/, reply.error)
  end

  def test_nonzero_exit_gives_an_error_and_is_retried_once
    reply = run_call('exit1', retries: 1)
    assert_nil reply.output
    assert reply.error
    assert_equal 2, events.size
  end

  def test_schema_violation_is_not_retried
    run_call('schema_invalid', retries: 2)
    assert_equal 1, events.size
  end

  def test_missing_command_gives_an_error_without_raising
    reply = Koholint::Agents::ClaudeCli.new(command: '/nonexistent/claude', retries: 0).call(system: 's', prompt: 'p', schema: SCHEMA)
    assert_nil reply.output
    assert reply.error
  end

  def test_timeout_kills_the_process_group_and_removes_the_directory
    reply = run_call('sleep', timeout: 3, retries: 0)
    assert_nil reply.output
    assert_match(/timeout/, reply.error)
    pid = recorded['pid']
    grandchild = events.find { |e| e['grandchild'] }['grandchild']
    assert wait_gone(pid, grandchild), 'child or grandchild still alive after timeout'
    refute_path_exists recorded['cwd']
  end

  def test_timeout_is_retried
    run_call('sleep', timeout: 3, retries: 1)
    assert_equal 2, events.count { |e| e['pid'] }
  end

  def test_image_is_unsupported_and_runs_nothing
    reply = run_call(image: 'PNGBYTES')
    assert_nil reply.output
    assert_equal 'image_unsupported', reply.error
    refute_path_exists @log
  end

  def violation(value, schema) = Koholint::Agents::ClaudeCli.new.send(:violation, value, schema)

  def test_schema_keywords
    {
      { type: 'array', items: { type: 'integer' } } => [[[1, 2], nil], [[1, 'a'], /\[1\]/]],
      { oneOf: [{ type: 'integer' }, { type: 'number', minimum: 0 }] } => [['x', /oneOf/], [1.5, nil], [1, /oneOf/]],
      { anyOf: [{ type: 'string' }, { type: 'integer' }] } => [[1, nil], [1.5, /anyOf/]],
      { type: 'object', properties: { a: { type: 'string' } }, additionalProperties: false } =>
        [[{ 'a' => 'x' }, nil], [{ 'a' => 'x', 'b' => 1 }, /unexpected b/]],
      { type: 'integer', minimum: 1, maximum: 5 } => [[3, nil], [0, /minimum/], [6, /maximum/]],
      { type: 'string', minLength: 2, maxLength: 3 } => [['ab', nil], ['a', /minLength/], ['abcd', /maxLength/]],
      { type: %w[string null] } => [['a', nil], [nil, nil], [1, /string or null/]],
      { enum: %w[a b] } => [['a', nil], ['c', /enum/]],
      { type: 'object', properties: { n: { type: 'object', required: ['k'] } } } =>
        [[{ 'n' => { 'k' => 1 } }, nil], [{ 'n' => {} }, /n: missing k/]]
    }.each do |schema, cases|
      cases.each do |value, pattern|
        problem = violation(value, schema)
        if pattern
          assert_match pattern, problem.to_s, "#{schema} with #{value.inspect}"
        else
          assert_nil problem, "#{schema} with #{value.inspect}"
        end
      end
    end
  end

  def test_live_call
    skip 'set LIVE_CLAUDE=1' unless ENV['LIVE_CLAUDE'] == '1'
    client = Koholint::Agents::ClaudeCli.new(model: 'haiku', timeout: 90)
    reply = client.call(system: 'Answer with one word.', prompt: 'Say hello.', schema: SCHEMA)
    assert_nil reply.error
    assert reply.output['answer']
    assert_operator reply.cost_usd, :>, 0
  end
end
