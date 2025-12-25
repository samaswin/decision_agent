# frozen_string_literal: true

class PerformanceMetric < ApplicationRecord
  validates :operation, presence: true
  validates :duration_ms, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :status, inclusion: { in: %w[success failure error] }, allow_nil: true

  scope :recent, ->(time_range = 3600) { where("created_at >= ?", Time.now - time_range) }
  scope :by_operation, ->(operation) { where(operation: operation) }
  scope :successful, -> { where(status: "success") }
  scope :failed, -> { where(status: "failure") }
  scope :with_errors, -> { where(status: "error") }
  scope :slow, ->(threshold_ms = 1000) { where("duration_ms > ?", threshold_ms) }

  # Performance statistics
  def self.average_duration(time_range: 3600)
    recent(time_range).where.not(duration_ms: nil).average(:duration_ms).to_f
  end

  def self.percentile(pct, time_range: 3600)
    durations = recent(time_range).where.not(duration_ms: nil).order(:duration_ms).pluck(:duration_ms)
    return 0.0 if durations.empty?

    index = ((durations.length - 1) * pct).ceil
    durations[index].to_f
  end

  def self.p50(time_range: 3600)
    percentile(0.50, time_range: time_range)
  end

  def self.p95(time_range: 3600)
    percentile(0.95, time_range: time_range)
  end

  def self.p99(time_range: 3600)
    percentile(0.99, time_range: time_range)
  end

  def self.max_duration(time_range: 3600)
    recent(time_range).maximum(:duration_ms).to_f
  end

  def self.min_duration(time_range: 3600)
    recent(time_range).minimum(:duration_ms).to_f
  end

  def self.success_rate(time_range: 3600)
    total = recent(time_range).where.not(status: nil).count
    return 0.0 if total.zero?

    successful_count = recent(time_range).successful.count
    successful_count.to_f / total
  end

  def self.count_by_operation(time_range: 3600)
    recent(time_range).group(:operation).count
  end

  # Time series aggregation
  def self.average_duration_by_time(bucket_size: 60, time_range: 3600)
    recent(time_range)
      .where.not(duration_ms: nil)
      .group("(EXTRACT(EPOCH FROM created_at)::bigint / #{bucket_size}) * #{bucket_size}")
      .average(:duration_ms)
  end

  # Parse JSON metadata field
  def parsed_metadata
    return {} if metadata.nil?

    JSON.parse(metadata, symbolize_names: true)
  rescue JSON::ParserError
    {}
  end
end
