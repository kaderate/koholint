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
    client.call(system: 'be brief', prompt: 'hello there', schema: SCHEMA, image: image)
  ensure
    ENV.delete('FAKE_CLAUDE_LOG')
    ENV.delete('FAKE_CLAUDE_MODE')
  end

  def recorded = JSON.parse(File.read(@log))

  def test_success_returns_output_cost_latency_tokens
    reply = run_call
    assert_equal({ 'answer' => 'ok' }, reply.output)
    assert_nil reply.error
    assert_in_delta 0.0123, reply.cost_usd
    assert_equal 321, reply.latency_ms
    assert_equal({ 'input_tokens' => 10, 'output_tokens' => 5 }, reply.tokens)
  end

  def test_argv_carries_the_isolation_flags
    run_call(model: 'haiku', max_call_usd: 0.1)
    argv = recorded['argv']
    assert_equal '-p', argv.first
    assert_equal 'haiku', argv[argv.index('--model') + 1]
    assert_equal '', argv[argv.index('--tools') + 1]
    assert_equal '', argv[argv.index('--setting-sources') + 1]
    assert_includes argv, '--no-session-persistence'
    assert_equal 'json', argv[argv.index('--output-format') + 1]
    assert_equal SCHEMA.to_json, argv[argv.index('--json-schema') + 1]
    assert_equal 'be brief', argv[argv.index('--system-prompt') + 1]
    assert_equal '0.1', argv[argv.index('--max-budget-usd') + 1]
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

  def test_nonzero_exit_gives_an_error_and_is_retried
    reply = run_call('exit1', retries: 1)
    assert_nil reply.output
    assert reply.error
  end

  def test_missing_command_gives_an_error_without_raising
    reply = Koholint::Agents::ClaudeCli.new(command: '/nonexistent/claude', retries: 0).call(system: 's', prompt: 'p', schema: SCHEMA)
    assert_nil reply.output
    assert reply.error
  end

  def test_timeout_kills_the_process_and_gives_an_error
    reply = run_call('sleep', timeout: 1, retries: 0)
    assert_nil reply.output
    assert_match(/timeout/, reply.error)
    pid = recorded['pid']
    gone = 50.times.any? do
      Process.kill(0, pid)
      sleep 0.1
      false
    rescue Errno::ESRCH
      true
    end
    assert gone, 'child still alive after timeout'
  end

  def test_image_is_unsupported_and_runs_nothing
    reply = run_call(image: 'PNGBYTES')
    assert_nil reply.output
    assert_equal 'image_unsupported', reply.error
    refute_path_exists @log
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
