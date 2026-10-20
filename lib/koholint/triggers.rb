require 'koholint/ledger'

module Koholint
  class Triggers
    PRESSING_SKILLS = %w[advance_dialogue talk_to].freeze

    def self.from_events(events)
      triggers = new
      events.each do |event|
        next unless Ledger.pick(event, :type).to_s == 'action'

        result = Ledger.pick(event, :result)
        next unless result.is_a?(Hash)

        from = Ledger.place_of(Ledger.pick(result, :from))
        to = Ledger.place_of(Ledger.pick(result, :to))
        triggers.reset_unless(from) if from
        clearing = clearing(skill: Ledger.pick(event, :skill), params: Ledger.pick(event, :params), result:)
        triggers.clear(**clearing) if clearing && from
        skill = Ledger.pick(event, :skill)
        params = Ledger.pick(event, :params)
        if to && scripted?(skill:, params:, result:)
          triggers.record(place: to, cell: cell_of(result), skill: skill.to_s, direction: direction_of(skill, params),
                          input: Array(Ledger.pick(result, :trigger_input)).first)
        end
        triggers.reset_unless(to) if to
      end
      triggers
    end

    def self.scripted?(skill:, params:, result:)
      before = Ledger.pick(result, :dialog_before)
      after = Ledger.pick(result, :dialog_after)
      before == false && after == true && !pressing_a?(skill, params)
    end

    def self.clearing(skill:, params:, result:)
      return unless %w[walk step].include?(skill.to_s)
      return unless Ledger.pick(result, :stopped_by).to_s == 'done'
      return unless Ledger.pick(result, :dialog_before) == false && Ledger.pick(result, :dialog_after) == false
      return if Array(Ledger.pick(result, :trigger_input)).any?
      return unless Ledger.pick(result, :moved_cells).to_i.positive? || Ledger.pick(result, :moved_px).to_i.positive? || Ledger.pick(result, :frames).to_i >= 4

      input = Ledger.pick(params, :direction)&.to_s
      from = Ledger.pick(result, :from)
      row = Ledger.pick(from, :row)
      col = Ledger.pick(from, :col)
      return unless %w[up right down left].include?(input) && row && col

      { place: Ledger.place_of(from), cell: [row, col], input: }
    end

    def self.pressing_a?(skill, params)
      skill = skill.to_s
      PRESSING_SKILLS.include?(skill) || (skill == 'press' && Ledger.pick(params, :button).to_s == 'a')
    end

    def self.cell_of(result)
      to = Ledger.pick(result, :to)
      row = Ledger.pick(to, :row)
      col = Ledger.pick(to, :col)
      row && col ? [row, col] : nil
    end

    def self.direction_of(skill, params)
      skill.to_s == 'walk' ? Ledger.pick(params, :direction)&.to_s : nil
    end

    def initialize
      @counts = Hash.new(0)
      @inputs = Hash.new(0)
    end

    def record(place:, cell:, skill:, direction: nil, input: nil)
      return unless cell

      @counts[[place, cell.to_a, direction&.to_s || skill.to_s]] += 1
      @inputs[[place, cell.to_a, input.to_sym]] += 1 if input
    end

    def forbidden(place, cell)
      return [] unless cell

      @inputs.filter_map { |(p, c, input), _| input if p == place && c == cell.to_a }
    end

    def clear(place:, cell:, input:)
      @inputs.delete([place, cell.to_a, input.to_sym])
    end

    def input_count(place, cell, input)
      cell ? @inputs[[place, cell.to_a, input.to_sym]] : 0
    end

    def count(place, cell)
      return 0 unless cell

      @counts.sum { |(p, c, _), n| p == place && c == cell.to_a ? n : 0 }
    end

    def reset_unless(place)
      @counts.select! { |key, _| key[0] == place }
      @inputs.select! { |key, _| key[0] == place }
    end
  end
end
