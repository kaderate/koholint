require 'koholint/summary'
require 'koholint/trace'

module Koholint
  module RunCompare
    FIELDS = %w[tag flow_version model frames dollars calls calls_per_1000f usd_per_1000f highest_milestone places_seen stop_reason starred].freeze
    SECTIONS = %w[usage cost_by_skill].freeze

    module_function

    def timeline(events)
      places = {}
      milestones = {}
      events.each do |event|
        place = Summary.perceived_place(event)
        places[place] ||= event['frame'] if place
        milestone = event['type'] == 'perception' && event['state'].is_a?(Hash) ? event['state']['milestone'] : nil
        milestones[milestone] ||= event['frame'] if milestone.is_a?(String) && milestone != 'none'
      end
      { places:, milestones: }
    end

    def side(dir)
      summary = Summary.read_json(File.join(dir, Summary::FILE))
      { run_id: File.basename(dir), summary: FIELDS.to_h { |key| [key, summary[key]] },
        **SECTIONS.to_h { |key| [key.to_sym, summary[key].is_a?(Hash) ? summary[key] : {}] },
        **timeline(Trace.read(File.join(dir, 'trace.jsonl'))) }
    end

    def compare(dir_a, dir_b)
      a = side(dir_a)
      b = side(dir_b)
      { a: a.slice(:run_id, :summary), b: b.slice(:run_id, :summary),
        differences: FIELDS.reject { |key| a[:summary][key] == b[:summary][key] },
        **SECTIONS.to_h { |key| [key.to_sym, section(a[key.to_sym], b[key.to_sym])] },
        places: merge(a[:places], b[:places]).map { |place, frames| { place:, **frames } },
        milestones: merge(a[:milestones], b[:milestones]).map { |milestone, frames| { milestone:, **frames } } }
    end

    def section(left, right)
      { a: left, b: right, differences: (left.keys | right.keys).reject { |key| left[key] == right[key] } }
    end

    def merge(left, right)
      (left.keys | right.keys).map { |key| [key, { a: left[key], b: right[key] }] }
                              .sort_by { |_, frames| [frames.values.compact.min, frames[:a] ? 0 : 1] }
    end
  end
end
