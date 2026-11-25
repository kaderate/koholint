require 'koholint/explore_log'
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
    Memory = Data.define(:ledger, :triggers, :talk_log, :explore_log, :leads, :cards, :loop_watch, :zero_watch, :item_names, :item_tries, :stalled) do
      def initialize(ledger: nil, triggers: nil, talk_log: nil, explore_log: nil, leads: nil, cards: {}, loop_watch: nil, zero_watch: nil, item_names: {},
                     item_tries: {}, stalled: [])
        super(ledger: ledger || Ledger.new, triggers: triggers || Triggers.new, talk_log: talk_log || TalkLog.new, explore_log: explore_log || ExploreLog.new,
              leads: leads || Leads.new, cards:, loop_watch: loop_watch || LoopWatch.new, zero_watch: zero_watch || ZeroWatch.new, item_names:, item_tries:, stalled:)
      end

      def self.from_events(events)
        new(ledger: Ledger.from_events(events), triggers: Triggers.from_events(events), talk_log: TalkLog.from_events(events),
            explore_log: ExploreLog.from_events(events), leads: Leads.from_events(events), cards: PlaceCard.latest(events),
            loop_watch: LoopWatch.from_events(events), zero_watch: ZeroWatch.from_events(events), item_names: Items.pickup_names(events), item_tries: item_tries(events), stalled: stalled(events))
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
