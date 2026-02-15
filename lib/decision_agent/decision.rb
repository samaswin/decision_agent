# frozen_string_literal: true

module DecisionAgent
  # Result of {Agent#decide}: the chosen decision, confidence, explanations, and audit data.
  class Decision
    attr_reader :decision, :confidence, :explanations, :evaluations, :audit_payload

    def initialize(decision:, confidence:, explanations:, evaluations:, audit_payload:)
      validate_confidence!(confidence)

      @decision = decision.to_s.freeze
      @confidence = confidence.to_f
      @explanations = Array(explanations).map(&:freeze).freeze
      @evaluations = Array(evaluations).freeze
      @audit_payload = deep_freeze(audit_payload)

      freeze
    end

    # Returns array of condition descriptions that led to this decision
    # @param verbose [Boolean] If true, returns detailed condition information
    # @return [Array<String>] Array of condition descriptions
    def because(verbose: false)
      all_explainability_results.flat_map { |er| er.because(verbose: verbose) }
    end

    # Returns array of condition descriptions that failed
    # @param verbose [Boolean] If true, returns detailed condition information
    # @return [Array<String>] Array of failed condition descriptions
    def failed_conditions(verbose: false)
      all_explainability_results.flat_map { |er| er.failed_conditions(verbose: verbose) }
    end

    # Returns explainability data in machine-readable format
    # @param verbose [Boolean] If true, returns detailed explainability information
    # @return [Hash] Explainability data
    def explainability(verbose: false)
      {
        decision: @decision,
        because: because(verbose: verbose),
        failed_conditions: failed_conditions(verbose: verbose),
        rule_traces: verbose ? all_explainability_results.map { |er| er.to_h(verbose: true) } : nil
      }.compact
    end

    # Returns the decision as a hash (explainability-shaped plus confidence, evaluations, audit).
    #
    # @return [Hash] Symbol-keyed hash with :decision, :because, :failed_conditions, :confidence,
    #   :explanations, :evaluations, :audit_payload, :explainability
    def to_h
      # Structure decision result as explainability by default
      # This makes explainability the primary format for decision results
      explainability_data = explainability(verbose: false)

      {
        # Explainability fields (primary structure)
        decision: explainability_data[:decision],
        because: explainability_data[:because],
        failed_conditions: explainability_data[:failed_conditions],
        # Additional metadata for completeness
        confidence: @confidence,
        explanations: @explanations,
        evaluations: @evaluations.map(&:to_h),
        audit_payload: @audit_payload,
        # Full explainability data (includes rule_traces in verbose mode)
        explainability: explainability_data
      }
    end

    private

    def all_explainability_results
      @evaluations.flat_map { |evaluation| extract_explainability_from_evaluation(evaluation) }
    end

    def extract_explainability_from_evaluation(evaluation)
      return [] unless evaluation.metadata.is_a?(Hash)
      return [] unless evaluation.metadata[:explainability]

      explainability_data = normalize_hash_keys(evaluation.metadata[:explainability])
      rule_traces = reconstruct_rule_traces(explainability_data)
      evaluator_name = explainability_data[:evaluator_name] || evaluation.evaluator_name

      [Explainability::ExplainabilityResult.new(
        evaluator_name: evaluator_name,
        rule_traces: rule_traces
      )]
    end

    def normalize_hash_keys(data)
      return data unless data.is_a?(Hash)

      data.transform_keys(&:to_sym)
    end

    def reconstruct_rule_traces(explainability_data)
      rule_traces_data = explainability_data[:rule_traces] || []
      rule_traces_data.map { |rt_data| reconstruct_rule_trace(rt_data) }
    end

    def reconstruct_rule_trace(rt_data)
      normalized_rt = normalize_hash_keys(rt_data)
      condition_traces = reconstruct_condition_traces(normalized_rt)

      Explainability::RuleTrace.new(
        rule_id: normalized_rt[:rule_id],
        matched: normalized_rt[:matched],
        condition_traces: condition_traces,
        decision: normalized_rt[:decision],
        weight: normalized_rt[:weight],
        reason: normalized_rt[:reason]
      )
    end

    def reconstruct_condition_traces(rule_trace_data)
      condition_traces_data = rule_trace_data[:condition_traces] || []
      condition_traces_data.map { |ct_data| reconstruct_condition_trace(ct_data) }
    end

    def reconstruct_condition_trace(ct_data)
      normalized_ct = normalize_hash_keys(ct_data)

      Explainability::ConditionTrace.new(
        field: normalized_ct[:field],
        operator: normalized_ct[:operator],
        expected_value: normalized_ct[:expected_value],
        actual_value: normalized_ct[:actual_value],
        result: normalized_ct[:result]
      )
    end

    public

    # @param other [Object] Object to compare
    # @return [Boolean] true if other is a Decision with same decision, confidence, explanations, evaluations
    def ==(other)
      other.is_a?(Decision) &&
        @decision == other.decision &&
        (@confidence - other.confidence).abs < 0.0001 &&
        @explanations == other.explanations &&
        @evaluations == other.evaluations
    end

    private

    def validate_confidence!(confidence)
      confidence_value = confidence.to_f
      raise InvalidConfidenceError, confidence unless confidence_value.between?(0.0, 1.0)
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
