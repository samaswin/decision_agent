# frozen_string_literal: true

module DecisionAgent
  module Monitoring
    module Storage
      # Base adapter interface for metrics storage
      # Subclasses must implement all abstract methods
      class BaseAdapter
        # Record a decision
        # @param decision [String] The decision made
        # @param context [Hash] Decision context
        # @param confidence [Float, nil] Confidence score (0-1)
        # @param evaluations_count [Integer] Number of evaluations
        # @param duration_ms [Float, nil] Decision duration in milliseconds
        # @param status [String, nil] Decision status (success, failure, error)
        # @return [void]
        def record_decision(decision, context, confidence: nil, evaluations_count: 0, duration_ms: nil, status: nil)
          raise NotImplementedError, "#{self.class} must implement #record_decision"
        end

        # Record an evaluation
        # @param evaluator_name [String] Name of the evaluator
        # @param score [Float, nil] Evaluation score
        # @param success [Boolean, nil] Whether evaluation succeeded
        # @param duration_ms [Float, nil] Evaluation duration
        # @param details [Hash] Additional details
        # @return [void]
        def record_evaluation(evaluator_name, score: nil, success: nil, duration_ms: nil, details: {})
          raise NotImplementedError, "#{self.class} must implement #record_evaluation"
        end

        # Record a performance metric
        # @param operation [String] Operation name
        # @param duration_ms [Float, nil] Duration in milliseconds
        # @param status [String, nil] Status (success, failure, error)
        # @param metadata [Hash] Additional metadata
        # @return [void]
        def record_performance(operation, duration_ms: nil, status: nil, metadata: {})
          raise NotImplementedError, "#{self.class} must implement #record_performance"
        end

        # Record an error
        # @param error_type [String] Type of error
        # @param message [String, nil] Error message
        # @param stack_trace [Array, nil] Stack trace
        # @param severity [String, nil] Error severity (low, medium, high, critical)
        # @param context [Hash] Error context
        # @return [void]
        def record_error(error_type, message: nil, stack_trace: nil, severity: nil, context: {})
          raise NotImplementedError, "#{self.class} must implement #record_error"
        end

        # Get statistics for a time range
        # @param time_range [Integer] Time range in seconds
        # @return [Hash] Statistics summary
        def statistics(time_range: 3600)
          raise NotImplementedError, "#{self.class} must implement #statistics"
        end

        # Get time series data
        # @param metric_type [Symbol] Type of metric (:decisions, :evaluations, :performance, :errors)
        # @param bucket_size [Integer] Bucket size in seconds
        # @param time_range [Integer] Time range in seconds
        # @return [Hash] Time series data
        def time_series(metric_type, bucket_size: 60, time_range: 3600)
          raise NotImplementedError, "#{self.class} must implement #time_series"
        end

        # Get count of metrics stored
        # @return [Hash] Count by metric type
        def metrics_count
          raise NotImplementedError, "#{self.class} must implement #metrics_count"
        end

        # Clean up old metrics
        # @param older_than [Integer] Remove metrics older than this many seconds
        # @return [Integer] Number of metrics removed
        def cleanup(older_than:)
          raise NotImplementedError, "#{self.class} must implement #cleanup"
        end

        # Check if adapter is available (dependencies installed)
        # @return [Boolean]
        def self.available?
          raise NotImplementedError, "#{self} must implement .available?"
        end
      end
    end
  end
end
