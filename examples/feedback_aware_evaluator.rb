# frozen_string_literal: true

require_relative "../lib/decision_agent"

module Examples
  # Example evaluator that uses feedback to adjust decisions
  #
  # Use case: Human-in-the-loop system where feedback indicates
  # when the automated decision was incorrect or needs adjustment.
  #
  # This demonstrates how custom evaluators can leverage the feedback
  # parameter to create adaptive decision systems while keeping the
  # core decision agent deterministic.
  #
  # Example usage:
  #   evaluator = Examples::FeedbackAwareEvaluator.new(
  #     base_decision: "approve",
  #     base_weight: 0.8
  #   )
  #
  #   # First decision (no feedback)
  #   result = evaluator.evaluate(context, feedback: {})
  #   # => Evaluation(decision: "approve", weight: 0.8)
  #
  #   # Subsequent decision with override feedback
  #   result = evaluator.evaluate(
  #     context,
  #     feedback: { override: "reject", reason: "Manual review required" }
  #   )
  #   # => Evaluation(decision: "reject", weight: 0.9)
  #
  #   # Decision with confidence adjustment based on past accuracy
  #   result = evaluator.evaluate(
  #     context,
  #     feedback: { past_accuracy: 0.95 }  # Boost confidence
  #   )
  #   # => Evaluation(decision: "approve", weight: 0.76)
  #
  class FeedbackAwareEvaluator < DecisionAgent::Evaluators::Base
    def initialize(base_decision:, base_weight: 0.5)
      @base_decision = base_decision
      @base_weight = base_weight
    end

    def evaluate(context, feedback: {})
      # Priority 1: Check for explicit override in feedback
      if feedback[:override]
        return override_decision(feedback)
      end

      # Priority 2: Check for confidence adjustment based on historical performance
      if feedback[:past_accuracy]
        return adjusted_decision(feedback)
      end

      # Priority 3: Check for source-based weight adjustment
      if feedback[:source]
        return source_adjusted_decision(feedback)
      end

      # Default: Return base decision with no adjustments
      base_decision(feedback)
    end

    private

    def override_decision(feedback)
      DecisionAgent::Evaluation.new(
        decision: feedback[:override],
        weight: 0.9, # High confidence for manual override
        reason: feedback[:reason] || "Manual override from feedback",
        evaluator_name: evaluator_name,
        metadata: {
          feedback_override: true,
          original_decision: @base_decision,
          override_timestamp: Time.now.utc.strftime("%Y-%m-%dT%H:%M:%S.%6NZ")
        }
      )
    end

    def adjusted_decision(feedback)
      # Adjust weight based on past accuracy (0.0 - 1.0)
      accuracy = feedback[:past_accuracy].to_f
      adjusted_weight = @base_weight * accuracy

      # Clamp to valid range
      adjusted_weight = [[adjusted_weight, 0.0].max, 1.0].min

      DecisionAgent::Evaluation.new(
        decision: @base_decision,
        weight: adjusted_weight,
        reason: "Base decision with #{(accuracy * 100).round}% past accuracy adjustment",
        evaluator_name: evaluator_name,
        metadata: {
          base_weight: @base_weight,
          adjusted_weight: adjusted_weight,
          past_accuracy: accuracy,
          adjustment_factor: accuracy
        }
      )
    end

    def source_adjusted_decision(feedback)
      # Adjust weight based on feedback source
      weight_adjustments = {
        "user_override" => 0.5,      # Reduce confidence when user manually overrode
        "automated_test" => 1.0,     # No adjustment for automated tests
        "peer_review" => 1.1,        # Slight boost for peer-reviewed decisions
        "expert_review" => 1.2       # Higher boost for expert review
      }

      source = feedback[:source].to_s
      multiplier = weight_adjustments[source] || 1.0
      adjusted_weight = @base_weight * multiplier

      # Clamp to valid range
      adjusted_weight = [[adjusted_weight, 0.0].max, 1.0].min

      DecisionAgent::Evaluation.new(
        decision: @base_decision,
        weight: adjusted_weight,
        reason: "Base decision adjusted by feedback source: #{source}",
        evaluator_name: evaluator_name,
        metadata: {
          base_weight: @base_weight,
          adjusted_weight: adjusted_weight,
          feedback_source: source,
          multiplier: multiplier
        }
      )
    end

    def base_decision(feedback)
      DecisionAgent::Evaluation.new(
        decision: @base_decision,
        weight: @base_weight,
        reason: "Base decision (no feedback adjustments)",
        evaluator_name: evaluator_name,
        metadata: {
          base_weight: @base_weight,
          feedback_present: !feedback.empty?,
          feedback_keys: feedback.keys
        }
      )
    end
  end
end

# Demonstration
if __FILE__ == $PROGRAM_NAME
  puts "=" * 60
  puts "Feedback-Aware Evaluator Example"
  puts "=" * 60
  puts

  # Create a feedback-aware evaluator
  evaluator = Examples::FeedbackAwareEvaluator.new(
    base_decision: "approve",
    base_weight: 0.8
  )

  context = DecisionAgent::Context.new({ user_id: 123, action: "submit" })

  # Example 1: No feedback (base behavior)
  puts "Example 1: No Feedback"
  result = evaluator.evaluate(context, feedback: {})
  puts "  Decision: #{result.decision}"
  puts "  Weight: #{result.weight}"
  puts "  Reason: #{result.reason}"
  puts

  # Example 2: Manual override
  puts "Example 2: Manual Override via Feedback"
  result = evaluator.evaluate(
    context,
    feedback: { override: "reject", reason: "Fraud detected manually" }
  )
  puts "  Decision: #{result.decision}"
  puts "  Weight: #{result.weight}"
  puts "  Reason: #{result.reason}"
  puts "  Metadata: #{result.metadata.inspect}"
  puts

  # Example 3: Past accuracy adjustment
  puts "Example 3: Confidence Adjustment Based on Past Accuracy"
  result = evaluator.evaluate(
    context,
    feedback: { past_accuracy: 0.95 }
  )
  puts "  Decision: #{result.decision}"
  puts "  Weight: #{result.weight} (adjusted from 0.8 by 95% accuracy)"
  puts "  Reason: #{result.reason}"
  puts

  # Example 4: Source-based adjustment
  puts "Example 4: Source-Based Weight Adjustment"
  result = evaluator.evaluate(
    context,
    feedback: { source: "expert_review" }
  )
  puts "  Decision: #{result.decision}"
  puts "  Weight: #{result.weight} (boosted by expert review)"
  puts "  Reason: #{result.reason}"
  puts

  # Example 5: Using in an agent
  puts "Example 5: Using in a Full Agent"
  agent = DecisionAgent::Agent.new(evaluators: [evaluator])

  decision_result = agent.decide(
    context: { user_id: 456, action: "delete" },
    feedback: { override: "manual_review", reason: "Sensitive operation" }
  )

  puts "  Final Decision: #{decision_result.decision}"
  puts "  Confidence: #{decision_result.confidence}"
  puts "  Explanations:"
  decision_result.explanations.each { |exp| puts "    - #{exp}" }
  puts

  puts "=" * 60
  puts "Note: Built-in evaluators (JsonRuleEvaluator, StaticEvaluator)"
  puts "      ignore feedback to maintain determinism. Custom evaluators"
  puts "      like this one can use feedback for adaptive behavior."
  puts "=" * 60
end
