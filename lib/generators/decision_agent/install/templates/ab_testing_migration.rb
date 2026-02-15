# frozen_string_literal: true

class CreateDecisionAgentABTestingTables < ActiveRecord::Migration[7.0]
  def change
    # A/B Tests table
    create_table :ab_test_models do |t|
      t.string :name, null: false
      t.string :champion_version_id, null: false
      t.string :challenger_version_id, null: false
      t.text :traffic_split, null: false # JSON: { champion: 90, challenger: 10 }
      t.datetime :start_date
      t.datetime :end_date
      t.string :status, null: false, default: "scheduled" # scheduled, running, completed, cancelled
      t.timestamps
    end

    add_index :ab_test_models, :status
    add_index :ab_test_models, :start_date
    add_index :ab_test_models, %i[status start_date], name: "index_ab_tests_on_status_and_start_date"

    # A/B Test Assignments table
    create_table :ab_test_assignment_models do |t|
      t.references :ab_test_model, null: false, foreign_key: true, index: true
      t.string :user_id # Optional: for consistent assignment to same users
      t.string :variant, null: false # "champion" or "challenger"
      t.string :version_id, null: false
      t.datetime :timestamp, null: false, default: -> { "CURRENT_TIMESTAMP" }

      # Decision results (populated after decision is made)
      t.string :decision_result
      t.float :confidence
      t.text :context # JSON: additional context

      t.timestamps
    end

    add_index :ab_test_assignment_models, :user_id
    add_index :ab_test_assignment_models, :variant
    add_index :ab_test_assignment_models, :timestamp
    add_index :ab_test_assignment_models, %i[ab_test_model_id variant], name: "index_assignments_on_test_and_variant"

    # Optional: Index for querying assignments with decisions
    add_index :ab_test_assignment_models, :decision_result, where: "decision_result IS NOT NULL", name: "index_assignments_with_decisions"
  end
end
