module DecisionAgent
  module ABTesting
    # Tracks individual assignments of users/requests to A/B test variants
    class ABTestAssignment
      attr_reader :id, :ab_test_id, :user_id, :variant, :version_id,
                  :timestamp, :decision_result, :confidence, :context

      # @param ab_test_id [String, Integer] The A/B test ID
      # @param variant [Symbol] :champion or :challenger
      # @param version_id [String, Integer] The rule version ID that was used
      # @param options [Hash] Optional configuration
      # @option options [String] :user_id User identifier (optional)
      # @option options [Time] :timestamp When the assignment occurred
      # @option options [String] :decision_result The decision outcome
      # @option options [Float] :confidence Confidence score of the decision
      # @option options [Hash] :context Additional context for the decision
      # @option options [String, Integer] :id Optional ID (for persistence)
      def initialize(
        ab_test_id:,
        variant:,
        version_id:,
        **options
      )
        @id = options[:id]
        @ab_test_id = ab_test_id
        @user_id = options[:user_id]
        @variant = variant
        @version_id = version_id
        @timestamp = options[:timestamp] || Time.now.utc
        @decision_result = options[:decision_result]
        @confidence = options[:confidence]
        @context = options[:context] || {}

        validate!
      end

      # Update the assignment with decision results
      # @param decision [String] The decision result
      # @param confidence [Float] The confidence score
      def record_decision(decision, confidence)
        @decision_result = decision
        @confidence = confidence
      end

      # Convert to hash representation
      # @return [Hash]
      def to_h
        {
          id: @id,
          ab_test_id: @ab_test_id,
          user_id: @user_id,
          variant: @variant,
          version_id: @version_id,
          timestamp: @timestamp,
          decision_result: @decision_result,
          confidence: @confidence,
          context: @context
        }
      end

      private

      def validate!
        raise ValidationError, "AB test ID is required" if @ab_test_id.nil?
        raise ValidationError, "Variant is required" if @variant.nil?
        raise ValidationError, "Version ID is required" if @version_id.nil?

        raise ValidationError, "Variant must be :champion or :challenger, got: #{@variant}" unless %i[champion challenger].include?(@variant)

        return unless @confidence && (@confidence.negative? || @confidence > 1)

        raise ValidationError, "Confidence must be between 0 and 1, got: #{@confidence}"
      end
    end
  end
end
