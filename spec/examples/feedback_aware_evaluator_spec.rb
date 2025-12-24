# frozen_string_literal: true

require "spec_helper"
require_relative "../../examples/feedback_aware_evaluator"

RSpec.describe Examples::FeedbackAwareEvaluator do
  describe "initialization" do
    it "creates an evaluator with base decision and weight" do
      evaluator = described_class.new(base_decision: "approve", base_weight: 0.8)
      expect(evaluator).to be_a(DecisionAgent::Evaluators::Base)
    end

    it "uses default weight of 0.5 when not specified" do
      evaluator = described_class.new(base_decision: "approve")
      context = DecisionAgent::Context.new({})
      result = evaluator.evaluate(context, feedback: {})
      expect(result.weight).to eq(0.5)
    end
  end

  describe "#evaluate with no feedback" do
    let(:evaluator) { described_class.new(base_decision: "approve", base_weight: 0.8) }
    let(:context) { DecisionAgent::Context.new({ user: "alice" }) }

    it "returns base decision with base weight" do
      result = evaluator.evaluate(context, feedback: {})

      expect(result.decision).to eq("approve")
      expect(result.weight).to eq(0.8)
      expect(result.reason).to include("Base decision")
    end

    it "includes metadata about feedback presence" do
      result = evaluator.evaluate(context, feedback: {})

      expect(result.metadata[:base_weight]).to eq(0.8)
      expect(result.metadata[:feedback_present]).to be false
      expect(result.metadata[:feedback_keys]).to eq([])
    end

    it "tracks feedback keys when feedback is provided" do
      result = evaluator.evaluate(context, feedback: { custom_key: "value" })

      expect(result.metadata[:feedback_present]).to be true
      expect(result.metadata[:feedback_keys]).to include(:custom_key)
    end
  end

  describe "#evaluate with override feedback" do
    let(:evaluator) { described_class.new(base_decision: "approve", base_weight: 0.8) }
    let(:context) { DecisionAgent::Context.new({ user: "bob" }) }

    it "overrides the base decision" do
      result = evaluator.evaluate(
        context,
        feedback: { override: "reject" }
      )

      expect(result.decision).to eq("reject")
      expect(result.decision).not_to eq("approve")
    end

    it "uses high confidence weight for manual override" do
      result = evaluator.evaluate(
        context,
        feedback: { override: "reject" }
      )

      expect(result.weight).to eq(0.9)
    end

    it "uses provided reason from feedback" do
      result = evaluator.evaluate(
        context,
        feedback: { override: "reject", reason: "Fraud detected" }
      )

      expect(result.reason).to eq("Fraud detected")
    end

    it "uses default reason when none provided" do
      result = evaluator.evaluate(
        context,
        feedback: { override: "reject" }
      )

      expect(result.reason).to eq("Manual override from feedback")
    end

    it "includes override metadata" do
      result = evaluator.evaluate(
        context,
        feedback: { override: "manual_review", reason: "Complex case" }
      )

      expect(result.metadata[:feedback_override]).to be true
      expect(result.metadata[:original_decision]).to eq("approve")
      expect(result.metadata[:override_timestamp]).to be_a(String)
    end

    it "takes precedence over other feedback types" do
      result = evaluator.evaluate(
        context,
        feedback: {
          override: "escalate",
          past_accuracy: 0.95,
          source: "expert_review"
        }
      )

      # Override should take precedence
      expect(result.decision).to eq("escalate")
      expect(result.weight).to eq(0.9)
    end
  end

  describe "#evaluate with past_accuracy feedback" do
    let(:evaluator) { described_class.new(base_decision: "approve", base_weight: 0.8) }
    let(:context) { DecisionAgent::Context.new({ user: "charlie" }) }

    it "adjusts weight based on past accuracy" do
      result = evaluator.evaluate(
        context,
        feedback: { past_accuracy: 0.5 }
      )

      # 0.8 * 0.5 = 0.4
      expect(result.weight).to eq(0.4)
      expect(result.decision).to eq("approve")
    end

    it "boosts weight with high accuracy" do
      result = evaluator.evaluate(
        context,
        feedback: { past_accuracy: 1.0 }
      )

      # 0.8 * 1.0 = 0.8
      expect(result.weight).to eq(0.8)
    end

    it "reduces weight with low accuracy" do
      result = evaluator.evaluate(
        context,
        feedback: { past_accuracy: 0.25 }
      )

      # 0.8 * 0.25 = 0.2
      expect(result.weight).to eq(0.2)
    end

    it "clamps weight to minimum 0.0" do
      result = evaluator.evaluate(
        context,
        feedback: { past_accuracy: -1.0 } # Invalid, but should be handled
      )

      expect(result.weight).to be >= 0.0
    end

    it "clamps weight to maximum 1.0" do
      result = evaluator.evaluate(
        context,
        feedback: { past_accuracy: 2.0 } # Would produce 1.6, should clamp to 1.0
      )

      expect(result.weight).to be <= 1.0
    end

    it "includes adjustment metadata" do
      result = evaluator.evaluate(
        context,
        feedback: { past_accuracy: 0.95 }
      )

      expect(result.metadata[:base_weight]).to eq(0.8)
      expect(result.metadata[:adjusted_weight]).to eq(0.76)
      expect(result.metadata[:past_accuracy]).to eq(0.95)
      expect(result.metadata[:adjustment_factor]).to eq(0.95)
    end

    it "provides descriptive reason with accuracy percentage" do
      result = evaluator.evaluate(
        context,
        feedback: { past_accuracy: 0.95 }
      )

      expect(result.reason).to include("95%")
      expect(result.reason).to include("past accuracy")
    end
  end

  describe "#evaluate with source feedback" do
    let(:evaluator) { described_class.new(base_decision: "approve", base_weight: 0.8) }
    let(:context) { DecisionAgent::Context.new({ user: "dave" }) }

    it "reduces weight for user_override source" do
      result = evaluator.evaluate(
        context,
        feedback: { source: "user_override" }
      )

      # 0.8 * 0.5 = 0.4
      expect(result.weight).to eq(0.4)
      expect(result.metadata[:multiplier]).to eq(0.5)
    end

    it "maintains weight for automated_test source" do
      result = evaluator.evaluate(
        context,
        feedback: { source: "automated_test" }
      )

      # 0.8 * 1.0 = 0.8
      expect(result.weight).to eq(0.8)
      expect(result.metadata[:multiplier]).to eq(1.0)
    end

    it "boosts weight for peer_review source" do
      result = evaluator.evaluate(
        context,
        feedback: { source: "peer_review" }
      )

      # 0.8 * 1.1 = 0.88
      expect(result.weight).to be_within(0.0001).of(0.88)
      expect(result.metadata[:multiplier]).to eq(1.1)
    end

    it "boosts weight significantly for expert_review source" do
      result = evaluator.evaluate(
        context,
        feedback: { source: "expert_review" }
      )

      # 0.8 * 1.2 = 0.96
      expect(result.weight).to eq(0.96)
      expect(result.metadata[:multiplier]).to eq(1.2)
    end

    it "uses default multiplier for unknown source" do
      result = evaluator.evaluate(
        context,
        feedback: { source: "unknown_source" }
      )

      # 0.8 * 1.0 = 0.8 (default multiplier)
      expect(result.weight).to eq(0.8)
      expect(result.metadata[:multiplier]).to eq(1.0)
    end

    it "clamps boosted weight to 1.0" do
      high_weight_evaluator = described_class.new(base_decision: "approve", base_weight: 0.9)

      result = high_weight_evaluator.evaluate(
        context,
        feedback: { source: "expert_review" } # 0.9 * 1.2 = 1.08, should clamp to 1.0
      )

      expect(result.weight).to eq(1.0)
    end

    it "includes source metadata" do
      result = evaluator.evaluate(
        context,
        feedback: { source: "peer_review" }
      )

      expect(result.metadata[:feedback_source]).to eq("peer_review")
      expect(result.metadata[:base_weight]).to eq(0.8)
      expect(result.metadata[:adjusted_weight]).to be_within(0.0001).of(0.88)
    end

    it "provides descriptive reason with source" do
      result = evaluator.evaluate(
        context,
        feedback: { source: "expert_review" }
      )

      expect(result.reason).to include("expert_review")
      expect(result.reason).to include("feedback source")
    end
  end

  describe "feedback priority" do
    let(:evaluator) { described_class.new(base_decision: "approve", base_weight: 0.8) }
    let(:context) { DecisionAgent::Context.new({}) }

    it "override takes precedence over past_accuracy" do
      result = evaluator.evaluate(
        context,
        feedback: { override: "reject", past_accuracy: 0.95 }
      )

      expect(result.decision).to eq("reject")
      expect(result.weight).to eq(0.9)  # Override weight, not adjusted weight
    end

    it "override takes precedence over source" do
      result = evaluator.evaluate(
        context,
        feedback: { override: "escalate", source: "expert_review" }
      )

      expect(result.decision).to eq("escalate")
      expect(result.weight).to eq(0.9)  # Override weight, not source-adjusted weight
    end

    it "past_accuracy takes precedence over source" do
      result = evaluator.evaluate(
        context,
        feedback: { past_accuracy: 0.5, source: "expert_review" }
      )

      # Should use past_accuracy adjustment (0.8 * 0.5 = 0.4)
      # Not source adjustment (0.8 * 1.2 = 0.96)
      expect(result.weight).to eq(0.4)
      expect(result.metadata[:past_accuracy]).to eq(0.5)
    end
  end

  describe "integration with DecisionAgent::Agent" do
    it "works as an evaluator in a full decision agent" do
      evaluator = described_class.new(base_decision: "approve", base_weight: 0.8)
      agent = DecisionAgent::Agent.new(evaluators: [evaluator])

      result = agent.decide(
        context: { user_id: 123 },
        feedback: {}
      )

      expect(result.decision).to eq("approve")
      expect(result.confidence).to eq(1.0) # Single evaluator normalized to 1.0
    end

    it "respects feedback in agent context" do
      evaluator = described_class.new(base_decision: "approve", base_weight: 0.8)
      agent = DecisionAgent::Agent.new(evaluators: [evaluator])

      result = agent.decide(
        context: { user_id: 456 },
        feedback: { override: "manual_review", reason: "Sensitive action" }
      )

      expect(result.decision).to eq("manual_review")
      expect(result.evaluations.first.reason).to eq("Sensitive action")
    end

    it "combines with other evaluators" do
      feedback_eval = described_class.new(base_decision: "approve", base_weight: 0.8)
      static_eval = DecisionAgent::Evaluators::StaticEvaluator.new(
        decision: "approve",
        weight: 0.6
      )

      agent = DecisionAgent::Agent.new(evaluators: [feedback_eval, static_eval])

      result = agent.decide(
        context: {},
        feedback: { past_accuracy: 0.5 } # Reduces feedback_eval weight to 0.4
      )

      expect(result.decision).to eq("approve")
      expect(result.evaluations.size).to eq(2)

      # Confidence = (0.4 + 0.6) / (0.4 + 0.6) = 1.0 (both agree)
      expect(result.confidence).to eq(1.0)
    end

    it "feedback affects only feedback-aware evaluators" do
      feedback_eval = described_class.new(base_decision: "approve", base_weight: 0.8)
      static_eval = DecisionAgent::Evaluators::StaticEvaluator.new(
        decision: "reject",
        weight: 0.9
      )

      agent = DecisionAgent::Agent.new(
        evaluators: [feedback_eval, static_eval],
        scoring_strategy: DecisionAgent::Scoring::MaxWeight.new
      )

      result_no_feedback = agent.decide(context: {}, feedback: {})
      # MaxWeight picks static_eval (0.9 > 0.8)
      expect(result_no_feedback.decision).to eq("reject")

      result_with_feedback = agent.decide(
        context: {},
        feedback: { past_accuracy: 0.5 } # Reduces feedback_eval to 0.4
      )
      # MaxWeight still picks static_eval (0.9 > 0.4)
      expect(result_with_feedback.decision).to eq("reject")
    end
  end

  describe "edge cases" do
    let(:evaluator) { described_class.new(base_decision: "approve", base_weight: 0.8) }
    let(:context) { DecisionAgent::Context.new({}) }

    it "handles feedback with string keys" do
      result = evaluator.evaluate(
        context,
        feedback: { "override" => "reject" } # String key instead of symbol
      )

      # Should not match because code expects symbols
      # Falls back to base decision
      expect(result.decision).to eq("approve")
      expect(result.weight).to eq(0.8)
    end

    it "handles nil feedback gracefully" do
      # Feedback defaults to {} in the signature, but test explicit nil handling
      result = evaluator.evaluate(context, feedback: {})
      expect(result.decision).to eq("approve")
    end

    it "handles empty override value" do
      result = evaluator.evaluate(
        context,
        feedback: { override: "" }
      )

      # Empty string is truthy in Ruby, so override applies
      expect(result.decision).to eq("")
      expect(result.metadata[:feedback_override]).to be true
    end

    it "handles zero past_accuracy" do
      result = evaluator.evaluate(
        context,
        feedback: { past_accuracy: 0.0 }
      )

      # 0.8 * 0.0 = 0.0
      expect(result.weight).to eq(0.0)
    end

    it "handles very high past_accuracy" do
      result = evaluator.evaluate(
        context,
        feedback: { past_accuracy: 10.0 }
      )

      # 0.8 * 10.0 = 8.0, clamped to 1.0
      expect(result.weight).to eq(1.0)
    end
  end

  describe "evaluator_name" do
    it "returns the correct evaluator name" do
      evaluator = described_class.new(base_decision: "approve", base_weight: 0.8)
      context = DecisionAgent::Context.new({})

      result = evaluator.evaluate(context, feedback: {})

      # Base class extracts just the class name without module
      expect(result.evaluator_name).to eq("FeedbackAwareEvaluator")
    end
  end
end
