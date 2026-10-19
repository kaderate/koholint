require_relative 'test_helper'
require 'base64'
require 'json'
require 'tmpdir'
require 'koholint/agents/claude_cli'
require 'koholint/png'

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

  def grandchild_pid
    event = events.find { |e| e['grandchild'] }
    flunk 'fake never logged its grandchild' unless event
    event['grandchild']
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
                '--strict-mcp-config', '--disable-slash-commands',
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

  def test_stderr_last_line_is_in_the_error
    reply = run_call('stderr_exit2', retries: 0)
    assert_equal 'transport: exit 2: auth failed: bad token', reply.error
  end

  def test_stderr_line_is_capped
    reply = run_call('stderr_exit2', retries: 0)
    assert_operator reply.error.length, :<=, 'transport: exit 2: '.length + 200
  end

  def test_schema_violation_is_not_retried
    run_call('schema_invalid', retries: 2)
    assert_equal 1, events.size
  end

  def test_missing_command_gives_an_error_without_raising
    client = Koholint::Agents::ClaudeCli.new(command: '/nonexistent/claude', retries: 0)
    reply = client.call(system: 's', prompt: 'p', schema: SCHEMA)
    assert_nil reply.output
    assert reply.error
  end

  def test_timeout_kills_the_process_group_and_removes_the_directory
    reply = run_call('sleep', timeout: 5, retries: 0)
    assert_nil reply.output
    assert_match(/timeout/, reply.error)
    pid = recorded['pid']
    grandchild = grandchild_pid
    assert wait_gone(pid, grandchild), 'child or grandchild still alive after timeout'
    refute_path_exists recorded['cwd']
  end

  def test_timeout_returns_promptly_when_a_detached_descendant_holds_stdout
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    reply = run_call('detached', timeout: 5, retries: 0)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    assert_match(/timeout/, reply.error)
    assert_operator elapsed, :<, 5 + 4
  ensure
    detached = events.find { |e| e['grandchild'] }
    Process.kill('KILL', detached['grandchild']) if detached && alive?(detached['grandchild'])
  end

  def test_timeout_is_retried
    run_call('sleep', timeout: 5, retries: 1)
    assert_equal 2, events.count { |e| e['pid'] }
  end

  def test_image_goes_on_stdin_as_a_stream_json_user_message
    reply = run_call(image: "\x89PNG-bytes".b, model: 'haiku', max_call_usd: 0.1)
    assert_equal({ 'answer' => 'ok' }, reply.output)
    assert_in_delta 0.0123, reply.cost_usd
    expected = ['-p', '--model', 'haiku', '--tools', '', '--no-session-persistence', '--setting-sources', '',
                '--strict-mcp-config', '--disable-slash-commands',
                '--input-format', 'stream-json', '--output-format', 'stream-json', '--verbose',
                '--json-schema', SCHEMA.to_json, '--system-prompt', 'be brief', '--max-budget-usd', '0.1']
    assert_equal expected, recorded['argv']
    lines = recorded['stdin'].lines
    assert_equal 1, lines.size
    message = JSON.parse(lines.first)
    assert_equal 'user', message['type']
    image, text = message['message']['content']
    assert_equal({ 'type' => 'base64', 'media_type' => 'image/png', 'data' => Base64.strict_encode64("\x89PNG-bytes".b) }, image['source'])
    assert_equal 'hello there', text['text']
    refute_includes recorded['stdin'], Dir.pwd
    assert_empty recorded['entries']
  end

  def test_image_call_failure_is_reported
    reply = run_call('is_error', image: 'PNG')
    assert_nil reply.output
    assert_match(/claude error: boom/, reply.error)
  end

  def violation(value, schema) = Koholint::Agents::ClaudeCli.new.send(:violation, value, schema)

  def assert_valid(value, schema) = assert_nil(violation(value, schema), "#{schema} with #{value.inspect}")

  def assert_invalid(value, schema, pattern)
    assert_match pattern, violation(value, schema).to_s, "#{schema} with #{value.inspect}"
  end

  def test_schema_items
    schema = { type: 'array', items: { type: 'integer' } }
    assert_valid [1, 2], schema
    assert_invalid [1, 'a'], schema, /\[1\]/
  end

  def test_schema_one_of
    schema = { oneOf: [{ type: 'integer' }, { type: 'number', minimum: 0 }] }
    assert_valid 1.5, schema
    assert_invalid 'x', schema, /oneOf/
    assert_invalid 1, schema, /oneOf/
  end

  def test_schema_any_of
    schema = { anyOf: [{ type: 'string' }, { type: 'integer' }] }
    assert_valid 1, schema
    assert_invalid 1.5, schema, /anyOf/
  end

  def test_schema_additional_properties_false
    schema = { type: 'object', properties: { a: { type: 'string' } }, additionalProperties: false }
    assert_valid({ 'a' => 'x' }, schema)
    assert_invalid({ 'a' => 'x', 'b' => 1 }, schema, /unexpected b/)
  end

  def test_schema_minimum_maximum
    schema = { type: 'integer', minimum: 1, maximum: 5 }
    assert_valid 3, schema
    assert_invalid 0, schema, /minimum/
    assert_invalid 6, schema, /maximum/
  end

  def test_schema_min_max_length
    schema = { type: 'string', minLength: 2, maxLength: 3 }
    assert_valid 'ab', schema
    assert_invalid 'a', schema, /minLength/
    assert_invalid 'abcd', schema, /maxLength/
  end

  def test_schema_array_valued_type
    schema = { type: %w[string null] }
    assert_valid 'a', schema
    assert_valid nil, schema
    assert_invalid 1, schema, /string or null/
  end

  def test_schema_integer_accepts_whole_floats
    assert_valid 2.0, { type: 'integer' }
    assert_invalid 2.5, { type: 'integer' }, /integer/
  end

  def test_schema_enum
    schema = { enum: %w[a b] }
    assert_valid 'a', schema
    assert_invalid 'c', schema, /enum/
  end

  def test_schema_nested_required
    schema = { type: 'object', properties: { n: { type: 'object', required: ['k'] } } }
    assert_valid({ 'n' => { 'k' => 1 } }, schema)
    assert_invalid({ 'n' => {} }, schema, /n: missing k/)
  end

  def test_live_call
    skip 'set LIVE_CLAUDE=1' unless ENV['LIVE_CLAUDE'] == '1'
    client = Koholint::Agents::ClaudeCli.new(model: 'haiku', timeout: 90)
    reply = client.call(system: 'Answer with one word.', prompt: 'Say hello.', schema: SCHEMA)
    assert_nil reply.error
    assert reply.output['answer']
    assert_operator reply.cost_usd, :>, 0
  end

  def test_live_image_call
    skip 'set LIVE_CLAUDE=1' unless ENV['LIVE_CLAUDE'] == '1'
    schema = { type: 'object', properties: { transcription: { type: 'string' } }, required: ['transcription'], additionalProperties: false }
    client = Koholint::Agents::ClaudeCli.new(model: 'haiku', timeout: 90)
    reply = client.call(system: 'Transcribe the text in the image.', prompt: 'What does the image say?', schema:, image: hello_png)
    assert_nil reply.error
    assert_kind_of String, reply.output['transcription']
    assert_operator reply.cost_usd, :>, 0
  end

  def hello_png
    glyphs = { 'H' => %w[101 101 111 101 101], 'E' => %w[111 100 110 100 111], 'L' => %w[100 100 100 100 111], 'O' => %w[111 101 101 101 111] }
    cell = 24
    bitmap = 'HELLO'.chars.flat_map { |c| glyphs[c].map { |row| "#{row}0" } }
    cols = 'HELLO'.size * 4
    rows = (0...5).map { |r| 'HELLO'.chars.map { |c| "#{glyphs[c][r]}0" }.join }
    pixels = rows.flat_map { |row| ([row.chars.flat_map { |b| ([b == '1' ? [0, 0, 0] : [255, 255, 255]] * cell).flatten }.pack('C*')] * cell) }
    bitmap.clear
    Koholint::Png.encode(rgb: pixels.join, width: cols * cell, height: 5 * cell)
  end
end
