require 'json'
require 'zlib'
require 'koholint'
require 'koholint/objectives'

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
      dialogue: %i[place text source page],
      lead: %i[id place source quote claim importance],
      goal: %i[text]
    }.freeze
    ALLOWED = { dialogue: { source: %w[agent] }, lead: { importance: %w[high normal low] } }.freeze
    OPTIONAL = { decision: { prompt_sha: ->(v) { v.is_a?(String) && v.match?(/\A\h{64}\z/) }, image: ->(v) { [true, false].include?(v) },
                              plan: ->(v) { v.is_a?(String) && v.length <= 200 && !v.match?(/[[:cntrl:]]/) } },
                 objective: { because: ->(v) { v.is_a?(String) && v.match?(/\Alead-\d+\z/) }, predicate: ->(v) { Objectives.valid_predicate?(v) } } }.freeze

    def self.read(path)
      found = located(path)
      return [] unless File.exist?(found)
      return parse(File.foreach(path)) if found == path

      events = []
      Zlib::GzipReader.open(found) { |gz| parse(gz.each_line, events) }
      events
    rescue Zlib::Error, EOFError
      events
    end

    def self.intact?(path)
      found = located(path)
      found == path || (Zlib::GzipReader.open(found) { |gz| gz.read && true })
    rescue Zlib::Error, EOFError
      false
    end

    def self.archived(path) = "#{path}.gz"

    def self.located(path) = !File.exist?(path) && File.exist?(archived(path)) ? archived(path) : path

    def self.compress(path, into: archived(path)) = write_archive(File.binread(path), into)

    def self.write_archive(bytes, into)
      Zlib::GzipWriter.open("#{into}.tmp", Zlib::BEST_COMPRESSION) do |gz|
        gz.mtime = 1
        gz.write(bytes)
      end
      File.rename("#{into}.tmp", into)
    end

    def self.raw(path)
      found = located(path)
      return nil unless File.file?(found)

      found == path ? File.binread(path) : Zlib::GzipReader.open(found, &:read)
    end

    def self.decompress(path)
      raise Error, "archived trace #{archived(path)} is corrupt" unless intact?(path)

      File.binwrite("#{path}.tmp", Zlib::GzipReader.open(archived(path), &:read))
      File.rename("#{path}.tmp", path)
      File.delete(archived(path))
    end

    def self.parse(lines, events = [])
      lines.each do |line|
        events << JSON.parse(line)
      rescue JSON::ParserError
        nil
      end
      events
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

      OPTIONAL.fetch(type.to_sym, {}).each do |field, valid|
        raise InvalidEvent, "#{type} #{field} is invalid" if fields.key?(field) && !valid.call(fields[field])
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
