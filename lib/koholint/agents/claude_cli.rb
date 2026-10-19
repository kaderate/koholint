require 'json'
require 'tmpdir'
require 'fileutils'

module Koholint
  module Agents
    Reply = Struct.new(:output, :cost_usd, :latency_ms, :tokens, :error)

    class ClaudeCli
      TYPES = { 'string' => String, 'integer' => Integer, 'number' => Numeric, 'boolean' => [true, false].freeze,
                'array' => Array, 'object' => Hash }.freeze

      def initialize(model: 'sonnet', command: 'claude', timeout: 90, max_call_usd: 0.25, retries: 1)
        @model = model
        @command = command
        @timeout = timeout
        @max_call_usd = max_call_usd
        @retries = retries
      end

      def call(system:, prompt:, schema:, image: nil)
        return Reply.new(nil, nil, nil, nil, 'image_unsupported') if image

        reply = nil
        (@retries + 1).times do
          reply = attempt(system:, prompt:, schema:)
          break unless reply.error&.start_with?('timeout', 'transport')
        end
        reply
      end

      private

      def argv(system, schema)
        [@command, '-p', '--model', @model, '--tools', '', '--no-session-persistence', '--setting-sources', '',
         '--output-format', 'json', '--json-schema', JSON.generate(schema), '--system-prompt', system,
         '--max-budget-usd', @max_call_usd.to_s]
      end

      def attempt(system:, prompt:, schema:)
        Dir.mktmpdir('koholint-claude') do |dir|
          status, out = run(argv(system, schema), prompt, dir)
          interpret(status, out, schema)
        end
      rescue SystemCallError => e
        failure("transport: #{e.message}")
      end

      def run(args, prompt, dir)
        in_r, in_w = IO.pipe
        out_r, out_w = IO.pipe
        pid = Process.spawn(*args, chdir: dir, pgroup: true, in: in_r, out: out_w, err: File::NULL)
        in_r.close
        out_w.close
        reader = Thread.new { out_r.read }
        writer = Thread.new do
          in_w.write(prompt)
        rescue Errno::EPIPE
          nil
        ensure
          in_w.close
        end
        waiter = Process.detach(pid)
        if waiter.join(@timeout)
          writer.join
          [waiter.value, reader.value]
        else
          kill_group(pid)
          waiter.join
          writer.join
          [:timeout, nil]
        end
      ensure
        [in_r, in_w, out_r, out_w].each { |io| io&.close unless io&.closed? }
      end

      def kill_group(pid)
        Process.kill('KILL', -pid)
      rescue Errno::ESRCH, Errno::EPERM
        nil
      end

      def interpret(status, out, schema)
        return failure("timeout after #{@timeout}s") if status == :timeout

        data = parse(out)
        return failure(status.success? ? 'invalid json' : "transport: exit #{status.exitstatus}") unless data.is_a?(Hash)

        cost = data['total_cost_usd']
        latency = data['duration_api_ms']
        tokens = data['usage']
        reply = ->(error) { Reply.new(nil, cost, latency, tokens, error) }
        return reply.call("claude error: #{data['result'] || 'is_error'}") if data['is_error']

        output = data['structured_output']
        return reply.call('missing structured_output') unless output.is_a?(Hash)

        problem = violation(output, schema)
        return reply.call("schema violation: #{problem}") if problem

        Reply.new(output, cost, latency, tokens, nil)
      end

      def parse(out)
        JSON.parse(out.to_s)
      rescue JSON::ParserError
        nil
      end

      def failure(error) = Reply.new(nil, nil, nil, nil, error)

      def violation(value, schema)
        schema = schema.transform_keys(&:to_s)
        type = TYPES[schema['type']]
        return "expected #{schema['type']}" if type && !type.is_a?(Array) && !value.is_a?(type)
        return "expected #{schema['type']}" if type.is_a?(Array) && !type.include?(value)
        return "#{value.inspect} not in enum" if schema['enum'] && !schema['enum'].include?(value)
        return nil unless value.is_a?(Hash)

        missing = Array(schema['required']).map(&:to_s) - value.keys
        return "missing #{missing.join(', ')}" unless missing.empty?

        (schema['properties'] || {}).each do |key, sub|
          next unless value.key?(key.to_s)

          problem = violation(value[key.to_s], sub)
          return "#{key}: #{problem}" if problem
        end
        nil
      end
    end
  end
end
