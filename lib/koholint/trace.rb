require 'json'
require 'koholint'

module Koholint
  class Trace
    class InvalidEvent < Error; end

    REQUIRED = {
      perception: %i[state],
      decision: %i[decision_point input options choice justification confidence agent latency_ms cost_usd],
      action: %i[skill params result],
      notable: %i[kind detail],
      objective: %i[id status predicate],
      budget_stop: %i[kind],
      stop: %i[reason],
      keyframe: %i[path],
      save: %i[path sav_sha256 source],
      screen: %i[place terrain_hash objects_hash grid static_sprites],
      screen_changed: %i[place cells],
      affordance: %i[appearance action direction result method context source],
      grid_contradiction: %i[place row col direction believed observed],
      dialogue: %i[place text source page]
    }.freeze
    ALLOWED = { dialogue: { source: %w[agent] } }.freeze

    def self.read(path)
      return [] unless File.exist?(path)

      File.foreach(path).filter_map do |line|
        JSON.parse(line)
      rescue JSON::ParserError
        nil
      end
    end

    def initialize(path, schema_version: 1)
      @path = path
      @version = schema_version
      File.write(path, "\n", mode: 'a') if File.exist?(path) && !File.read(path).then { |c| c.empty? || c.end_with?("\n") }
    end

    def emit(type, frame:, **fields)
      required = REQUIRED[type.to_sym] or raise InvalidEvent, "unknown event type #{type.inspect}"
      missing = required - fields.keys
      raise InvalidEvent, "#{type} missing #{missing.join(', ')}" unless missing.empty?

      ALLOWED.fetch(type.to_sym, {}).each do |field, values|
        raise InvalidEvent, "#{type} #{field} must be one of #{values.join(', ')}" unless values.include?(fields[field])
      end

      event = JSON.parse(JSON.generate({ v: @version, type: type.to_s, frame: frame }.merge(fields)))
      File.open(@path, 'a') do |file|
        file.write("#{JSON.generate(event)}\n")
        file.flush
      end
      event
    end
  end
end
