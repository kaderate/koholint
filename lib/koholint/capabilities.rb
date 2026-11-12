require 'json'
require 'koholint'

module Koholint
  # Learned capabilities: compositions of existing skills with their trigger, trials and history (data/capabilities.json).
  module Capabilities
    class Invalid < Error; end

    DEFAULT_PATH = File.expand_path('../../data/capabilities.json', __dir__)
    STATUSES = %w[hypothesis validated operational rejected inconclusive deprecated].freeze
    REQUIRED = %w[id name version status trigger target steps effect evidence source history].freeze
    TEMPLATES = %w[$row $col $direction].freeze
    ID = /\A[a-z0-9]+(-[a-z0-9]+)*\z/
    NAME = /\A[a-z][a-z0-9_]*\z/
    PLACES_TO_VALIDATE = 2
    RUN = /\A\d{8}-\d{6}-\h{4}\z/

    module_function

    def load(path = DEFAULT_PATH)
      entries = JSON.parse(File.read(path))
      raise Invalid, 'capabilities must be a list' unless entries.is_a?(Array)

      validate_all!(entries)
      entries
    end

    def write(entries, path = DEFAULT_PATH)
      validate_all!(entries)
      File.write(path, "#{JSON.pretty_generate(entries)}\n")
    end

    def validate_all!(entries)
      entries.each { |entry| validate!(entry) }
      %w[id name].each do |key|
        values = entries.map { |entry| entry[key] }
        raise Invalid, "capability #{key} #{values.find { |v| values.count(v) > 1 }} is used twice" unless values.uniq.size == values.size
      end
    end

    def validate!(entry)
      raise Invalid, 'a capability must be an object' unless entry.is_a?(Hash)

      id = entry['id'].inspect
      raise Invalid, "#{id}: missing #{(REQUIRED - entry.keys).join(', ')}" unless (REQUIRED - entry.keys).empty?
      raise Invalid, "#{id}: unknown key #{(entry.keys - REQUIRED).first}" unless (entry.keys - REQUIRED).empty?
      raise Invalid, "#{id}: id must be lowercase words joined by dashes" unless entry['id'].is_a?(String) && entry['id'].match?(ID)
      raise Invalid, "#{id}: name must be a lowercase identifier" unless entry['name'].is_a?(String) && entry['name'].match?(NAME)
      raise Invalid, "#{id}: status must be one of #{STATUSES.join(', ')}" unless STATUSES.include?(entry['status'])
      raise Invalid, "#{id}: target must name an object id" unless entry['target'].is_a?(Hash) && entry['target']['object'].is_a?(Integer)
      raise Invalid, "#{id}: source must be a non-empty string" unless entry['source'].is_a?(String) && !entry['source'].strip.empty?
      validate_steps!(id, entry['steps'])
      validate_history!(id, entry)
      raise Invalid, "#{id}: validated needs successes in #{PLACES_TO_VALIDATE} places" if %w[validated operational].include?(entry['status']) && success_places(entry).size < PLACES_TO_VALIDATE
    end

    def validate_steps!(id, steps)
      raise Invalid, "#{id}: steps must be a non-empty list" unless steps.is_a?(Array) && !steps.empty?

      require 'koholint/skills/registry'
      known = Skills::Composite::CAPS.keys & Skills::Registry.default.names
      steps.each do |step|
        raise Invalid, "#{id}: a step needs skill, params and accept" unless step.is_a?(Hash) && step.keys.sort == %w[accept params skill]
        raise Invalid, "#{id}: skill #{step['skill']} cannot be composed" unless known.include?(step['skill'])
        raise Invalid, "#{id}: accept must list stop reasons" unless step['accept'].is_a?(Array) && !step['accept'].empty? && step['accept'].all?(String)

        templates = step['params'].values.grep(/\A\$/)
        raise Invalid, "#{id}: unknown parameter #{(templates - TEMPLATES).first}" unless (templates - TEMPLATES).empty?
      end
    end

    def validate_history!(id, entry)
      history = entry['history']
      raise Invalid, "#{id}: history must hold one record per version" unless entry['version'].is_a?(Integer) && history.is_a?(Array) && history.size == entry['version']
      raise Invalid, "#{id}: the last history record must carry the current status" unless history.last['status'] == entry['status']
      raise Invalid, "#{id}: evidence must be a list of trials" unless entry['evidence'].is_a?(Array) && entry['evidence'].all?(Hash)

      entry['evidence'].select { |trial| trial['outcome'] == 'success' }.each do |trial|
        raise Invalid, "#{id}: a success needs place, run, parent and frame" unless traced?(trial)
      end
    end

    def traced?(trial)
      place = trial['place']
      place.is_a?(Array) && place.size == 2 && place.all?(Integer) && trial['frame'].is_a?(Integer) &&
        [trial['run'], trial['parent']].all? { |run| run.is_a?(String) && run.match?(RUN) }
    end

    def success_places(entry) = entry['evidence'].select { |trial| trial['outcome'] == 'success' }.map { |trial| trial['place'] }.uniq

    def operational(entries = load) = entries.select { |entry| entry['status'] == 'operational' }

    def transition(entry, status, reason, evidence: entry['evidence'])
      version = entry['version'] + 1
      entry.merge('status' => status, 'version' => version, 'evidence' => evidence,
                  'history' => entry['history'] + [{ 'version' => version, 'status' => status, 'reason' => reason }])
    end
  end
end
