require "spec_helper"

RSpec.describe "Comprehensive Edge Cases" do
  # ============================================================
  # JSON Rule DSL Edge Cases
  # ============================================================

  describe "JSON Rule DSL edge cases" do
    describe "invalid operators" do
      it "raises error when operator is unknown" do
        rules = {
          version: "1.0",
          ruleset: "test",
          rules: [
            {
              id: "rule_1",
              if: { field: "status", op: "unknown_op", value: "active" },
              then: { decision: "approve" }
            }
          ]
        }

        expect {
          DecisionAgent::Evaluators::JsonRuleEvaluator.new(rules_json: rules)
        }.to raise_error(DecisionAgent::InvalidRuleDslError, /Unsupported operator 'unknown_op'/)
      end

      it "raises error when operator is misspelled" do
        rules = {
          version: "1.0",
          ruleset: "test",
          rules: [
            {
              id: "rule_1",
              if: { field: "score", op: "greather_than", value: 10 },
              then: { decision: "pass" }
            }
          ]
        }

        expect {
          DecisionAgent::Evaluators::JsonRuleEvaluator.new(rules_json: rules)
        }.to raise_error(DecisionAgent::InvalidRuleDslError, /Unsupported operator 'greather_than'/)
      end

      it "raises error when operator is nil" do
        rules = {
          version: "1.0",
          ruleset: "test",
          rules: [
            {
              id: "rule_1",
              if: { field: "status", op: nil, value: "active" },
              then: { decision: "approve" }
            }
          ]
        }

        expect {
          DecisionAgent::Evaluators::JsonRuleEvaluator.new(rules_json: rules)
        }.to raise_error(DecisionAgent::InvalidRuleDslError, /missing 'op'/)
      end
    end

    describe "deeply nested conditions" do
      it "handles deeply nested all/any combinations" do
        rules = {
          version: "1.0",
          ruleset: "test",
          rules: [
            {
              id: "rule_1",
              if: {
                all: [
                  {
                    any: [
                      { field: "a", op: "eq", value: 1 },
                      {
                        all: [
                          { field: "b", op: "eq", value: 2 },
                          { field: "c", op: "eq", value: 3 }
                        ]
                      }
                    ]
                  },
                  { field: "d", op: "eq", value: 4 }
                ]
              },
              then: { decision: "complex_match" }
            }
          ]
        }

        evaluator = DecisionAgent::Evaluators::JsonRuleEvaluator.new(rules_json: rules)

        # Should match via first branch of 'any'
        context1 = DecisionAgent::Context.new({ a: 1, d: 4 })
        expect(evaluator.evaluate(context1)).not_to be_nil

        # Should match via second branch of 'any'
        context2 = DecisionAgent::Context.new({ b: 2, c: 3, d: 4 })
        expect(evaluator.evaluate(context2)).not_to be_nil

        # Should not match (missing 'd')
        context3 = DecisionAgent::Context.new({ a: 1 })
        expect(evaluator.evaluate(context3)).to be_nil
      end

      it "handles empty nested conditions gracefully" do
        rules = {
          version: "1.0",
          ruleset: "test",
          rules: [
            {
              id: "rule_1",
              if: {
                all: [
                  { field: "status", op: "eq", value: "active" },
                  { any: [] }
                ]
              },
              then: { decision: "approve" }
            }
          ]
        }

        evaluator = DecisionAgent::Evaluators::JsonRuleEvaluator.new(rules_json: rules)
        context = DecisionAgent::Context.new({ status: "active" })

        # any: [] should return false, making the all condition false
        evaluation = evaluator.evaluate(context)
        expect(evaluation).to be_nil
      end
    end

    describe "missing fields in nested structures" do
      it "handles missing intermediate nested fields" do
        rules = {
          version: "1.0",
          ruleset: "test",
          rules: [
            {
              id: "rule_1",
              if: { field: "user.profile.role", op: "eq", value: "admin" },
              then: { decision: "allow" }
            }
          ]
        }

        evaluator = DecisionAgent::Evaluators::JsonRuleEvaluator.new(rules_json: rules)

        # Missing profile
        context1 = DecisionAgent::Context.new({ user: {} })
        expect(evaluator.evaluate(context1)).to be_nil

        # user is nil
        context2 = DecisionAgent::Context.new({ user: nil })
        expect(evaluator.evaluate(context2)).to be_nil

        # profile is nil
        context3 = DecisionAgent::Context.new({ user: { profile: nil } })
        expect(evaluator.evaluate(context3)).to be_nil
      end

      it "handles array-like nested access attempts" do
        rules = {
          version: "1.0",
          ruleset: "test",
          rules: [
            {
              id: "rule_1",
              if: { field: "items.0.name", op: "eq", value: "first" },
              then: { decision: "match" }
            }
          ]
        }

        evaluator = DecisionAgent::Evaluators::JsonRuleEvaluator.new(rules_json: rules)

        # This should gracefully fail since array access isn't supported in current implementation
        context = DecisionAgent::Context.new({ items: [{ name: "first" }] })
        evaluation = evaluator.evaluate(context)

        # Current implementation doesn't support array indexing
        expect(evaluation).to be_nil
      end

      it "returns nil for very deeply missing nested fields" do
        rules = {
          version: "1.0",
          ruleset: "test",
          rules: [
            {
              id: "rule_1",
              if: { field: "a.b.c.d.e.f.g.h", op: "eq", value: "deep" },
              then: { decision: "found" }
            }
          ]
        }

        evaluator = DecisionAgent::Evaluators::JsonRuleEvaluator.new(rules_json: rules)

        # Missing at various levels
        expect(evaluator.evaluate(DecisionAgent::Context.new({}))).to be_nil
        expect(evaluator.evaluate(DecisionAgent::Context.new({ a: {} }))).to be_nil
        expect(evaluator.evaluate(DecisionAgent::Context.new({ a: { b: { c: {} } } }))).to be_nil
      end

      it "handles partial path matches gracefully" do
        rules = {
          version: "1.0",
          ruleset: "test",
          rules: [
            {
              id: "rule_1",
              if: { field: "user.settings.theme", op: "eq", value: "dark" },
              then: { decision: "dark_mode" }
            }
          ]
        }

        evaluator = DecisionAgent::Evaluators::JsonRuleEvaluator.new(rules_json: rules)

        # Path exists partially but value is wrong type
        context = DecisionAgent::Context.new({ user: { settings: "not_a_hash" } })
        expect(evaluator.evaluate(context)).to be_nil
      end
    end

    describe "very deep nesting (5+ levels)" do
      it "evaluates 5-level nested all/any combinations" do
        rules = {
          version: "1.0",
          ruleset: "test",
          rules: [
            {
              id: "rule_1",
              if: {
                all: [
                  {
                    any: [
                      {
                        all: [
                          {
                            any: [
                              {
                                all: [
                                  { field: "a", op: "eq", value: 1 },
                                  { field: "b", op: "eq", value: 2 }
                                ]
                              }
                            ]
                          }
                        ]
                      }
                    ]
                  }
                ]
              },
              then: { decision: "very_nested_match" }
            }
          ]
        }

        evaluator = DecisionAgent::Evaluators::JsonRuleEvaluator.new(rules_json: rules)

        # Should match
        context1 = DecisionAgent::Context.new({ a: 1, b: 2 })
        result = evaluator.evaluate(context1)
        expect(result).not_to be_nil
        expect(result.decision).to eq("very_nested_match")

        # Should not match (missing b)
        context2 = DecisionAgent::Context.new({ a: 1 })
        expect(evaluator.evaluate(context2)).to be_nil
      end

      it "evaluates 7-level nested structures" do
        rules = {
          version: "1.0",
          ruleset: "test",
          rules: [
            {
              id: "rule_1",
              if: {
                all: [
                  {
                    any: [
                      {
                        all: [
                          {
                            any: [
                              {
                                all: [
                                  {
                                    any: [
                                      {
                                        all: [
                                          { field: "x", op: "eq", value: true }
                                        ]
                                      }
                                    ]
                                  }
                                ]
                              }
                            ]
                          }
                        ]
                      }
                    ]
                  }
                ]
              },
              then: { decision: "extremely_nested" }
            }
          ]
        }

        evaluator = DecisionAgent::Evaluators::JsonRuleEvaluator.new(rules_json: rules)

        context = DecisionAgent::Context.new({ x: true })
        result = evaluator.evaluate(context)
        expect(result).not_to be_nil
        expect(result.decision).to eq("extremely_nested")
      end

      it "handles mixed all/any at each level" do
        rules = {
          version: "1.0",
          ruleset: "test",
          rules: [
            {
              id: "rule_1",
              if: {
                all: [
                  { field: "level1", op: "eq", value: 1 },
                  {
                    any: [
                      { field: "level2a", op: "eq", value: 2 },
                      {
                        all: [
                          { field: "level3a", op: "eq", value: 3 },
                          {
                            any: [
                              { field: "level4a", op: "eq", value: 4 },
                              {
                                all: [
                                  { field: "level5a", op: "eq", value: 5 },
                                  { field: "level5b", op: "eq", value: 6 }
                                ]
                              }
                            ]
                          }
                        ]
                      }
                    ]
                  }
                ]
              },
              then: { decision: "mixed_deep_match" }
            }
          ]
        }

        evaluator = DecisionAgent::Evaluators::JsonRuleEvaluator.new(rules_json: rules)

        # Match via first branch (level2a)
        context1 = DecisionAgent::Context.new({ level1: 1, level2a: 2 })
        expect(evaluator.evaluate(context1)&.decision).to eq("mixed_deep_match")

        # Match via nested path (level4a)
        context2 = DecisionAgent::Context.new({ level1: 1, level3a: 3, level4a: 4 })
        expect(evaluator.evaluate(context2)&.decision).to eq("mixed_deep_match")

        # Match via deepest path
        context3 = DecisionAgent::Context.new({ level1: 1, level3a: 3, level5a: 5, level5b: 6 })
        expect(evaluator.evaluate(context3)&.decision).to eq("mixed_deep_match")

        # No match (missing level1)
        context4 = DecisionAgent::Context.new({ level2a: 2 })
        expect(evaluator.evaluate(context4)).to be_nil
      end
    end

    describe "large rule sets" do
      it "evaluates 100 rules efficiently (first-match semantics)" do
        rules_array = 100.times.map do |i|
          {
            id: "rule_#{i}",
            if: { field: "number", op: "eq", value: i },
            then: { decision: "matched_#{i}", weight: 0.5 + (i / 200.0) }
          }
        end

        rules = {
          version: "1.0",
          ruleset: "large_set",
          rules: rules_array
        }

        evaluator = DecisionAgent::Evaluators::JsonRuleEvaluator.new(rules_json: rules)

        # Should match first rule
        context1 = DecisionAgent::Context.new({ number: 0 })
        result1 = evaluator.evaluate(context1)
        expect(result1.decision).to eq("matched_0")
        expect(result1.metadata[:rule_id]).to eq("rule_0")

        # Should match middle rule
        context2 = DecisionAgent::Context.new({ number: 50 })
        result2 = evaluator.evaluate(context2)
        expect(result2.decision).to eq("matched_50")

        # Should match last rule
        context3 = DecisionAgent::Context.new({ number: 99 })
        result3 = evaluator.evaluate(context3)
        expect(result3.decision).to eq("matched_99")

        # Should not match any rule
        context4 = DecisionAgent::Context.new({ number: 100 })
        expect(evaluator.evaluate(context4)).to be_nil
      end

      it "handles 500 rules without stack overflow" do
        rules_array = 500.times.map do |i|
          {
            id: "rule_#{i}",
            if: {
              all: [
                { field: "category", op: "eq", value: "test" },
                { field: "id", op: "eq", value: i }
              ]
            },
            then: { decision: "rule_#{i}" }
          }
        end

        rules = {
          version: "1.0",
          ruleset: "very_large_set",
          rules: rules_array
        }

        evaluator = DecisionAgent::Evaluators::JsonRuleEvaluator.new(rules_json: rules)

        # Should evaluate without error
        context = DecisionAgent::Context.new({ category: "test", id: 250 })
        result = evaluator.evaluate(context)
        expect(result.decision).to eq("rule_250")
      end
    end

    describe "unicode support" do
      it "handles unicode field names" do
        rules = {
          version: "1.0",
          ruleset: "test",
          rules: [
            {
              id: "rule_1",
              if: { field: "user.名前", op: "eq", value: "太郎" },
              then: { decision: "japanese_match" }
            }
          ]
        }

        evaluator = DecisionAgent::Evaluators::JsonRuleEvaluator.new(rules_json: rules)

        context = DecisionAgent::Context.new({ user: { "名前": "太郎" } })
        result = evaluator.evaluate(context)
        expect(result).not_to be_nil
        expect(result.decision).to eq("japanese_match")
      end

      it "compares unicode values correctly" do
        rules = {
          version: "1.0",
          ruleset: "test",
          rules: [
            {
              id: "rule_1",
              if: { field: "message", op: "eq", value: "Héllo Wörld 🌍" },
              then: { decision: "unicode_match" }
            }
          ]
        }

        evaluator = DecisionAgent::Evaluators::JsonRuleEvaluator.new(rules_json: rules)

        context = DecisionAgent::Context.new({ message: "Héllo Wörld 🌍" })
        result = evaluator.evaluate(context)
        expect(result).not_to be_nil
        expect(result.decision).to eq("unicode_match")

        # Should not match with different unicode
        context2 = DecisionAgent::Context.new({ message: "Hello World 🌍" })
        expect(evaluator.evaluate(context2)).to be_nil
      end

      it "handles emoji in decision values" do
        rules = {
          version: "1.0",
          ruleset: "test",
          rules: [
            {
              id: "rule_1",
              if: { field: "status", op: "eq", value: "happy" },
              then: { decision: "😊_approved", reason: "User is happy 🎉" }
            }
          ]
        }

        evaluator = DecisionAgent::Evaluators::JsonRuleEvaluator.new(rules_json: rules)

        context = DecisionAgent::Context.new({ status: "happy" })
        result = evaluator.evaluate(context)
        expect(result.decision).to eq("😊_approved")
        expect(result.reason).to eq("User is happy 🎉")
      end

      it "handles mixed unicode in nested field paths" do
        rules = {
          version: "1.0",
          ruleset: "test",
          rules: [
            {
              id: "rule_1",
              if: { field: "用户.配置.语言", op: "eq", value: "中文" },
              then: { decision: "chinese_locale" }
            }
          ]
        }

        evaluator = DecisionAgent::Evaluators::JsonRuleEvaluator.new(rules_json: rules)

        context = DecisionAgent::Context.new({
          "用户": {
            "配置": {
              "语言": "中文"
            }
          }
        })
        result = evaluator.evaluate(context)
        expect(result).not_to be_nil
        expect(result.decision).to eq("chinese_locale")
      end
    end

    describe "malformed dot notation edge cases" do
      it "rejects leading dots in field paths" do
        rules = {
          version: "1.0",
          ruleset: "test",
          rules: [
            {
              id: "rule_1",
              if: { field: ".field", op: "eq", value: "test" },
              then: { decision: "match" }
            }
          ]
        }

        # Validator catches empty segments and raises error
        expect {
          DecisionAgent::Evaluators::JsonRuleEvaluator.new(rules_json: rules)
        }.to raise_error(DecisionAgent::InvalidRuleDslError, /empty segments/)
      end

      it "handles trailing dots in field paths" do
        rules = {
          version: "1.0",
          ruleset: "test",
          rules: [
            {
              id: "rule_1",
              if: { field: "field.nested.", op: "eq", value: "test" },
              then: { decision: "match" }
            }
          ]
        }

        # Trailing dots might be accepted but won't match in practice
        # Or they might be rejected - test actual behavior
        evaluator = DecisionAgent::Evaluators::JsonRuleEvaluator.new(rules_json: rules)
        context = DecisionAgent::Context.new({ field: { nested: { "": "test" } } })

        # Evaluation behavior depends on implementation
        # Just verify it doesn't crash
        result = evaluator.evaluate(context)
        # Result may be nil or match depending on how empty string keys are handled
        expect(result).to be_a(DecisionAgent::Evaluation).or be_nil
      end

      it "rejects consecutive dots in field paths" do
        rules = {
          version: "1.0",
          ruleset: "test",
          rules: [
            {
              id: "rule_1",
              if: { field: "field..nested", op: "eq", value: "test" },
              then: { decision: "match" }
            }
          ]
        }

        # Validator catches empty segments and raises error
        expect {
          DecisionAgent::Evaluators::JsonRuleEvaluator.new(rules_json: rules)
        }.to raise_error(DecisionAgent::InvalidRuleDslError, /empty segments/)
      end

      it "rejects multiple consecutive dots in field paths" do
        rules = {
          version: "1.0",
          ruleset: "test",
          rules: [
            {
              id: "rule_1",
              if: { field: "a..b..c", op: "eq", value: "test" },
              then: { decision: "match" }
            }
          ]
        }

        # Validator catches empty segments and raises error
        expect {
          DecisionAgent::Evaluators::JsonRuleEvaluator.new(rules_json: rules)
        }.to raise_error(DecisionAgent::InvalidRuleDslError, /empty segments/)
      end
    end
  end

  # ============================================================
  # Evaluator Behavior Edge Cases
  # ============================================================

  describe "evaluator behavior edge cases" do
    describe "nil returns and empty evaluations" do
      it "handles all evaluators returning nil" do
        nil_evaluator = Class.new(DecisionAgent::Evaluators::Base) do
          def evaluate(context, feedback: {})
            nil
          end
        end

        agent = DecisionAgent::Agent.new(evaluators: [nil_evaluator.new])

        expect {
          agent.decide(context: {})
        }.to raise_error(DecisionAgent::NoEvaluationsError)
      end

      it "handles mix of nil and valid evaluations" do
        nil_evaluator = Class.new(DecisionAgent::Evaluators::Base) do
          def evaluate(context, feedback: {})
            nil
          end
        end

        valid_evaluator = DecisionAgent::Evaluators::StaticEvaluator.new(
          decision: "approve",
          weight: 0.8
        )

        agent = DecisionAgent::Agent.new(evaluators: [nil_evaluator.new, valid_evaluator])

        result = agent.decide(context: {})

        expect(result.decision).to eq("approve")
        expect(result.evaluations.size).to eq(1)
      end
    end

    describe "zero weight handling" do
      it "handles evaluator with zero weight" do
        zero_weight_evaluator = DecisionAgent::Evaluators::StaticEvaluator.new(
          decision: "approve",
          weight: 0.0,
          reason: "Zero weight"
        )

        agent = DecisionAgent::Agent.new(evaluators: [zero_weight_evaluator])

        result = agent.decide(context: {})

        expect(result.decision).to eq("approve")
        expect(result.evaluations.first.weight).to eq(0.0)
      end

      it "handles mix of zero and non-zero weights" do
        zero_weight = DecisionAgent::Evaluators::StaticEvaluator.new(
          decision: "reject",
          weight: 0.0,
          name: "ZeroWeight"
        )

        normal_weight = DecisionAgent::Evaluators::StaticEvaluator.new(
          decision: "approve",
          weight: 0.8,
          name: "NormalWeight"
        )

        agent = DecisionAgent::Agent.new(
          evaluators: [zero_weight, normal_weight],
          scoring_strategy: DecisionAgent::Scoring::WeightedAverage.new
        )

        result = agent.decide(context: {})

        # With weighted average, the non-zero weight should dominate
        expect(result.decision).to eq("approve")
      end

      it "handles all evaluators with zero weight" do
        zero_weight1 = DecisionAgent::Evaluators::StaticEvaluator.new(
          decision: "approve",
          weight: 0.0
        )

        zero_weight2 = DecisionAgent::Evaluators::StaticEvaluator.new(
          decision: "reject",
          weight: 0.0
        )

        agent = DecisionAgent::Agent.new(evaluators: [zero_weight1, zero_weight2])

        result = agent.decide(context: {})

        # Should still make a decision even with all zero weights
        expect(result.decision).to be_a(String)
        expect(result.confidence).to be_between(0.0, 1.0)
      end
    end
  end

  # ============================================================
  # Conflict Resolution Edge Cases
  # ============================================================

  describe "conflict resolution edge cases" do
    describe "equal weights" do
      it "handles equal weights in WeightedAverage" do
        eval1 = DecisionAgent::Evaluators::StaticEvaluator.new(
          decision: "approve",
          weight: 0.5,
          name: "Eval1"
        )

        eval2 = DecisionAgent::Evaluators::StaticEvaluator.new(
          decision: "reject",
          weight: 0.5,
          name: "Eval2"
        )

        agent = DecisionAgent::Agent.new(
          evaluators: [eval1, eval2],
          scoring_strategy: DecisionAgent::Scoring::WeightedAverage.new
        )

        result = agent.decide(context: {})

        # Should choose one decision
        expect(["approve", "reject"]).to include(result.decision)
        # Confidence should reflect the tie
        expect(result.confidence).to eq(0.5)
      end

      it "handles equal weights in MaxWeight" do
        eval1 = DecisionAgent::Evaluators::StaticEvaluator.new(
          decision: "option_a",
          weight: 0.7,
          name: "Eval1"
        )

        eval2 = DecisionAgent::Evaluators::StaticEvaluator.new(
          decision: "option_b",
          weight: 0.7,
          name: "Eval2"
        )

        eval3 = DecisionAgent::Evaluators::StaticEvaluator.new(
          decision: "option_c",
          weight: 0.7,
          name: "Eval3"
        )

        agent = DecisionAgent::Agent.new(
          evaluators: [eval1, eval2, eval3],
          scoring_strategy: DecisionAgent::Scoring::MaxWeight.new
        )

        result = agent.decide(context: {})

        # Should choose one of the options
        expect(["option_a", "option_b", "option_c"]).to include(result.decision)
        expect(result.confidence).to eq(0.7)
      end

      it "handles equal weights in Consensus" do
        eval1 = DecisionAgent::Evaluators::StaticEvaluator.new(
          decision: "approve",
          weight: 0.6,
          name: "Eval1"
        )

        eval2 = DecisionAgent::Evaluators::StaticEvaluator.new(
          decision: "reject",
          weight: 0.6,
          name: "Eval2"
        )

        agent = DecisionAgent::Agent.new(
          evaluators: [eval1, eval2],
          scoring_strategy: DecisionAgent::Scoring::Consensus.new
        )

        result = agent.decide(context: {})

        # Should choose one decision, likely with reduced confidence
        expect(["approve", "reject"]).to include(result.decision)
      end
    end

    describe "mixed decisions" do
      it "handles three-way split in decisions" do
        eval1 = DecisionAgent::Evaluators::StaticEvaluator.new(
          decision: "approve",
          weight: 0.5,
          name: "Eval1"
        )

        eval2 = DecisionAgent::Evaluators::StaticEvaluator.new(
          decision: "reject",
          weight: 0.5,
          name: "Eval2"
        )

        eval3 = DecisionAgent::Evaluators::StaticEvaluator.new(
          decision: "manual_review",
          weight: 0.5,
          name: "Eval3"
        )

        agent = DecisionAgent::Agent.new(
          evaluators: [eval1, eval2, eval3],
          scoring_strategy: DecisionAgent::Scoring::WeightedAverage.new
        )

        result = agent.decide(context: {})

        expect(["approve", "reject", "manual_review"]).to include(result.decision)
      end

      it "handles many evaluators with diverse decisions" do
        evaluators = 10.times.map do |i|
          DecisionAgent::Evaluators::StaticEvaluator.new(
            decision: "decision_#{i % 5}",  # 5 different decisions
            weight: 0.1 * (i + 1),          # Varying weights
            name: "Eval#{i}"
          )
        end

        agent = DecisionAgent::Agent.new(
          evaluators: evaluators,
          scoring_strategy: DecisionAgent::Scoring::WeightedAverage.new
        )

        result = agent.decide(context: {})

        expect(result.decision).to be_a(String)
        expect(result.confidence).to be_between(0.0, 1.0)
        expect(result.evaluations.size).to eq(10)
      end

      it "handles 50 evaluators with diverse decisions" do
        evaluators = 50.times.map do |i|
          DecisionAgent::Evaluators::StaticEvaluator.new(
            decision: "decision_#{i % 10}",  # 10 different decisions
            weight: 0.02 * (i + 1),          # Varying weights 0.02 to 1.0
            name: "Eval#{i}"
          )
        end

        agent = DecisionAgent::Agent.new(
          evaluators: evaluators,
          scoring_strategy: DecisionAgent::Scoring::WeightedAverage.new
        )

        result = agent.decide(context: {})

        expect(result.decision).to be_a(String)
        expect(result.decision).to match(/decision_\d/)
        expect(result.confidence).to be_between(0.0, 1.0)
        expect(result.evaluations.size).to eq(50)
      end

      it "handles all evaluators with same decision but different weights" do
        evaluators = 20.times.map do |i|
          DecisionAgent::Evaluators::StaticEvaluator.new(
            decision: "unanimous",
            weight: 0.05 * (i + 1),  # Weights from 0.05 to 1.0
            name: "Eval#{i}"
          )
        end

        agent = DecisionAgent::Agent.new(
          evaluators: evaluators,
          scoring_strategy: DecisionAgent::Scoring::WeightedAverage.new
        )

        result = agent.decide(context: {})

        expect(result.decision).to eq("unanimous")
        # All weights point to same decision, confidence should be high
        expect(result.confidence).to eq(1.0)
        expect(result.evaluations.size).to eq(20)
      end
    end
  end

  # ============================================================
  # Scoring Strategy Edge Cases
  # ============================================================

  describe "scoring strategy edge cases" do
    describe "MaxWeight edge cases" do
      it "handles single evaluation" do
        eval1 = DecisionAgent::Evaluators::StaticEvaluator.new(
          decision: "approve",
          weight: 0.6
        )

        agent = DecisionAgent::Agent.new(
          evaluators: [eval1],
          scoring_strategy: DecisionAgent::Scoring::MaxWeight.new
        )

        result = agent.decide(context: {})

        expect(result.decision).to eq("approve")
        expect(result.confidence).to eq(0.6)
      end

      it "ignores lower weights completely" do
        high = DecisionAgent::Evaluators::StaticEvaluator.new(
          decision: "approve",
          weight: 0.9,
          name: "High"
        )

        low1 = DecisionAgent::Evaluators::StaticEvaluator.new(
          decision: "reject",
          weight: 0.2,
          name: "Low1"
        )

        low2 = DecisionAgent::Evaluators::StaticEvaluator.new(
          decision: "reject",
          weight: 0.3,
          name: "Low2"
        )

        agent = DecisionAgent::Agent.new(
          evaluators: [low1, high, low2],
          scoring_strategy: DecisionAgent::Scoring::MaxWeight.new
        )

        result = agent.decide(context: {})

        expect(result.decision).to eq("approve")
        expect(result.confidence).to eq(0.9)
      end
    end

    describe "Consensus edge cases" do
      it "reduces confidence when no clear consensus" do
        eval1 = DecisionAgent::Evaluators::StaticEvaluator.new(
          decision: "option_a",
          weight: 0.4,
          name: "Eval1"
        )

        eval2 = DecisionAgent::Evaluators::StaticEvaluator.new(
          decision: "option_b",
          weight: 0.4,
          name: "Eval2"
        )

        eval3 = DecisionAgent::Evaluators::StaticEvaluator.new(
          decision: "option_c",
          weight: 0.4,
          name: "Eval3"
        )

        agent = DecisionAgent::Agent.new(
          evaluators: [eval1, eval2, eval3],
          scoring_strategy: DecisionAgent::Scoring::Consensus.new(minimum_agreement: 0.5)
        )

        result = agent.decide(context: {})

        # No option has 50% agreement, confidence should be reduced
        expect(result.confidence).to be < 0.5
      end

      it "handles unanimous decision" do
        evaluators = 5.times.map do |i|
          DecisionAgent::Evaluators::StaticEvaluator.new(
            decision: "approve",
            weight: 0.6 + (i * 0.05),
            name: "Eval#{i}"
          )
        end

        agent = DecisionAgent::Agent.new(
          evaluators: evaluators,
          scoring_strategy: DecisionAgent::Scoring::Consensus.new
        )

        result = agent.decide(context: {})

        expect(result.decision).to eq("approve")
        # Should have high confidence due to unanimous agreement
        expect(result.confidence).to be > 0.5
      end

      it "handles varying minimum agreement thresholds" do
        eval1 = DecisionAgent::Evaluators::StaticEvaluator.new(
          decision: "approve",
          weight: 0.8,
          name: "Eval1"
        )

        eval2 = DecisionAgent::Evaluators::StaticEvaluator.new(
          decision: "approve",
          weight: 0.7,
          name: "Eval2"
        )

        eval3 = DecisionAgent::Evaluators::StaticEvaluator.new(
          decision: "reject",
          weight: 0.6,
          name: "Eval3"
        )

        # Test with low threshold
        agent_low = DecisionAgent::Agent.new(
          evaluators: [eval1, eval2, eval3],
          scoring_strategy: DecisionAgent::Scoring::Consensus.new(minimum_agreement: 0.3)
        )

        result_low = agent_low.decide(context: {})
        expect(result_low.decision).to eq("approve")

        # Test with high threshold
        agent_high = DecisionAgent::Agent.new(
          evaluators: [eval1, eval2, eval3],
          scoring_strategy: DecisionAgent::Scoring::Consensus.new(minimum_agreement: 0.9)
        )

        result_high = agent_high.decide(context: {})
        # Should still choose approve but with lower confidence
        expect(result_high.decision).to eq("approve")
      end
    end

    describe "Threshold edge cases" do
      it "returns fallback when all evaluations below threshold" do
        low_weight = DecisionAgent::Evaluators::StaticEvaluator.new(
          decision: "approve",
          weight: 0.5
        )

        agent = DecisionAgent::Agent.new(
          evaluators: [low_weight],
          scoring_strategy: DecisionAgent::Scoring::Threshold.new(
            threshold: 0.8,
            fallback_decision: "needs_review"
          )
        )

        result = agent.decide(context: {})

        expect(result.decision).to eq("needs_review")
        expect(result.confidence).to be < 0.8
      end

      it "returns decision when exactly at threshold" do
        exact_weight = DecisionAgent::Evaluators::StaticEvaluator.new(
          decision: "approve",
          weight: 0.75
        )

        agent = DecisionAgent::Agent.new(
          evaluators: [exact_weight],
          scoring_strategy: DecisionAgent::Scoring::Threshold.new(threshold: 0.75)
        )

        result = agent.decide(context: {})

        expect(result.decision).to eq("approve")
        expect(result.confidence).to eq(0.75)
      end

      it "handles threshold with conflicting evaluations" do
        high = DecisionAgent::Evaluators::StaticEvaluator.new(
          decision: "approve",
          weight: 0.9,
          name: "High"
        )

        medium = DecisionAgent::Evaluators::StaticEvaluator.new(
          decision: "approve",
          weight: 0.7,
          name: "Medium"
        )

        low = DecisionAgent::Evaluators::StaticEvaluator.new(
          decision: "reject",
          weight: 0.4,
          name: "Low"
        )

        agent = DecisionAgent::Agent.new(
          evaluators: [high, medium, low],
          scoring_strategy: DecisionAgent::Scoring::Threshold.new(threshold: 0.75)
        )

        result = agent.decide(context: {})

        # Average of approve votes is 0.8, which exceeds threshold
        expect(result.decision).to eq("approve")
      end

      it "handles very high threshold" do
        evaluator = DecisionAgent::Evaluators::StaticEvaluator.new(
          decision: "approve",
          weight: 0.99
        )

        agent = DecisionAgent::Agent.new(
          evaluators: [evaluator],
          scoring_strategy: DecisionAgent::Scoring::Threshold.new(
            threshold: 0.999,
            fallback_decision: "uncertain"
          )
        )

        result = agent.decide(context: {})

        expect(result.decision).to eq("uncertain")
      end
    end

    describe "stress tests with large evaluator counts" do
      it "handles 100 evaluators efficiently with WeightedAverage" do
        evaluators = 100.times.map do |i|
          DecisionAgent::Evaluators::StaticEvaluator.new(
            decision: "decision_#{i % 10}",
            weight: (i + 1) / 200.0,  # Weights from 0.005 to 0.505
            name: "Eval#{i}"
          )
        end

        agent = DecisionAgent::Agent.new(
          evaluators: evaluators,
          scoring_strategy: DecisionAgent::Scoring::WeightedAverage.new
        )

        result = agent.decide(context: {})

        expect(result.decision).to be_a(String)
        expect(result.confidence).to be_between(0.0, 1.0)
        expect(result.evaluations.size).to eq(100)
      end

      it "handles 100 evaluators with all same decision" do
        evaluators = 100.times.map do |i|
          DecisionAgent::Evaluators::StaticEvaluator.new(
            decision: "consensus",
            weight: 0.5 + (i / 200.0),  # Weights from 0.5 to 0.995
            name: "Eval#{i}"
          )
        end

        agent = DecisionAgent::Agent.new(
          evaluators: evaluators,
          scoring_strategy: DecisionAgent::Scoring::WeightedAverage.new
        )

        result = agent.decide(context: {})

        expect(result.decision).to eq("consensus")
        expect(result.confidence).to eq(1.0)
      end

      it "handles 100 evaluators with MaxWeight strategy" do
        evaluators = 100.times.map do |i|
          DecisionAgent::Evaluators::StaticEvaluator.new(
            decision: "decision_#{i}",
            weight: i / 100.0,  # Weights from 0.0 to 0.99
            name: "Eval#{i}"
          )
        end

        agent = DecisionAgent::Agent.new(
          evaluators: evaluators,
          scoring_strategy: DecisionAgent::Scoring::MaxWeight.new
        )

        result = agent.decide(context: {})

        # Should pick the last one with highest weight (0.99)
        expect(result.decision).to eq("decision_99")
        expect(result.confidence).to be_within(0.001).of(0.99)
      end

      it "handles 100 evaluators with Consensus strategy" do
        # Create 60 "approve" votes and 40 "reject" votes
        evaluators = []
        60.times do |i|
          evaluators << DecisionAgent::Evaluators::StaticEvaluator.new(
            decision: "approve",
            weight: 0.6,
            name: "ApproveEval#{i}"
          )
        end
        40.times do |i|
          evaluators << DecisionAgent::Evaluators::StaticEvaluator.new(
            decision: "reject",
            weight: 0.7,
            name: "RejectEval#{i}"
          )
        end

        agent = DecisionAgent::Agent.new(
          evaluators: evaluators,
          scoring_strategy: DecisionAgent::Scoring::Consensus.new(minimum_agreement: 0.5)
        )

        result = agent.decide(context: {})

        # Approve has 60% agreement, should win
        expect(result.decision).to eq("approve")
        expect(result.evaluations.size).to eq(100)
      end
    end

    describe "floating point precision edge cases" do
      it "handles repeating decimals (0.333333...)" do
        eval1 = DecisionAgent::Evaluators::StaticEvaluator.new(
          decision: "approve",
          weight: 1.0 / 3.0,  # 0.333333...
          name: "Eval1"
        )

        eval2 = DecisionAgent::Evaluators::StaticEvaluator.new(
          decision: "approve",
          weight: 1.0 / 3.0,
          name: "Eval2"
        )

        eval3 = DecisionAgent::Evaluators::StaticEvaluator.new(
          decision: "approve",
          weight: 1.0 / 3.0,
          name: "Eval3"
        )

        agent = DecisionAgent::Agent.new(
          evaluators: [eval1, eval2, eval3],
          scoring_strategy: DecisionAgent::Scoring::WeightedAverage.new
        )

        result = agent.decide(context: {})

        expect(result.decision).to eq("approve")
        # Sum should be very close to 1.0
        expect(result.confidence).to be_within(0.0001).of(1.0)
      end

      it "normalizes confidence to 4 decimal places" do
        eval1 = DecisionAgent::Evaluators::StaticEvaluator.new(
          decision: "approve",
          weight: 0.123456789,  # Many decimal places
          name: "Eval1"
        )

        agent = DecisionAgent::Agent.new(
          evaluators: [eval1],
          scoring_strategy: DecisionAgent::Scoring::WeightedAverage.new
        )

        result = agent.decide(context: {})

        # Confidence should be rounded to 4 decimal places
        expect(result.confidence.to_s.split('.').last.length).to be <= 4
      end

      it "handles very small weights (0.0001)" do
        eval1 = DecisionAgent::Evaluators::StaticEvaluator.new(
          decision: "approve",
          weight: 0.0001,
          name: "Eval1"
        )

        eval2 = DecisionAgent::Evaluators::StaticEvaluator.new(
          decision: "reject",
          weight: 0.0001,
          name: "Eval2"
        )

        agent = DecisionAgent::Agent.new(
          evaluators: [eval1, eval2],
          scoring_strategy: DecisionAgent::Scoring::WeightedAverage.new
        )

        result = agent.decide(context: {})

        # Should handle small weights without precision errors
        expect(result.decision).to be_a(String)
        expect(result.confidence).to be_between(0.0, 1.0)
      end

      it "handles weights that sum to slightly above 1.0 due to precision" do
        eval1 = DecisionAgent::Evaluators::StaticEvaluator.new(
          decision: "approve",
          weight: 0.7,
          name: "Eval1"
        )

        eval2 = DecisionAgent::Evaluators::StaticEvaluator.new(
          decision: "approve",
          weight: 0.3 + 0.0000001,  # Slightly above to create >1.0 sum
          name: "Eval2"
        )

        agent = DecisionAgent::Agent.new(
          evaluators: [eval1, eval2],
          scoring_strategy: DecisionAgent::Scoring::WeightedAverage.new
        )

        result = agent.decide(context: {})

        # Should normalize to 1.0 or below
        expect(result.confidence).to be <= 1.0
      end

      it "handles Consensus with floating point agreement rates" do
        # Create evaluators where agreement is not a clean fraction
        evaluators = 7.times.map do |i|
          DecisionAgent::Evaluators::StaticEvaluator.new(
            decision: i < 4 ? "approve" : "reject",  # 4/7 = 0.571428...
            weight: 0.6,
            name: "Eval#{i}"
          )
        end

        agent = DecisionAgent::Agent.new(
          evaluators: evaluators,
          scoring_strategy: DecisionAgent::Scoring::Consensus.new(minimum_agreement: 0.57)
        )

        result = agent.decide(context: {})

        # Should handle fractional agreement correctly
        expect(result.decision).to eq("approve")
        expect(result.confidence).to be_a(Float)
      end
    end
  end

  # ============================================================
  # Decision Replay Edge Cases
  # ============================================================

  describe "decision replay edge cases" do
    describe "strict mode behavior" do
      it "detects confidence differences above tolerance in strict mode" do
        evaluator = DecisionAgent::Evaluators::StaticEvaluator.new(
          decision: "approve",
          weight: 0.8
        )

        agent = DecisionAgent::Agent.new(evaluators: [evaluator])

        context = { user: "alice" }
        original_result = agent.decide(context: context)

        modified_payload = original_result.audit_payload.dup
        # Tolerance is 0.0001, so this should trigger an error
        modified_payload[:confidence] = original_result.confidence + 0.001

        expect {
          DecisionAgent::Replay.run(modified_payload, strict: true)
        }.to raise_error(DecisionAgent::ReplayMismatchError)
      end

      it "passes when confidence is identical in strict mode" do
        evaluator = DecisionAgent::Evaluators::StaticEvaluator.new(
          decision: "approve",
          weight: 0.8
        )

        agent = DecisionAgent::Agent.new(evaluators: [evaluator])

        context = { user: "alice" }
        original_result = agent.decide(context: context)

        expect {
          DecisionAgent::Replay.run(original_result.audit_payload, strict: true)
        }.not_to raise_error
      end

      it "allows confidence within tolerance in strict mode" do
        evaluator = DecisionAgent::Evaluators::StaticEvaluator.new(
          decision: "approve",
          weight: 0.8
        )

        agent = DecisionAgent::Agent.new(evaluators: [evaluator])

        context = { user: "alice" }
        original_result = agent.decide(context: context)

        modified_payload = original_result.audit_payload.dup
        # Tolerance is 0.0001, so this should NOT trigger an error
        modified_payload[:confidence] = original_result.confidence + 0.00005

        expect {
          DecisionAgent::Replay.run(modified_payload, strict: true)
        }.not_to raise_error
      end
    end

    describe "non-strict mode behavior" do
      it "logs but doesn't raise on decision mismatch" do
        evaluator = DecisionAgent::Evaluators::StaticEvaluator.new(
          decision: "approve",
          weight: 0.8
        )

        agent = DecisionAgent::Agent.new(evaluators: [evaluator])

        context = { user: "alice" }
        original_result = agent.decide(context: context)

        modified_payload = original_result.audit_payload.dup
        modified_payload[:decision] = "reject"

        result = nil
        expect {
          result = DecisionAgent::Replay.run(modified_payload, strict: false)
        }.to output(/Decision changed/).to_stderr

        expect(result).not_to be_nil
      end

      it "logs but doesn't raise on confidence mismatch" do
        evaluator = DecisionAgent::Evaluators::StaticEvaluator.new(
          decision: "approve",
          weight: 0.8
        )

        agent = DecisionAgent::Agent.new(evaluators: [evaluator])

        context = { user: "alice" }
        original_result = agent.decide(context: context)

        modified_payload = original_result.audit_payload.dup
        modified_payload[:confidence] = 0.5

        result = nil
        expect {
          result = DecisionAgent::Replay.run(modified_payload, strict: false)
        }.to output(/Confidence changed/).to_stderr

        expect(result).not_to be_nil
      end

      it "continues with multiple mismatches in non-strict mode" do
        evaluator = DecisionAgent::Evaluators::StaticEvaluator.new(
          decision: "approve",
          weight: 0.8
        )

        agent = DecisionAgent::Agent.new(evaluators: [evaluator])

        context = { user: "alice" }
        original_result = agent.decide(context: context)

        modified_payload = original_result.audit_payload.dup
        modified_payload[:decision] = "reject"
        modified_payload[:confidence] = 0.3

        result = nil
        expect {
          result = DecisionAgent::Replay.run(modified_payload, strict: false)
        }.to output(/Decision changed.*Confidence changed/m).to_stderr

        expect(result.decision).to eq("approve")  # Should use replayed value
      end
    end

    describe "replay validation errors" do
      it "raises error when context is missing" do
        invalid_payload = {
          decision: "approve",
          confidence: 0.8,
          evaluations: []
        }

        expect {
          DecisionAgent::Replay.run(invalid_payload, strict: true)
        }.to raise_error(DecisionAgent::InvalidRuleDslError, /context/)
      end

      it "raises error when decision is missing" do
        invalid_payload = {
          context: {},
          confidence: 0.8,
          evaluations: []
        }

        expect {
          DecisionAgent::Replay.run(invalid_payload, strict: true)
        }.to raise_error(DecisionAgent::InvalidRuleDslError, /decision/)
      end

      it "raises error when confidence is missing" do
        invalid_payload = {
          context: {},
          decision: "approve",
          evaluations: []
        }

        expect {
          DecisionAgent::Replay.run(invalid_payload, strict: true)
        }.to raise_error(DecisionAgent::InvalidRuleDslError, /confidence/)
      end

      it "raises error when evaluations is missing" do
        invalid_payload = {
          context: {},
          decision: "approve",
          confidence: 0.8
        }

        expect {
          DecisionAgent::Replay.run(invalid_payload, strict: true)
        }.to raise_error(DecisionAgent::InvalidRuleDslError, /evaluations/)
      end

      it "handles empty audit payload" do
        expect {
          DecisionAgent::Replay.run({}, strict: true)
        }.to raise_error(DecisionAgent::InvalidRuleDslError)
      end
    end

    describe "replay with different scoring strategies" do
      it "correctly replays with WeightedAverage strategy" do
        evaluator = DecisionAgent::Evaluators::StaticEvaluator.new(
          decision: "approve",
          weight: 0.8
        )

        agent = DecisionAgent::Agent.new(
          evaluators: [evaluator],
          scoring_strategy: DecisionAgent::Scoring::WeightedAverage.new
        )

        original_result = agent.decide(context: { test: true })

        replayed_result = DecisionAgent::Replay.run(
          original_result.audit_payload,
          strict: true
        )

        expect(replayed_result.decision).to eq(original_result.decision)
        expect(replayed_result.confidence).to be_within(0.0001).of(original_result.confidence)
      end

      it "correctly replays with Threshold strategy" do
        evaluator = DecisionAgent::Evaluators::StaticEvaluator.new(
          decision: "approve",
          weight: 0.9
        )

        agent = DecisionAgent::Agent.new(
          evaluators: [evaluator],
          scoring_strategy: DecisionAgent::Scoring::Threshold.new(
            threshold: 0.8,
            fallback_decision: "review"
          )
        )

        original_result = agent.decide(context: { test: true })

        replayed_result = DecisionAgent::Replay.run(
          original_result.audit_payload,
          strict: true
        )

        expect(replayed_result.decision).to eq(original_result.decision)
        expect(replayed_result.confidence).to be_within(0.0001).of(original_result.confidence)
      end
    end
  end

  # ============================================================
  # Error Handling Edge Cases
  # ============================================================

  describe "error handling edge cases" do
    describe "invalid JSON rule formats" do
      it "raises error for non-hash JSON" do
        expect {
          DecisionAgent::Evaluators::JsonRuleEvaluator.new(rules_json: [1, 2, 3])
        }.to raise_error(DecisionAgent::InvalidRuleDslError)
      end

      it "raises error for string input instead of hash" do
        expect {
          DecisionAgent::Evaluators::JsonRuleEvaluator.new(rules_json: "not a hash")
        }.to raise_error(DecisionAgent::InvalidRuleDslError)
      end

      it "raises error when rules is not an array" do
        rules = {
          version: "1.0",
          rules: "not an array"
        }

        expect {
          DecisionAgent::Evaluators::JsonRuleEvaluator.new(rules_json: rules)
        }.to raise_error(DecisionAgent::InvalidRuleDslError)
      end

      it "raises error when rule is not a hash" do
        rules = {
          version: "1.0",
          rules: ["not a hash", "also not a hash"]
        }

        expect {
          DecisionAgent::Evaluators::JsonRuleEvaluator.new(rules_json: rules)
        }.to raise_error(DecisionAgent::InvalidRuleDslError)
      end
    end

    describe "no evaluations scenarios" do
      it "raises NoEvaluationsError when single evaluator returns nil" do
        nil_evaluator = Class.new(DecisionAgent::Evaluators::Base) do
          def evaluate(context, feedback: {})
            nil
          end
        end

        agent = DecisionAgent::Agent.new(evaluators: [nil_evaluator.new])

        expect {
          agent.decide(context: {})
        }.to raise_error(DecisionAgent::NoEvaluationsError)
      end

      it "raises NoEvaluationsError when all evaluators return nil" do
        nil_evaluator1 = Class.new(DecisionAgent::Evaluators::Base) do
          def evaluate(context, feedback: {})
            nil
          end
        end

        nil_evaluator2 = Class.new(DecisionAgent::Evaluators::Base) do
          def evaluate(context, feedback: {})
            nil
          end
        end

        agent = DecisionAgent::Agent.new(evaluators: [nil_evaluator1.new, nil_evaluator2.new])

        expect {
          agent.decide(context: {})
        }.to raise_error(DecisionAgent::NoEvaluationsError) do |error|
          expect(error.message).to include("No evaluators returned a decision")
        end
      end

      it "raises NoEvaluationsError when all evaluators raise exceptions" do
        failing_evaluator1 = Class.new(DecisionAgent::Evaluators::Base) do
          def evaluate(context, feedback: {})
            raise StandardError, "Error 1"
          end
        end

        failing_evaluator2 = Class.new(DecisionAgent::Evaluators::Base) do
          def evaluate(context, feedback: {})
            raise StandardError, "Error 2"
          end
        end

        agent = DecisionAgent::Agent.new(evaluators: [failing_evaluator1.new, failing_evaluator2.new])

        expect {
          agent.decide(context: {})
        }.to raise_error(DecisionAgent::NoEvaluationsError)
      end

      it "succeeds when at least one evaluator succeeds despite others failing" do
        failing_evaluator = Class.new(DecisionAgent::Evaluators::Base) do
          def evaluate(context, feedback: {})
            raise StandardError, "Intentional failure"
          end
        end

        good_evaluator = DecisionAgent::Evaluators::StaticEvaluator.new(
          decision: "approve",
          weight: 0.8
        )

        agent = DecisionAgent::Agent.new(evaluators: [failing_evaluator.new, good_evaluator])

        result = agent.decide(context: {})

        expect(result.decision).to eq("approve")
      end
    end

    describe "boundary condition validation" do
      it "validates weight is not above 1.0" do
        expect {
          DecisionAgent::Evaluation.new(
            decision: "test",
            weight: 1.1,
            reason: "test",
            evaluator_name: "test"
          )
        }.to raise_error(DecisionAgent::InvalidWeightError)
      end

      it "validates weight is not negative" do
        expect {
          DecisionAgent::Evaluation.new(
            decision: "test",
            weight: -0.5,
            reason: "test",
            evaluator_name: "test"
          )
        }.to raise_error(DecisionAgent::InvalidWeightError)
      end

      it "validates confidence is not above 1.0" do
        expect {
          DecisionAgent::Decision.new(
            decision: "test",
            confidence: 1.001,
            explanations: [],
            evaluations: [],
            audit_payload: {}
          )
        }.to raise_error(DecisionAgent::InvalidConfidenceError)
      end

      it "validates confidence is not negative" do
        expect {
          DecisionAgent::Decision.new(
            decision: "test",
            confidence: -0.001,
            explanations: [],
            evaluations: [],
            audit_payload: {}
          )
        }.to raise_error(DecisionAgent::InvalidConfidenceError)
      end
    end
  end
end
