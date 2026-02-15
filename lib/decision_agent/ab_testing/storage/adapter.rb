# frozen_string_literal: true

module DecisionAgent
  module ABTesting
    module Storage
      # Base adapter interface for A/B test persistence
      class Adapter
        # Save an A/B test
        # @param test [ABTest] The test to save
        # @return [ABTest] The saved test with ID
        def save_test(test)
          raise NotImplementedError, "#{self.class} must implement #save_test"
        end

        # Get an A/B test by ID
        # @param test_id [String, Integer] The test ID
        # @return [ABTest, nil] The test or nil
        def get_test(test_id)
          raise NotImplementedError, "#{self.class} must implement #get_test"
        end

        # Update an A/B test
        # @param test_id [String, Integer] The test ID
        # @param attributes [Hash] Attributes to update
        # @return [ABTest] The updated test
        def update_test(test_id, attributes)
          raise NotImplementedError, "#{self.class} must implement #update_test"
        end

        # List A/B tests
        # @param status [String, nil] Filter by status
        # @param limit [Integer, nil] Limit results
        # @return [Array<ABTest>] Array of tests
        def list_tests(status: nil, limit: nil)
          raise NotImplementedError, "#{self.class} must implement #list_tests"
        end

        # Save an assignment
        # @param assignment [ABTestAssignment] The assignment to save
        # @return [ABTestAssignment] The saved assignment with ID
        def save_assignment(assignment)
          raise NotImplementedError, "#{self.class} must implement #save_assignment"
        end

        # Update an assignment
        # @param assignment_id [String, Integer] The assignment ID
        # @param attributes [Hash] Attributes to update
        # @return [ABTestAssignment] The updated assignment
        def update_assignment(assignment_id, attributes)
          raise NotImplementedError, "#{self.class} must implement #update_assignment"
        end

        # Get assignments for a test
        # @param test_id [String, Integer] The test ID
        # @return [Array<ABTestAssignment>] Array of assignments
        def get_assignments(test_id)
          raise NotImplementedError, "#{self.class} must implement #get_assignments"
        end

        # Delete a test and its assignments
        # @param test_id [String, Integer] The test ID
        # @return [Boolean] True if deleted
        def delete_test(test_id)
          raise NotImplementedError, "#{self.class} must implement #delete_test"
        end
      end
    end
  end
end
