module Koholint
  module Agents
    module Prompts
      ROLE = <<~TEXT.freeze
        You play a Game Boy action-adventure game through a harness. You are a player who knows the game's manual and the genre, not a walkthrough: nothing about this particular game is given to you beyond the manual in each message, so rely on what you observe.
        Each message describes the current state: the phase, Link's position on an 8x10 grid of cells, a map of what is known about each cell, the neighbours of Link, the current objective and the results of recent skills.
        Unknown cells are not walls: a cell marked ? simply has not been observed yet, so treat it as worth trying. Cells marked ! were observed under other conditions and may have changed. Believe the observed results over your own guesses.
      TEXT

      OUTPUT_RULES = <<~TEXT.freeze
        Answer with a single JSON object that matches the provided schema and nothing else: no prose, no code fences.
        Always include a short justification grounded in the observations and a confidence between 0 and 1.
      TEXT

      OBJECTIVE = <<~TEXT.freeze
        Decision: choose the next objective.
        An objective is a short goal with a title and a predicate that the harness can check from memory. The predicate is one of four kinds: leave_place (place), reach_place (place), reach_cell (place, row, col) or dialogue_closed. A place is [room, map] as integers, row is 0-7 and col is 0-9.
        leave_place means finding a way out of the current place. new_place (no fields) means reaching a place not yet visited in this run. reach_cell targets that are already reachable over cells observed free are refused: choose goals that need exploration.
        Pick an objective that is achievable from the current state and different from objectives that already failed or were abandoned. Give the exact fields of the chosen kind and no others.
        Output fields: title, predicate, justification, confidence.
      TEXT

      SKILL = <<~TEXT.freeze
        Decision: choose the next skill to run towards the current objective.
        A skill is a bounded action with parameters; the harness runs it and reports how it stopped. Choose exactly one skill from the schema with parameters that satisfy it.
        goto walks several cells along a path planned over the grid and stops when blocked. Cells marked ! may be doubtful: they looked free but blocked Link repeatedly; goto avoids a doubtful edge, and the neighbour lines say how many times each direction was blocked.
        step moves Link a few pixels (1 to 16) along one axis and does not recentre him; the offset line shows how far he is from the centre of his cell, and a passage may be offset from the cell grid.
        Do not repeat a skill that just stopped the same way from the same state; try something different or gather information. When on-screen text matters, transcribe it in the optional transcription field. When images are attached they are the pages of the dialogue that just closed, oldest first, each page showing the top and the bottom of the screen stacked, and the pages are stacked vertically in sheets. Then give the full transcription of all the pages, in order, in transcription, one paragraph per page separated by a blank line.
        Output fields: skill, params, justification, confidence, and optionally transcription.
      TEXT

      def self.system_for(decision_point)
        body = case decision_point.name
               when :choose_objective then OBJECTIVE
               when :choose_skill then SKILL
               else raise ArgumentError, "no system prompt for #{decision_point.name}"
               end
        [ROLE, body, OUTPUT_RULES].join("\n")
      end
    end
  end
end
