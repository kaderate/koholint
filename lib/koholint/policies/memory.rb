require 'koholint/explore_log'
require 'koholint/leads'
require 'koholint/ledger'
require 'koholint/loop_watch'
require 'koholint/place_card'
require 'koholint/talk_log'
require 'koholint/triggers'
require 'koholint/zero_watch'

module Koholint
  module Policies
    Memory = Data.define(:ledger, :triggers, :talk_log, :explore_log, :leads, :cards, :loop_watch, :zero_watch) do
      def initialize(ledger: nil, triggers: nil, talk_log: nil, explore_log: nil, leads: nil, cards: {}, loop_watch: nil, zero_watch: nil)
        super(ledger: ledger || Ledger.new, triggers: triggers || Triggers.new, talk_log: talk_log || TalkLog.new, explore_log: explore_log || ExploreLog.new,
              leads: leads || Leads.new, cards:, loop_watch: loop_watch || LoopWatch.new, zero_watch: zero_watch || ZeroWatch.new)
      end

      def self.from_events(events)
        new(ledger: Ledger.from_events(events), triggers: Triggers.from_events(events), talk_log: TalkLog.from_events(events),
            explore_log: ExploreLog.from_events(events), leads: Leads.from_events(events), cards: PlaceCard.latest(events),
            loop_watch: LoopWatch.from_events(events), zero_watch: ZeroWatch.from_events(events))
      end
    end
  end
end
