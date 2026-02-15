# frozen_string_literal: true

require "spec_helper"

RSpec.describe DecisionAgent::Evaluators::StaticEvaluator do
  describe "#initialize" do
    it "sets decision and default attributes" do
      evaluator = described_class.new(decision: "approve")

      expect(evaluator.decision).to eq("approve")
      expect(evaluator.weight).to eq(1.0)
      expect(evaluator.reason).to eq("Static decision")
      expect(evaluator.name).to eq("StaticEvaluator")
      expect(evaluator.custom_metadata).to be_nil
    end

    it "accepts custom weight, reason, name, and metadata" do
      evaluator = described_class.new(
        decision: "reject",
        weight: 0.7,
        reason: "Custom reason",
        name: "MyEvaluator",
        metadata: { source: "test" }
      )

      expect(evaluator.decision).to eq("reject")
      expect(evaluator.weight).to eq(0.7)
      expect(evaluator.reason).to eq("Custom reason")
      expect(evaluator.name).to eq("MyEvaluator")
      expect(evaluator.custom_metadata).to eq({ source: "test" })
    end

    it "converts weight to float" do
      evaluator = described_class.new(decision: "approve", weight: "0.5")

      expect(evaluator.weight).to eq(0.5)
    end
  end

  describe "#evaluate" do
    let(:evaluator) { described_class.new(decision: "approve", weight: 0.9, reason: "Always approve") }

    it "returns an Evaluation with the static decision" do
      result = evaluator.evaluate({})

      expect(result).to be_a(DecisionAgent::Evaluation)
      expect(result.decision).to eq("approve")
      expect(result.weight).to eq(0.9)
      expect(result.reason).to eq("Always approve")
      expect(result.evaluator_name).to eq("StaticEvaluator")
    end

    it "ignores context entirely" do
      result1 = evaluator.evaluate({ user: "alice" })
      result2 = evaluator.evaluate({ user: "bob", amount: 1000 })

      expect(result1.decision).to eq(result2.decision)
      expect(result1.weight).to eq(result2.weight)
    end

    it "ignores feedback" do
      result = evaluator.evaluate({}, feedback: { override: true })

      expect(result.decision).to eq("approve")
    end

    it "uses default metadata when custom_metadata is nil" do
      result = evaluator.evaluate({})

      expect(result.metadata).to eq({ type: "static" })
    end

    it "uses custom metadata when provided" do
      evaluator = described_class.new(
        decision: "reject",
        metadata: { source: "manual", priority: "high" }
      )

      result = evaluator.evaluate({})

      expect(result.metadata).to eq({ source: "manual", priority: "high" })
    end
  end
end
