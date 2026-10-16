module Koholint
  module BootScript
    MAX_MACRO_FRAMES = 120
    TITLE_PHASE_FRAMES = 6000

    module_function

    def input_at(frame)
      return title_input(frame) if frame < TITLE_PHASE_FRAMES

      since = frame - TITLE_PHASE_FRAMES
      if since < 3 then [:a]
      elsif since >= 60 && since < 63 then [:start]
      elsif since > 120 && (since % 90) < 3 then [:a]
      else []
      end
    end

    def macro_at(frame)
      buttons = input_at(frame)
      frames = 1
      frames += 1 while frames < MAX_MACRO_FRAMES && input_at(frame + frames) == buttons
      { buttons: buttons, frames: frames }
    end

    def title_input(frame)
      phase = frame % 120
      if frame < 10 || phase < 3 then [:start]
      elsif phase > 60 && phase < 63 then [:a]
      else []
      end
    end
    private_class_method :title_input
  end
end
