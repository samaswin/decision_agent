# frozen_string_literal: true

# Stores named tags that point to a specific RuleVersion.
# A tag is a mutable pointer (re-pointing updates the existing row) but
# the content of the target version is immutable.
#
# version_id is stored as a plain integer without a foreign-key constraint
# so that tags survive the deletion of the version they originally pointed to.
class RuleVersionTag < ApplicationRecord
  validates :model_id, presence: true
  validates :name,     presence: true
  validates :version_id, presence: true
  validates :name, uniqueness: { scope: :model_id, message: "already exists for this model" }

  scope :for_model,    ->(model_id) { where(model_id: model_id) }
  scope :sorted_by_name, -> { order(name: :asc) }

  # Resolve the version this tag currently points to.
  # Returns nil if the version has been deleted.
  def version
    RuleVersion.find_by(id: version_id)
  end
end
