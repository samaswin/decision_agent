# A/B Test model for decision_agent gem
# Stores A/B test configurations
class ABTestModel < ActiveRecord::Base
  has_many :ab_test_assignment_models, dependent: :destroy

  validates :name, presence: true
  validates :champion_version_id, presence: true
  validates :challenger_version_id, presence: true
  validates :status, presence: true, inclusion: { in: %w[scheduled running completed cancelled] }

  serialize :traffic_split, JSON

  before_validation :set_defaults

  # Scopes
  scope :active, -> { where(status: "running") }
  scope :scheduled, -> { where(status: "scheduled") }
  scope :completed, -> { where(status: "completed") }
  scope :running_or_scheduled, -> { where(status: %w[running scheduled]) }

  # Check if test is currently running
  def running?
    status == "running" &&
      (start_date.nil? || start_date <= Time.current) &&
      (end_date.nil? || end_date > Time.current)
  end

  # Get statistics for this test
  def statistics
    {
      total_assignments: ab_test_assignment_models.count,
      champion_count: ab_test_assignment_models.where(variant: "champion").count,
      challenger_count: ab_test_assignment_models.where(variant: "challenger").count,
      with_decisions: ab_test_assignment_models.where.not(decision_result: nil).count,
      avg_confidence: ab_test_assignment_models.where.not(confidence: nil).average(:confidence)&.to_f
    }
  end

  # Get assignments by variant
  def champion_assignments
    ab_test_assignment_models.where(variant: "champion")
  end

  def challenger_assignments
    ab_test_assignment_models.where(variant: "challenger")
  end

  private

  def set_defaults
    self.traffic_split ||= { champion: 90, challenger: 10 }
    self.status ||= "scheduled"
  end
end
