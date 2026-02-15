# frozen_string_literal: true

require "spec_helper"
require "decision_agent"
require "decision_agent/dmn/model"
require "decision_agent/evaluators/dmn_evaluator"

RSpec.describe DecisionAgent::Evaluators::DmnEvaluator do
  def build_model(hit_policy: "FIRST", rules: [])
    model = DecisionAgent::Dmn::Model.new(id: "test_model", name: "Test Model")
    decision = DecisionAgent::Dmn::Decision.new(id: "decision_1", name: "Test Decision")

    table = DecisionAgent::Dmn::DecisionTable.new(id: "dt1", hit_policy: hit_policy)
    table.add_input(DecisionAgent::Dmn::Input.new(id: "i1", label: "age"))
    table.add_output(DecisionAgent::Dmn::Output.new(id: "o1", label: "risk", name: "decision"))

    rules.each do |rule_def|
      rule = DecisionAgent::Dmn::Rule.new(id: rule_def[:id])
      rule.add_input_entry(rule_def[:input])
      rule.add_output_entry(rule_def[:output])
      table.add_rule(rule)
    end

    decision.decision_table = table
    model.add_decision(decision)
    model
  end

  describe "#initialize" do
    it "creates an evaluator with a valid model and decision_id" do
      model = build_model(rules: [{ id: "r1", input: ">= 18", output: "low" }])

      evaluator = described_class.new(model: model, decision_id: "decision_1")

      expect(evaluator.model).not_to be_nil
      expect(evaluator.decision_id).to eq("decision_1")
    end

    it "raises InvalidDmnModelError for unknown decision_id" do
      model = build_model(rules: [{ id: "r1", input: ">= 18", output: "low" }])

      expect do
        described_class.new(model: model, decision_id: "nonexistent")
      end.to raise_error(DecisionAgent::Dmn::InvalidDmnModelError, /not found/)
    end

    it "raises InvalidDmnModelError when decision has no table" do
      model = DecisionAgent::Dmn::Model.new(id: "m1", name: "M1")
      decision = DecisionAgent::Dmn::Decision.new(id: "d1", name: "D1")
      model.add_decision(decision)

      expect do
        described_class.new(model: model, decision_id: "d1")
      end.to raise_error(DecisionAgent::Dmn::InvalidDmnModelError, /no decision table/)
    end

    it "accepts a custom name" do
      model = build_model(rules: [{ id: "r1", input: ">= 18", output: "low" }])

      evaluator = described_class.new(model: model, decision_id: "decision_1", name: "CustomEval")

      result = evaluator.evaluate({ "age" => 25 })
      expect(result.evaluator_name).to eq("CustomEval")
    end
  end

  describe "#evaluate" do
    describe "FIRST hit policy" do
      let(:first_rules) do
        [
          { id: "r1", input: "< 18", output: "reject" },
          { id: "r2", input: ">= 18", output: "approve" }
        ]
      end
      let(:model) { build_model(hit_policy: "FIRST", rules: first_rules) }
      let(:evaluator) { described_class.new(model: model, decision_id: "decision_1") }

      it "returns the first matching rule" do
        result = evaluator.evaluate({ "age" => 25 })

        expect(result).to be_a(DecisionAgent::Evaluation)
        expect(result.decision).to eq("approve")
      end

      it "returns nil when no rules match" do
        result = evaluator.evaluate({ "other_field" => "value" })

        expect(result).to be_nil
      end

      it "includes explainability metadata" do
        result = evaluator.evaluate({ "age" => 25 })

        expect(result.metadata).to have_key(:explainability)
        expect(result.metadata[:hit_policy]).to eq("FIRST")
      end
    end

    describe "UNIQUE hit policy" do
      let(:unique_rules) do
        [
          { id: "r1", input: "< 18", output: "minor" },
          { id: "r2", input: ">= 65", output: "senior" }
        ]
      end
      let(:model) { build_model(hit_policy: "UNIQUE", rules: unique_rules) }
      let(:evaluator) { described_class.new(model: model, decision_id: "decision_1") }

      it "returns the single matching rule" do
        result = evaluator.evaluate({ "age" => 10 })

        expect(result.decision).to eq("minor")
      end

      it "raises error when no rules match" do
        expect do
          evaluator.evaluate({ "age" => 30 })
        end.to raise_error(DecisionAgent::Dmn::InvalidDmnModelError, /none matched/)
      end
    end

    describe "ANY hit policy" do
      let(:any_rules) do
        [
          { id: "r1", input: "> 0", output: "positive" },
          { id: "r2", input: ">= 1", output: "positive" }
        ]
      end
      let(:model) { build_model(hit_policy: "ANY", rules: any_rules) }
      let(:evaluator) { described_class.new(model: model, decision_id: "decision_1") }

      it "returns result when all matching rules have same output" do
        result = evaluator.evaluate({ "age" => 5 })

        expect(result.decision).to eq("positive")
      end
    end

    describe "COLLECT hit policy" do
      let(:collect_rules) do
        [
          { id: "r1", input: "> 0", output: "rule_a" },
          { id: "r2", input: "> 5", output: "rule_b" }
        ]
      end
      let(:model) { build_model(hit_policy: "COLLECT", rules: collect_rules) }
      let(:evaluator) { described_class.new(model: model, decision_id: "decision_1") }

      it "returns result with collect metadata" do
        result = evaluator.evaluate({ "age" => 10 })

        expect(result.metadata[:collect_count]).to eq(2)
        expect(result.metadata[:collect_decisions]).to eq(%w[rule_a rule_b])
      end
    end
  end
end
