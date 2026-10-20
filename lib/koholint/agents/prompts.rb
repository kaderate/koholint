require 'digest'

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
        An objective is a short goal with a title and a predicate that the harness can check from memory. The predicate is one of six kinds: leave_place (place), reach_place (place), reach_cell (place, row, col), dialogue_closed, new_place or new_text (no fields). A place is [room, map] as integers, row is 0-7 and col is 0-9.
        leave_place means finding a way out of the current place. new_place means reaching a place not yet visited in this run. new_text means reading a text you have not read yet in this run: talk to a person, read a sign or an object. reach_cell targets that are already reachable over cells observed free are refused: choose goals that need exploration.
        Pick an objective that is achievable from the current state and different from objectives that already failed or were abandoned. Give the exact fields of the chosen kind and no others.
        The goal is your long-term goal, shown in the context with when you set it. Review it at every objective: re-read the leads and what people told you before restating it, then repeat it to keep it or rewrite it. Revise it when what you learned or reached makes it obsolete, for example when it names a place you already reached or left. Use the high leads of the context when choosing the goal and the objective; when a lead motivates the objective, give its id in because.
        The plan field is mandatory on every call: one line saying what you will do over the next few calls and why. Your previous plan, if any, is shown in the context.
        Output fields: title, predicate, justification, confidence, plan, goal, and optionally because.
      TEXT

      SKILL = <<~TEXT.freeze
        Decision: choose the next skill to run towards the current objective.
        A skill is a bounded action with parameters; the harness runs it and reports how it stopped. Choose exactly one skill from the schema with parameters that satisfy it.
        goto walks several cells along a path planned over the grid and stops when blocked. Cells marked ! may be doubtful: they looked free but blocked Link repeatedly; goto avoids a doubtful edge, and the neighbour lines say how many times each direction was blocked.
        talk_to walks next to a person or object at (row, col), faces it and presses A; use it instead of composing walk and press yourself. If it gets no response from one side, the listing of things on screen shows which sides failed: the skill tries another side by itself, and you can also walk next to a person from a specific side and press A.
        step moves Link a few pixels (1 to 16) along one axis and does not recentre him; the offset line shows how far he is from the centre of his cell, and a passage may be offset from the cell grid.
        A dialogue that opens by itself is triggered by the game and may repeat while you stay where it triggers. The context lists the things on screen with how many times you talked to each: people or objects you have never tried to talk to are worth trying before repeating an action that keeps failing.
        Do not repeat a skill that just stopped the same way from the same state; try something different or gather information. When on-screen text matters, transcribe it in the optional transcription field. When an image is attached it shows the top and the bottom of the screen stacked; a dialogue box may be in either.
        Texts are what people say and what signs or objects you read show. When you transcribe a text, you may also extract leads: up to five, each with a quote copied word for word from your transcription, a short claim saying what it tells you, and an importance. high: it states a goal, a destination, an item to obtain, a condition or obstacle, or a danger. normal: a local hint, such as a passage or what a room is for. low: flavour, small talk, shop prices. A lead whose quote is not in the transcription is dropped.
        The goal is your long-term goal, shown in the context: set it in goal when you have a reason, revise it only when new information changes it, omit it to keep it. Use the high leads when choosing it.
        The plan field is mandatory on every call: one line saying what you will do over the next few calls and why. Your previous plan, if any, is shown in the context.
        Output fields: skill, params, justification, confidence, plan, and optionally transcription, leads and goal.
      TEXT

      SHEETS = <<~TEXT.freeze
        The attached images are the pages of the dialogue that just closed, oldest first: each page shows the top and the bottom of the screen stacked, and the pages are stacked vertically in sheets. Give the full transcription of all the pages, in order, in transcription, one paragraph per page separated by a blank line, then extract its leads.
      TEXT

      def self.system_for(decision_point, sheets: false)
        body = case decision_point.name
               when :choose_objective then OBJECTIVE
               when :choose_skill then SKILL
               else raise ArgumentError, "no system prompt for #{decision_point.name}"
               end
        body = [body.chomp.sub(/^Output fields:.*\z/m, '').chomp, SHEETS.chomp, body[/^Output fields:.*/m]].join("\n") if sheets
        [ROLE, body, OUTPUT_RULES].join("\n")
      end

      def self.digest = Digest::SHA256.hexdigest(constants.sort.map { |name| const_get(name) }.grep(String).join("\0"))
    end
  end
end
