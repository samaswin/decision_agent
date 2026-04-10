# frozen_string_literal: true

require "json"

module DecisionAgent
  module Evaluators
    class JsonRuleEvaluator < Base
      attr_reader :ruleset_name

      def initialize(rules_json:, name: nil)
        @rules_json = rules_json.is_a?(String) ? rules_json : JSON.generate(rules_json)
        @ruleset = Dsl::RuleParser.parse(@rules_json)
        @ruleset_name = @ruleset["ruleset"] || "unknown"
        @name = name || "JsonRuleEvaluator(#{@ruleset_name})"

        # Pre-build O(1) rule lookup map keyed by rule_id
        @rules_by_id = (@ruleset["rules"] || []).each_with_index.to_h do |rule, i|
          [rule["id"] || "rule_#{i}", rule]
        end.freeze

        # Freeze ruleset to ensure thread-safety
        deep_freeze(@ruleset)
        @rules_json.freeze
        @ruleset_name.freeze
        @name.freeze
      end

      def evaluate(context, feedback: {})
        ctx = context.is_a?(DecisionAgent::Context) ? context : DecisionAgent::Context.new(context)

        # Collect explainability traces (this also finds the matching rule)
        explainability_result = collect_explainability(ctx)

        # Find the matched rule from explainability result
        matched_rule_trace = explainability_result&.matched_rules&.first
        return nil unless matched_rule_trace

        # Find the original rule to get the then clause (O(1) lookup)
        matched_rule = @rules_by_id[matched_rule_trace.rule_id]
        return nil unless matched_rule

        then_clause = matched_rule["then"]

        metadata = {
          type: "json_rule",
          rule_id: matched_rule["id"],
          ruleset: @ruleset_name
        }

        # Add explainability data to metadata
        metadata[:explainability] = explainability_result.to_h if explainability_result

        Evaluation.new(
          decision: then_clause["decision"],
          weight: then_clause["weight"] || 1.0,
          reason: then_clause["reason"] || "Rule matched",
          evaluator_name: @name,
          metadata: metadata
        )
      end

      private

      def collect_explainability(context)
        rules = @ruleset["rules"] || []

        # Fast pass: find the first matching rule without building trace objects.
        # This avoids allocating TraceCollector + RuleTrace for every non-matching rule.
        matched_index = nil
        rules.each_with_index do |rule, i|
          next unless rule["if"]

          if Dsl::ConditionEvaluator.evaluate(rule["if"], context)
            matched_index = i
            break
          end
        end

        # Trace pass: re-evaluate only the matched rule with full condition tracing.
        rule_traces = []
        if matched_index
          rule = rules[matched_index]
          rule_id = rule["id"] || "rule_#{matched_index}"
          trace_collector = Explainability::TraceCollector.new
          Dsl::ConditionEvaluator.evaluate(rule["if"], context, trace_collector: trace_collector)
          then_clause = rule["then"] || {}
          rule_traces << Explainability::RuleTrace.new(
            rule_id: rule_id,
            matched: true,
            condition_traces: trace_collector.traces,
            decision: then_clause["decision"],
            weight: then_clause["weight"],
            reason: then_clause["reason"]
          )
        end

        Explainability::ExplainabilityResult.new(
          evaluator_name: @name,
          rule_traces: rule_traces
        )
      end

      # Deep freeze helper method
      def deep_freeze(obj)
        case obj
        when Hash
          obj.each do |k, v|
            deep_freeze(k)
            deep_freeze(v)
          end
          obj.freeze
        when Array
          obj.each { |item| deep_freeze(item) }
          obj.freeze
        when String, Symbol, Numeric, TrueClass, FalseClass, NilClass
          obj.freeze
        else
          obj.freeze if obj.respond_to?(:freeze)
        end
        obj
      end
    end
  end
end
