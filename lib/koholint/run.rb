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
      manifest = begin
        JSON.parse(File.read(File.join(dir, 'manifest.json')))
      rescue Errno::ENOENT, JSON::ParserError
        raise Error, "no run at #{dir}"
      end
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

    def fork(at_frame:, flow_version:, rom_path: Koholint.rom_path)
      raise Error, "cannot fork at frame #{at_frame}: run has #{inputs.frames} frames" unless (0..inputs.frames).cover?(at_frame)

      child = self.class.create(root: File.dirname(dir), flow_version: flow_version, budget: manifest['budget'],
                                parent: { 'id' => id, 'frame' => at_frame }, seed: manifest['seed'], rom_path: rom_path)
      journal = InputLog.new(File.join(child.dir, 'inputs.log'))
      inputs.each_frame.first(at_frame).each { |buttons| journal.append(buttons) }
      journal.flush
      events = Trace.read(File.join(dir, 'trace.jsonl')).select do |event|
        event['frame'] < at_frame && !%w[stop budget_stop].include?(event['type'])
      end
      rewrite_trace(File.join(child.dir, 'trace.jsonl'), events)
      events.select { |event| event['type'] == 'save' }.each do |event|
        FileUtils.cp(File.join(dir, 'save', event['path']), File.join(child.dir, 'save'))
      end
      Dir.glob(File.join(dir, 'keyframes', 'kf-*.zlib')).each do |path|
        FileUtils.cp(path, File.join(child.dir, 'keyframes')) if File.basename(path)[/\d+/].to_i <= at_frame
      end
      self.class.open(child.dir, flow_version: flow_version, rom_path: rom_path)
    end

    def lock!
      return if @lock_file

      file = File.open(File.join(dir, 'run.lock'), File::CREAT | File::RDWR)
      unless file.flock(File::LOCK_EX | File::LOCK_NB)
        file.close
        raise Error, "run #{id} is already in use by another process"
      end
      @lock_file = file
    end

    def unlock!
      @lock_file&.close
      @lock_file = nil
    end

    def truncate_trace!(frames)
      path = File.join(dir, 'trace.jsonl')
      kept = Trace.read(path).reject do |event|
        event['frame'] > frames || (%w[perception decision].include?(event['type']) && event['frame'] >= frames)
      end
      rewrite_trace(path, kept)
    end

    def write_manifest
      tmp = File.join(dir, 'manifest.json.tmp')
      File.write(tmp, JSON.pretty_generate(@manifest))
      File.rename(tmp, File.join(dir, 'manifest.json'))
    end

    private

    def rewrite_trace(path, events)
      tmp = "#{path}.tmp"
      File.write(tmp, events.map { |event| "#{JSON.generate(event)}\n" }.join)
      File.rename(tmp, path)
    end
  end
end
