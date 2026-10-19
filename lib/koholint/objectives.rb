require 'koholint'

module Koholint
  class Objectives
    PREDICATES = {
      'leave_place' => %i[place],
      'reach_place' => %i[place],
      'reach_cell' => %i[place row col],
      'dialogue_closed' => %i[]
    }.freeze

    ATTEMPT_LIMIT = 10

    def self.normalize(predicate)
      predicate.to_h.transform_keys(&:to_sym)
    end

    def self.valid_predicate?(predicate)
      return false unless predicate.respond_to?(:to_h) && !predicate.is_a?(String)

      fields = normalize(predicate)
      required = PREDICATES[fields[:kind].to_s] or return false
      required.all? { |key| !fields[key].nil? }
    rescue TypeError, ArgumentError
      false
    end

    attr_reader :current, :history

    def initialize(trace:, stall_frames: 1800, loop_window: 12)
      @trace = trace
      @stall_frames = stall_frames
      @loop_window = loop_window
      @history = []
      @counter = 0
      @current = nil
    end

    def start(frame:, title:, predicate:)
      raise ArgumentError, "invalid predicate #{predicate.inspect}" unless self.class.valid_predicate?(predicate)

      @counter += 1
      id = "obj-#{@counter}"
      @current = { id:, title:, predicate: self.class.normalize(predicate), started_frame: frame, attempts: [] }
      @signature = nil
      @last_change_frame = frame
      @seen_alive = false
      @dialogue_seen = false
      @repeat = 0
      @last_key = nil
      @last_state_part = nil
      @trace.emit(:objective, frame:, id:, status: 'started', title:, predicate: @current[:predicate])
      id
    end

    def record_attempt(skill:, params:, result_summary:)
      return unless @current

      attempts = @current[:attempts]
      attempts << { skill:, params:, result_summary: }
      attempts.shift while attempts.size > ATTEMPT_LIMIT
      key = [@last_state_part, skill, params]
      @repeat = key == @last_key ? @repeat + 1 : 1
      @last_key = key
    end

    def update(state, frame:)
      return nil unless @current
      return nil if state.loading?

      place = [state.room_id, state.map_id]
      cell = cell_of(state)
      @last_state_part = [place, cell, state.dialog_state]
      signature = [place, cell, state.dialog_state, state.hp]
      if signature != @signature
        @signature = signature
        @last_change_frame = frame
        @last_key = nil
        @repeat = 0
      end
      @dialogue_seen ||= state.dialog_open?

      return finish(:failed, frame:) if died?(state)
      return finish(:achieved, frame:) if achieved?(state, place, cell)
      return finish(:abandoned, frame:, reason: 'loop') if @repeat >= @loop_window
      return finish(:abandoned, frame:, reason: 'stall') if frame - @last_change_frame >= @stall_frames

      nil
    end

    def abandon(frame:, reason:)
      return nil unless @current

      finish(:abandoned, frame:, reason:)
    end

    def attempts_for_prompt
      return [] unless @current

      @current[:attempts].map { |a| "#{a[:skill]} #{a[:params].to_json} -> #{a[:result_summary]}" }
    end

    private

    def cell_of(state)
      return nil unless state.x && state.y

      [(state.y - 8) / 16, state.x / 16]
    end

    def died?(state)
      alive = state.hp.to_i.positive?
      @seen_alive ||= alive
      @seen_alive && !alive && state.hp == 0
    end

    def achieved?(state, place, cell)
      predicate = @current[:predicate]
      target = predicate[:place]
      case predicate[:kind].to_s
      when 'leave_place' then place != target
      when 'reach_place' then place == target
      when 'reach_cell' then place == target && cell == [predicate[:row], predicate[:col]]
      when 'dialogue_closed' then @dialogue_seen && !state.dialog_open?
      end
    end

    def finish(outcome, frame:, reason: nil)
      done = @current
      @current = nil
      fields = { id: done[:id], status: outcome.to_s, predicate: done[:predicate] }
      fields[:reason] = reason if reason
      @trace.emit(:objective, frame:, **fields)
      @history << { id: done[:id], title: done[:title], predicate: done[:predicate], outcome:, reason:,
                    started_frame: done[:started_frame], ended_frame: frame }
      outcome
    end
  end
end
