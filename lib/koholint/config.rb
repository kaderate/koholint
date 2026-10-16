module Koholint
  module Config
    ROOT = File.expand_path('../..', __dir__)

    class << self
      attr_writer :env_path

      def env_path = @env_path || File.join(ROOT, '.env')

      def get(name)
        ENV[name] || file_values[name]
      end

      def parse(text)
        text.each_line.with_object({}) do |line, values|
          line = line.strip.delete_prefix('export ').strip
          next if line.empty? || line.start_with?('#') || !line.include?('=')

          key, value = line.split('=', 2)
          values[key.strip] = value.strip.sub(/\A(["'])(.*)\1\z/, '\2')
        end
      end

      private

      def file_values
        File.file?(env_path) ? parse(File.read(env_path)) : {}
      end
    end
  end
end
