require "monitor"

module DecisionAgent
  module ABTesting
    module Storage
      # In-memory storage adapter for A/B tests
      # Useful for testing and development
      class MemoryAdapter < Adapter
        include MonitorMixin

        def initialize
          super
          @tests = {}
          @assignments = {}
          @test_id_counter = 0
          @assignment_id_counter = 0
        end

        def save_test(test)
          synchronize do
            @test_id_counter += 1
            test_data = test.to_h.merge(id: @test_id_counter)
            @tests[@test_id_counter] = test_data

            ABTest.new(**test_data)
          end
        end

        def get_test(test_id)
          synchronize do
            test_data = @tests[test_id.to_i]
            test_data ? ABTest.new(**test_data) : nil
          end
        end

        def update_test(test_id, attributes)
          synchronize do
            test_data = @tests[test_id.to_i]
            raise TestNotFoundError, "Test not found: #{test_id}" unless test_data

            test_data.merge!(attributes)
            @tests[test_id.to_i] = test_data

            ABTest.new(**test_data)
          end
        end

        def list_tests(status: nil, limit: nil)
          synchronize do
            tests = @tests.values

            tests = tests.select { |t| t[:status] == status } if status
            tests = tests.last(limit) if limit

            tests.map { |t| ABTest.new(**t) }
          end
        end

        def save_assignment(assignment)
          synchronize do
            @assignment_id_counter += 1
            assignment_data = assignment.to_h.merge(id: @assignment_id_counter)
            @assignments[@assignment_id_counter] = assignment_data

            ABTestAssignment.new(**assignment_data)
          end
        end

        def update_assignment(assignment_id, attributes)
          synchronize do
            assignment_data = @assignments[assignment_id.to_i]
            raise "Assignment not found: #{assignment_id}" unless assignment_data

            assignment_data.merge!(attributes)
            @assignments[assignment_id.to_i] = assignment_data

            ABTestAssignment.new(**assignment_data)
          end
        end

        def get_assignments(test_id)
          synchronize do
            assignments = @assignments.values.select { |a| a[:ab_test_id] == test_id }
            assignments.map { |a| ABTestAssignment.new(**a) }
          end
        end

        def delete_test(test_id)
          synchronize do
            @tests.delete(test_id.to_i)
            @assignments.delete_if { |_id, a| a[:ab_test_id] == test_id }
            true
          end
        end

        # Additional helper methods
        def clear!
          synchronize do
            @tests.clear
            @assignments.clear
            @test_id_counter = 0
            @assignment_id_counter = 0
          end
        end

        def test_count
          synchronize { @tests.size }
        end

        def assignment_count
          synchronize { @assignments.size }
        end
      end
    end
  end
end
