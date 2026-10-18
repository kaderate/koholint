require 'test_helper'

class CalibrationBoundaryTest < Minitest::Test
  ROOT = File.expand_path('..', __dir__)
  AGENT_SIDE = Dir[File.join(ROOT, 'lib/koholint/policies/**/*.rb')] +
               %w[decision engine].map { |name| File.join(ROOT, "lib/koholint/#{name}.rb") }
  FORBIDDEN = %w[write poke instance_variable_get instance_variable_set send public_send __send__ mmu motherboard const_get .fill(].freeze

  def self.violations(source) = FORBIDDEN.select { |token| source.include?(token) }

  def test_agent_side_code_never_references_calibration
    refute_empty AGENT_SIDE
    offenders = AGENT_SIDE.select { |path| File.read(path).match?(%r{Calibration|calibration/}) }
    assert_empty offenders
  end

  def test_only_the_grid_builder_uses_calibration_outside_it
    outside = Dir[File.join(ROOT, 'lib/**/*.rb')].reject { |path| path.start_with?(File.join(ROOT, 'lib/koholint/calibration/')) }
    users = outside.select { |path| File.read(path).match?(%r{Calibration|calibration/}) }
    assert_equal [File.join(ROOT, 'lib/koholint/vision/grid_builder.rb')], users
  end

  def test_calibration_code_never_writes_emulator_memory
    files = Dir[File.join(ROOT, 'lib/koholint/calibration/**/*.rb')]
    refute_empty files
    offenders = files.select { |path| self.class.violations(File.read(path)).any? }
    assert_empty offenders
  end

  def test_scanner_flags_evasive_writes_and_passes_clean_code
    ['emulator.debug_write(0xFF98, 1)', 'x.send(:write)', 'instance_variable_get(:@driver)', 'mmu.write(1, 2)',
     'x.public_send(:a)', 'x.__send__(:a)', 'e.motherboard', 'Object.const_get(:X)', 'a.fill(0)', 'e.poke(1)',
     'write_byte(1)'].each { |code| refute_empty self.class.violations(code), code }
    assert_empty self.class.violations("copy = Emulator.restore(emulator.dump)\ncopy.step([:up])\nPerception.read(copy)")
  end
end
