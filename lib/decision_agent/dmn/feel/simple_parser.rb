# frozen_string_literal: true

require_relative "../errors"
require_relative "types"

module DecisionAgent
  module Dmn
    module Feel
      # Simple regex-based parser for common FEEL expressions
      # Handles arithmetic, logical operators, and simple comparisons
      # Uses operator precedence climbing for correct evaluation order
      class SimpleParser
        ARITHMETIC_OPS = %w[+ - * / ** %].freeze
        LOGICAL_OPS = %w[and or].freeze
        COMPARISON_OPS = %w[>= <= != > < =].freeze

        # Operator precedence (higher number = higher precedence)
        PRECEDENCE = {
          "or" => 1,
          "and" => 2,
          "=" => 3,
          "!=" => 3,
          "<" => 4,
          "<=" => 4,
          ">" => 4,
          ">=" => 4,
          "+" => 5,
          "-" => 5,
          "*" => 6,
          "/" => 6,
          "%" => 6,
          "**" => 7
        }.freeze

        def initialize
          @tokens = []
          @position = 0
        end

        # Check if expression can be handled by simple parser
        def self.can_parse?(expression)
          expr = expression.to_s.strip
          # Can't handle: lists, contexts, functions, quantifiers, for expressions
          return false if expr.match?(/[\[{]/) # Lists or contexts
          return false if expr.match?(/\w+\s*\(/) # Function calls
          return false if expr.match?(/\b(some|every|for|if)\b/) # Complex constructs

          true
        end

        # Parse expression and return AST-like structure
        def parse(expression)
          expr = expression.to_s.strip
          raise DecisionAgent::Dmn::FeelParseError, "Empty expression" if expr.empty?

          @tokens = tokenize(expr)
          @position = 0

          parse_expression
        end

        private

        # Tokenize the expression
        def tokenize(expr)
          tokens = []
          i = 0

          while i < expr.length
            char = expr[i]

            if char.match?(/\s/)
              i += 1
              next
            end

            token, consumed = tokenize_char(expr, i, char, tokens)
            raise DecisionAgent::Dmn::FeelParseError, "Unexpected character: #{char} at position #{i}" unless token

            tokens << token
            i += consumed
          end

          tokens
        end

        # Dispatch tokenization for a single character position
        # Returns [token, chars_consumed] or [nil, 0] if unrecognized
        def tokenize_char(expr, pos, char, tokens)
          tokenize_multi_char_op(expr, pos) ||
            tokenize_number(expr, pos, char, tokens) ||
            tokenize_single_char_op(char) ||
            tokenize_string(expr, pos, char) ||
            tokenize_keyword(expr, pos, char) ||
            [nil, 0]
        end

        # Try to match multi-character operators (>=, <=, !=, **, and, or)
        def tokenize_multi_char_op(expr, pos)
          return nil unless pos + 1 < expr.length

          two_char = expr[pos, 2]
          return [{ type: :operator, value: two_char }, 2] if %w[>= <= != ** or].include?(two_char)
          return nil unless two_char == "an" && pos + 2 < expr.length && expr[pos, 3] == "and"

          [{ type: :operator, value: "and" }, 3]
        end

        # Try to tokenize a number (integer or float, including negative)
        def tokenize_number(expr, pos, char, tokens)
          return nil unless number_start?(char, expr, pos, tokens)

          num_str = String.new
          if char == "-"
            num_str << "-"
            pos += 1
          end

          while pos < expr.length && expr[pos].match?(/[\d.]/)
            num_str << expr[pos]
            pos += 1
          end

          value = num_str.include?(".") ? num_str.to_f : num_str.to_i
          [{ type: :number, value: value }, (char == "-" ? 1 : 0) + num_str.delete("-").length]
        end

        def number_start?(char, expr, pos, tokens)
          return true if char.match?(/\d/)

          char == "-" && pos + 1 < expr.length && expr[pos + 1].match?(/\d/) &&
            (tokens.empty? || tokens.last[:type] == :operator || tokens.last[:type] == :paren)
        end

        # Try to tokenize a single-character operator or parenthesis
        def tokenize_single_char_op(char)
          return nil unless "+-*/%><()=".include?(char)

          type = %w[( )].include?(char) ? :paren : :operator
          [{ type: type, value: char }, 1]
        end

        # Try to tokenize a quoted string
        def tokenize_string(expr, pos, char)
          return nil unless char == '"'

          str = String.new
          idx = pos + 1
          while idx < expr.length && expr[idx] != '"'
            str << expr[idx]
            idx += 1
          end
          idx += 1 # Skip closing quote

          [{ type: :string, value: str }, idx - pos]
        end

        # Try to tokenize a keyword (boolean, operator, or field reference)
        def tokenize_keyword(expr, pos, char)
          return nil unless char.match?(/[a-zA-Z]/)

          word = String.new
          idx = pos
          while idx < expr.length && expr[idx].match?(/[a-zA-Z_]/)
            word << expr[idx]
            idx += 1
          end

          [keyword_token(word), idx - pos]
        end

        def keyword_token(word)
          case word.downcase
          when "true"  then { type: :boolean, value: true }
          when "false" then { type: :boolean, value: false }
          when "not"   then { type: :operator, value: "not" }
          when "and", "or" then { type: :operator, value: word.downcase }
          else { type: :field, value: word }
          end
        end

        # Parse expression with operator precedence
        def parse_expression(min_precedence = 0)
          left = parse_unary

          while @position < @tokens.length
            token = current_token
            break unless token && token[:type] == :operator

            op = token[:value]
            precedence = PRECEDENCE[op]
            break if precedence.nil? || precedence < min_precedence

            consume_token # Consume operator

            right = parse_expression(precedence + 1)

            left = {
              type: operator_type(op),
              operator: op,
              left: left,
              right: right
            }
          end

          left
        end

        # Parse unary expressions (not, -, +)
        def parse_unary
          token = current_token

          if token && token[:type] == :operator
            case token[:value]
            when "not"
              consume_token
              operand = parse_unary
              return {
                type: :logical,
                operator: "not",
                operand: operand
              }
            when "-"
              consume_token
              operand = parse_unary
              return {
                type: :arithmetic,
                operator: "negate",
                operand: operand
              }
            when "+"
              consume_token # Skip unary plus
              return parse_unary
            end
          end

          parse_primary
        end

        # Parse primary expressions (numbers, strings, booleans, fields, parentheses)
        def parse_primary
          token = current_token

          raise DecisionAgent::Dmn::FeelParseError, "Unexpected end of expression" unless token

          case token[:type]
          when :number
            consume_token
            { type: :literal, value: token[:value] }

          when :string
            consume_token
            { type: :literal, value: token[:value] }

          when :boolean
            consume_token
            { type: :boolean, value: token[:value] }

          when :field
            consume_token
            { type: :field, name: token[:value] }

          when :paren
            raise DecisionAgent::Dmn::FeelParseError, "Unexpected closing parenthesis" unless token[:value] == "("

            consume_token
            expr = parse_expression
            closing = current_token
            raise DecisionAgent::Dmn::FeelParseError, "Expected closing parenthesis" unless closing && closing[:value] == ")"

            consume_token
            expr

          else
            raise DecisionAgent::Dmn::FeelParseError, "Unexpected token: #{token.inspect}"
          end
        end

        def current_token
          @tokens[@position]
        end

        def consume_token
          @position += 1
        end

        def operator_type(op)
          return :arithmetic if ARITHMETIC_OPS.include?(op)
          return :logical if LOGICAL_OPS.include?(op) || op == "not"
          return :comparison if COMPARISON_OPS.include?(op)

          :unknown
        end
      end
    end
  end
end
