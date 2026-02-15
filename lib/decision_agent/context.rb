# frozen_string_literal: true

module DecisionAgent
  # Immutable, thread-safe wrapper around input data passed to evaluators.
  # Data is deep-copied and deep-frozen on construction.
  class Context
    attr_reader :data

    # @param data [Hash, Object] Input data; non-Hash is treated as empty Hash
    def initialize(data)
      # Create a deep copy before freezing to avoid mutating the original
      # This is necessary for thread-safety even if it adds some overhead
      data_hash = data.is_a?(Hash) ? data : {}
      @data = deep_freeze(deep_dup(data_hash))
    end

    # @param key [Object] Key to look up
    # @return [Object, nil] Value for key, or nil if missing
    def [](key)
      @data[key]
    end

    # @param key [Object] Key to look up
    # @param default [Object] Value returned when key is missing (default: nil)
    # @return [Object] Value for key, or default
    def fetch(key, default = nil)
      @data.fetch(key, default)
    end

    # @param key [Object] Key to check
    # @return [Boolean] Whether the key exists
    def key?(key)
      @data.key?(key)
    end

    # @return [Hash] The underlying frozen data hash
    def to_h
      @data
    end

    def ==(other)
      other.is_a?(Context) && @data == other.data
    end

    private

    def deep_dup(obj)
      case obj
      when Hash
        obj.transform_values { |v| deep_dup(v) }
      when Array
        obj.map { |v| deep_dup(v) }
      else
        obj
      end
    end

    def deep_freeze(obj)
      return obj if obj.frozen?

      case obj
      when Hash
        obj.each_value { |v| deep_freeze(v) }
        obj.freeze
      when Array
        obj.each { |v| deep_freeze(v) }
        obj.freeze
      when String, Symbol, Numeric, TrueClass, FalseClass, NilClass
        obj.freeze
      else
        obj.freeze if obj.respond_to?(:freeze)
      end
      obj
    end
  end
end
