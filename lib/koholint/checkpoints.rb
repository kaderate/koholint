require 'json'
require 'koholint'

module Koholint
  module Checkpoints
    class Invalid < Error; end

    DEFAULT_PATH = File.expand_path('../../data/checkpoints.json', __dir__)
    REQUIRED = %w[name run frame flow source].freeze
    KEYS = (REQUIRED + %w[note]).freeze
    NAME = /\A[a-z0-9]+(-[a-z0-9]+)*\z/
    RUN = /\A\d{8}-\d{6}-\h{4}\z/
    FLOW = /\Aflow-\d+\z/

    module_function

    def catalogue = @catalogue ||= load

    def load(path = DEFAULT_PATH)
      entries = JSON.parse(File.read(path))
      raise Invalid, 'checkpoints must be a list' unless entries.is_a?(Array)

      entries.each { |entry| validate!(entry) }
      names = entries.map { |entry| entry['name'] }
      raise Invalid, "checkpoint #{names.find { |n| names.count(n) > 1 }} is named twice" unless names.uniq.size == names.size

      entries.to_h { |entry| [entry['name'], entry.freeze] }.freeze
    end

    def validate!(entry)
      raise Invalid, 'a checkpoint must be an object' unless entry.is_a?(Hash)

      name = entry['name'].inspect
      raise Invalid, "#{name}: missing #{(REQUIRED - entry.keys).join(', ')}" unless (REQUIRED - entry.keys).empty?
      raise Invalid, "#{name}: unknown key #{(entry.keys - KEYS).first}" unless (entry.keys - KEYS).empty?
      raise Invalid, "#{name}: name must be lowercase words joined by dashes" unless entry['name'].is_a?(String) && entry['name'].match?(NAME)
      raise Invalid, "#{name}: run must be a run id" unless entry['run'].is_a?(String) && entry['run'].match?(RUN)
      raise Invalid, "#{name}: frame must be a non-negative integer" unless entry['frame'].is_a?(Integer) && !entry['frame'].negative?
      raise Invalid, "#{name}: flow must be a flow version" unless entry['flow'].is_a?(String) && entry['flow'].match?(FLOW)
      raise Invalid, "#{name}: source must be a non-empty string" unless entry['source'].is_a?(String) && !entry['source'].strip.empty?
    end

    def frame_for(run, at, checkpoints = catalogue)
      return Integer(at) if at.to_s.match?(/\A\d+\z/)

      point = checkpoints[at.to_s] or raise Error, "no checkpoint #{at} in data/checkpoints.json"
      raise Error, "checkpoint #{at} is in run #{point['run']}, not #{run.id}" unless point['run'] == run.id
      raise Error, "checkpoint #{at} was recorded with #{point['flow']}, run #{run.id} is #{run.manifest['flow_version']}" unless point['flow'] == run.manifest['flow_version']

      point['frame']
    end
  end
end
