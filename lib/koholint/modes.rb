require 'json'
require 'set'
require 'koholint'

module Koholint
  module Modes
    class Invalid < Error; end

    DEFAULT_PATH = File.expand_path('../../data/modes.json', __dir__)
    TUPLE_FIELDS = %i[game_mode game_submode dialog_state motion_blocked scene_state link_motion_state game_over_stage].freeze
    SIGNAL_FIELDS = %i[room_transition link_airborne link_z link_knockback].freeze
    FIELDS = (TUPLE_FIELDS + SIGNAL_FIELDS).freeze
    KINDS = %w[play dialogue menu map cutscene save game_over transition title].freeze
    PHASES = %w[boot loading playing locked dialogue menu map save game_over cutscene].freeze
    CONFIDENCES = %w[hypothesis verified].freeze
    REQUIRED = %w[name kind phase match enter exit inputs source confidence verified_count].freeze
    KEYS = (REQUIRED + %w[ready cursor options note]).freeze
    CURSOR_KEYS = %w[field addr count columns wraps].freeze
    OPTION_KEYS = %w[text quits].freeze
    BYTES = Set.new(0..255).freeze
    IN_PLAY = %i[loading playing locked dialogue cutscene game_over].freeze

    Mode = Data.define(:name, :kind, :phase, :match, :ready, :enter, :exit, :inputs, :cursor, :options, :source, :confidence,
                       :verified_count, :note, :sets, :ready_sets) do
      def matches?(state) = sets.all? { |field, values| values.include?(state[field].to_i) }

      def ready?(state) = ready_sets.all? { |field, values| values.include?(state[field].to_i) }

      def overlaps?(other) = (sets.keys | other.sets.keys).all? { |field| !(set(field) & other.set(field)).empty? }

      def refines?(other) = (sets.keys | other.sets.keys).all? { |field| set(field).subset?(other.set(field)) }

      def set(field) = sets.fetch(field, BYTES)

      def choices = (options || []).each_with_index.reject { |option, _| option['quits'] }.map { |option, index| [index, option['text']] }

      def quits?(index) = options&.dig(index, 'quits') == true
    end

    module_function

    def catalogue = @catalogue ||= load

    def load(path = DEFAULT_PATH)
      modes = JSON.parse(File.read(path)).map { |entry| build(entry) }
      validate_catalogue!(modes)
      modes.freeze
    end

    def for(state, modes = catalogue)
      matching = modes.select { |mode| mode.matches?(state) }
      matching.find { |mode| matching.all? { |other| mode.refines?(other) } }
    end

    def phase(state, booted: false, modes: catalogue)
      phase = self.for(state, modes)&.phase&.to_sym || :unknown
      booted || IN_PLAY.include?(phase) ? phase : :boot
    end

    def ready?(state, modes = catalogue) = self.for(state, modes)&.ready?(state) || false

    def tuple(state) = TUPLE_FIELDS.to_h { |field| [field, state[field]] }

    def build(entry)
      validate!(entry)
      Mode.new(name: entry['name'], kind: entry['kind'], phase: entry['phase'], match: entry['match'], ready: entry['ready'] || {},
               enter: entry['enter'], exit: entry['exit'], inputs: entry['inputs'], cursor: entry['cursor'], options: entry['options'],
               source: entry['source'], confidence: entry['confidence'], verified_count: entry['verified_count'], note: entry['note'],
               sets: sets(entry['name'], entry['match']), ready_sets: sets(entry['name'], entry['ready'] || {}))
    end

    def validate!(entry)
      name = entry['name'] || entry.inspect
      REQUIRED.each { |key| raise Invalid, "#{name}: missing #{key}" unless entry.key?(key) }
      raise Invalid, "#{name}: unknown kind #{entry['kind']}" unless KINDS.include?(entry['kind'])
      raise Invalid, "#{name}: unknown phase #{entry['phase']}" unless PHASES.include?(entry['phase'])
      raise Invalid, "#{name}: unknown confidence #{entry['confidence']}" unless CONFIDENCES.include?(entry['confidence'])
      raise Invalid, "#{name}: verified_count must be a non-negative integer" unless entry['verified_count'].is_a?(Integer) && entry['verified_count'] >= 0
      raise Invalid, "#{name}: verified needs verified_count >= 2" if entry['confidence'] == 'verified' && entry['verified_count'] < 2
      raise Invalid, "#{name}: match must be a non-empty object" unless entry['match'].is_a?(Hash) && !entry['match'].empty?
      unknown = entry.keys - KEYS
      raise Invalid, "#{name}: unknown keys #{unknown.join(', ')}" unless unknown.empty?

      validate_cursor!(name, entry['cursor'], entry['options'])
    end

    def validate_cursor!(name, cursor, options)
      raise Invalid, "#{name}: options need a cursor" if options && !cursor
      return unless cursor

      raise Invalid, "#{name}: cursor must be an object" unless cursor.is_a?(Hash)
      unknown = cursor.keys - CURSOR_KEYS
      raise Invalid, "#{name}: unknown cursor keys #{unknown.join(', ')}" unless unknown.empty?
      raise Invalid, "#{name}: cursor field #{cursor['field']} is not in data/addresses.json" unless address_names.include?(cursor['field'])
      raise Invalid, "#{name}: cursor count must be a positive integer" unless cursor['count'].is_a?(Integer) && cursor['count'].positive?
      return unless options

      raise Invalid, "#{name}: #{options.size} options for a cursor of #{cursor['count']}" unless options.is_a?(Array) && options.size == cursor['count']

      options.each do |option|
        raise Invalid, "#{name}: an option needs a text" unless option.is_a?(Hash) && option['text'].is_a?(String)
        raise Invalid, "#{name}: unknown option keys" unless (option.keys - OPTION_KEYS).empty?
        raise Invalid, "#{name}: quits must be true or absent" unless [nil, true].include?(option['quits'])
      end
    end

    def address_names = @address_names ||= JSON.parse(File.read(File.expand_path('../../data/addresses.json', __dir__))).map { |entry| entry['name'] }

    def option_limit = catalogue.filter_map { |mode| mode.cursor['count'] if mode.options }.max

    def validate_catalogue!(modes)
      duplicate = modes.map(&:name).tally.find { |_, count| count > 1 }
      raise Invalid, "duplicate mode #{duplicate.first}" if duplicate

      modes.combination(2).each do |a, b|
        next unless a.overlaps?(b)
        next if a.refines?(b) ^ b.refines?(a)

        raise Invalid, "#{a.name} and #{b.name} match the same states ambiguously"
      end
    end

    def sets(name, match)
      raise Invalid, "#{name}: match and ready must be objects" unless match.is_a?(Hash)

      match.to_h do |field, spec|
        raise Invalid, "#{name}: unknown field #{field}" unless FIELDS.include?(field.to_sym)

        [field.to_sym, values(name, spec)]
      end
    end

    def values(name, spec)
      case spec
      when Integer then byte(name, spec) && Set[spec]
      when Array
        raise Invalid, "#{name}: empty value list" if spec.empty?

        Set.new(spec.map { |value| byte(name, value) })
      when 'nonzero' then BYTES - Set[0]
      when Hash
        raise Invalid, "#{name}: only {\"not\": ...} is allowed" unless spec.keys == ['not']

        BYTES - values(name, spec['not'])
      else raise Invalid, "#{name}: bad value #{spec.inspect}"
      end
    end

    def byte(name, value)
      raise Invalid, "#{name}: #{value.inspect} is not a byte" unless value.is_a?(Integer) && BYTES.include?(value)

      value
    end
  end
end
