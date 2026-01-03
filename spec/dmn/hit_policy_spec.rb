require "spec_helper"
require "decision_agent"
require "decision_agent/dmn/model"
require "decision_agent/evaluators/dmn_evaluator"

RSpec.describe "DMN Hit Policies" do
  let(:model) { DecisionAgent::Dmn::Model.new(id: "test_model", name: "Test Model") }

  def create_decision_table(hit_policy, rules_data)
    table = DecisionAgent::Dmn::DecisionTable.new(id: "test_table", hit_policy: hit_policy)

    # Add inputs
    table.add_input(DecisionAgent::Dmn::Input.new(id: "input1", label: "value"))
    table.add_output(DecisionAgent::Dmn::Output.new(id: "output1", label: "decision", name: "decision"))

    # Add rules
    rules_data.each do |rule_data|
      rule = DecisionAgent::Dmn::Rule.new(id: rule_data[:id], description: rule_data[:description])
      rule.add_input_entry(rule_data[:input])
      rule.add_output_entry(rule_data[:output])
      table.add_rule(rule)
    end

    decision = DecisionAgent::Dmn::Decision.new(id: "test_decision", name: "Test Decision")
    decision.decision_table = table
    model.add_decision(decision)

    table
  end

  describe "UNIQUE hit policy" do
    it "returns result when exactly one rule matches" do
      create_decision_table("UNIQUE", [
        { id: "rule1", input: ">= 10", output: '"approved"', description: "High value" },
        { id: "rule2", input: "< 10", output: '"rejected"', description: "Low value" }
      ])

      evaluator = DecisionAgent::Evaluators::DmnEvaluator.new(
        model: model,
        decision_id: "test_decision"
      )

      evaluation = evaluator.evaluate(DecisionAgent::Context.new(value: 15))
      expect(evaluation).not_to be_nil
      expect(evaluation.decision).to eq("approved")
    end

    it "raises error when no rules match" do
      create_decision_table("UNIQUE", [
        { id: "rule1", input: ">= 10", output: '"approved"', description: "High value" },
        { id: "rule2", input: "> 20", output: '"rejected"', description: "Very high value" }
      ])

      evaluator = DecisionAgent::Evaluators::DmnEvaluator.new(
        model: model,
        decision_id: "test_decision"
      )

      # Value 5 doesn't match >= 10 or > 20, so no rules match
      expect do
        evaluator.evaluate(DecisionAgent::Context.new(value: 5))
      end.to raise_error(DecisionAgent::Dmn::InvalidDmnModelError, /UNIQUE hit policy requires exactly one matching rule/)
    end

    it "raises error when multiple rules match" do
      create_decision_table("UNIQUE", [
        { id: "rule1", input: ">= 5", output: '"approved"', description: "Rule 1" },
        { id: "rule2", input: ">= 10", output: '"approved"', description: "Rule 2" }
      ])

      evaluator = DecisionAgent::Evaluators::DmnEvaluator.new(
        model: model,
        decision_id: "test_decision"
      )

      expect do
        evaluator.evaluate(DecisionAgent::Context.new(value: 15))
      end.to raise_error(DecisionAgent::Dmn::InvalidDmnModelError, /UNIQUE hit policy requires exactly one matching rule, but 2 matched/)
    end
  end

  describe "FIRST hit policy" do
    it "returns first matching rule when multiple rules match" do
      create_decision_table("FIRST", [
        { id: "rule1", input: ">= 5", output: '"first"', description: "First rule" },
        { id: "rule2", input: ">= 10", output: '"second"', description: "Second rule" }
      ])

      evaluator = DecisionAgent::Evaluators::DmnEvaluator.new(
        model: model,
        decision_id: "test_decision"
      )

      evaluation = evaluator.evaluate(DecisionAgent::Context.new(value: 15))
      expect(evaluation).not_to be_nil
      expect(evaluation.decision).to eq("first")
      expect(evaluation.metadata[:rule_id]).to eq("rule1")
    end

    it "returns nil when no rules match" do
      create_decision_table("FIRST", [
        { id: "rule1", input: ">= 10", output: '"approved"', description: "High value" }
      ])

      evaluator = DecisionAgent::Evaluators::DmnEvaluator.new(
        model: model,
        decision_id: "test_decision"
      )

      evaluation = evaluator.evaluate(DecisionAgent::Context.new(value: 5))
      expect(evaluation).to be_nil
    end
  end

  describe "PRIORITY hit policy" do
    it "returns first matching rule (rule order determines priority)" do
      create_decision_table("PRIORITY", [
        { id: "rule1", input: ">= 5", output: '"high_priority"', description: "High priority rule" },
        { id: "rule2", input: ">= 10", output: '"low_priority"', description: "Low priority rule" }
      ])

      evaluator = DecisionAgent::Evaluators::DmnEvaluator.new(
        model: model,
        decision_id: "test_decision"
      )

      evaluation = evaluator.evaluate(DecisionAgent::Context.new(value: 15))
      expect(evaluation).not_to be_nil
      expect(evaluation.decision).to eq("high_priority")
      expect(evaluation.metadata[:rule_id]).to eq("rule1")
    end
  end

  describe "ANY hit policy" do
    it "returns result when all matching rules have same output" do
      create_decision_table("ANY", [
        { id: "rule1", input: ">= 5", output: '"approved"', description: "Rule 1" },
        { id: "rule2", input: ">= 10", output: '"approved"', description: "Rule 2" }
      ])

      evaluator = DecisionAgent::Evaluators::DmnEvaluator.new(
        model: model,
        decision_id: "test_decision"
      )

      evaluation = evaluator.evaluate(DecisionAgent::Context.new(value: 15))
      expect(evaluation).not_to be_nil
      expect(evaluation.decision).to eq("approved")
    end

    it "raises error when matching rules have different outputs" do
      create_decision_table("ANY", [
        { id: "rule1", input: ">= 5", output: '"approved"', description: "Rule 1" },
        { id: "rule2", input: ">= 10", output: '"rejected"', description: "Rule 2" }
      ])

      evaluator = DecisionAgent::Evaluators::DmnEvaluator.new(
        model: model,
        decision_id: "test_decision"
      )

      expect do
        evaluator.evaluate(DecisionAgent::Context.new(value: 15))
      end.to raise_error(DecisionAgent::Dmn::InvalidDmnModelError, /ANY hit policy requires all matching rules to have the same output/)
    end
  end

  describe "COLLECT hit policy" do
    it "returns first match with metadata about all matches" do
      create_decision_table("COLLECT", [
        { id: "rule1", input: ">= 5", output: '"match1"', description: "Rule 1" },
        { id: "rule2", input: ">= 10", output: '"match2"', description: "Rule 2" }
      ])

      evaluator = DecisionAgent::Evaluators::DmnEvaluator.new(
        model: model,
        decision_id: "test_decision"
      )

      evaluation = evaluator.evaluate(DecisionAgent::Context.new(value: 15))
      expect(evaluation).not_to be_nil
      expect(evaluation.decision).to eq("match1")
      expect(evaluation.metadata[:collect_count]).to eq(2)
      expect(evaluation.metadata[:collect_decisions]).to eq(%w[match1 match2])
      expect(evaluation.metadata[:collect_rule_ids]).to eq(%w[rule1 rule2])
    end

    it "returns nil when no rules match" do
      create_decision_table("COLLECT", [
        { id: "rule1", input: ">= 10", output: '"approved"', description: "High value" }
      ])

      evaluator = DecisionAgent::Evaluators::DmnEvaluator.new(
        model: model,
        decision_id: "test_decision"
      )

      evaluation = evaluator.evaluate(DecisionAgent::Context.new(value: 5))
      expect(evaluation).to be_nil
    end
  end
end

