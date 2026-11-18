require 'json'
require 'koholint/items'

module Koholint
  # Exit edges measured by the offline exit bench, per place, way and context (the milestone and the items held), with their trials;
  # an edge is verified when two independent visits agree, and only verified edges in the current context route play.
  module Exits
    DEFAULT_PATH = File.expand_path('../../data/exits.json', __dir__)
    VERIFIED_AT = 2

    module_function

    def load(path = DEFAULT_PATH) = File.exist?(path) ? validate!(JSON.parse(File.read(path))) : { 'edges' => [], 'benches' => [] }

    def write(data, path = DEFAULT_PATH)
      validate!(data)
      File.write("#{path}.tmp", "#{JSON.pretty_generate(data)}\n")
      File.rename("#{path}.tmp", path)
    end

    def validate!(data)
      raise ArgumentError, 'exits data needs edges and benches' unless data['edges'].is_a?(Array) && data['benches'].is_a?(Array)

      data['edges'].each do |edge|
        %w[place way context trials status verified_count].each { |key| raise ArgumentError, "exit edge lacks #{key}: #{edge.inspect}" unless edge.key?(key) }
        raise ArgumentError, "exit edge #{key_of(edge).inspect} is verified below #{VERIFIED_AT} checks" if edge['status'] == 'verified' && edge['verified_count'] < VERIFIED_AT
      end
      data
    end

    def context(state)
      fields = state.to_h.transform_keys(&:to_s)
      { 'milestone' => fields['milestone'].to_s, 'held' => Items.held_ids(fields).sort }
    end

    def key_of(edge) = [edge['place'], edge['way'], edge['context']]

    # Adds one crossing to its edge and recounts it: two destinations make it contradicted, agreeing trials from distinct visits verify it.
    def record(data, place:, way:, context:, trial:, refutes: nil)
      edge = data['edges'].find { |known| key_of(known) == [place, way, context] }
      edge ||= { 'place' => place, 'way' => way, 'context' => context, 'trials' => [], 'refutes' => [] }.tap { |fresh| data['edges'] << fresh }
      edge['trials'] << trial
      (edge['refutes'] << refutes).uniq! if refutes
      reached = edge['trials'].select { |known| known['to'] }
      destinations = reached.map { |known| known['to'] }.uniq
      edge['to'] = destinations.first if destinations.size == 1
      edge.delete('to') if destinations.size > 1
      edge['verified_count'] = destinations.size == 1 ? reached.map { |known| known['visit'] }.uniq.size : 0
      edge['status'] = if destinations.size > 1 then 'contradicted'
                       elsif edge['verified_count'] >= VERIFIED_AT then 'verified'
                       elsif destinations.empty? then 'unreached'
                       else 'observed'
                       end
      edge
    end

    def verified(data = load) = data['edges'].select { |edge| edge['status'] == 'verified' }

    def way_key(way) = way.is_a?(Array) ? way : way.to_sym

    # The verified edges of a context as ExploreLog keys, and the places a bench measured in it.
    def for_context(data, context)
      edges = verified(data).select { |edge| edge['context'] == context }.to_h { |edge| [[edge['place'], way_key(edge['way'])], edge['to']] }
      benches = data['benches'].select { |bench| bench['context'] == context }.to_h { |bench| [bench['place'], bench] }
      { edges:, benches: }
    end

    def digest_part(data = load) = verified(data).map { |edge| edge.slice('place', 'way', 'context', 'to') }.sort_by(&:inspect)
  end
end
