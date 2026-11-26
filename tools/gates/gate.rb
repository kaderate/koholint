$LOAD_PATH.unshift(File.expand_path('../../lib', __dir__))
require 'optparse'
require_relative 'metrics'

# ruby tools/gates/gate.rb GATE|all [--root DIR]   plays each gate with the stub and checks it against expected.json for FLOW_VERSION
# ruby tools/gates/gate.rb GATE --check RUN_DIR    checks a run already played
options = { root: File.expand_path('~/.capy/work/runs/gates') }
OptionParser.new do |parser|
  parser.on('--root DIR') { |dir| options[:root] = File.expand_path(dir) }
  parser.on('--check DIR') { |dir| options[:check] = File.expand_path(dir) }
end.parse!

config = JSON.parse(File.read(File.join(__dir__, 'gates.json')))
expected = JSON.parse(File.read(File.join(__dir__, 'expected.json')))
names = ARGV.first == 'all' ? config['gates'].keys : [ARGV.fetch(0)]
abort "unknown gate #{(names - config['gates'].keys).join(', ')}; gates: #{config['gates'].keys.join(', ')}" unless (names - config['gates'].keys).empty?

require 'koholint'
failed = names.count do |name|
  gate = config['gates'][name]
  dir = options[:check] || begin
    require_relative 'stub'
    parent = config['roots'].map { |root| File.join(File.expand_path(root), gate['run']) }.find { |path| File.directory?(path) } or
      abort "#{name}: run #{gate['run']} not found under #{config['roots'].join(', ')}"
    Gates.play(parent, frame: gate['frame'], tag: "gate-#{name}", frames: config['frames'], root: options[:root])
  end
  manifest = JSON.parse(File.read(File.join(dir, 'manifest.json')))
  parent = manifest['parent'] || {}
  abort "#{name}: #{dir} forks #{parent['id']} @#{parent['frame']}, not #{gate['run']} @#{gate['frame']}" unless [parent['id'], parent['frame']] == [gate['run'], gate['frame']]

  flow = manifest['flow_version']
  measured = Gates.metrics(dir)
  want = expected.dig(flow, name)
  puts "#{name} #{flow} #{dir} #{JSON.generate(measured)}"
  unless want
    puts "#{name}: no expected numbers for #{flow}; add them to tools/gates/expected.json"
    next true
  end

  wrong = Gates.mismatches(want, measured)
  wrong.each { |field, was, now| puts "#{name}: #{field} expected #{was.inspect}, measured #{now.inspect}" }
  wrong.any?
end
exit(failed.zero? ? 0 : 1)
