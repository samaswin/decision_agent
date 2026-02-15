# frozen_string_literal: true

module DecisionAgent
  # Immutable, thread-safe wrapper around input data passed to evaluators.
  # Data is deep-copied and deep-frozen on construction.
  class Context
    attr_reader :data

    # @param data [Hash, Object] Input data; non-Hash is treated as empty Hash
    def initialize(data)
      data_hash = data.is_a?(Hash) ? data : {}
      @data = if all_frozen?(data_hash)
                data_hash
              else
                deep_freeze(deep_dup(data_hash))
              end
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

    def all_frozen?(obj)
      case obj
      when Hash
        obj.frozen? && obj.each_value.all? { |v| all_frozen?(v) }
      when Array
        obj.frozen? && obj.all? { |v| all_frozen?(v) }
      else
        obj.frozen?
      end
    end

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
