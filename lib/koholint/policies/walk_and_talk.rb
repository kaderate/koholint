require 'koholint/decision'

module Koholint
  module Policies
    class WalkAndTalk
      CYCLE_FRAMES = 30
      TALK_EVERY = 10

      def decide(_decision_point, state, _context)
        step = state.frame / CYCLE_FRAMES
        choice = if (step % TALK_EVERY) == TALK_EVERY - 1
                   { buttons: [:a], frames: 2 }
                 else
                   { buttons: [DecisionPoint::DIRECTIONS[step % DecisionPoint::DIRECTIONS.size]], frames: CYCLE_FRAMES }
                 end
        { choice: choice, justification: 'fixed cycle', confidence: 1.0, agent: 'walk_and_talk' }
      end
    end
  end
end
