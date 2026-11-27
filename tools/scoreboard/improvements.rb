require 'json'
require_relative 'diagnose'

module Scoreboard
  # data/improvements.json: the loop's candidates, each aimed at one stall that diagnose measured, with its paired trials and verdict.
  module Improvements
    PATH = File.expand_path('../../data/improvements.json', __dir__)
    KINDS = %w[fact rule skill].freeze
    STATUSES = %w[proposed testing published failed].freeze
    KEYS = %w[id kind stall status change trials verdict evidence].freeze
    STALL_KEYS = %w[run from to class].freeze
    TRIAL_KEYS = %w[run arm from frames usd calls new_places longest_stall].freeze
    RUN = /\A\d{8}-\d{6}-\h{4}\z/
    ID = /\A[a-z0-9]+(-[a-z0-9]+)*\z/
    PUBLISHED_AT = 2

    class Invalid < StandardError; end

    module_function

    def load(path = PATH)
      entries = JSON.parse(File.read(path))
      raise Invalid, 'improvements must be a list' unless entries.is_a?(Array)

      entries.each { |entry| validate!(entry) }
      ids = entries.map { |entry| entry['id'] }
      raise Invalid, "#{ids.find { |id| ids.count(id) > 1 }} is listed twice" unless ids.uniq.size == ids.size

      entries
    end

    def validate!(entry)
      raise Invalid, 'a candidate must be an object' unless entry.is_a?(Hash)

      id = entry['id'].inspect
      raise Invalid, "#{id}: keys must be #{KEYS.join(', ')}" unless entry.keys.sort == KEYS.sort
      raise Invalid, "#{id}: id must be lowercase words joined by dashes" unless entry['id'].is_a?(String) && entry['id'].match?(ID)
      raise Invalid, "#{id}: kind must be one of #{KINDS.join(', ')}" unless KINDS.include?(entry['kind'])
      raise Invalid, "#{id}: status must be one of #{STATUSES.join(', ')}" unless STATUSES.include?(entry['status'])
      %w[change evidence].each { |key| raise Invalid, "#{id}: #{key} must be a non-empty string" unless text?(entry[key]) }
      stall!(id, entry['stall'])
      raise Invalid, "#{id}: trials must be a list" unless entry['trials'].is_a?(Array)

      entry['trials'].each { |trial| trial!(id, trial) }
      decided = %w[published failed].include?(entry['status'])
      raise Invalid, "#{id}: a #{entry['status']} candidate needs a verdict" if decided && !text?(entry['verdict'])
      raise Invalid, "#{id}: only a published or failed candidate has a verdict" unless decided || entry['verdict'].nil?
      arms = entry['trials'].map { |trial| trial['arm'] }
      raise Invalid, "#{id}: published needs #{PUBLISHED_AT} candidate trials and a baseline" if entry['status'] == 'published' && (arms.count('candidate') < PUBLISHED_AT || !arms.include?('baseline'))
    end

    def stall!(id, stall)
      raise Invalid, "#{id}: stall keys must be #{STALL_KEYS.join(', ')}" unless stall.is_a?(Hash) && stall.keys.sort == STALL_KEYS.sort
      raise Invalid, "#{id}: stall run must be a run id" unless stall['run'].is_a?(String) && stall['run'].match?(RUN)
      raise Invalid, "#{id}: stall frames must be integers, from before to" unless [stall['from'], stall['to']].all?(Integer) && stall['from'] < stall['to']
      raise Invalid, "#{id}: stall class must be a diagnose class" unless Diagnose::CLASSES.include?(stall['class'])
    end

    def trial!(id, trial)
      raise Invalid, "#{id}: trial keys must be #{TRIAL_KEYS.join(', ')}" unless trial.is_a?(Hash) && trial.keys.sort == TRIAL_KEYS.sort
      raise Invalid, "#{id}: trial run must be a run id" unless trial['run'].is_a?(String) && trial['run'].match?(RUN)
      raise Invalid, "#{id}: trial arm must be baseline or candidate" unless %w[baseline candidate].include?(trial['arm'])
      raise Invalid, "#{id}: trial numbers must be non-negative" unless TRIAL_KEYS.drop(2).all? { |key| trial[key].is_a?(Numeric) && !trial[key].negative? }
    end

    def text?(value) = value.is_a?(String) && !value.strip.empty?
  end
end
