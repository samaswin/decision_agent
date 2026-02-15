# frozen_string_literal: true

require "parslet"
require_relative "../errors"

module DecisionAgent
  module Dmn
    module Feel
      # Transforms Parslet parse tree into AST
      class Transformer < Parslet::Transform
        # Extract a context entry key from various node representations
        def self.extract_entry_key(key_node)
          return key_node.to_s if key_node.is_a?(Parslet::Slice)
          return key_node.to_s unless key_node.is_a?(Hash)

          case key_node[:type]
          when :field      then key_node[:name].to_s
          when :string     then key_node[:value].to_s
          when :identifier then key_node[:name].to_s
          else
            key_node[:identifier]&.to_s || key_node[:string]&.to_s || key_node.to_s
          end
        end

        # Extract a name string from a node that may be a Hash or raw value
        def self.extract_name(name_node)
          return name_node.to_s.strip unless name_node.is_a?(Hash)
          return name_node[:name].to_s.strip if name_node[:type] == :field

          name_node[:identifier]&.to_s&.strip || name_node.to_s
        end

        # Apply a single postfix operation to the current AST node
        def self.apply_postfix_op(current, op)
          return current unless op.is_a?(Hash)

          if op[:property_access]
            { type: :property_access, object: current, property: op[:property_access][:property][:identifier].to_s }
          elsif op[:function_call]
            { type: :function_call, name: current, arguments: op[:function_call][:arguments] || [] }
          elsif op[:filter]
            { type: :filter, list: current, condition: op[:filter][:filter] }
          else
            current
          end
        end

        # Extract variable name from a potentially transformed node
        def self.extract_variable_name(var_node)
          if var_node.is_a?(Hash) && var_node[:type] == :field
            var_node[:name]
          elsif var_node.is_a?(Hash) && var_node[:identifier]
            var_node[:identifier].to_s
          else
            var_node.to_s
          end
        end

        # Literals
        rule(null: simple(:_)) { { type: :null, value: nil } }

        rule(boolean: simple(:val)) do
          { type: :boolean, value: val.to_s == "true" }
        end

        rule(number: simple(:val)) do
          str = val.to_s
          value = str.include?(".") ? str.to_f : str.to_i
          { type: :number, value: value }
        end

        rule(string: simple(:val)) do
          { type: :string, value: val.to_s }
        end

        # Argument wrapper (unwrap the arg node to get the inner expression)
        rule(arg: subtree(:expr)) do
          expr
        end

        # List literal
        rule(list_literal: { list: subtree(:items) }) do
          items_array = case items
                        when Array then items
                        when Hash then [items]
                        when nil then []
                        else [items]
                        end
          { type: :list_literal, elements: items_array }
        end

        # Context entry (unwrap the entry wrapper)
        rule(entry: { key: subtree(:k), value: subtree(:v) }) do
          { key: k, value: v }
        end

        # Context literal
        rule(context_literal: { context: subtree(:entries) }) do
          entries_array = case entries
                          when Array then entries
                          when Hash then [entries]
                          when nil then []
                          else [entries]
                          end

          pairs = entries_array.map do |entry|
            [Transformer.extract_entry_key(entry[:key]), entry[:value]]
          end

          { type: :context_literal, pairs: pairs }
        end

        # Range literal
        rule(range: {
               start_bracket: simple(:sb),
               start: subtree(:s),
               end: subtree(:e),
               end_bracket: simple(:eb)
             }) do
          {
            type: :range,
            start: s,
            end: e,
            start_inclusive: sb.to_s == "[",
            end_inclusive: eb.to_s == "]"
          }
        end

        # Identifier
        rule(identifier: simple(:name)) do
          { type: :field, name: name.to_s.strip }
        end

        # Identifier or function call (with arguments)
        rule(identifier_or_call: { name: subtree(:name), arguments: subtree(:args) }) do
          # It's a function call
          args_array = case args
                       when Array then args
                       when Hash then args.empty? ? [] : [args]
                       when nil then []
                       else [args]
                       end

          {
            type: :function_call,
            name: Transformer.extract_name(name),
            arguments: args_array
          }
        end

        # Identifier or function call (just identifier, no arguments)
        rule(identifier_or_call: { name: subtree(:name) }) do
          { type: :field, name: Transformer.extract_name(name) }
        end

        # Comparison operations
        rule(comparison: { left: subtree(:l), op: simple(:o), right: subtree(:r) }) do
          {
            type: :comparison,
            operator: o.to_s,
            left: l,
            right: r
          }
        end

        # Between expression
        rule(between: { value: subtree(:val), min: subtree(:min), max: subtree(:max) }) do
          {
            type: :between,
            value: val,
            min: min,
            max: max
          }
        end

        # In expression
        rule(in: { value: subtree(:val), list: subtree(:list) }) do
          {
            type: :in,
            value: val,
            list: list
          }
        end

        # Instance of
        rule(instance_of: { value: subtree(:val), type: simple(:t) }) do
          {
            type: :instance_of,
            value: val,
            type_name: t.to_s
          }
        end

        # Arithmetic operations
        rule(arithmetic: { left: subtree(:l), op: simple(:o), right: subtree(:r) }) do
          {
            type: :arithmetic,
            operator: o.to_s,
            left: l,
            right: r
          }
        end

        rule(term: { left: subtree(:l), op: simple(:o), right: subtree(:r) }) do
          {
            type: :arithmetic,
            operator: o.to_s,
            left: l,
            right: r
          }
        end

        rule(exponentiation: { left: subtree(:l), op: simple(:o), right: subtree(:r) }) do
          {
            type: :arithmetic,
            operator: o.to_s,
            left: l,
            right: r
          }
        end

        # Unary operations
        rule(unary: { op: simple(:o), operand: subtree(:operand) }) do
          if o.to_s == "not"
            {
              type: :logical,
              operator: "not",
              operand: operand
            }
          elsif o.to_s == "-" && operand.is_a?(Hash) && operand[:type] == :number
            # Special case: unary minus on a number literal -> negative number literal
            {
              type: :number,
              value: -operand[:value]
            }
          else
            {
              type: :arithmetic,
              operator: "negate",
              operand: operand
            }
          end
        end

        # Logical operations
        rule(or: { left: subtree(:l), or_ops: subtree(:ops) }) do
          ops_array = Array(ops)
          # Build nested or structure
          ops_array.reduce(l) do |left_side, op|
            {
              type: :logical,
              operator: "or",
              left: left_side,
              right: op[:right]
            }
          end
        end

        rule(and: { left: subtree(:l), and_ops: subtree(:ops) }) do
          ops_array = Array(ops)
          # Build nested and structure
          ops_array.reduce(l) do |left_side, op|
            {
              type: :logical,
              operator: "and",
              left: left_side,
              right: op[:right]
            }
          end
        end

        # Postfix operations (property access, function calls, filters)
        rule(postfix: { base: subtree(:base), postfix_ops: subtree(:ops) }) do
          Array(ops).reduce(base) { |current, op| Transformer.apply_postfix_op(current, op) }
        end

        # If-then-else conditional
        rule(condition: subtree(:c), then_expr: subtree(:t), else_expr: subtree(:e)) do
          {
            type: :conditional,
            condition: c,
            then_expr: t,
            else_expr: e
          }
        end

        # Quantified expressions
        rule(quantifier: simple(:q), var: subtree(:v), list: subtree(:l), condition: subtree(:c)) do
          {
            type: :quantified,
            quantifier: q.to_s,
            variable: Transformer.extract_variable_name(v),
            list: l,
            condition: c
          }
        end

        # For expression
        rule(var: subtree(:v), list: subtree(:l), return_expr: subtree(:r)) do
          {
            type: :for,
            variable: Transformer.extract_variable_name(v),
            list: l,
            return_expr: r
          }
        end

        # Function definition
        rule(function_def: { params: subtree(:params), body: subtree(:body) }) do
          params_array = case params
                         when Array then params.map { |p| p[:param][:identifier].to_s }
                         when Hash then [params[:param][:identifier].to_s]
                         when nil then []
                         else []
                         end

          {
            type: :function_definition,
            parameters: params_array,
            body: body
          }
        end
      end
    end
  end
end
