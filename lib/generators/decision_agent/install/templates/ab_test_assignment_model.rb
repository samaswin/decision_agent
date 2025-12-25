# A/B Test Assignment model for decision_agent gem
# Tracks individual variant assignments and their results
class ABTestAssignmentModel < ActiveRecord::Base
  belongs_to :ab_test_model

  validates :variant, presence: true, inclusion: { in: %w[champion challenger] }
  validates :version_id, presence: true
  validates :timestamp, presence: true

  before_validation :set_defaults

  # Scopes
  scope :champion, -> { where(variant: "champion") }
  scope :challenger, -> { where(variant: "challenger") }
  scope :with_decisions, -> { where.not(decision_result: nil) }
  scope :recent, -> { order(timestamp: :desc) }
  scope :for_user, ->(user_id) { where(user_id: user_id) }

  serialize :context, JSON

  # Check if decision has been recorded
  def decision_recorded?
    decision_result.present?
  end

  # Get the test this assignment belongs to
  def test
    ab_test_model
  end

  # Record decision result
  def record_decision!(decision, confidence_score)
    update!(
      decision_result: decision,
      confidence: confidence_score
    )
  end

  private

  def set_defaults
    self.timestamp ||= Time.current
    self.context ||= {}
  end
end
