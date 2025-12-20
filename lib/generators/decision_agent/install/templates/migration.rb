class CreateDecisionAgentTables < ActiveRecord::Migration[7.0]
  def change
    # Rules table
    create_table :rules do |t|
      t.string :rule_id, null: false, index: { unique: true }
      t.string :ruleset, null: false
      t.text :description
      t.string :status, default: 'active'
      t.timestamps
    end

    # Rule versions table
    create_table :rule_versions do |t|
      t.string :rule_id, null: false, index: true
      t.integer :version_number, null: false
      t.text :content, null: false  # JSON rule definition
      t.string :created_by, null: false, default: 'system'
      t.text :changelog
      t.string :status, null: false, default: 'draft'  # draft, active, archived
      t.timestamps
    end

    add_index :rule_versions, [:rule_id, :version_number], unique: true
    add_index :rule_versions, [:rule_id, :status]
  end
end
