require 'koholint/explore_log'
require 'koholint/healers'
require 'koholint/hurts'
require 'koholint/items'
require 'koholint/leads'
require 'koholint/ledger'
require 'koholint/loop_watch'
require 'koholint/place_card'
require 'koholint/talk_log'
require 'koholint/triggers'
require 'koholint/zero_watch'

module Koholint
  module Policies
    Memory = Data.define(:ledger, :triggers, :talk_log, :explore_log, :leads, :cards, :loop_watch, :zero_watch, :item_names, :item_tries, :stalled, :healers,
                         :retreats, :reoffers, :souvenirs_taken, :hurts) do
      def initialize(ledger: nil, triggers: nil, talk_log: nil, explore_log: nil, leads: nil, cards: {}, loop_watch: nil, zero_watch: nil, item_names: {},
                     item_tries: {}, stalled: [], healers: nil, retreats: [], reoffers: {}, souvenirs_taken: [], hurts: nil)
        super(ledger: ledger || Ledger.new, triggers: triggers || Triggers.new, talk_log: talk_log || TalkLog.new, explore_log: explore_log || ExploreLog.new,
              leads: leads || Leads.new, cards:, loop_watch: loop_watch || LoopWatch.new, zero_watch: zero_watch || ZeroWatch.new, item_names:, item_tries:, stalled:,
              healers: healers || Healers.new, retreats:, reoffers:, souvenirs_taken:, hurts: hurts || Hurts.new)
      end

      def self.from_events(events)
        new(ledger: Ledger.from_events(events), triggers: Triggers.from_events(events), talk_log: TalkLog.from_events(events),
            explore_log: ExploreLog.from_events(events), leads: Leads.from_events(events), cards: PlaceCard.latest(events),
            loop_watch: LoopWatch.from_events(events), zero_watch: ZeroWatch.from_events(events), item_names: Items.pickup_names(events), item_tries: item_tries(events), stalled: stalled(events),
            healers: Healers.from_events(events), hurts: Hurts.from_events(events),
            retreats: retreats(events), reoffers: reoffers(events), souvenirs_taken: souvenirs_taken(events))
      end

      RETREAT = /\(retreat by the (\S*) side\)/
      REOFFER = /\Athe loop is cut: (.+), set aside, is taken up again \(/

      # Each retreat the harness sent: [place, side Link had come in by, frame], read back from its justification.
      def self.retreats(events)
        events.filter_map do |event|
          side = event['type'] == 'decision' && event['justification'].to_s[RETREAT, 1]
          [[event.dig('input', 'room_id'), event.dig('input', 'map_id')], side, event['frame']] if side
        end
      end

      def self.souvenirs_taken(events)
        events.filter_map { |event| event['candidate'] if event['type'] == 'objective' && event['status'] == 'started' && event['candidate'].to_s.start_with?('souvenir-') }.uniq
      end

      def self.reoffers(events)
        events.filter_map { |event| event['justification'].to_s[REOFFER, 1] if event['type'] == 'decision' }.tally
      end

      # The candidates whose objective was abandoned on a stall.
      def self.stalled(events)
        objectives = events.select { |event| event['type'] == 'objective' }
        ids = objectives.select { |event| event['status'] == 'abandoned' && event['reason'] == 'stall' }.map { |event| event['id'] }
        objectives.filter_map { |event| event['candidate'] if event['status'] == 'started' && ids.include?(event['id']) }.uniq
      end

      # Each item objective started: [item, place, type] => what Link knew of that person then ([texts read, reachable]).
      def self.item_tries(events)
        events.select { |event| event['type'] == 'objective' && event['status'] == 'started' && event.dig('target', 'item') }.to_h do |event|
          target = event['target']
          [[target['item'], target['place'], target['type']], target['seen']]
        end
      end
    end
  end
end
