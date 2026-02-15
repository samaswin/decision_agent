# frozen_string_literal: true

module DecisionAgent
  # Single evaluation produced by an evaluator: a suggested decision, weight, reason, and optional metadata.
  class Evaluation
    attr_reader :decision, :weight, :reason, :evaluator_name, :metadata

    # @param decision [String, #to_s] The suggested decision value
    # @param weight [Numeric] Importance of this evaluation (0.0 to 1.0)
    # @param reason [String, #to_s] Human-readable reason for the decision
    # @param evaluator_name [String, #to_s] Name of the evaluator that produced this
    # @param metadata [Hash] Optional extra data (e.g. explainability)
    # @raise [InvalidWeightError] when weight is not between 0.0 and 1.0
    def initialize(decision:, weight:, reason:, evaluator_name:, metadata: {})
      validate_weight!(weight)

      @decision = decision.to_s.freeze
      @weight = weight.to_f
      @reason = reason.to_s.freeze
      @evaluator_name = evaluator_name.to_s.freeze
      @metadata = deep_freeze(metadata)

      freeze
    end

    # @return [Hash] Symbol-keyed hash of decision, weight, reason, evaluator_name, metadata
    def to_h
      {
        decision: @decision,
        weight: @weight,
        reason: @reason,
        evaluator_name: @evaluator_name,
        metadata: @metadata
      }
    end

    # @param other [Object] Object to compare
    # @return [Boolean] true if other is an Evaluation with same attributes
    def ==(other)
      other.is_a?(Evaluation) &&
        @decision == other.decision &&
        @weight == other.weight &&
        @reason == other.reason &&
        @evaluator_name == other.evaluator_name &&
        @metadata == other.metadata
    end

    private

    def validate_weight!(weight)
      weight_value = weight.to_f
      raise InvalidWeightError, weight unless weight_value.between?(0.0, 1.0)
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
