# frozen_string_literal: true

class EvaluationMetric < ApplicationRecord
  belongs_to :decision_log, optional: true

  validates :evaluator_name, presence: true
  validates :score, numericality: true, allow_nil: true

  scope :recent, ->(time_range = 3600) { where("created_at >= ?", Time.now - time_range) }
  scope :by_evaluator, ->(evaluator) { where(evaluator_name: evaluator) }
  scope :successful, -> { where(success: true) }
  scope :failed, -> { where(success: false) }

  # Aggregation helpers
  def self.average_score_by_evaluator(time_range: 3600)
    recent(time_range)
      .where.not(score: nil)
      .group(:evaluator_name)
      .average(:score)
  end

  def self.success_rate_by_evaluator(time_range: 3600)
    recent(time_range)
      .where.not(success: nil)
      .group(:evaluator_name)
      .select("evaluator_name, AVG(CASE WHEN success THEN 1.0 ELSE 0.0 END) as success_rate")
  end

  def self.count_by_evaluator(time_range: 3600)
    recent(time_range)
      .group(:evaluator_name)
      .count
  end

  # Parse JSON details field
  def parsed_details
    return {} if details.nil?
    JSON.parse(details, symbolize_names: true)
  rescue JSON::ParserError
    {}
  end
end
