require 'json'
require 'koholint'

module Koholint
  module Addresses
    class Invalid < Error; end

    DEFAULT_PATH = File.expand_path('../../data/addresses.json', __dir__)
    CONFIDENCES = %w[hypothesis verified].freeze

    module_function

    def load(path = DEFAULT_PATH)
      JSON.parse(File.read(path)).to_h do |entry|
        validate!(entry)
        [entry.fetch('name').to_sym, Integer(entry.fetch('addr'))]
      end
    end

    def validate!(entry)
      %w[name addr source confidence verified_count].each do |key|
        raise Invalid, "#{entry['name'] || entry.inspect}: missing #{key}" unless entry.key?(key)
      end
      raise Invalid, "#{entry['name']}: unknown confidence #{entry['confidence']}" unless CONFIDENCES.include?(entry['confidence'])
      return unless entry['confidence'] == 'verified' && entry['verified_count'] < 2

      raise Invalid, "#{entry['name']}: verified needs verified_count >= 2"
    end
  end
end
