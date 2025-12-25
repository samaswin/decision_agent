# frozen_string_literal: true

class CreateDecisionAgentMonitoringTables < ActiveRecord::Migration[7.0]
  def change
    # Decision logs table
    create_table :decision_logs do |t|
      t.string :decision, null: false
      t.float :confidence
      t.integer :evaluations_count, default: 0
      t.float :duration_ms
      t.string :status # success, failure, error
      t.text :context # JSON
      t.text :metadata # JSON

      t.timestamps
    end

    add_index :decision_logs, :decision
    add_index :decision_logs, :status
    add_index :decision_logs, :confidence
    add_index :decision_logs, :created_at
    add_index :decision_logs, [:decision, :created_at]
    add_index :decision_logs, [:status, :created_at]

    # Evaluation metrics table
    create_table :evaluation_metrics do |t|
      t.references :decision_log, foreign_key: true, index: true
      t.string :evaluator_name, null: false
      t.float :score
      t.boolean :success
      t.float :duration_ms
      t.text :details # JSON

      t.timestamps
    end

    add_index :evaluation_metrics, :evaluator_name
    add_index :evaluation_metrics, :success
    add_index :evaluation_metrics, :created_at
    add_index :evaluation_metrics, [:evaluator_name, :created_at]
    add_index :evaluation_metrics, [:evaluator_name, :success]

    # Performance metrics table
    create_table :performance_metrics do |t|
      t.string :operation, null: false
      t.float :duration_ms
      t.string :status # success, failure, error
      t.text :metadata # JSON

      t.timestamps
    end

    add_index :performance_metrics, :operation
    add_index :performance_metrics, :status
    add_index :performance_metrics, :duration_ms
    add_index :performance_metrics, :created_at
    add_index :performance_metrics, [:operation, :created_at]
    add_index :performance_metrics, [:status, :created_at]

    # Error metrics table
    create_table :error_metrics do |t|
      t.string :error_type, null: false
      t.text :message
      t.text :stack_trace # JSON array
      t.string :severity # low, medium, high, critical
      t.text :context # JSON

      t.timestamps
    end

    add_index :error_metrics, :error_type
    add_index :error_metrics, :severity
    add_index :error_metrics, :created_at
    add_index :error_metrics, [:error_type, :created_at]
    add_index :error_metrics, [:severity, :created_at]

    # PostgreSQL-specific optimizations (optional)
    if adapter_name == "PostgreSQL"
      # Partial indexes for active records (recent data)
      execute <<-SQL
        CREATE INDEX index_decision_logs_on_recent
        ON decision_logs (created_at DESC)
        WHERE created_at >= NOW() - INTERVAL '7 days';
      SQL

      execute <<-SQL
        CREATE INDEX index_performance_metrics_on_recent
        ON performance_metrics (created_at DESC)
        WHERE created_at >= NOW() - INTERVAL '7 days';
      SQL

      execute <<-SQL
        CREATE INDEX index_error_metrics_on_recent_critical
        ON error_metrics (created_at DESC)
        WHERE severity IN ('high', 'critical') AND created_at >= NOW() - INTERVAL '7 days';
      SQL

      # Consider table partitioning for large-scale deployments
      # Example: Partition by month for decision_logs
      # This is commented out by default - enable if needed
      # execute <<-SQL
      #   CREATE TABLE decision_logs_partitioned (LIKE decision_logs INCLUDING ALL)
      #   PARTITION BY RANGE (created_at);
      # SQL
    end
  end
end
