module DecisionAgent
  module ABTesting
    # Agent wrapper that adds A/B testing capabilities to the standard Agent
    # Automatically handles variant assignment and decision tracking
    class ABTestingAgent
      attr_reader :ab_test_manager, :version_manager

      # @param ab_test_manager [ABTestManager] The A/B test manager
      # @param version_manager [Versioning::VersionManager] Version manager for rules
      # @param evaluators [Array] Base evaluators (can be overridden by versioned rules)
      # @param scoring_strategy [Scoring::Base] Scoring strategy
      # @param audit_adapter [Audit::Adapter] Audit adapter
      def initialize(
        ab_test_manager:,
        version_manager: nil,
        evaluators: [],
        scoring_strategy: nil,
        audit_adapter: nil
      )
        @ab_test_manager = ab_test_manager
        @version_manager = version_manager || ab_test_manager.version_manager
        @base_evaluators = evaluators
        @scoring_strategy = scoring_strategy
        @audit_adapter = audit_adapter
      end

      # Make a decision with A/B testing support
      # @param context [Hash, Context] The decision context
      # @param feedback [Hash] Optional feedback
      # @param ab_test_id [String, Integer, nil] Optional A/B test ID
      # @param user_id [String, nil] Optional user ID for consistent assignment
      # @return [Hash] Decision result with A/B test metadata
      def decide(context:, feedback: {}, ab_test_id: nil, user_id: nil)
        ctx = context.is_a?(Context) ? context : Context.new(context)

        # If A/B test is specified, use variant assignment
        if ab_test_id
          decide_with_ab_test(ctx, feedback, ab_test_id, user_id)
        else
          # Standard decision without A/B testing
          agent = build_agent(@base_evaluators)
          decision = agent.decide(context: ctx, feedback: feedback)

          {
            decision: decision.decision,
            confidence: decision.confidence,
            explanations: decision.explanations,
            evaluations: decision.evaluations,
            ab_test: nil
          }
        end
      end

      # Get A/B test results
      # @param test_id [String, Integer] The test ID
      # @return [Hash] Test results and statistics
      def get_test_results(test_id)
        @ab_test_manager.get_results(test_id)
      end

      # List active A/B tests
      # @return [Array<ABTest>] Active tests
      def active_tests
        @ab_test_manager.active_tests
      end

      private

      def decide_with_ab_test(context, feedback, ab_test_id, user_id)
        # Assign variant
        assignment = @ab_test_manager.assign_variant(test_id: ab_test_id, user_id: user_id)

        # Get the version for the assigned variant
        version = @version_manager.get_version(version_id: assignment[:version_id])
        raise VersionNotFoundError, "Version not found: #{assignment[:version_id]}" unless version

        # Build evaluators from the versioned rule content
        evaluators = build_evaluators_from_version(version)

        # Create agent with version-specific evaluators
        agent = build_agent(evaluators)

        # Make decision
        decision = agent.decide(context: context, feedback: feedback)

        # Record the decision result
        @ab_test_manager.record_decision(
          assignment_id: assignment[:assignment_id],
          decision: decision.decision,
          confidence: decision.confidence
        )

        # Return decision with A/B test metadata
        {
          decision: decision.decision,
          confidence: decision.confidence,
          explanations: decision.explanations,
          evaluations: decision.evaluations,
          ab_test: {
            test_id: ab_test_id,
            variant: assignment[:variant],
            version_id: assignment[:version_id],
            assignment_id: assignment[:assignment_id]
          }
        }
      end

      def build_agent(evaluators)
        Agent.new(
          evaluators: evaluators.empty? ? @base_evaluators : evaluators,
          scoring_strategy: @scoring_strategy,
          audit_adapter: @audit_adapter
        )
      end

      def build_evaluators_from_version(version)
        content = version[:content]

        # If the version content contains evaluator configurations, build them
        # Otherwise, use base evaluators
        if content.is_a?(Hash) && content[:evaluators]
          content[:evaluators].map do |eval_config|
            build_evaluator_from_config(eval_config)
          end
        elsif content.is_a?(Hash) && content[:rules]
          # Build a JsonRuleEvaluator from the full content (ruleset + rules)
          [Evaluators::JsonRuleEvaluator.new(rules_json: content)]
        else
          # Fallback to base evaluators
          @base_evaluators
        end
      end

      def build_evaluator_from_config(config)
        case config[:type]
        when "json_rule"
          Evaluators::JsonRuleEvaluator.new(
            rules_json: config[:rules]
          )
        when "static"
          Evaluators::StaticEvaluator.new(
            decision: config[:decision],
            weight: config[:weight] || 1.0,
            reason: config[:reason]
          )
        else
          raise "Unknown evaluator type: #{config[:type]}"
        end
      end
    end
  end
end
