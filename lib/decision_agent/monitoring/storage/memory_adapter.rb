# frozen_string_literal: true

require_relative "base_adapter"
require "monitor"

module DecisionAgent
  module Monitoring
    module Storage
      # In-memory adapter for metrics storage (default, no dependencies)
      class MemoryAdapter < BaseAdapter
        include MonitorMixin

        def initialize(window_size: 3600)
          super()
          @window_size = window_size
          @metrics = {
            decisions: [],
            evaluations: [],
            performance: [],
            errors: []
          }
        end

        def record_decision(decision, context, confidence: nil, evaluations_count: 0, duration_ms: nil, status: nil)
          synchronize do
            @metrics[:decisions] << {
              decision: decision,
              context: context,
              confidence: confidence,
              evaluations_count: evaluations_count,
              duration_ms: duration_ms,
              status: status,
              timestamp: Time.now
            }
            cleanup_old_metrics
          end
        end

        def record_evaluation(evaluator_name, score: nil, success: nil, duration_ms: nil, details: {})
          synchronize do
            @metrics[:evaluations] << {
              evaluator_name: evaluator_name,
              score: score,
              success: success,
              duration_ms: duration_ms,
              details: details,
              timestamp: Time.now
            }
            cleanup_old_metrics
          end
        end

        def record_performance(operation, duration_ms: nil, status: nil, metadata: {})
          synchronize do
            @metrics[:performance] << {
              operation: operation,
              duration_ms: duration_ms,
              status: status,
              metadata: metadata,
              timestamp: Time.now
            }
            cleanup_old_metrics
          end
        end

        def record_error(error_type, message: nil, stack_trace: nil, severity: nil, context: {})
          synchronize do
            @metrics[:errors] << {
              error_type: error_type,
              message: message,
              stack_trace: stack_trace,
              severity: severity,
              context: context,
              timestamp: Time.now
            }
            cleanup_old_metrics
          end
        end

        def statistics(time_range: 3600)
          synchronize do
            cutoff = Time.now - time_range
            recent_decisions = @metrics[:decisions].select { |m| m[:timestamp] >= cutoff }
            recent_evaluations = @metrics[:evaluations].select { |m| m[:timestamp] >= cutoff }
            recent_performance = @metrics[:performance].select { |m| m[:timestamp] >= cutoff }
            recent_errors = @metrics[:errors].select { |m| m[:timestamp] >= cutoff }

            {
              decisions: decision_statistics(recent_decisions),
              evaluations: evaluation_statistics(recent_evaluations),
              performance: performance_statistics(recent_performance),
              errors: error_statistics(recent_errors)
            }
          end
        end

        def time_series(metric_type, bucket_size: 60, time_range: 3600)
          synchronize do
            cutoff = Time.now - time_range
            metrics = @metrics[metric_type].select { |m| m[:timestamp] >= cutoff }

            buckets = Hash.new(0)
            metrics.each do |metric|
              bucket = (metric[:timestamp].to_i / bucket_size) * bucket_size
              buckets[bucket] += 1
            end

            timestamps = buckets.keys.sort
            {
              timestamps: timestamps.map { |ts| Time.at(ts).iso8601 },
              data: timestamps.map { |ts| buckets[ts] }
            }
          end
        end

        def metrics_count
          synchronize do
            {
              decisions: @metrics[:decisions].size,
              evaluations: @metrics[:evaluations].size,
              performance: @metrics[:performance].size,
              errors: @metrics[:errors].size
            }
          end
        end

        def cleanup(older_than:)
          synchronize do
            cutoff = Time.now - older_than
            count = 0

            @metrics.each_value do |metric_array|
              before_size = metric_array.size
              metric_array.reject! { |m| m[:timestamp] < cutoff }
              count += before_size - metric_array.size
            end

            count
          end
        end

        def self.available?
          true # Always available, no dependencies
        end

        private

        def cleanup_old_metrics
          cutoff = Time.now - @window_size
          @metrics.each_value do |metric_array|
            metric_array.reject! { |m| m[:timestamp] < cutoff }
          end
        end

        def decision_statistics(decisions)
          total = decisions.size
          confidences = decisions.map { |d| d[:confidence] }.compact
          statuses = decisions.map { |d| d[:status] }.compact

          {
            total: total,
            by_decision: decisions.group_by { |d| d[:decision] }.transform_values(&:count),
            average_confidence: confidences.empty? ? 0.0 : confidences.sum / confidences.size.to_f,
            success_rate: calculate_success_rate(statuses)
          }
        end

        def evaluation_statistics(evaluations)
          total = evaluations.size
          scores = evaluations.map { |e| e[:score] }.compact

          {
            total: total,
            by_evaluator: evaluations.group_by { |e| e[:evaluator_name] }.transform_values(&:count),
            average_score: scores.empty? ? 0.0 : scores.sum / scores.size.to_f,
            success_rate_by_evaluator: evaluations.select { |e| e[:success] }
                                                  .group_by { |e| e[:evaluator_name] }
                                                  .transform_values(&:count)
          }
        end

        def performance_statistics(performance_metrics)
          total = performance_metrics.size
          durations = performance_metrics.map { |p| p[:duration_ms] }.compact.sort
          statuses = performance_metrics.map { |p| p[:status] }.compact

          {
            total: total,
            average_duration_ms: durations.empty? ? 0.0 : durations.sum / durations.size.to_f,
            p50: percentile(durations, 0.50),
            p95: percentile(durations, 0.95),
            p99: percentile(durations, 0.99),
            success_rate: calculate_success_rate(statuses)
          }
        end

        def error_statistics(errors)
          {
            total: errors.size,
            by_type: errors.group_by { |e| e[:error_type] }.transform_values(&:count),
            by_severity: errors.group_by { |e| e[:severity] }.transform_values(&:count),
            critical_count: errors.count { |e| e[:severity] == "critical" }
          }
        end

        def percentile(sorted_array, pct)
          return 0.0 if sorted_array.empty?

          index = ((sorted_array.length - 1) * pct).ceil
          sorted_array[index].to_f
        end

        def calculate_success_rate(statuses)
          return 0.0 if statuses.empty?

          successful = statuses.count { |s| s == "success" }
          successful.to_f / statuses.size
        end
      end
    end
  end
end
