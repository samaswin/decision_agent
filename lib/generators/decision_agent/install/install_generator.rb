# frozen_string_literal: true

require "rails/generators"
require "rails/generators/migration"

module DecisionAgent
  module Generators
    class InstallGenerator < Rails::Generators::Base
      include Rails::Generators::Migration

      source_root File.expand_path("templates", __dir__)

      desc "Installs DecisionAgent models and migrations for Rails"

      class_option :monitoring, type: :boolean,
                                default: false,
                                desc: "Install monitoring tables and models for persistent metrics storage"

      class_option :ab_testing, type: :boolean,
                                default: false,
                                desc: "Install A/B testing tables and models for variant testing"

      def self.next_migration_number(dirname)
        next_migration_number = current_migration_number(dirname) + 1
        ActiveRecord::Migration.next_migration_number(next_migration_number)
      end

      def copy_migration
        migration_template "migration.rb",
                           "db/migrate/create_decision_agent_tables.rb",
                           migration_version: migration_version

        if options[:monitoring]
          migration_template "monitoring_migration.rb",
                             "db/migrate/create_decision_agent_monitoring_tables.rb",
                             migration_version: migration_version
        end

        return unless options[:ab_testing]

        migration_template "ab_testing_migration.rb",
                           "db/migrate/create_decision_agent_ab_testing_tables.rb",
                           migration_version: migration_version
      end

      def copy_models
        copy_file "rule.rb", "app/models/rule.rb"
        copy_file "rule_version.rb", "app/models/rule_version.rb"

        if options[:monitoring]
          copy_file "decision_log.rb", "app/models/decision_log.rb"
          copy_file "evaluation_metric.rb", "app/models/evaluation_metric.rb"
          copy_file "performance_metric.rb", "app/models/performance_metric.rb"
          copy_file "error_metric.rb", "app/models/error_metric.rb"
        end

        return unless options[:ab_testing]

        copy_file "ab_test_model.rb", "app/models/ab_test_model.rb"
        copy_file "ab_test_assignment_model.rb", "app/models/ab_test_assignment_model.rb"
      end

      def copy_rake_tasks
        copy_file "decision_agent_tasks.rake", "lib/tasks/decision_agent.rake" if options[:monitoring]
        copy_file "ab_testing_tasks.rake", "lib/tasks/ab_testing.rake" if options[:ab_testing]
      end

      def show_readme
        readme "README" if behavior == :invoke
      end

      private

      def migration_version
        "[#{Rails::VERSION::MAJOR}.#{Rails::VERSION::MINOR}]"
      end
    end
  end
end
