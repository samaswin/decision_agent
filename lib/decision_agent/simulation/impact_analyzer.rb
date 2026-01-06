require_relative "errors"

module DecisionAgent
  module Simulation
    # Analyzer for quantifying rule change impact
    class ImpactAnalyzer
      attr_reader :version_manager

      def initialize(version_manager: nil)
        @version_manager = version_manager || Versioning::VersionManager.new
      end

      # Analyze impact of a proposed rule change
      # @param baseline_version [String, Integer, Hash] Baseline rule version
      # @param proposed_version [String, Integer, Hash] Proposed rule version
      # @param test_data [Array<Hash>] Test contexts to evaluate
      # @param options [Hash] Analysis options
      #   - :parallel [Boolean] Use parallel execution (default: true)
      #   - :thread_count [Integer] Number of threads (default: 4)
      #   - :calculate_risk [Boolean] Calculate risk score (default: true)
      # @return [Hash] Impact analysis report
      def analyze(baseline_version:, proposed_version:, test_data:, options: {})
        options = {
          parallel: true,
          thread_count: 4,
          calculate_risk: true
        }.merge(options)

        baseline_agent = build_agent_from_version(baseline_version)
        proposed_agent = build_agent_from_version(proposed_version)

        # Execute both versions on test data
        results = execute_comparison(test_data, baseline_agent, proposed_agent, options)

        # Build impact report
        build_impact_report(results, options)
      end

      # Calculate risk score for a rule change
      # @param results [Array<Hash>] Comparison results
      # @return [Float] Risk score between 0.0 (low risk) and 1.0 (high risk)
      def calculate_risk_score(results)
        return 0.0 if results.empty?

        total = results.size
        decision_changes = results.count { |r| r[:decision_changed] }
        large_confidence_shifts = results.count { |r| (r[:confidence_delta] || 0).abs > 0.2 }
        rejections_increased = count_rejection_increases(results)

        # Risk factors
        change_rate = decision_changes.to_f / total
        confidence_volatility = large_confidence_shifts.to_f / total
        rejection_risk = rejections_increased.to_f / total

        # Weighted risk score
        risk_score = (
          (change_rate * 0.4) +
          (confidence_volatility * 0.3) +
          (rejection_risk * 0.3)
        )

        [risk_score, 1.0].min # Cap at 1.0
      end

      private

      def build_agent_from_version(version)
        version_hash = resolve_version(version)
        evaluators = build_evaluators_from_version(version_hash)
        Agent.new(
          evaluators: evaluators,
          scoring_strategy: Scoring::WeightedAverage.new,
          audit_adapter: Audit::NullAdapter.new
        )
      end

      def resolve_version(version)
        case version
        when String, Integer
          version_data = @version_manager.get_version(version_id: version)
          raise VersionComparisonError, "Version not found: #{version}" unless version_data

          version_data
        when Hash
          version
        else
          raise VersionComparisonError, "Invalid version format: #{version.class}"
        end
      end

      def build_evaluators_from_version(version)
        content = version[:content] || version["content"]
        raise VersionComparisonError, "Version has no content" unless content

        if content.is_a?(Hash) && content[:evaluators]
          build_evaluators_from_config(content[:evaluators])
        elsif content.is_a?(Hash) && (content[:rules] || content["rules"])
          [Evaluators::JsonRuleEvaluator.new(rules_json: content)]
        else
          raise VersionComparisonError, "Cannot build evaluators from version content"
        end
      end

      def build_evaluators_from_config(configs)
        Array(configs).map do |config|
          case config[:type] || config["type"]
          when "json_rule"
            Evaluators::JsonRuleEvaluator.new(rules_json: config[:rules] || config["rules"])
          when "dmn"
            model = config[:model] || config["model"]
            decision_id = config[:decision_id] || config["decision_id"]
            Evaluators::DmnEvaluator.new(model: model, decision_id: decision_id)
          else
            raise VersionComparisonError, "Unknown evaluator type: #{config[:type]}"
          end
        end
      end

      def execute_comparison(test_data, baseline_agent, proposed_agent, options)
        results = []
        mutex = Mutex.new

        if options[:parallel] && test_data.size > 1
          execute_parallel(test_data, baseline_agent, proposed_agent, options, mutex) do |result|
            mutex.synchronize { results << result }
          end
        else
          test_data.each do |context|
            result = execute_single_comparison(context, baseline_agent, proposed_agent)
            results << result
          end
        end

        results
      end

      def execute_parallel(test_data, baseline_agent, proposed_agent, options, _mutex)
        thread_count = [options[:thread_count], test_data.size].min
        queue = Queue.new
        test_data.each { |c| queue << c }

        threads = Array.new(thread_count) do
          Thread.new do
            loop do
              context = begin
                queue.pop(true)
              rescue StandardError
                nil
              end
              break unless context

              result = execute_single_comparison(context, baseline_agent, proposed_agent)
              yield result
            end
          end
        end

        threads.each(&:join)
      end

      def execute_single_comparison(context, baseline_agent, proposed_agent)
        ctx = context.is_a?(Context) ? context : Context.new(context)

        # Measure baseline performance
        baseline_start = Time.now
        begin
          baseline_decision = baseline_agent.decide(context: ctx)
          baseline_duration_ms = (Time.now - baseline_start) * 1000
          baseline_evaluations_count = baseline_decision.evaluations&.size || 0
        rescue NoEvaluationsError
          baseline_decision = nil
          baseline_duration_ms = (Time.now - baseline_start) * 1000
          baseline_evaluations_count = 0
        end

        # Measure proposed performance
        proposed_start = Time.now
        begin
          proposed_decision = proposed_agent.decide(context: ctx)
          proposed_duration_ms = (Time.now - proposed_start) * 1000
          proposed_evaluations_count = proposed_decision.evaluations&.size || 0
        rescue NoEvaluationsError
          proposed_decision = nil
          proposed_duration_ms = (Time.now - proposed_start) * 1000
          proposed_evaluations_count = 0
        end

        # Handle cases where one or both decisions failed
        if baseline_decision.nil? && proposed_decision.nil?
          decision_changed = false
          confidence_delta = 0
        elsif baseline_decision.nil?
          decision_changed = true
          confidence_delta = proposed_decision.confidence
        elsif proposed_decision.nil?
          decision_changed = true
          confidence_delta = -baseline_decision.confidence
        else
          decision_changed = baseline_decision.decision != proposed_decision.decision
          confidence_delta = proposed_decision.confidence - baseline_decision.confidence
        end

        {
          context: ctx.to_h,
          baseline_decision: baseline_decision&.decision,
          baseline_confidence: baseline_decision&.confidence || 0,
          baseline_duration_ms: baseline_duration_ms,
          baseline_evaluations_count: baseline_evaluations_count,
          proposed_decision: proposed_decision&.decision,
          proposed_confidence: proposed_decision&.confidence || 0,
          proposed_duration_ms: proposed_duration_ms,
          proposed_evaluations_count: proposed_evaluations_count,
          decision_changed: decision_changed,
          confidence_delta: confidence_delta,
          confidence_shift_magnitude: confidence_delta.abs,
          performance_delta_ms: proposed_duration_ms - baseline_duration_ms,
          performance_delta_percent: if baseline_duration_ms.positive?
                                       (
                                                 (proposed_duration_ms - baseline_duration_ms) / baseline_duration_ms * 100
                                               )
                                     else
                                       0
                                     end
        }
      end

      def build_impact_report(results, options)
        total = results.size
        decision_changes = results.count { |r| r[:decision_changed] }
        confidence_deltas = results.map { |r| r[:confidence_delta] }.compact

        # Decision distribution changes
        baseline_distribution = results.group_by { |r| r[:baseline_decision] }.transform_values(&:count)
        proposed_distribution = results.group_by { |r| r[:proposed_decision] }.transform_values(&:count)

        # Confidence statistics
        avg_confidence_delta = confidence_deltas.any? ? confidence_deltas.sum / confidence_deltas.size : 0
        max_confidence_shift = confidence_deltas.map(&:abs).max || 0

        # Rule execution frequency (approximate from decision distribution)
        baseline_frequency = calculate_rule_frequency(results, :baseline_decision)
        proposed_frequency = calculate_rule_frequency(results, :proposed_decision)

        # Performance impact estimation
        performance_impact = calculate_performance_impact(results)

        report = {
          total_contexts: total,
          decision_changes: decision_changes,
          change_rate: total.positive? ? (decision_changes.to_f / total) : 0,
          decision_distribution: {
            baseline: baseline_distribution,
            proposed: proposed_distribution
          },
          confidence_impact: {
            average_delta: avg_confidence_delta,
            max_shift: max_confidence_shift,
            positive_shifts: confidence_deltas.count(&:positive?),
            negative_shifts: confidence_deltas.count(&:negative?)
          },
          rule_execution_frequency: {
            baseline: baseline_frequency,
            proposed: proposed_frequency
          },
          performance_impact: performance_impact,
          results: results
        }

        if options[:calculate_risk]
          report[:risk_score] = calculate_risk_score(results)
          report[:risk_level] = categorize_risk(report[:risk_score])
        end

        report
      end

      def calculate_rule_frequency(results, decision_key)
        # Approximate rule frequency from decision distribution
        # In a real implementation, this would track which rules fired
        results.group_by { |r| r[decision_key] }.transform_values { |v| v.size.to_f / results.size }
      end

      def count_rejection_increases(results)
        results.count do |r|
          baseline = r[:baseline_decision].to_s.downcase
          proposed = r[:proposed_decision].to_s.downcase
          (baseline.include?("approve") || baseline.include?("accept")) &&
            (proposed.include?("reject") || proposed.include?("deny"))
        end
      end

      def categorize_risk(risk_score)
        case risk_score
        when 0.0...0.2
          "low"
        when 0.2...0.5
          "medium"
        when 0.5...0.8
          "high"
        else
          "critical"
        end
      end

      # Calculate performance impact metrics
      # @param results [Array<Hash>] Comparison results with performance data
      # @return [Hash] Performance impact metrics
      def calculate_performance_impact(results)
        return {} if results.empty?

        baseline_durations = results.map { |r| r[:baseline_duration_ms] }.compact
        proposed_durations = results.map { |r| r[:proposed_duration_ms] }.compact
        performance_deltas = results.map { |r| r[:performance_delta_ms] }.compact
        performance_delta_percents = results.map { |r| r[:performance_delta_percent] }.compact

        baseline_evaluations = results.map { |r| r[:baseline_evaluations_count] }.compact
        proposed_evaluations = results.map { |r| r[:proposed_evaluations_count] }.compact

        # Calculate latency statistics
        baseline_avg_latency = baseline_durations.any? ? baseline_durations.sum / baseline_durations.size : 0
        proposed_avg_latency = proposed_durations.any? ? proposed_durations.sum / proposed_durations.size : 0
        baseline_min_latency = baseline_durations.min || 0
        baseline_max_latency = baseline_durations.max || 0
        proposed_min_latency = proposed_durations.min || 0
        proposed_max_latency = proposed_durations.max || 0

        # Calculate throughput (decisions per second)
        baseline_throughput = baseline_avg_latency.positive? ? (1000.0 / baseline_avg_latency) : 0
        proposed_throughput = proposed_avg_latency.positive? ? (1000.0 / proposed_avg_latency) : 0

        # Calculate performance delta
        avg_performance_delta_ms = performance_deltas.any? ? performance_deltas.sum / performance_deltas.size : 0
        avg_performance_delta_percent = performance_delta_percents.any? ? performance_delta_percents.sum / performance_delta_percents.size : 0
        throughput_delta_percent = baseline_throughput.positive? ? ((proposed_throughput - baseline_throughput) / baseline_throughput * 100) : 0

        # Calculate rule complexity impact
        baseline_avg_evaluations = baseline_evaluations.any? ? baseline_evaluations.sum.to_f / baseline_evaluations.size : 0
        proposed_avg_evaluations = proposed_evaluations.any? ? proposed_evaluations.sum.to_f / proposed_evaluations.size : 0
        evaluations_delta = proposed_avg_evaluations - baseline_avg_evaluations

        # Performance impact categorization
        performance_impact_level = categorize_performance_impact(avg_performance_delta_percent)

        {
          latency: {
            baseline: {
              average_ms: baseline_avg_latency.round(4),
              min_ms: baseline_min_latency.round(4),
              max_ms: baseline_max_latency.round(4)
            },
            proposed: {
              average_ms: proposed_avg_latency.round(4),
              min_ms: proposed_min_latency.round(4),
              max_ms: proposed_max_latency.round(4)
            },
            delta_ms: avg_performance_delta_ms.round(4),
            delta_percent: avg_performance_delta_percent.round(2)
          },
          throughput: {
            baseline_decisions_per_second: baseline_throughput.round(2),
            proposed_decisions_per_second: proposed_throughput.round(2),
            delta_percent: throughput_delta_percent.round(2)
          },
          rule_complexity: {
            baseline_avg_evaluations: baseline_avg_evaluations.round(2),
            proposed_avg_evaluations: proposed_avg_evaluations.round(2),
            evaluations_delta: evaluations_delta.round(2)
          },
          impact_level: performance_impact_level,
          summary: build_performance_summary(
            avg_performance_delta_percent,
            throughput_delta_percent,
            evaluations_delta
          )
        }
      end

      # Categorize performance impact level
      # @param delta_percent [Float] Performance delta percentage
      # @return [String] Impact level: "improvement", "neutral", "minor_degradation", "moderate_degradation", "significant_degradation"
      def categorize_performance_impact(delta_percent)
        case delta_percent
        when -Float::INFINITY...-5.0
          "improvement"
        when -5.0...5.0
          "neutral"
        when 5.0...15.0
          "minor_degradation"
        when 15.0...30.0
          "moderate_degradation"
        else
          "significant_degradation"
        end
      end

      # Build human-readable performance summary
      # @param latency_delta_percent [Float] Latency delta percentage
      # @param throughput_delta_percent [Float] Throughput delta percentage
      # @param evaluations_delta [Float] Evaluations delta
      # @return [String] Summary text
      def build_performance_summary(latency_delta_percent, throughput_delta_percent, evaluations_delta)
        parts = []

        if latency_delta_percent.abs > 5.0
          direction = latency_delta_percent.positive? ? "slower" : "faster"
          parts << "Average latency is #{latency_delta_percent.abs.round(2)}% #{direction}"
        end

        if throughput_delta_percent.abs > 5.0
          direction = throughput_delta_percent.positive? ? "higher" : "lower"
          parts << "Throughput is #{throughput_delta_percent.abs.round(2)}% #{direction}"
        end

        if evaluations_delta.abs > 0.5
          direction = evaluations_delta.positive? ? "more" : "fewer"
          parts << "Average #{direction} #{evaluations_delta.abs.round(2)} rule evaluations per decision"
        end

        if parts.empty?
          "Performance impact is minimal (<5% change)"
        else
          "#{parts.join('. ')}."
        end
      end
    end
  end
end
