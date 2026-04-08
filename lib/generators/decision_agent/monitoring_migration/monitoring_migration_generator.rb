# frozen_string_literal: true

require "rails/generators"
require "rails/generators/migration"

module DecisionAgent
  module Generators
    # Standalone generator that installs only the monitoring tables and models.
    #
    # Usage:
    #   rails generate decision_agent:monitoring_migration
    #
    # This is a focused alternative to the full install generator's --monitoring
    # flag. It generates:
    #   - db/migrate/create_decision_agent_monitoring_tables.rb
    #   - app/models/decision_log.rb
    #   - app/models/evaluation_metric.rb
    #   - app/models/performance_metric.rb
    #   - app/models/error_metric.rb
    #   - lib/tasks/decision_agent.rake
    class MonitoringMigrationGenerator < Rails::Generators::Base
      include Rails::Generators::Migration

      source_root File.expand_path("../../install/templates", __dir__)

      desc "Generates the DecisionAgent monitoring migration and ActiveRecord models"

      def self.next_migration_number(dirname)
        next_migration_number = current_migration_number(dirname) + 1
        ActiveRecord::Migration.next_migration_number(next_migration_number)
      end

      def copy_migration
        migration_template "monitoring_migration.rb",
                           "db/migrate/create_decision_agent_monitoring_tables.rb",
                           migration_version: migration_version
      end

      def copy_models
        copy_file "decision_log.rb",        "app/models/decision_log.rb"
        copy_file "evaluation_metric.rb",   "app/models/evaluation_metric.rb"
        copy_file "performance_metric.rb",  "app/models/performance_metric.rb"
        copy_file "error_metric.rb",        "app/models/error_metric.rb"
      end

      def copy_rake_tasks
        copy_file "decision_agent_tasks.rake", "lib/tasks/decision_agent.rake"
      end

      def show_readme
        say "\n"
        say "DecisionAgent monitoring tables generated successfully!", :green
        say "\nNext steps:"
        say "  1. Run migrations:    rails db:migrate"
        say "  2. Verify models:     DecisionLog, EvaluationMetric, PerformanceMetric, ErrorMetric"
        say "  3. Use the adapter:   DecisionAgent::Monitoring::Storage::ActiveRecordAdapter.new"
        say "\nSee docs/PERSISTENT_MONITORING.md for configuration and query examples."
      end

      private

      def migration_version
        "[#{Rails::VERSION::MAJOR}.#{Rails::VERSION::MINOR}]"
      end
    end
  end
end
