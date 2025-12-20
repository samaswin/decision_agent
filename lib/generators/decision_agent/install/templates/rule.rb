class Rule < ApplicationRecord
  has_many :rule_versions, primary_key: :rule_id, foreign_key: :rule_id, dependent: :destroy

  validates :rule_id, presence: true, uniqueness: true
  validates :ruleset, presence: true
  validates :status, inclusion: { in: %w[active inactive archived] }

  scope :active, -> { where(status: 'active') }
  scope :by_ruleset, ->(ruleset) { where(ruleset: ruleset) }

  # Get the active version for this rule
  def active_version
    rule_versions.find_by(status: 'active')
  end

  # Get all versions ordered by version number
  def versions
    rule_versions.order(version_number: :desc)
  end

  # Create a new version
  def create_version(content:, created_by: 'system', changelog: nil)
    DecisionAgent::Versioning::VersionManager.new.save_version(
      rule_id: rule_id,
      rule_content: content,
      created_by: created_by,
      changelog: changelog
    )
  end
end
