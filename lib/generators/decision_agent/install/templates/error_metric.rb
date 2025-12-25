# frozen_string_literal: true

class ErrorMetric < ApplicationRecord
  validates :error_type, presence: true
  validates :severity, inclusion: { in: %w[low medium high critical] }, allow_nil: true

  scope :recent, ->(time_range = 3600) { where("created_at >= ?", Time.now - time_range) }
  scope :by_type, ->(error_type) { where(error_type: error_type) }
  scope :by_severity, ->(severity) { where(severity: severity) }
  scope :critical, -> { where(severity: "critical") }
  scope :high_severity, -> { where(severity: %w[high critical]) }

  # Aggregation helpers
  def self.count_by_type(time_range: 3600)
    recent(time_range).group(:error_type).count
  end

  def self.count_by_severity(time_range: 3600)
    recent(time_range).group(:severity).count
  end

  def self.error_rate(time_range: 3600, total_operations: nil)
    error_count = recent(time_range).count
    return 0.0 if total_operations.nil? || total_operations.zero?

    error_count.to_f / total_operations
  end

  # Time series aggregation
  def self.count_by_time_bucket(bucket_size: 60, time_range: 3600)
    recent(time_range)
      .group("(EXTRACT(EPOCH FROM created_at)::bigint / #{bucket_size}) * #{bucket_size}")
      .count
  end

  # Parse JSON context field
  def parsed_context
    return {} if context.nil?

    JSON.parse(context, symbolize_names: true)
  rescue JSON::ParserError
    {}
  end

  # Parse JSON stack_trace field
  def parsed_stack_trace
    return [] if stack_trace.nil?

    JSON.parse(stack_trace)
  rescue JSON::ParserError
    []
  end
end
