# frozen_string_literal: true

require_relative "feel/evaluator"
require_relative "errors"

module DecisionAgent
  module Dmn
    # Represents a node in a decision tree
    class TreeNode
      attr_reader :id, :label, :condition, :decision, :children
      attr_accessor :parent

      def initialize(id:, label: nil, condition: nil, decision: nil)
        @id = id
        @label = label
        @condition = condition # FEEL expression to evaluate
        @decision = decision   # Output decision if this is a leaf node
        @children = []
        @parent = nil
      end

      def add_child(node)
        node.parent = self
        @children << node
      end

      def leaf?
        @children.empty?
      end

      def to_h
        {
          id: @id,
          label: @label,
          condition: @condition,
          decision: @decision,
          children: @children.map(&:to_h)
        }
      end
    end

    # Evaluates decision trees
    class DecisionTree
      attr_reader :id, :name, :root

      def initialize(id:, name:, root: nil)
        @id = id
        @name = name
        @root = root || TreeNode.new(id: "root", label: "Root")
        @feel_evaluator = Feel::Evaluator.new
      end

      # Evaluate the decision tree with given context
      def evaluate(context)
        traverse(@root, context)
      end

      # Build a decision tree from a hash representation
      def self.from_hash(hash)
        tree = new(id: hash[:id], name: hash[:name])
        tree.instance_variable_set(:@root, build_node(hash[:root]))
        tree
      end

      # Convert tree to hash representation
      def to_h
        {
          id: @id,
          name: @name,
          root: @root.to_h
        }
      end

      # Get all leaf nodes (decision outcomes)
      def leaf_nodes
        collect_leaf_nodes(@root)
      end

      # Get tree depth
      def depth
        calculate_depth(@root)
      end

      # Get all paths from root to leaves
      def paths
        collect_paths(@root, [])
      end

      private

      def traverse(node, context)
        # If this is a leaf node, return the decision
        return node.decision if node.leaf?

        # Track if any condition was successfully evaluated
        any_condition_evaluated = false
        has_children_with_conditions = node.children.any?(&:condition)

        # Evaluate each child's condition until we find a match
        node.children.each do |child|
          next unless child.condition

          begin
            result = @feel_evaluator.evaluate(child.condition, "condition", context.to_h)
            any_condition_evaluated = true

            return traverse(child, context) if result
            # Condition matched, continue down this branch

            # Condition evaluated to false - check if this child has a false branch
            # If child has multiple leaf children with no conditions, take the second one
            if !child.leaf? && child.children.all? { |c| c.condition.nil? && c.leaf? } && child.children.size > 1
              return child.children[1].decision
            end
          rescue StandardError
            # If condition evaluation fails, skip this branch
            next
          end
        end

        # No matching condition found, check for a default branch (no condition)
        # Take default if: no children have conditions, OR at least one condition was successfully evaluated
        if !has_children_with_conditions || any_condition_evaluated
          default_child = node.children.find { |c| c.condition.nil? }
          return traverse(default_child, context) if default_child
        end

        # No match found
        nil
      end

      def self.build_node(hash)
        node = TreeNode.new(
          id: hash[:id],
          label: hash[:label],
          condition: hash[:condition],
          decision: hash[:decision]
        )

        hash[:children]&.each do |child_hash|
          node.add_child(build_node(child_hash))
        end

        node
      end

      def collect_leaf_nodes(node, leaves = [])
        if node.leaf?
          leaves << node
        else
          node.children.each { |child| collect_leaf_nodes(child, leaves) }
        end
        leaves
      end

      def calculate_depth(node, current_depth = 0)
        return current_depth if node.leaf?

        max_child_depth = node.children.map { |child| calculate_depth(child, current_depth + 1) }.max
        max_child_depth || current_depth
      end

      def collect_paths(node, current_path, paths = [])
        current_path += [node]

        if node.leaf?
          paths << current_path
        else
          node.children.each { |child| collect_paths(child, current_path, paths) }
        end

        paths
      end
    end

    # Parser for DMN decision trees (literal expressions)
    class DecisionTreeParser
      def self.parse(xml_element)
        # Parse DMN literal expression (decision tree representation)
        # This is a simplified parser - full DMN tree parsing would be more complex
        tree_id = xml_element["id"]
        tree_name = xml_element["name"] || tree_id

        DecisionTree.new(id: tree_id, name: tree_name)

        # Parse the tree structure from XML
        # Note: This is a placeholder for full DMN literal expression parsing
        # In a complete implementation, this would parse the DMN tree structure
      end
    end
  end
end
