# frozen_string_literal: true

require "spec_helper"
require "decision_agent/dmn/model"

RSpec.describe DecisionAgent::Dmn::Model do
  describe "#initialize" do
    it "creates a model with id, name, and default namespace" do
      model = described_class.new(id: "model_1", name: "Test Model")

      expect(model.id).to eq("model_1")
      expect(model.name).to eq("Test Model")
      expect(model.namespace).to eq("http://decision_agent.local")
      expect(model.decisions).to eq([])
    end

    it "accepts a custom namespace" do
      model = described_class.new(id: "m1", name: "M1", namespace: "http://example.com")

      expect(model.namespace).to eq("http://example.com")
    end
  end

  describe "#add_decision" do
    it "adds a Decision to the model" do
      model = described_class.new(id: "m1", name: "M1")
      decision = DecisionAgent::Dmn::Decision.new(id: "d1", name: "Decision 1")

      model.add_decision(decision)

      expect(model.decisions.size).to eq(1)
      expect(model.decisions.first.id).to eq("d1")
    end

    it "raises TypeError for non-Decision objects" do
      model = described_class.new(id: "m1", name: "M1")

      expect { model.add_decision("not a decision") }.to raise_error(TypeError, /Expected Decision/)
    end
  end

  describe "#find_decision" do
    it "finds a decision by id" do
      model = described_class.new(id: "m1", name: "M1")
      decision = DecisionAgent::Dmn::Decision.new(id: "d1", name: "Decision 1")
      model.add_decision(decision)

      expect(model.find_decision("d1")).to eq(decision)
    end

    it "returns nil for unknown decision id" do
      model = described_class.new(id: "m1", name: "M1")

      expect(model.find_decision("unknown")).to be_nil
    end
  end

  describe "#freeze" do
    it "freezes the model and its decisions" do
      model = described_class.new(id: "m1", name: "M1")
      decision = DecisionAgent::Dmn::Decision.new(id: "d1", name: "D1")
      model.add_decision(decision)
      model.freeze

      expect(model).to be_frozen
      expect(model.decisions).to be_frozen
      expect { model.add_decision(DecisionAgent::Dmn::Decision.new(id: "d2", name: "D2")) }.to raise_error(FrozenError)
    end
  end
end

RSpec.describe DecisionAgent::Dmn::Decision do
  describe "#initialize" do
    it "creates a decision with id and name" do
      decision = described_class.new(id: "d1", name: "Decision 1")

      expect(decision.id).to eq("d1")
      expect(decision.name).to eq("Decision 1")
      expect(decision.decision_table).to be_nil
      expect(decision.description).to be_nil
      expect(decision.information_requirements).to eq([])
    end

    it "accepts a description" do
      decision = described_class.new(id: "d1", name: "D1", description: "A test decision")

      expect(decision.description).to eq("A test decision")
    end
  end

  describe "#decision_table=" do
    it "sets a valid DecisionTable" do
      decision = described_class.new(id: "d1", name: "D1")
      table = DecisionAgent::Dmn::DecisionTable.new(id: "dt1")

      decision.decision_table = table

      expect(decision.decision_table).to eq(table)
    end

    it "raises TypeError for non-DecisionTable objects" do
      decision = described_class.new(id: "d1", name: "D1")

      expect { decision.decision_table = "not a table" }.to raise_error(TypeError, /Expected DecisionTable/)
    end
  end
end

