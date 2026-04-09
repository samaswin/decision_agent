# frozen_string_literal: true

require "rails/generators"
require "rails/generators/migration"

module DecisionAgent
  module Generators
    # Standalone generator that installs only the versioning tables and models.
    #
    # Usage:
    #   rails generate decision_agent:versioning_migration
    #
    # This is a focused alternative to the full install generator. It generates:
    #   - db/migrate/create_decision_agent_versioning_tables.rb
    #   - app/models/rule_version.rb
    #   - app/models/rule_version_tag.rb
    class VersioningMigrationGenerator < Rails::Generators::Base
      include Rails::Generators::Migration

      source_root File.expand_path("../../install/templates", __dir__)

      desc "Generates the DecisionAgent versioning migration and ActiveRecord models"

      def self.next_migration_number(dirname)
        next_migration_number = current_migration_number(dirname) + 1
        ActiveRecord::Migration.next_migration_number(next_migration_number)
      end

      def copy_migration
        migration_template "versioning_migration.rb",
                           "db/migrate/create_decision_agent_versioning_tables.rb",
                           migration_version: migration_version
      end

      def copy_models
        copy_file "rule_version.rb",     "app/models/rule_version.rb"
        copy_file "rule_version_tag.rb", "app/models/rule_version_tag.rb"
      end

      def show_readme
        say "\n"
        say "DecisionAgent versioning tables generated successfully!", :green
        say "\nNext steps:"
        say "  1. Run migrations:      rails db:migrate"
        say "  2. Verify models:       RuleVersion, RuleVersionTag"
        say "  3. Use the adapter:     DecisionAgent::Versioning::ActiveRecordAdapter.new"
        say "\nSee docs/VERSIONING.md for configuration and usage examples."
      end

      private

      def migration_version
        "[#{Rails::VERSION::MAJOR}.#{Rails::VERSION::MINOR}]"
      end
    end
  end
end
