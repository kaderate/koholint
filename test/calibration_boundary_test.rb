require 'test_helper'

class CalibrationBoundaryTest < Minitest::Test
  ROOT = File.expand_path('..', __dir__)
  # Task 6 will move engine usage behind the grid builder and update this list.
  AGENT_SIDE = Dir[File.join(ROOT, 'lib/koholint/policies/**/*.rb')] +
               %w[decision engine].map { |name| File.join(ROOT, "lib/koholint/#{name}.rb") }
  WRITE_PATTERN = /\bwrite\b|\bpoke\b|instance_variable_set|\bmmu\b/

  def test_agent_side_code_never_references_calibration
    refute_empty AGENT_SIDE
    offenders = AGENT_SIDE.select { |path| File.read(path).match?(%r{Calibration|calibration/}) }
    assert_empty offenders
  end

  def test_calibration_code_never_writes_emulator_memory
    files = Dir[File.join(ROOT, 'lib/koholint/calibration/**/*.rb')]
    refute_empty files
    offenders = files.select { |path| File.read(path).match?(WRITE_PATTERN) }
    assert_empty offenders
  end
end
