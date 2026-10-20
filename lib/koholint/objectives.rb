require 'koholint'

module Koholint
  class Objectives
    PREDICATES = {
      'leave_place' => %i[place],
      'reach_place' => %i[place],
      'reach_cell' => %i[place row col],
      'dialogue_closed' => %i[],
      'new_place' => %i[]
    }.freeze

    ATTEMPT_LIMIT = 10
    UNREACHABLE_PAIRS = 6
    UNREACHABLE_TOTAL = 8
    UNREACHABLE_NO_PATH = 3
    UNREACHABLE_NO_PATH_SEARCH = 6

    def self.normalize(predicate)
      predicate.to_h.transform_keys(&:to_sym)
    end

    def self.valid_predicate?(predicate)
      return false unless predicate.respond_to?(:to_h) && !predicate.is_a?(String)

      fields = normalize(predicate)
      required = PREDICATES[fields[:kind].to_s] or return false
      return false unless (fields.keys - [:kind] - required).empty?

      required.all? { |key| valid_field?(key, fields[key]) }
    rescue TypeError, ArgumentError
      false
    end

    def self.valid_field?(key, value)
      case key
      when :place then value.is_a?(Array) && value.size == 2 && value.all?(Integer)
      when :row then value.is_a?(Integer) && value.between?(0, 7)
      when :col then value.is_a?(Integer) && value.between?(0, 9)
      end
    end
    private_class_method :valid_field?

    TERMINAL = %w[achieved failed abandoned].freeze

    attr_reader :current, :history, :visited, :trace

    def self.resume(trace:, events:, frame:, **options)
      started = events.select { |e| e['type'] == 'objective' && e['status'] == 'started' }
      finished = events.select { |e| e['type'] == 'objective' && TERMINAL.include?(e['status']) }.map { |e| e['id'] }
      objectives = new(trace:, counter: started.size, **options)
      started.reject { |e| finished.include?(e['id']) }.each { |e| objectives.orphan(e, frame:) }
      objectives
    end

    def initialize(trace:, stall_frames: 1800, loop_window: 12, counter: 0, visited: [])
      @trace = trace
      @stall_frames = stall_frames
      @loop_window = loop_window
      @history = []
      @counter = counter
      @current = nil
      @visited = visited.map { |place| place.to_a.dup }
      @last_frame = 0
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
      @last_frame = frame
      @blocked_total = 0
      @no_path = 0
      @blocked_pairs = Hash.new(0)
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

    def touch(frame:)
      @last_change_frame = frame if @current
    end

    def update(state, frame:)
      return nil if state.loading?

      playing = %i[playing locked dialogue].include?(state.phase)
      place = [state.room_id, state.map_id]
      first_visit = playing && @visited.any? && !@visited.include?(place)
      @visited << place if playing && !@visited.include?(place)
      return nil unless @current

      @last_frame = frame
      cell = state.cell
      position = cell || [:px, state.x, state.y]
      @last_state_part = [place, position]
      signature = [place, position, state.dialog_open?, state.hp]
      if signature != @signature
        @signature = signature
        @last_change_frame = frame
      end
      @dialogue_seen ||= state.dialog_open?

      return finish(:failed, frame:) if died?(state)
      return finish(:achieved, frame:) if achieved?(state, place, cell, first_visit)
      return finish(:abandoned, frame:, reason: 'loop') if @repeat >= @loop_window
      return finish(:abandoned, frame:, reason: 'stall') if frame - @last_change_frame >= @stall_frames

      nil
    end

    def note_blocked(blocked_at:, target:, frame: @last_frame)
      return nil unless @current

      cell = self.class.normalize(blocked_at)
      pair = [cell[:row], cell[:col], cell[:direction].to_s]
      @blocked_total += 1
      @blocked_pairs[pair] += 1
      return nil unless self.class.normalize(target)[:kind].to_s == 'reach_cell'
      return finish(:abandoned, frame:, reason: 'unreachable') if @blocked_pairs[pair] >= UNREACHABLE_PAIRS || @blocked_total >= UNREACHABLE_TOTAL

      nil
    end

    def note_no_path(frame: @last_frame)
      return nil unless @current

      @no_path += 1
      limit = @current[:predicate][:kind].to_s == 'reach_cell' ? UNREACHABLE_NO_PATH : UNREACHABLE_NO_PATH_SEARCH
      return finish(:abandoned, frame:, reason: 'unreachable') if @no_path >= limit

      nil
    end

    def abandon(frame:, reason:)
      return nil unless @current

      finish(:abandoned, frame:, reason:)
    end

    def orphan(started, frame:)
      @trace.emit(:objective, frame:, id: started['id'], status: 'abandoned', predicate: started['predicate'], reason: 'resume')
      @history << { id: started['id'], title: started['title'], predicate: started['predicate'], outcome: :abandoned, reason: 'resume',
                    started_frame: started['frame'], ended_frame: frame }
    end

    def attempts_for_prompt
      return [] unless @current

      @current[:attempts].map { |a| "#{a[:skill]} #{a[:params].to_json} -> #{a[:result_summary]}" }
    end

    private

    def died?(state)
      alive = state.hp.to_i.positive?
      @seen_alive ||= alive
      @seen_alive && !alive && state.hp == 0
    end

    def achieved?(state, place, cell, first_visit)
      predicate = @current[:predicate]
      target = predicate[:place]
      case predicate[:kind].to_s
      when 'leave_place' then place != target
      when 'reach_place' then place == target
      when 'reach_cell' then place == target && cell == [predicate[:row], predicate[:col]]
      when 'dialogue_closed' then @dialogue_seen && !state.dialog_open?
      when 'new_place' then first_visit
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
