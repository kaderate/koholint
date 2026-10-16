require 'digest'
require 'fileutils'
require 'json'
require 'securerandom'
require 'koholint'
require 'koholint/trace'
require 'koholint/input_log'

module Koholint
  class Run
    class VersionMismatch < Error; end
    class RomMismatch < Error; end

    attr_reader :dir, :manifest

    def self.create(root: 'runs', flow_version:, budget:, parent: nil, seed: 0, rom_path: Koholint.rom_path)
      dir = unique_dir(root)
      FileUtils.mkdir_p(File.join(dir, 'save'))
      FileUtils.mkdir_p(File.join(dir, 'keyframes'))
      File.write(File.join(dir, 'trace.jsonl'), '')
      File.write(File.join(dir, 'world.json'), '{}')
      File.write(File.join(dir, 'suggestions.md'), '')
      InputLog.new(File.join(dir, 'inputs.log')).flush
      manifest = { 'flow_version' => flow_version, 'rom_sha256' => rom_hash(rom_path), 'seed' => seed,
                   'budget' => JSON.parse(JSON.generate(budget)), 'status' => 'created', 'parent' => parent }
      new(dir, manifest).tap(&:write_manifest)
    end

    def self.open(dir, flow_version:, rom_path: Koholint.rom_path)
      manifest = JSON.parse(File.read(File.join(dir, 'manifest.json')))
      if manifest['flow_version'] != flow_version
        raise VersionMismatch, "run #{File.basename(dir)} is flow #{manifest['flow_version']}, not #{flow_version}"
      end
      raise RomMismatch, "run #{File.basename(dir)} was recorded with another ROM" if manifest['rom_sha256'] != rom_hash(rom_path)

      new(dir, manifest)
    end

    def self.rom_hash(path) = Digest::SHA256.file(path).hexdigest

    def self.unique_dir(root)
      loop do
        dir = File.join(root, "#{Time.now.strftime('%Y%m%d-%H%M%S')}-#{SecureRandom.hex(2)}")
        return dir unless File.exist?(dir)
      end
    end
    private_class_method :unique_dir

    def initialize(dir, manifest)
      @dir = dir
      @manifest = manifest
    end

    def id = File.basename(dir)
    def trace = @trace ||= Trace.new(File.join(dir, 'trace.jsonl'))
    def inputs = @inputs ||= InputLog.new(File.join(dir, 'inputs.log'))

    def status=(value)
      @manifest['status'] = value
      write_manifest
    end

    def write_manifest
      tmp = File.join(dir, 'manifest.json.tmp')
      File.write(tmp, JSON.pretty_generate(@manifest))
      File.rename(tmp, File.join(dir, 'manifest.json'))
    end
  end
end
