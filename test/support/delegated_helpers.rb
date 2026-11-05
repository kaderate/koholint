require_relative '../test_helper'
require 'tmpdir'
require 'digest'
require 'koholint/engine'
require 'koholint/agents/claude_cli'
require 'koholint/policies/delegated'
require 'koholint/policies/start_game'
require 'koholint/skills/registry'
require 'koholint/vision/beliefs'
require 'koholint/vision/capabilities'
require 'koholint/vision/grid'
require 'koholint/policies/walk_and_talk'
require 'support/emulator_cache'

module DelegatedHelpers
  Reply = Koholint::Agents::Reply
  SHOT = 'PNGBYTES'.b
  PAGE = ("\x10".b * (640 * 384 * 3)).freeze
  OPEN = { dialog_state: 130 }.freeze

  class ScriptedClient
    attr_reader :calls

    def initialize(objective: nil, skill: nil, default: nil)
      @objective = [objective].flatten(1).compact
      @skill = [skill].flatten(1).compact
      @default = default
      @calls = []
    end

    def call(system:, prompt:, schema:, image: nil, images: nil)
      @calls << { system:, prompt:, schema:, image:, images: }
      queue = system.include?('choose the next objective') ? @objective : @skill
      step = queue.empty? ? @default : queue.shift
      raise step if step.is_a?(Exception)

      step.respond_to?(:call) ? step.call : step
    end
  end

  def ok(output = nil, cost: 0.01, **fields) = Reply.new((output || fields).merge('justification' => 'because', 'confidence' => 0.5), cost, 200, {}, nil)
  def failing(message) = Reply.new(nil, 0.02, nil, nil, message)
  def objective(kind: 'leave_place', place: [163, 16]) = ok('title' => 'go', 'predicate' => { 'kind' => kind, 'place' => place })
  def walk(direction = 'up') = ok('skill' => 'walk', 'params' => { 'direction' => direction, 'cells' => 1 })

  def state(**over)
    Koholint::GameState.new(frame: 100, room_id: 163, map_id: 16, x: 68, y: 60, direction: :up, hp: 24, max_hp: 24,
                            milestone: :none, game_mode: 0x0B, game_submode: 7, dialog_state: 0, **over)
  end

  def grid
    cells = Array.new(8) { Array.new(10) { 'floor' } }
    Koholint::Vision::Grid.new(cells:, static_sprites: {}, beliefs: Koholint::Vision::Beliefs.new, capabilities: Koholint::Vision::Capabilities.new)
  end

  def trace
    @dir ||= Dir.mktmpdir
    Koholint::Trace.new(File.join(@dir, 'trace.jsonl'))
  end

  def teardown = (FileUtils.rm_rf(@dir) if @dir)

  def policy(client, triggers: nil, **opts)
    @objectives = Koholint::Objectives.new(trace: trace, **opts)
    Koholint::Policies::Delegated.new(client:, registry: Koholint::Skills::Registry.default, objectives: @objectives, manual: 'notes', triggers:)
  end

  def decide(policy, state = self.state)
    point = policy.decision_point_for(state)
    [point, policy.decide(point, state, { grid: })]
  end
end
