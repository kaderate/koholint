require 'digest'
require 'fileutils'
require 'json'
require 'open3'
require 'securerandom'
require 'koholint'
require 'koholint/agents/prompts'
require 'koholint/trace'
require 'koholint/input_log'

module Koholint
  class Run
    class VersionMismatch < Error; end
    class RomMismatch < Error; end

    attr_reader :dir, :manifest

    def self.create(root: 'runs', flow_version:, budget:, parent: nil, seed: 0, rom_path: Koholint.rom_path, tag: nil, model: nil)
      dir = unique_dir(root)
      FileUtils.mkdir_p(File.join(dir, 'save'))
      FileUtils.mkdir_p(File.join(dir, 'keyframes'))
      File.write(File.join(dir, 'trace.jsonl'), '')
      File.write(File.join(dir, 'world.json'), '{}')
      File.write(File.join(dir, 'suggestions.md'), '')
      InputLog.new(File.join(dir, 'inputs.log')).flush
      manifest = { 'flow_version' => flow_version, 'rom_sha256' => rom_hash(rom_path), 'seed' => seed,
                   'budget' => JSON.parse(JSON.generate(budget)), 'status' => 'created', 'parent' => parent,
                   'tag' => tag, 'harness_sha' => harness_sha, 'prompts_sha' => Agents::Prompts.digest, 'model' => model }
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

    def self.harness_sha
      sha, status = Open3.capture2('git', '-C', File.expand_path('../..', __dir__), 'rev-parse', 'HEAD', err: File::NULL)
      status.success? ? sha.strip : nil
    rescue SystemCallError
      nil
    end

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
    def trace = @trace ||= restore_trace!.then { Trace.new(trace_path) }
    def trace_path = File.join(dir, 'trace.jsonl')

    def restore_trace!
      Trace.decompress(trace_path) if Trace.located(trace_path) != trace_path
      self
    end
    def inputs = @inputs ||= InputLog.new(File.join(dir, 'inputs.log'))

    def status=(value)
      @manifest['status'] = value
      write_manifest
    end

    def fork(at_frame:, flow_version:, rom_path: Koholint.rom_path)
      raise Error, "cannot fork at frame #{at_frame}: run has #{inputs.frames} frames" unless (0..inputs.frames).cover?(at_frame)

      child = self.class.create(root: File.dirname(dir), flow_version: flow_version, budget: manifest['budget'],
                                parent: { 'id' => id, 'frame' => at_frame }, seed: manifest['seed'], rom_path: rom_path,
                                tag: manifest['tag'], model: manifest['model'])
      journal = InputLog.new(File.join(child.dir, 'inputs.log'))
      inputs.each_frame.first(at_frame).each { |buttons| journal.append(buttons) }
      journal.flush
      events = Trace.read(File.join(dir, 'trace.jsonl')).select do |event|
        event['frame'] < at_frame && !%w[stop budget_stop].include?(event['type'])
      end
      rewrite_trace(File.join(child.dir, 'trace.jsonl'), events)
      events.select { |event| event['type'] == 'save' }.each { |event| copy_save(event, File.join(child.dir, 'save')) }
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
      restore_trace!
      path = trace_path
      kept = Trace.read(path).reject do |event|
        event['frame'] > frames || (event['frame'] == frames && decided_at_resume?(event))
      end
      decided = kept.rindex { |event| event['type'] == 'decision' } || -1
      rewrite_trace(path, kept.reject.with_index { |event, index| event['type'] == 'dialogue' && index > decided })
    end

    def truncate_prompts!(frames)
      Dir.glob(File.join(dir, 'prompts', '*')).each do |path|
        File.delete(path) if File.basename(path).to_i >= frames
      end
    end

    def write_activity(fields)
      key = fields.values_at(:kind, :detail)
      return if key == @activity_key

      tmp = File.join(dir, 'activity.json.tmp')
      File.write(tmp, JSON.generate({ started_at: wall_clock, detail: {} }.merge(fields)))
      File.rename(tmp, File.join(dir, 'activity.json'))
      @activity_key = key
    rescue StandardError
      begin
        File.delete(tmp) if tmp
      rescue StandardError
        nil
      end
    end

    def write_manifest
      tmp = File.join(dir, 'manifest.json.tmp')
      File.write(tmp, JSON.pretty_generate(@manifest))
      File.rename(tmp, File.join(dir, 'manifest.json'))
    end

    private

    def decided_at_resume?(event) = %w[perception decision lead goal].include?(event['type']) || (event['type'] == 'notable' && %w[lead_rejected revisit].include?(event['kind']))

    def copy_save(event, into)
      path = File.join(dir, 'save', event['path'])
      return FileUtils.cp(path, into) if File.file?(path)

      require 'koholint/replay'
      ram = Replay.to(self, event['frame']).cartridge_ram
      raise Error, "save #{event['path']} of run #{id} cannot be rebuilt by replay" unless Digest::SHA256.hexdigest(ram) == event['sav_sha256']

      File.binwrite(File.join(into, event['path']), ram)
    end

    def wall_clock = Time.now.to_f

    def rewrite_trace(path, events)
      tmp = "#{path}.tmp"
      File.write(tmp, events.map { |event| "#{JSON.generate(event)}\n" }.join)
      File.rename(tmp, path)
    end
  end
end
