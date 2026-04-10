# frozen_string_literal: true

require_relative "adapter"
require_relative "file_storage_adapter"

module DecisionAgent
  module Versioning
    # ActiveRecord-based version storage adapter for Rails applications
    # Requires ActiveRecord models to be set up in the Rails app
    class ActiveRecordAdapter < Adapter
      include StatusValidator

      def initialize
        return if defined?(ActiveRecord)

        raise DecisionAgent::ConfigurationError,
              "ActiveRecord is not available. Please ensure Rails/ActiveRecord is loaded."
      end

      def create_version(rule_id:, content:, metadata: {})
        # Validate status if provided
        status = metadata[:status] || "active"
        validate_status!(status)

        # Retry on SQLite busy exceptions (common with concurrent operations)
        retry_with_backoff(max_retries: 10) do
          # Use a transaction with pessimistic locking to prevent race conditions
          version = nil

          rule_version_class.transaction do
            # Lock the last version for this rule to prevent concurrent reads
            # This ensures only one thread can calculate the next version number at a time
            last_version = rule_version_class.where(rule_id: rule_id)
                                             .order(version_number: :desc)
                                             .lock
                                             .first
            next_version_number = last_version ? last_version.version_number + 1 : 1

            # Deactivate previous active versions
            # Use update_all for better concurrency (avoids SQLite locking issues)
            # Status "archived" is valid, so no need to trigger validations
            rule_version_class.where(rule_id: rule_id, status: "active")
                              .update_all(status: "archived")

            # Create new version
            version = rule_version_class.create!(
              rule_id: rule_id,
              version_number: next_version_number,
              content: content.to_json,
              created_by: metadata[:created_by] || "system",
              changelog: metadata[:changelog] || "Version #{next_version_number}",
              status: status
            )
          end

          serialize_version(version)
        end
      end

      def list_versions(rule_id:, limit: nil)
        query = rule_version_class.where(rule_id: rule_id)
                                  .order(version_number: :desc)
        query = query.limit(limit) if limit

        query.map { |v| serialize_version(v) }
      end

      def list_all_versions(limit: nil)
        query = rule_version_class.order(created_at: :desc)
        query = query.limit(limit) if limit

        query.map { |v| serialize_version(v) }
      end

      def get_version(version_id:)
        version = rule_version_class.find_by(id: version_id)
        version ? serialize_version(version) : nil
      end

      def get_version_by_number(rule_id:, version_number:)
        version = rule_version_class.find_by(
          rule_id: rule_id,
          version_number: version_number
        )
        version ? serialize_version(version) : nil
      end

      def get_active_version(rule_id:)
        version = rule_version_class.find_by(rule_id: rule_id, status: "active")
        version ? serialize_version(version) : nil
      end

      def activate_version(version_id:)
        # Retry on SQLite busy exceptions (common with concurrent operations)
        retry_with_backoff(max_retries: 10) do
          version = nil

          rule_version_class.transaction do
            # Find and lock the version to activate
            version = rule_version_class.lock.find(version_id)

            # Deactivate all other versions for this rule within the same transaction
            # The lock ensures only one thread can perform this operation at a time
            # Use update_all for better concurrency (avoids SQLite locking issues)
            # Status "archived" is valid, so no need to trigger validations
            rule_version_class.where(rule_id: version.rule_id, status: "active")
                              .where.not(id: version_id)
                              .update_all(status: "archived")

            # Activate this version
            version.update!(status: "active")
          end

          serialize_version(version)
        end
      end

      def delete_version(version_id:)
        version = rule_version_class.find_by(id: version_id)

        # Version not found
        raise DecisionAgent::NotFoundError, "Version not found: #{version_id}" unless version

        # Prevent deletion of active versions
        raise DecisionAgent::ValidationError, "Cannot delete active version. Please activate another version first." if version.status == "active"

        # Delete the version
        version.destroy
        true
      rescue ActiveRecord::RecordNotFound
        raise DecisionAgent::NotFoundError, "Version not found: #{version_id}"
      end

      # Create (or update) a named tag pointing to a specific version.
      # Tags are unique per model; calling this with an existing name re-points the tag.
      def create_tag(model_id:, version_id:, name:)
        raise DecisionAgent::ValidationError, "Tag name cannot be blank" if name.nil? || name.to_s.strip.empty?
        raise DecisionAgent::NotFoundError, "Version not found: #{version_id}" unless get_version(version_id: version_id)

        retry_with_backoff(max_retries: 10) do
          tag = nil
          rule_version_tag_class.transaction do
            existing = rule_version_tag_class.find_by(model_id: model_id, name: name)
            if existing
              existing.update!(version_id: version_id)
              tag = existing.reload
            else
              tag = rule_version_tag_class.create!(model_id: model_id, name: name, version_id: version_id)
            end
          end
          serialize_tag(tag)
        end
      end

      # Retrieve a tag by name for a given model.
      def get_tag(model_id:, name:)
        tag = rule_version_tag_class.find_by(model_id: model_id, name: name)
        tag ? serialize_tag(tag) : nil
      end

      # List all tags for a given model, sorted by name.
      def list_tags(model_id:)
        rule_version_tag_class.where(model_id: model_id).order(name: :asc).map { |t| serialize_tag(t) }
      end

      # Delete a tag by name. Returns true if deleted, false if the tag did not exist.
      def delete_tag(model_id:, name:)
        tag = rule_version_tag_class.find_by(model_id: model_id, name: name)
        return false unless tag

        tag.destroy
        true
      end

      private

      def rule_version_class
        # Look for the RuleVersion model in the main app
        if defined?(::RuleVersion)
          ::RuleVersion
        else
          raise DecisionAgent::ConfigurationError,
                "RuleVersion model not found. Please run the generator to create it."
        end
      end

      def rule_version_tag_class
        if defined?(::RuleVersionTag)
          ::RuleVersionTag
        else
          raise DecisionAgent::ConfigurationError,
                "RuleVersionTag model not found. Please run the versioning generator to create it."
        end
      end

      # Retry database operations that may encounter SQLite busy exceptions
      # This is especially important for concurrent operations on different rules
      def retry_with_backoff(max_retries: 10, base_delay: 0.01)
        retries = 0
        begin
          yield
        rescue ActiveRecord::StatementInvalid => e
          # Check if it's a SQLite busy exception
          # Handle different SQLite adapter implementations
          is_busy = begin
            # Check the underlying exception type
            cause = e.cause
            if cause
              cause.class.name.include?("BusyException") ||
                cause.class.name.include?("SQLite3::BusyException")
            else
              false
            end
          rescue StandardError => cause_check_error
            warn "[DecisionAgent] Error checking busy exception cause: #{cause_check_error.message}"
            false
          end || e.message.include?("database is locked") ||
                    e.message.include?("SQLite3::BusyException") ||
                    e.message.include?("BusyException")

          raise unless is_busy && retries < max_retries

          retries += 1
          # Exponential backoff with jitter
          delay = (base_delay * (2**retries)) + (rand * base_delay)
          sleep(delay)
          retry
        end
      end

      def serialize_version(version)
        # Parse JSON content with proper error handling
        parsed_content = begin
          JSON.parse(version.content)
        rescue JSON::ParserError => e
          raise DecisionAgent::ValidationError,
                "Invalid JSON in version #{version.id} for rule #{version.rule_id}: #{e.message}"
        rescue TypeError, NoMethodError
          raise DecisionAgent::ValidationError,
                "Invalid content in version #{version.id} for rule #{version.rule_id}: content is nil or not a string"
        end

        {
          id: version.id,
          rule_id: version.rule_id,
          version_number: version.version_number,
          content: parsed_content,
          created_by: version.created_by,
          created_at: version.created_at,
          changelog: version.changelog,
          status: version.status
        }
      end

      def serialize_tag(tag)
        {
          name: tag.name,
          version_id: tag.version_id,
          created_at: tag.updated_at || tag.created_at
        }
      end
    end
  end
end
