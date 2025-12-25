require "active_record"

module DecisionAgent
  module ABTesting
    module Storage
      # ActiveRecord storage adapter for A/B tests
      # Requires Rails models: ABTestModel, ABTestAssignmentModel
      class ActiveRecordAdapter < Adapter
        # Check if ActiveRecord models are available
        def self.available?
          defined?(::ABTestModel) && defined?(::ABTestAssignmentModel)
        end

        def initialize
          super
          raise "ActiveRecord models not available. Run the generator to create them." unless self.class.available?
        end

        def save_test(test)
          record = ::ABTestModel.create!(
            name: test.name,
            champion_version_id: test.champion_version_id,
            challenger_version_id: test.challenger_version_id,
            traffic_split: test.traffic_split,
            start_date: test.start_date,
            end_date: test.end_date,
            status: test.status
          )

          to_ab_test(record)
        end

        def get_test(test_id)
          record = ::ABTestModel.find_by(id: test_id)
          record ? to_ab_test(record) : nil
        end

        def update_test(test_id, attributes)
          record = ::ABTestModel.find(test_id)
          record.update!(attributes)
          to_ab_test(record)
        end

        def list_tests(status: nil, limit: nil)
          query = ::ABTestModel.order(created_at: :desc)
          query = query.where(status: status) if status
          query = query.limit(limit) if limit

          query.map { |record| to_ab_test(record) }
        end

        def save_assignment(assignment)
          record = ::ABTestAssignmentModel.create!(
            ab_test_id: assignment.ab_test_id,
            user_id: assignment.user_id,
            variant: assignment.variant.to_s,
            version_id: assignment.version_id,
            decision_result: assignment.decision_result,
            confidence: assignment.confidence,
            context: assignment.context,
            timestamp: assignment.timestamp
          )

          to_assignment(record)
        end

        def update_assignment(assignment_id, attributes)
          record = ::ABTestAssignmentModel.find(assignment_id)
          record.update!(attributes)
          to_assignment(record)
        end

        def get_assignments(test_id)
          ::ABTestAssignmentModel
            .where(ab_test_id: test_id)
            .order(timestamp: :desc)
            .map { |record| to_assignment(record) }
        end

        # rubocop:disable Naming/PredicateMethod
        def delete_test(test_id)
          record = ::ABTestModel.find(test_id)
          ::ABTestAssignmentModel.where(ab_test_id: test_id).delete_all
          record.destroy
          true
        end
        # rubocop:enable Naming/PredicateMethod

        # Get statistics from database
        def get_test_statistics(test_id)
          assignments = ::ABTestAssignmentModel.where(ab_test_id: test_id)

          {
            total_assignments: assignments.count,
            champion_count: assignments.where(variant: "champion").count,
            challenger_count: assignments.where(variant: "challenger").count,
            with_decisions: assignments.where.not(decision_result: nil).count,
            avg_confidence: assignments.where.not(confidence: nil).average(:confidence)&.to_f
          }
        end

        private

        def to_ab_test(record)
          ABTest.new(
            id: record.id,
            name: record.name,
            champion_version_id: record.champion_version_id,
            challenger_version_id: record.challenger_version_id,
            traffic_split: parse_traffic_split(record.traffic_split),
            start_date: record.start_date,
            end_date: record.end_date,
            status: record.status
          )
        end

        def to_assignment(record)
          ABTestAssignment.new(
            id: record.id,
            ab_test_id: record.ab_test_id,
            user_id: record.user_id,
            variant: record.variant.to_sym,
            version_id: record.version_id,
            timestamp: record.timestamp,
            decision_result: record.decision_result,
            confidence: record.confidence,
            context: parse_context(record.context)
          )
        end

        def parse_traffic_split(value)
          case value
          when Hash
            value.symbolize_keys
          when String
            JSON.parse(value).symbolize_keys
          else
            value
          end
        end

        def parse_context(value)
          case value
          when Hash
            value
          when String
            JSON.parse(value)
          else
            {}
          end
        end
      end
    end
  end
end
