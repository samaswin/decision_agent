# frozen_string_literal: true

class CreateDecisionAgentVersioningTables < ActiveRecord::Migration[7.0]
  def change
    # Rule versions table — stores the full content of each version as JSON
    create_table :rule_versions do |t|
      t.string  :rule_id,        null: false, index: true
      t.integer :version_number, null: false
      t.text    :content,        null: false # JSON rule definition
      t.string  :created_by,     null: false, default: "system"
      t.text    :changelog
      t.string  :status, null: false, default: "draft" # draft, active, archived
      t.timestamps
    end

    # ✅ CRITICAL: Unique constraint prevents duplicate version numbers per rule.
    # This protects against race conditions in concurrent version creation.
    add_index :rule_versions, %i[rule_id version_number], unique: true

    # Index for efficient queries by rule_id and status
    add_index :rule_versions, %i[rule_id status]

    # Optional: Partial unique index for PostgreSQL to enforce one active version per rule
    # Uncomment if using PostgreSQL:
    # add_index :rule_versions, [:rule_id, :status],
    #           unique: true,
    #           where: "status = 'active'",
    #           name: 'index_rule_versions_one_active_per_rule'

    # Version tags table — named pointers to specific versions (unique per model + name).
    # version_id is intentionally NOT a foreign key so tags survive version deletion.
    create_table :rule_version_tags do |t|
      t.string :model_id,   null: false
      t.string :name,       null: false
      t.bigint :version_id, null: false
      t.timestamps
    end

    # ✅ CRITICAL: Unique constraint — one tag name per model
    add_index :rule_version_tags, %i[model_id name], unique: true
    # Index for efficient tag listing per model
    add_index :rule_version_tags, :model_id
  end
end