RSpec.describe DecisionAgent::Dmn::DecisionTable do
  describe "#initialize" do
    it "creates a table with default UNIQUE hit policy" do
      table = described_class.new(id: "dt1")

      expect(table.id).to eq("dt1")
      expect(table.hit_policy).to eq("UNIQUE")
      expect(table.inputs).to eq([])
      expect(table.outputs).to eq([])
      expect(table.rules).to eq([])
    end

    it "accepts valid hit policies" do
      %w[UNIQUE FIRST PRIORITY ANY COLLECT].each do |policy|
        table = described_class.new(id: "dt1", hit_policy: policy)
        expect(table.hit_policy).to eq(policy)
      end
    end

    it "raises UnsupportedHitPolicyError for invalid hit policy" do
      expect do
        described_class.new(id: "dt1", hit_policy: "INVALID")
      end.to raise_error(DecisionAgent::Dmn::UnsupportedHitPolicyError, /not supported/)
    end
  end

  describe "#add_input" do
    it "adds an Input" do
      table = described_class.new(id: "dt1")
      input = DecisionAgent::Dmn::Input.new(id: "i1", label: "Age")

      table.add_input(input)

      expect(table.inputs.size).to eq(1)
    end

    it "raises TypeError for non-Input objects" do
      table = described_class.new(id: "dt1")

      expect { table.add_input("not an input") }.to raise_error(TypeError, /Expected Input/)
    end
  end

  describe "#add_output" do
    it "adds an Output" do
      table = described_class.new(id: "dt1")
      output = DecisionAgent::Dmn::Output.new(id: "o1", label: "Risk")

      table.add_output(output)

      expect(table.outputs.size).to eq(1)
    end

    it "raises TypeError for non-Output objects" do
      table = described_class.new(id: "dt1")

      expect { table.add_output("not an output") }.to raise_error(TypeError, /Expected Output/)
    end
  end

  describe "#add_rule" do
    it "adds a Rule" do
      table = described_class.new(id: "dt1")
      rule = DecisionAgent::Dmn::Rule.new(id: "r1")

      table.add_rule(rule)

      expect(table.rules.size).to eq(1)
    end

    it "raises TypeError for non-Rule objects" do
      table = described_class.new(id: "dt1")

      expect { table.add_rule("not a rule") }.to raise_error(TypeError, /Expected Rule/)
    end
  end

  describe "#freeze" do
    it "freezes the table and all components" do
      table = described_class.new(id: "dt1")
      table.add_input(DecisionAgent::Dmn::Input.new(id: "i1", label: "Age"))
      table.add_output(DecisionAgent::Dmn::Output.new(id: "o1", label: "Risk"))
      table.add_rule(DecisionAgent::Dmn::Rule.new(id: "r1"))
      table.freeze

      expect(table).to be_frozen
      expect(table.inputs).to be_frozen
      expect(table.outputs).to be_frozen
      expect(table.rules).to be_frozen
    end
  end
end

RSpec.describe DecisionAgent::Dmn::Input do
  it "creates an input with defaults" do
    input = described_class.new(id: "i1", label: "Age")

    expect(input.id).to eq("i1")
    expect(input.label).to eq("Age")
    expect(input.expression).to eq("Age")
    expect(input.type_ref).to eq("string")
  end

  it "accepts custom expression and type_ref" do
    input = described_class.new(id: "i1", label: "Age", expression: "customer.age", type_ref: "integer")

    expect(input.expression).to eq("customer.age")
    expect(input.type_ref).to eq("integer")
  end
end

RSpec.describe DecisionAgent::Dmn::Output do
  it "creates an output with defaults" do
    output = described_class.new(id: "o1", label: "Risk Level")

    expect(output.id).to eq("o1")
    expect(output.label).to eq("Risk Level")
    expect(output.name).to eq("Risk Level")
    expect(output.type_ref).to eq("string")
  end

  it "accepts custom name and type_ref" do
    output = described_class.new(id: "o1", label: "Risk Level", name: "risk", type_ref: "string")

    expect(output.name).to eq("risk")
  end
end

RSpec.describe DecisionAgent::Dmn::Rule do
  describe "#initialize" do
    it "creates a rule with id" do
      rule = described_class.new(id: "r1")

      expect(rule.id).to eq("r1")
      expect(rule.description).to be_nil
      expect(rule.input_entries).to eq([])
      expect(rule.output_entries).to eq([])
    end
  end

  describe "#add_input_entry" do
    it "adds an input entry as a string" do
      rule = described_class.new(id: "r1")
      rule.add_input_entry("> 18")

      expect(rule.input_entries).to eq(["> 18"])
    end
  end

  describe "#add_output_entry" do
    it "adds an output entry" do
      rule = described_class.new(id: "r1")
      rule.add_output_entry("approved")

      expect(rule.output_entries).to eq(["approved"])
    end
  end

  describe "#freeze" do
    it "freezes the rule and its entries" do
      rule = described_class.new(id: "r1", description: "Test rule")
      rule.add_input_entry("> 18")
      rule.add_output_entry("approved")
      rule.freeze

      expect(rule).to be_frozen
      expect(rule.input_entries).to be_frozen
      expect(rule.output_entries).to be_frozen
    end
  end
end
