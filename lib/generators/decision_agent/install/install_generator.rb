require 'rails/generators'
require 'rails/generators/migration'

module DecisionAgent
  module Generators
    class InstallGenerator < Rails::Generators::Base
      include Rails::Generators::Migration

      source_root File.expand_path('templates', __dir__)

      desc "Installs DecisionAgent models and migrations for Rails"

      def self.next_migration_number(dirname)
        next_migration_number = current_migration_number(dirname) + 1
        ActiveRecord::Migration.next_migration_number(next_migration_number)
      end

      def copy_migration
        migration_template "migration.rb",
                          "db/migrate/create_decision_agent_tables.rb",
                          migration_version: migration_version
      end

      def copy_models
        copy_file "rule.rb", "app/models/rule.rb"
        copy_file "rule_version.rb", "app/models/rule_version.rb"
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
