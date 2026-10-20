module Koholint
  module BootScript
    TITLE = 0
    FILE_SELECT = 2
    NAME_ENTRY = 3
    FILE_SELECT_READY = 7
    NAME_ENTRY_READY = 2
    PULSE_PERIOD = 20
    PRESS_FRAMES = 3
    WAIT_FRAMES = 5
    PROBE_DIRECTIONS = %i[up right down left].freeze
    PROBE_FRAMES = 8
    PROBE_IDLE_FRAMES = 30

    module_function

    def macro_for(state)
      case state.game_mode
      when TITLE then title(state.frame)
      when FILE_SELECT then state.game_submode == FILE_SELECT_READY ? press(:a) : wait
      when NAME_ENTRY then name_entry(state)
      else wait
      end
    end

    def probe_free(step)
      direction = PROBE_DIRECTIONS[step % (PROBE_DIRECTIONS.size + 1)]
      direction ? { buttons: [direction], frames: PROBE_FRAMES } : { buttons: [], frames: PROBE_IDLE_FRAMES }
    end

    def title(frame)
      phase = frame % PULSE_PERIOD
      return { buttons: [:start], frames: PRESS_FRAMES - phase } if phase < PRESS_FRAMES

      { buttons: [], frames: PULSE_PERIOD - phase }
    end

    def name_entry(state)
      return wait unless state.game_submode == NAME_ENTRY_READY

      state.name_length.to_i.zero? ? press(:a) : press(:start)
    end

    def press(button) = { buttons: [button], frames: PRESS_FRAMES }

    def wait = { buttons: [], frames: WAIT_FRAMES }
    private_class_method :title, :name_entry, :press, :wait
  end
end
