require 'json'
require 'koholint'
require 'koholint/agents/claude_cli'
require 'koholint/autopilot'
require 'koholint/budget'
require 'koholint/capabilities'
require 'koholint/cli'
require 'koholint/engine'
require 'koholint/policies/delegated'
require 'koholint/skills/composite'

module Gates
  # The $0 stand-in for the model: it picks a souvenir, else a person or thing Link holds other items for, else a new place; it tries the
  # objective's person (talk, then touch), closes map and menu screens, and otherwise explores.
  class Stub
    EXPLORE = { 'skill' => 'explore', 'params' => {}, 'transcription' => '' }.freeze

    attr_reader :calls

    def initialize
      @calls = 0
    end

    def call(system:, prompt:, schema:, image: nil, images: nil)
      @calls += 1
      output = system.include?('choose the next objective') ? objective(prompt) : screen(schema) || attempt(prompt) || EXPLORE
      Koholint::Agents::Reply.new(output.merge('justification' => 'stub', 'confidence' => 0.5), 0.0, 1, {}, nil)
    end

    def objective(prompt)
      pick = prompt[/^- (souvenir-[\w-]+): /, 1] || prompt[/^- ((?:person|examine|need)-[\w-]+): .*Link holds other items/, 1]
      pick ? { 'candidate' => pick } : { 'title' => 'go right', 'predicate' => { 'kind' => 'new_place' } }
    end

    def attempt(prompt)
      type = prompt[/^To end it: .*?type (\d+)/, 1] or return
      row, col = prompt.match(/type #{type} at \((\d+),(\d+)\)/)&.captures&.map(&:to_i)
      return unless row

      talked = prompt[/Attempts on this objective:\n((?:- .*\n?)*)/, 1].to_s.include?('- talk_to')
      talked ? { 'skill' => 'touch', 'params' => { 'row' => row, 'col' => col, 'type' => type.to_i }, 'transcription' => '' } : { 'skill' => 'talk_to', 'params' => { 'row' => row, 'col' => col }, 'transcription' => '' }
    end

    def screen(schema)
      names = schema.to_s.scan(/"([a-z_]+)"/).flatten
      return if names.include?('explore')

      skill = %w[close_map close_menu].find { |name| names.include?(name) }
      { 'skill' => skill, 'params' => {}, 'transcription' => '' } if skill
    end
  end

  module_function

  # Forks the parent run at the frame and plays it with the stub for the given frames; returns the fork's directory.
  def play(parent, frame:, tag:, frames:, root:)
    run = Koholint::CLI.parent_run(parent)
    child = run.fork(at_frame: frame, flow_version: Koholint::FLOW_VERSION, root:, tag:)
    events = Koholint::CLI.events_for(child)
    budget = Koholint::Budget.new(frames:)
    learned = Koholint::Capabilities.operational.map { |entry| Koholint::Skills::Composite.new(entry) }
    policy = Koholint::Policies::Delegated.new(client: Stub.new, autopilot: Koholint::Autopilot.new, registry: Koholint::Skills::Registry.default(extra: learned),
                                               objectives: Koholint::CLI.objectives_for(child, events), memory: Koholint::Policies::Memory.from_events(events),
                                               manual: '', budget:, souvenirs: Koholint::Souvenirs.for_manifest(child.manifest))
    Koholint::Engine.resume(child.dir, policy:, budget:, grid: true).run
    child.dir
  end
end
