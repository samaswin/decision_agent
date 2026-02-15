# frozen_string_literal: true

require "spec_helper"
require "decision_agent/dmn/feel/transformer"

RSpec.describe DecisionAgent::Dmn::Feel::Transformer do
  let(:transformer) { described_class.new }

  describe ".extract_entry_key" do
    it "extracts key from field type hash" do
      result = described_class.extract_entry_key({ type: :field, name: "age" })

      expect(result).to eq("age")
    end

    it "extracts key from string type hash" do
      result = described_class.extract_entry_key({ type: :string, value: "name" })

      expect(result).to eq("name")
    end

    it "extracts key from identifier type hash" do
      result = described_class.extract_entry_key({ type: :identifier, name: "score" })

      expect(result).to eq("score")
    end

    it "converts non-hash values to string" do
      result = described_class.extract_entry_key("plain_key")

      expect(result).to eq("plain_key")
    end
  end

  describe ".extract_name" do
    it "extracts name from field hash" do
      result = described_class.extract_name({ type: :field, name: " age " })

      expect(result).to eq("age")
    end

    it "converts non-hash to stripped string" do
      result = described_class.extract_name(" hello ")

      expect(result).to eq("hello")
    end
  end

  describe ".apply_postfix_op" do
    it "creates property access node" do
      current = { type: :field, name: "obj" }
      op = { property_access: { property: { identifier: "name" } } }

      result = described_class.apply_postfix_op(current, op)

      expect(result[:type]).to eq(:property_access)
      expect(result[:property]).to eq("name")
      expect(result[:object]).to eq(current)
    end

    it "creates function call node" do
      current = { type: :field, name: "func" }
      op = { function_call: { arguments: [{ type: :number, value: 1 }] } }

      result = described_class.apply_postfix_op(current, op)

      expect(result[:type]).to eq(:function_call)
      expect(result[:arguments].size).to eq(1)
    end

    it "creates filter node" do
      current = { type: :field, name: "list" }
      op = { filter: { filter: { type: :comparison } } }

      result = described_class.apply_postfix_op(current, op)

      expect(result[:type]).to eq(:filter)
    end

    it "returns current node for non-hash op" do
      current = { type: :field, name: "x" }

      expect(described_class.apply_postfix_op(current, "invalid")).to eq(current)
    end
  end

  describe ".extract_variable_name" do
    it "extracts name from field hash" do
      result = described_class.extract_variable_name({ type: :field, name: "x" })

      expect(result).to eq("x")
    end

    it "extracts identifier from hash" do
      result = described_class.extract_variable_name({ identifier: "y" })

      expect(result).to eq("y")
    end

    it "converts other types to string" do
      result = described_class.extract_variable_name("z")

      expect(result).to eq("z")
    end
  end

  describe "transform rules" do
    it "transforms null literal" do
      result = transformer.apply(null: "null")

      expect(result).to eq({ type: :null, value: nil })
    end

    it "transforms boolean true" do
      result = transformer.apply(boolean: "true")

      expect(result).to eq({ type: :boolean, value: true })
    end

    it "transforms boolean false" do
      result = transformer.apply(boolean: "false")

      expect(result).to eq({ type: :boolean, value: false })
    end

    it "transforms integer number" do
      result = transformer.apply(number: "42")

      expect(result).to eq({ type: :number, value: 42 })
    end

    it "transforms float number" do
      result = transformer.apply(number: "3.14")

      expect(result).to eq({ type: :number, value: 3.14 })
    end

    it "transforms string" do
      result = transformer.apply(string: "hello")

      expect(result).to eq({ type: :string, value: "hello" })
    end

    it "transforms identifier" do
      result = transformer.apply(identifier: "age")

      expect(result).to eq({ type: :field, name: "age" })
    end

    it "transforms comparison" do
      result = transformer.apply(
        comparison: {
          left: { type: :field, name: "age" },
          op: ">=",
          right: { type: :number, value: 18 }
        }
      )

      expect(result[:type]).to eq(:comparison)
      expect(result[:operator]).to eq(">=")
    end

    it "transforms arithmetic" do
      result = transformer.apply(
        arithmetic: {
          left: { type: :number, value: 1 },
          op: "+",
          right: { type: :number, value: 2 }
        }
      )

      expect(result[:type]).to eq(:arithmetic)
      expect(result[:operator]).to eq("+")
    end

    it "transforms unary not" do
      result = transformer.apply(
        unary: {
          op: "not",
          operand: { type: :boolean, value: true }
        }
      )

      expect(result[:type]).to eq(:logical)
      expect(result[:operator]).to eq("not")
    end

    it "transforms unary minus on number to negative literal" do
      result = transformer.apply(
        unary: {
          op: "-",
          operand: { type: :number, value: 5 }
        }
      )

      expect(result).to eq({ type: :number, value: -5 })
    end

    it "transforms between expression" do
      result = transformer.apply(
        between: {
          value: { type: :field, name: "x" },
          min: { type: :number, value: 1 },
          max: { type: :number, value: 10 }
        }
      )

      expect(result[:type]).to eq(:between)
    end

    it "transforms in expression" do
      result = transformer.apply(
        in: {
          value: { type: :field, name: "x" },
          list: [{ type: :number, value: 1 }]
        }
      )

      expect(result[:type]).to eq(:in)
    end

    it "transforms instance_of" do
      result = transformer.apply(
        instance_of: {
          value: { type: :field, name: "x" },
          type: "number"
        }
      )

      expect(result[:type]).to eq(:instance_of)
      expect(result[:type_name]).to eq("number")
    end
  end
end
