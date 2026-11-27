require 'koholint/atlas'
require_relative 'measure'

module Scoreboard
  # Each stall of a run (Measure's spans of STALL_FRAMES or more) with what it cost and a class from the plain templates below. No model.
  module Diagnose
    CLASSES = %w[direction override model fact skill perception unclassified].freeze
    PLACE_AIMS = %w[reach_cell reach_place new_place leave_place].freeze
    REFUSED = 3
    # First match wins; a stall no template fits is 'unclassified'. model, fact and perception have no template yet: no stall has needed one.
    TEMPLATES = [
      ['override', 'a harness rule family answered more decisions than the model', ->(s) { s[:rules].values.first.to_i > s[:model] }],
      ['skill', "a skill was refused #{REFUSED} times or more", ->(s) { s[:refused] >= REFUSED }],
      ['direction', 'the model chose and a place or cell objective stayed open with no new place', ->(s) { s[:model].positive? && s[:aims].any? }]
    ].freeze

    module_function

    def run(dir)
      segment = Measure.segment(dir)
      spans = Measure.spans(segment[:new_frames], segment[:last], start: segment[:start], before: segment[:before].size)
      spans.select { |from, to| to - from >= Measure::STALL_FRAMES }.map { |from, to| classify(stall(File.basename(dir), segment[:events], from, to)) }
    end

    def stall(run, events, from, to)
      window = events.select { |event| event['frame'].to_i.between?(from, to) }
      decisions = window.select { |event| event['type'] == 'decision' }
      { run:, from:, to:, frames: to - from, usd: decisions.sum { |event| event['cost_usd'].to_f }.round(2),
        calls: decisions.count { |event| event['agent'] == 'claude' },
        model: decisions.count { |event| Measure.family(event['justification'].to_s, event['agent']).last == 'model' },
        rules: Measure.rules(decisions), aims: aims(events, from, to),
        refused: window.count { |event| event['type'] == 'action' && event.dig('result', 'stopped_by') == 'refused' },
        screens: window.filter_map { |event| Measure.place_of(event) if event['frame'].to_i < to }.uniq.map { |place| Koholint::Atlas.label(place) } }
    end

    # Objectives aimed at a place or a cell that were open at some frame of the stall, as "frame title".
    def aims(events, from, to)
      open = {}
      events.each do |event|
        break if event['frame'].to_i > to
        next unless event['type'] == 'objective'

        if event['status'] == 'started' then open[event['id']] = event
        elsif event['frame'].to_i < from then open.delete(event['id'])
        end
      end
      open.values.select { |event| PLACE_AIMS.include?(event.dig('predicate', 'kind')) }.map { |event| "#{event['frame']} #{event['title']}" }
    end

    def classify(stall)
      klass, why = TEMPLATES.find { |_, _, test| test.(stall) }&.first(2)
      stall.merge(class: klass || 'unclassified', why: why || 'no template fits')
    end

    def table(stalls)
      rows = stalls.sort_by { |stall| [-stall[:usd], -stall[:frames]] }.map do |s|
        evidence = ["model #{s[:model]}", *s[:rules].first(3).map { |name, n| "#{name} #{n}" }, ("refused #{s[:refused]}" if s[:refused].positive?),
                    *s[:aims].first(1).map { |aim| "objective #{aim}" }].compact
        "| #{s[:run]} | #{s[:from]}-#{s[:to]} | #{s[:frames]} | #{s[:usd]} | #{s[:calls]} | #{s[:screens].join(' ')} | #{s[:class]} | #{s[:why]}: #{evidence.join('; ')} |"
      end
      total = stalls.sum { |stall| stall[:frames] }
      classes = stalls.group_by { |stall| stall[:class] }.sort_by { |_, group| -group.sum { |stall| stall[:usd] } }.map do |klass, group|
        frames = group.sum { |stall| stall[:frames] }
        "| #{klass} | #{group.size} | #{frames} | #{total.positive? ? (100.0 * frames / total).round : 0}% | #{group.sum { |stall| stall[:usd] }.round(2)} |"
      end
      ['| run | frames | lost | usd | calls | screens | class | evidence |', '|---|---|---|---|---|---|---|---|', *rows, '',
       '| class | stalls | frames | share | usd |', '|---|---|---|---|---|', *classes].join("\n")
    end
  end
end
