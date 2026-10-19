require 'base64'
require 'json'
require 'tmpdir'
require 'fileutils'

module Koholint
  module Agents
    Reply = Struct.new(:output, :cost_usd, :latency_ms, :tokens, :error)

    class ClaudeCli
      READER_GRACE = 1
      attr_reader :model
      STDERR_KEEP = 2048

      def initialize(model: 'sonnet', command: 'claude', timeout: 90, max_call_usd: 0.25, retries: 1, lenient: [])
        @lenient = lenient.map(&:to_s)
        @model = model
        @command = command
        @timeout = timeout
        @max_call_usd = max_call_usd
        @retries = retries
        @cancelled = false
        @pid = nil
      end

      def cancel
        @cancelled = true
        pid = @pid
        kill_group(pid) if pid
      end

      def call(system:, prompt:, schema:, image: nil, images: [])
        pictures = [*images, *image]
        reply = nil
        (@retries + 1).times do
          return failure('cancelled') if @cancelled

          reply = attempt(system:, prompt:, schema:, images: pictures)
          break unless reply.error&.start_with?('timeout', 'transport')
        end
        reply
      end

      private

      def argv(system, schema, images)
        format = !images.empty? ? ['--input-format', 'stream-json', '--output-format', 'stream-json', '--verbose'] : ['--output-format', 'json']
        [@command, '-p', '--model', @model, '--tools', '', '--no-session-persistence', '--setting-sources', '',
         '--strict-mcp-config', '--disable-slash-commands', *format, '--json-schema', JSON.generate(schema), '--system-prompt', system, '--max-budget-usd', @max_call_usd.to_s]
      end

      def stdin_for(prompt, images)
        return prompt unless images.any?

        blocks = images.map { |png| { type: 'image', source: { type: 'base64', media_type: 'image/png', data: Base64.strict_encode64(png) } } }
        "#{JSON.generate(type: 'user', message: { role: 'user', content: [*blocks, { type: 'text', text: prompt }] })}\n"
      end

      def attempt(system:, prompt:, schema:, images:)
        Dir.mktmpdir('koholint-claude') do |dir|
          status, out, err = run(argv(system, schema, images), stdin_for(prompt, images), dir)
          return failure('cancelled') if @cancelled

          interpret(status, out, schema, stream: !images.empty?, err:)
        end
      rescue SystemCallError => e
        failure("transport: #{e.message}")
      end

      def run(args, prompt, dir)
        in_r, in_w = IO.pipe
        out_r, out_w = IO.pipe
        err_r, err_w = IO.pipe
        pid = Process.spawn(*args, chdir: dir, pgroup: true, in: in_r, out: out_w, err: err_w)
        @pid = pid
        kill_group(pid) if @cancelled
        in_r.close
        out_w.close
        err_w.close
        buffer = +''
        reader = Thread.new do
          loop { buffer << out_r.readpartial(65_536) }
        rescue EOFError, IOError
          nil
        end
        err_buffer = +''
        err_reader = Thread.new do
          loop do
            err_buffer << err_r.readpartial(4096)
            err_buffer.replace(err_buffer.byteslice(-STDERR_KEEP..)) if err_buffer.bytesize > STDERR_KEEP
          end
        rescue EOFError, IOError
          nil
        end
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
          [waiter.value, drain(reader, buffer), drain(err_reader, err_buffer)]
        else
          kill_group(pid)
          waiter.join
          writer.join
          drain(reader, buffer)
          drain(err_reader, err_buffer)
          [:timeout, nil, '']
        end
      ensure
        @pid = nil
        [in_r, in_w, out_r, out_w, err_r, err_w].each { |io| io&.close unless io&.closed? }
      end

      def drain(reader, buffer)
        reader.kill unless reader.join(READER_GRACE)
        buffer
      end

      def kill_group(pid)
        Process.kill('KILL', -pid)
      rescue Errno::ESRCH, Errno::EPERM
        nil
      end

      def interpret(status, out, schema, stream: false, err: '')
        return failure("timeout after #{@timeout}s") if status == :timeout

        data = stream ? result_line(out) : parse(out)
        unless data.is_a?(Hash)
          return failure(status.success? ? 'invalid json' : "transport: exit #{status.exitstatus}#{stderr_hint(err)}")
        end

        cost = data['total_cost_usd']
        latency = data['duration_api_ms']
        tokens = data['usage']
        reply = ->(error) { Reply.new(nil, cost, latency, tokens, error) }
        return reply.call("claude error: #{data['result'] || 'is_error'}") if data['is_error']

        output = data['structured_output']
        return reply.call('missing structured_output') unless output.is_a?(Hash)

        problem = violation(output, relaxed(schema))
        return reply.call("schema violation: #{problem}") if problem

        Reply.new(output, cost, latency, tokens, nil)
      end

      def relaxed(schema)
        schema = schema.transform_keys(&:to_s)
        return schema if @lenient.empty? || !schema['required']

        schema.merge('required' => Array(schema['required']).map(&:to_s) - @lenient)
      end

      def stderr_hint(err)
        line = err.to_s.scrub.lines.map(&:strip).reject(&:empty?).last
        line ? ": #{line[0, 200]}" : ''
      end

      def result_line(out)
        out.to_s.lines.reverse_each do |line|
          data = parse(line)
          return data if data.is_a?(Hash) && data['type'] == 'result'
        end
        nil
      end

      def parse(out)
        JSON.parse(out.to_s)
      rescue JSON::ParserError
        nil
      end

      def failure(error) = Reply.new(nil, nil, nil, nil, error)

      def violation(value, schema)
        schema = schema.transform_keys(&:to_s)
        types = Array(schema['type']).map(&:to_s)
        return "expected #{types.join(' or ')}" unless types.empty? || types.any? { |t| type_match?(t, value) }
        return "#{value.inspect} not in enum" if schema['enum'] && schema['enum'].map(&:to_s).none?(value.to_s)

        combinator_violation(value, schema) || scalar_violation(value, schema) || container_violation(value, schema)
      end

      def type_match?(type, value)
        case type
        when 'string' then value.is_a?(String)
        when 'integer' then value.is_a?(Integer) || (value.is_a?(Float) && value == value.floor)
        when 'number' then value.is_a?(Numeric)
        when 'boolean' then [true, false].include?(value)
        when 'array' then value.is_a?(Array)
        when 'object' then value.is_a?(Hash)
        when 'null' then value.nil?
        else false
        end
      end

      def combinator_violation(value, schema)
        if schema['oneOf']
          matches = schema['oneOf'].count { |sub| violation(value, sub).nil? }
          return "matches #{matches} of oneOf, expected 1" unless matches == 1
        end
        return 'matches none of anyOf' if schema['anyOf'] && schema['anyOf'].all? { |sub| violation(value, sub) }

        nil
      end

      def scalar_violation(value, schema)
        if value.is_a?(Numeric)
          return "#{value} below minimum" if schema['minimum'] && value < schema['minimum']
          return "#{value} above maximum" if schema['maximum'] && value > schema['maximum']
        elsif value.is_a?(String)
          return 'shorter than minLength' if schema['minLength'] && value.length < schema['minLength']
          return 'longer than maxLength' if schema['maxLength'] && value.length > schema['maxLength']
        end
        nil
      end

      def container_violation(value, schema)
        if value.is_a?(Array) && schema['items']
          value.each_with_index do |item, i|
            problem = violation(item, schema['items'])
            return "[#{i}]: #{problem}" if problem
          end
        elsif value.is_a?(Hash)
          return object_violation(value, schema)
        end
        nil
      end

      def object_violation(value, schema)
        missing = Array(schema['required']).map(&:to_s) - value.keys
        return "missing #{missing.join(', ')}" unless missing.empty?

        properties = (schema['properties'] || {}).transform_keys(&:to_s)
        if schema['additionalProperties'] == false
          extra = value.keys - properties.keys
          return "unexpected #{extra.join(', ')}" unless extra.empty?
        end
        properties.each do |key, sub|
          next unless value.key?(key)

          problem = violation(value[key], sub)
          return "#{key}: #{problem}" if problem
        end
        nil
      end
    end
  end
end
