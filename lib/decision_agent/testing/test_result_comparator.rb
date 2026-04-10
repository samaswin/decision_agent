# frozen_string_literal: true

module DecisionAgent
  module Testing
    # Comparison result for a single test scenario
    class ComparisonResult
      attr_reader :scenario_id, :match, :decision_match, :confidence_match, :differences, :actual, :expected

      def initialize(scenario_id:, match:, decision_match:, confidence_match:, differences:, actual:, expected:)
        @scenario_id = scenario_id.to_s.freeze
        @match = match
        @decision_match = decision_match
        @confidence_match = confidence_match
        @differences = differences.freeze
        @actual = actual
        @expected = expected

        freeze
      end

      def to_h
        {
          scenario_id: @scenario_id,
          match: @match,
          decision_match: @decision_match,
          confidence_match: @confidence_match,
          differences: @differences,
          actual: {
            decision: @actual[:decision],
            confidence: @actual[:confidence]
          },
          expected: {
            decision: @expected[:decision],
            confidence: @expected[:confidence]
          }
        }
      end
    end

    # Compares test results with expected outcomes
    class TestResultComparator
      attr_reader :comparison_results

      def initialize(options = {})
        @options = {
          confidence_tolerance: 0.01, # 1% tolerance for confidence comparison
          fuzzy_match: false # Whether to do fuzzy matching on decisions
        }.merge(options)
        @comparison_results = []
      end

      # Compare test results with expected results from scenarios
      # @param results [Array<TestResult>] Actual test results
      # @param scenarios [Array<TestScenario>] Test scenarios with expected results
      # @return [Hash] Comparison summary with accuracy metrics
      def compare(results, scenarios)
        @comparison_results = []

        # Create a map of scenario_id -> scenario for quick lookup
        scenarios.each_with_object({}) do |scenario, map|
          map[scenario.id] = scenario
        end

        # Create a map of scenario_id -> result for quick lookup
        result_map = results.each_with_object({}) do |result, map|
          map[result.scenario_id] = result
        end

        # Compare each scenario with its result
        scenarios.each do |scenario|
          next unless scenario.expected_result?

          result = result_map[scenario.id]
          # Only compare if we have a result (skip if result is missing)
          next unless result

          comparison = compare_single(scenario, result)
          @comparison_results << comparison
        end

        generate_summary
      end

      # Generate a summary report
      # @return [Hash] Summary with accuracy metrics and mismatches
      def generate_summary
        return empty_summary if @comparison_results.empty?

        total = @comparison_results.size
        matches = @comparison_results.count(&:match)
        mismatches = total - matches

        {
          total: total,
          matches: matches,
          mismatches: mismatches,
          accuracy_rate: matches.to_f / total,
          decision_accuracy: @comparison_results.count(&:decision_match).to_f / total,
          confidence_accuracy: @comparison_results.count(&:confidence_match).to_f / total,
          mismatches_detail: @comparison_results.reject(&:match).map(&:to_h)
        }
      end

      # Export comparison results to CSV
      # @param file_path [String] Path to output CSV file
      def export_csv(file_path)
        require "csv"

        CSV.open(file_path, "w") do |csv|
          csv << %w[scenario_id match decision_match confidence_match expected_decision actual_decision expected_confidence
                    actual_confidence differences]
          @comparison_results.each do |result|
            csv << [
              result.scenario_id,
              result.match,
              result.decision_match,
              result.confidence_match,
              result.expected[:decision],
              result.actual[:decision],
              result.expected[:confidence],
              result.actual[:confidence],
              result.differences.join("; ")
            ]
          end
        end
      end

      # Export comparison results to JSON
      # @param file_path [String] Path to output JSON file
      def export_json(file_path)
        require "json"

        File.write(file_path, JSON.pretty_generate({
                                                     summary: generate_summary,
                                                     results: @comparison_results.map(&:to_h)
                                                   }))
      end

      private

      def compare_single(scenario, result)
        return failed_comparison_result(scenario, result) if result.nil? || !result.success?

        differences = []
        decision_match = compare_decision(scenario, result, differences)
        confidence_match = compare_confidence(scenario, result, differences)

        ComparisonResult.new(
          scenario_id: scenario.id,
          match: decision_match && confidence_match,
          decision_match: decision_match,
          confidence_match: confidence_match,
          differences: differences,
          actual: { decision: result.decision&.to_s, confidence: result.confidence },
          expected: { decision: scenario.expected_decision&.to_s, confidence: scenario.expected_confidence }
        )
      end

      def failed_comparison_result(scenario, result)
        ComparisonResult.new(
          scenario_id: scenario.id,
          match: false,
          decision_match: false,
          confidence_match: false,
          differences: ["Test execution failed: #{result&.error&.message || 'No result'}"],
          actual: { decision: nil, confidence: nil },
          expected: { decision: scenario.expected_decision, confidence: scenario.expected_confidence }
        )
      end

      def compare_decision(scenario, result, differences)
        expected = scenario.expected_decision&.to_s
        actual = result.decision&.to_s

        match = if expected.nil?
                  true
                elsif @options[:fuzzy_match]
                  fuzzy_decision_match?(expected, actual)
                else
                  expected == actual
                end

        differences << "Decision mismatch: expected '#{expected}', got '#{actual}'" unless match
        match
      end

      def compare_confidence(scenario, result, differences)
        expected = scenario.expected_confidence
        actual = result.confidence

        return true if expected.nil?

        if actual.nil?
          differences << "Confidence missing in actual result"
          return false
        end

        tolerance = @options[:confidence_tolerance]
        match = (expected - actual).abs <= tolerance
        unless match
          diff = (expected - actual).abs.round(4)
          differences << "Confidence mismatch: expected #{expected}, got #{actual} (diff: #{diff})"
        end
        match
      end

      def fuzzy_decision_match?(expected, actual)
        return true if expected == actual
        return true if expected&.downcase == actual&.downcase
        return true if expected&.strip == actual&.strip

        false
      end

      def empty_summary
        {
          total: 0,
          matches: 0,
          mismatches: 0,
          accuracy_rate: 0.0,
          decision_accuracy: 0.0,
          confidence_accuracy: 0.0,
          mismatches_detail: []
        }
      end
    end
  end
end
