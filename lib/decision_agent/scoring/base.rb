# frozen_string_literal: true

module DecisionAgent
  module Scoring
    class Base
      def score(evaluations)
        raise NotImplementedError, "Subclasses must implement #score"
      end

      protected

      def normalize_confidence(value)
        [[value, 0.0].max, 1.0].min
      end

      def round_confidence(value)
        (value * 10_000).round / 10_000.0
      end
    end
  end
end
