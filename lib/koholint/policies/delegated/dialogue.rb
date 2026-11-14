module Koholint
  module Policies
    class Delegated
      module Dialogue
        def continue_dialogue(result, state)
          return result unless @flushing && state.dialog_open?

          @auto = true
          result.merge(choice: ADVANCE, justification: "harness: the dialogue goes on after #{@pages_read} pages read, keep advancing (replaces the model's choice): #{result[:justification]}")
        end

        private

        def drop_stale_sequence(state)
          return unless @sequence

          stale = state.phase != :dialogue && state.frame - @sequence[:last] > STALE_SEQUENCE_FRAMES
          @sequence = nil if stale || @sequence[:place] != [state.room_id, state.map_id]
        end

        def reopen_wait(decision_point, state)
          return unless decision_point.name == :choose_skill && @sequence && state.phase != :dialogue && !@sequence[:waited]

          @sequence[:waited] = true
          @waiting = true
          @objectives.touch(frame: state.frame)
          { choice: REOPEN_WAIT, justification: 'automatic dialogue advance: waiting for the dialogue to reopen', confidence: 1.0, agent: 'delegated',
            latency_ms: 0, cost_usd: 0.0, fallback: false, prompt: nil, image: nil }
        end

        def automatic_advance(decision_point, state, context)
          return unless decision_point.name == :choose_skill && state.phase == :dialogue && !@agent_driven

          if @sequence && sequence_full?(state)
            @flushes = @flushes.to_i + 1
            @flushing = @flushes == 1
            @agent_driven = true unless @flushing
            @objectives.touch(frame: state.frame)
            return
          end
          rgb = context[:dialogue_rgb]&.call or return
          unless @sequence
            @sequence = { pages: [], rows: [], start: state.frame, place: [state.room_id, state.map_id], source: @talk_source, contact: @contact }
            @contact = nil
            @objectives.touch(frame: state.frame)
          end
          @sequence[:last] = state.frame
          @sequence[:waited] = false
          @sequence[:pages] << rgb
          @sequence[:rows] << Vision::DialogueShot.text_rows(rgb)
          @auto = true
          announce(:acting, "automatic dialogue advance, page #{@page + 1}", state, skill: ADVANCE[:skill], page: @page + 1)
          { choice: ADVANCE, justification: 'automatic dialogue advance', confidence: 1.0, agent: 'delegated', latency_ms: 0, cost_usd: 0.0,
            fallback: false, prompt: nil, image: nil }
        end

        def sequence_full?(state)
          @sequence[:pages].size >= DIALOGUE_PAGE_LIMIT || state.frame - @sequence[:start] >= DIALOGUE_FRAME_LIMIT
        end

        def remember_text(transcription, state)
          pages = [transcription].flatten(1).compact.map { |page| page[:text] }
          return if pages.empty?

          text = Dialogues.text(pages)
          @objectives.note_text(text)
          @leads.note_read(text)
          source = @images || @reading ? @read_at[:source] : @talk_source
          place = @images || @reading ? @read_at[:place] : [state.room_id, state.map_id]
          conversation = @read_at[:conversation] if @images || @reading
          first = [transcription].flatten(1).compact.first
          @talk_log.store_pages(conversation, pages) if conversation && @images
          @talk_log.remember(place:, cell: [source[:row], source[:col]], text:, stamp: stamp(state), entity: source[:entity], conversation:, speaker: first[:speaker]) if source
          @revisit.read if @images || @reading
        end

        def notes_for(output, transcription, state)
          goal = @leads.change_goal(output['goal'], frame: state.frame, objectives: @objectives.finished)
          notes = goal ? { goal: } : {}
          here = [state.room_id, state.map_id]
          name = @leads.name_place(here, output['place_name']) if output['place_name'].is_a?(String) && state.phase(booted: true) != :loading
          notes[:place_name] = { place: here, name: } if name
          read = @images || @reading
          contact = @read_at[:contact] if read
          return notes unless output.key?('leads') || contact

          pages = [transcription].flatten(1).compact
          place = @read_at && read ? @read_at[:place] : [state.room_id, state.map_id]
          source = @images ? @read_at[:source] : @talk_source
          texts = pages.map { |page| page[:text] }
          leads, rejected, leaked = output.key?('leads') ? @leads.absorb(output['leads'], transcription: [texts.join(' '), Dialogues.text(texts)], place:, source:) : [[], 0, []]
          found = contact && @leads.contact(contact, text: Dialogues.text(texts), place:)
          notes.merge(leads: found ? leads + [found] : leads, leads_rejected: rejected, **(leaked.any? ? { leads_leaked: leaked } : {}))
        end

        def clean(text, cap: TRANSCRIPTION_LIMIT) = text.gsub(/[^\P{Cntrl}\n]/, '').strip.then { |t| cap ? t[0, cap] : t }

        def transcription_for(output, state, decision_point)
          text = output['transcription']
          return {} unless decision_point.name == :choose_skill && text.is_a?(String)
          @speaker = speaker_of(output)
          return { transcription: sequence_pages(text) }.reject { |_, v| v.empty? } if @images
          return {} unless state.phase == :dialogue && !clean(text).empty?

          { transcription: { text: clean(text), page: @page } }
        end

        def sequence_pages(text)
          paragraphs = text.split(/\n[^\S\n]*\n/).map { |chunk| clean(chunk, cap: nil) }.reject(&:empty?)
          chunks = paragraphs.flat_map { |paragraph| paragraph.scan(/.{1,#{TRANSCRIPTION_LIMIT}}/m) }
          chunks.first(DIALOGUE_PAGE_LIMIT).each_with_index.map { |t, i| page_entry(t, i + 1, speaker: @speaker) }
        end

        def page_entry(text, page, speaker: nil, cached: nil)
          { text:, page:, frame: @read_at[:start], place: @read_at[:place], conversation: @read_at[:conversation], speaker:, cached: }.compact
        end

        def speaker_of(output)
          name = output['speaker']
          name = name.is_a?(String) ? clean(name.tr("\n", ' '), cap: SPEAKER_LIMIT) : ''
          name.empty? ? nil : name
        end

        def cached_reading(decision_point, state)
          return unless decision_point.name == :choose_skill && @sequence && state.phase != :dialogue && !state.dialog_open?

          conversation = Vision::DialogueShot.signature(@sequence[:rows])
          pages = conversation && @talk_log.pages_for(conversation)
          return unless pages

          @read_at = @sequence.slice(:start, :place, :source, :contact).merge(conversation:)
          speaker = @talk_log.speaker_for(conversation)
          @page = @sequence[:pages].size
          @sequence = nil
          @objectives.touch(frame: state.frame)
          entries = pages.each_with_index.map { |text, i| page_entry(text, i + 1, speaker:, cached: true) }
          @reading = { transcription: entries }
          remember_text(entries, state)
          @reading
        end
      end
    end
  end
end
