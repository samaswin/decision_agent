# frozen_string_literal: true

require_relative "base_adapter"

module DecisionAgent
  module Monitoring
    module Storage
      # ActiveRecord adapter for persistent database storage
      class ActiveRecordAdapter < BaseAdapter
        def initialize
          super
          validate_models!
        end

        def record_decision(decision, context, confidence: nil, evaluations_count: 0, duration_ms: nil, status: nil)
          ::DecisionLog.create!(
            decision: decision,
            context: context.to_json,
            confidence: confidence,
            evaluations_count: evaluations_count,
            duration_ms: duration_ms,
            status: status
          )
        rescue StandardError => e
          warn "Failed to record decision to database: #{e.message}"
        end

        def record_evaluation(evaluator_name, score: nil, success: nil, duration_ms: nil, details: {})
          ::EvaluationMetric.create!(
            evaluator_name: evaluator_name,
            score: score,
            success: success,
            duration_ms: duration_ms,
            details: details.to_json
          )
        rescue StandardError => e
          warn "Failed to record evaluation to database: #{e.message}"
        end

        def record_performance(operation, duration_ms: nil, status: nil, metadata: {})
          ::PerformanceMetric.create!(
            operation: operation,
            duration_ms: duration_ms,
            status: status,
            metadata: metadata.to_json
          )
        rescue StandardError => e
          warn "Failed to record performance to database: #{e.message}"
        end

        def record_error(error_type, message: nil, stack_trace: nil, severity: nil, context: {})
          ::ErrorMetric.create!(
            error_type: error_type,
            message: message,
            stack_trace: stack_trace&.to_json,
            severity: severity,
            context: context.to_json
          )
        rescue StandardError => e
          warn "Failed to record error to database: #{e.message}"
        end

        def statistics(time_range: 3600)
          decisions = ::DecisionLog.recent(time_range)
          evaluations = ::EvaluationMetric.recent(time_range)
          performance = ::PerformanceMetric.recent(time_range)
          errors = ::ErrorMetric.recent(time_range)

          {
            decisions: {
              total: decisions.count,
              by_decision: decisions.group(:decision).count,
              average_confidence: decisions.where.not(confidence: nil).average(:confidence).to_f,
              success_rate: ::DecisionLog.success_rate(time_range: time_range)
            },
            evaluations: {
              total: evaluations.count,
              by_evaluator: evaluations.group(:evaluator_name).count,
              average_score: evaluations.where.not(score: nil).average(:score).to_f,
              success_rate_by_evaluator: evaluations.successful.group(:evaluator_name).count
            },
            performance: {
              total: performance.count,
              average_duration_ms: performance.average_duration(time_range: time_range),
              p50: performance.p50(time_range: time_range),
              p95: performance.p95(time_range: time_range),
              p99: performance.p99(time_range: time_range),
              success_rate: performance.success_rate(time_range: time_range)
            },
            errors: {
              total: errors.count,
              by_type: errors.group(:error_type).count,
              by_severity: errors.group(:severity).count,
              critical_count: errors.critical.count
            }
          }
        rescue StandardError => e
          warn "Failed to retrieve statistics from database: #{e.message}"
          default_statistics
        end

        def time_series(metric_type, bucket_size: 60, time_range: 3600)
          case metric_type
          when :decisions
            decisions_time_series(bucket_size, time_range)
          when :evaluations
            evaluations_time_series(bucket_size, time_range)
          when :performance
            performance_time_series(bucket_size, time_range)
          when :errors
            errors_time_series(bucket_size, time_range)
          else
            { data: [], timestamps: [] }
          end
        rescue StandardError => e
          warn "Failed to retrieve time series from database: #{e.message}"
          { data: [], timestamps: [] }
        end

        def metrics_count
          {
            decisions: ::DecisionLog.count,
            evaluations: ::EvaluationMetric.count,
            performance: ::PerformanceMetric.count,
            errors: ::ErrorMetric.count
          }
        rescue StandardError => e
          warn "Failed to get metrics count from database: #{e.message}"
          { decisions: 0, evaluations: 0, performance: 0, errors: 0 }
        end

        def cleanup(older_than:)
          cutoff_time = Time.now - older_than
          count = 0

          count += ::DecisionLog.where("created_at < ?", cutoff_time).delete_all
          count += ::EvaluationMetric.where("created_at < ?", cutoff_time).delete_all
          count += ::PerformanceMetric.where("created_at < ?", cutoff_time).delete_all
          count += ::ErrorMetric.where("created_at < ?", cutoff_time).delete_all

          count
        rescue StandardError => e
          warn "Failed to cleanup old metrics from database: #{e.message}"
          0
        end

        def self.available?
          defined?(ActiveRecord) &&
            defined?(::DecisionLog) &&
            defined?(::EvaluationMetric) &&
            defined?(::PerformanceMetric) &&
            defined?(::ErrorMetric)
        end

        private

        def validate_models!
          required_models = %w[DecisionLog EvaluationMetric PerformanceMetric ErrorMetric]
          missing_models = required_models.reject { |model| Object.const_defined?(model) }

          return if missing_models.empty?

          raise "Missing required models: #{missing_models.join(', ')}. " \
                "Run 'rails generate decision_agent:install --monitoring' to create them."
        end

        def decisions_time_series(bucket_size, time_range)
          counts = ::DecisionLog.recent(time_range)
                                .group(time_bucket_sql(:created_at, bucket_size))
                                .count

          format_time_series(counts)
        end

        def evaluations_time_series(bucket_size, time_range)
          counts = ::EvaluationMetric.recent(time_range)
                                     .group(time_bucket_sql(:created_at, bucket_size))
                                     .count

          format_time_series(counts)
        end

        def performance_time_series(bucket_size, time_range)
          durations = ::PerformanceMetric.recent(time_range)
                                         .where.not(duration_ms: nil)
                                         .group(time_bucket_sql(:created_at, bucket_size))
                                         .average(:duration_ms)

          format_time_series(durations)
        end

        def errors_time_series(bucket_size, time_range)
          counts = ::ErrorMetric.recent(time_range)
                                .group(time_bucket_sql(:created_at, bucket_size))
                                .count

          format_time_series(counts)
        end

        def time_bucket_sql(column, bucket_size)
          adapter = ActiveRecord::Base.connection.adapter_name.downcase

          case adapter
          when /postgres/
            "(EXTRACT(EPOCH FROM #{column})::bigint / #{bucket_size}) * #{bucket_size}"
          when /mysql/
            "(UNIX_TIMESTAMP(#{column}) DIV #{bucket_size}) * #{bucket_size}"
          when /sqlite/
            "(CAST(strftime('%s', #{column}) AS INTEGER) / #{bucket_size}) * #{bucket_size}"
          else
            # Fallback: use group by timestamp truncated to bucket
            column.to_s
          end
        end

        def format_time_series(data)
          timestamps = data.keys.sort
          values = timestamps.map { |ts| data[ts] }

          {
            timestamps: timestamps.map { |ts| Time.at(ts).iso8601 },
            data: values.map(&:to_f)
          }
        end

        def default_statistics
          {
            decisions: { total: 0, by_decision: {}, average_confidence: 0.0, success_rate: 0.0 },
            evaluations: { total: 0, by_evaluator: {}, average_score: 0.0, success_rate_by_evaluator: {} },
            performance: { total: 0, average_duration_ms: 0.0, p50: 0.0, p95: 0.0, p99: 0.0, success_rate: 0.0 },
            errors: { total: 0, by_type: {}, by_severity: {}, critical_count: 0 }
          }
        end
      end
    end
  end
end
