module DecisionAgent
  module ABTesting
    # Tracks individual assignments of users/requests to A/B test variants
    class ABTestAssignment
      attr_reader :id, :ab_test_id, :user_id, :variant, :version_id,
                  :timestamp, :decision_result, :confidence, :context

      # @param ab_test_id [String, Integer] The A/B test ID
      # @param user_id [String, nil] User identifier (optional)
      # @param variant [Symbol] :champion or :challenger
      # @param version_id [String, Integer] The rule version ID that was used
      # @param timestamp [Time] When the assignment occurred
      # @param decision_result [String, nil] The decision outcome
      # @param confidence [Float, nil] Confidence score of the decision
      # @param context [Hash] Additional context for the decision
      # @param id [String, Integer, nil] Optional ID (for persistence)
      def initialize(
        ab_test_id:,
        variant:,
        version_id:,
        user_id: nil,
        timestamp: Time.now.utc,
        decision_result: nil,
        confidence: nil,
        context: {},
        id: nil
      )
        @id = id
        @ab_test_id = ab_test_id
        @user_id = user_id
        @variant = variant
        @version_id = version_id
        @timestamp = timestamp
        @decision_result = decision_result
        @confidence = confidence
        @context = context

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

        unless %i[champion challenger].include?(@variant)
          raise ValidationError, "Variant must be :champion or :challenger, got: #{@variant}"
        end

        if @confidence && (@confidence < 0 || @confidence > 1)
          raise ValidationError, "Confidence must be between 0 and 1, got: #{@confidence}"
        end
      end
    end
  end
end
