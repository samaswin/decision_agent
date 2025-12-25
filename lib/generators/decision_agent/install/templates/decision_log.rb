# frozen_string_literal: true

class DecisionLog < ApplicationRecord
  has_many :evaluation_metrics, dependent: :destroy

  validates :decision, presence: true
  validates :confidence, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }, allow_nil: true
  validates :status, inclusion: { in: %w[success failure error] }, allow_nil: true

  scope :recent, ->(time_range = 3600) { where("created_at >= ?", Time.now - time_range) }
  scope :successful, -> { where(status: "success") }
  scope :failed, -> { where(status: "failure") }
  scope :with_errors, -> { where(status: "error") }
  scope :by_decision, ->(decision) { where(decision: decision) }
  scope :low_confidence, ->(threshold = 0.5) { where("confidence < ?", threshold) }
  scope :high_confidence, ->(threshold = 0.8) { where("confidence >= ?", threshold) }

  # Time series aggregation helpers
  def self.count_by_time_bucket(bucket_size: 60, time_range: 3600)
    recent(time_range)
      .group("(EXTRACT(EPOCH FROM created_at)::bigint / #{bucket_size}) * #{bucket_size}")
      .count
  end

  def self.average_confidence_by_time(bucket_size: 60, time_range: 3600)
    recent(time_range)
      .where.not(confidence: nil)
      .group("(EXTRACT(EPOCH FROM created_at)::bigint / #{bucket_size}) * #{bucket_size}")
      .average(:confidence)
  end

  def self.success_rate(time_range: 3600)
    total = recent(time_range).where.not(status: nil).count
    return 0.0 if total.zero?

    successful_count = recent(time_range).successful.count
    successful_count.to_f / total
  end

  # Parse JSON context field
  def parsed_context
    return {} if context.nil?
    JSON.parse(context, symbolize_names: true)
  rescue JSON::ParserError
    {}
  end

  # Parse JSON metadata field
  def parsed_metadata
    return {} if metadata.nil?
    JSON.parse(metadata, symbolize_names: true)
  rescue JSON::ParserError
    {}
  end
end
