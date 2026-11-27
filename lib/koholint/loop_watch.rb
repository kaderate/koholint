require 'koholint/game_state'
require 'koholint/objectives'

module Koholint
  class LoopWatch
    ENTRIES = 4
    WINDOW_FRAMES = 3600

    BREAK = 'loop in'
    HEAL_OVER = 'the heal is over:'

    attr_reader :hint, :notes

    def self.from_events(events)
      watch = new
      events.each do |event|
        state = event['state'] if event['type'] == 'perception'
        watch.observe(place: [state['room_id'], state['map_id']], frame: event['frame'], hp: state['hp']) if state && state['game_mode'] == Koholint::PLAY_MODE
        watch.news!(event['frame']) if event['type'] == 'lead'
        watch.act! if event['type'] == 'decision' && event['justification'].to_s.start_with?(BREAK, HEAL_OVER)
      end
      watch.notes.clear
      watch
    end

    def initialize
      @seen = {}
      @place = nil
      @entries = []
      @hint = nil
      @times = 0
      @notes = []
    end

    # The policy acts once per detection (a loop break, or the objective a heal set aside taken up again), also across a resume.
    def act! = @acted = true

    def pending_hint = (@hint unless @acted)

    def news!(frame) = @changed = frame

    # No hp change, no place never seen and no lead for Objectives::STALL_FRAMES: the protections that keep Link from enemies stop applying.
    def stalled?(frame) = !@changed.nil? && frame - @changed >= Objectives::STALL_FRAMES

    def observe(place:, frame:, hp: nil)
      @changed = frame unless @seen[place] && hp == @hp
      @hp = hp
      return if place == @place

      @place = place
      @hint = nil if @hint && !@hint[:places].include?(place.join('-'))
      unless @seen[place]
        @seen[place] = true
        @entries.clear
        @hint = nil
        return
      end
      @entries << [frame, place]
      @entries.shift while @entries.first[0] < frame - WINDOW_FRAMES
      here = @entries.select { |_, at| at == place }
      return if here.size < ENTRIES

      places = @entries.map(&:last).uniq.map { |at| at.join('-') }
      span = frame - here.first[0]
      @times += 1
      @hint = { place:, places:, span: }
      @acted = false
      @notes << { kind: 'stuck', detail: "loop: #{place.join('-')} entered #{ENTRIES} times in #{span} frames without a new place (#{places.join(', ')}), #{@times} times this run" }
      @entries.clear
    end
  end
end
