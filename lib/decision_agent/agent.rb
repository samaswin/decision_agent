# frozen_string_literal: true

require "json"
require "json/canonicalization"
require "openssl"

module DecisionAgent
  # Agent runs multiple evaluators over a context, scores their evaluations,
  # and returns a single {Decision} with the chosen outcome and confidence.
  class Agent
    attr_reader :evaluators, :scoring_strategy, :audit_adapter

    # Thread-safe cache for deterministic hash computation
    # This significantly improves performance when the same context/evaluations
    # are processed multiple times (common in benchmarks and high-throughput scenarios)
    @hash_cache = {}
    @hash_cache_mutex = Mutex.new
    @hash_cache_max_size = 1000 # Limit cache size to prevent memory bloat

    class << self
      attr_reader :hash_cache, :hash_cache_mutex, :hash_cache_max_size
    end

    # @param evaluators [Array<#evaluate>] Objects that respond to #evaluate(context, feedback:)
    # @param scoring_strategy [Scoring::Base, nil] Strategy to score evaluations (default: WeightedAverage)
    # @param audit_adapter [Audit::Base, nil] Adapter for recording decisions (default: NullAdapter)
    # @param validate_evaluations [Boolean, nil] If true, validate evaluations; nil = validate unless production
    def initialize(evaluators:, scoring_strategy: nil, audit_adapter: nil, validate_evaluations: nil)
      @evaluators = Array(evaluators)
      @scoring_strategy = scoring_strategy || Scoring::WeightedAverage.new
      @audit_adapter = audit_adapter || Audit::NullAdapter.new
      # Default to validating in development, skip in production for performance
      @validate_evaluations = validate_evaluations.nil? ? (ENV["RAILS_ENV"] != "production") : validate_evaluations

      validate_configuration!

      # Freeze instance variables for thread-safety
      @evaluators.freeze
    end

    # Runs all evaluators on the context, scores results, and returns a single decision.
    #
    # @param context [Context, Hash] Input data; converted to {Context} if a Hash
    # @param feedback [Hash] Optional feedback passed to each evaluator
    # @return [Decision] The chosen decision with confidence, explanations, and audit payload
    # @raise [NoEvaluationsError] when no evaluator returns a valid evaluation
    def decide(context:, feedback: {})
      ctx = context.is_a?(Context) ? context : Context.new(context)

      evaluations = collect_evaluations(ctx, feedback)

      raise NoEvaluationsError if evaluations.empty?

      # Validate all evaluations for correctness and thread-safety (optional for performance)
      EvaluationValidator.validate_all!(evaluations) if @validate_evaluations

      scored_result = @scoring_strategy.score(evaluations)

      decision_value = scored_result[:decision]
      confidence_value = scored_result[:confidence]

      explanations = build_explanations(evaluations, decision_value, confidence_value)

      audit_payload = build_audit_payload(
        context: ctx,
        evaluations: evaluations,
        decision: decision_value,
        confidence: confidence_value,
        feedback: feedback
      )

      decision = Decision.new(
        decision: decision_value,
        confidence: confidence_value,
        explanations: explanations,
        evaluations: evaluations,
        audit_payload: audit_payload
      )

      @audit_adapter.record(decision, ctx)

      decision
    end

    private

    def validate_configuration!
      raise InvalidConfigurationError, "At least one evaluator is required" if @evaluators.empty?

      @evaluators.each do |evaluator|
        raise InvalidEvaluatorError unless evaluator.respond_to?(:evaluate)
      end

      raise InvalidScoringStrategyError unless @scoring_strategy.respond_to?(:score)

      return if @audit_adapter.respond_to?(:record)

      raise InvalidAuditAdapterError
    end

    def collect_evaluations(context, feedback)
      @evaluators.map do |evaluator|
        evaluator.evaluate(context, feedback: feedback)
      rescue StandardError => e
        warn "[DecisionAgent] Evaluator #{evaluator.class} failed: #{e.message}"
        nil
      end.compact
    end

    def build_explanations(evaluations, final_decision, confidence)
      explanations = []

      matching_evals = evaluations.select { |e| e.decision == final_decision }

      explanations << "Decision: #{final_decision} (confidence: #{confidence.round(2)})"

      if matching_evals.size == 1
        evaluation = matching_evals.first
        explanations << "#{evaluation.evaluator_name}: #{evaluation.reason} (weight: #{evaluation.weight})"
      elsif matching_evals.size > 1
        explanations << "Based on #{matching_evals.size} evaluators:"
        matching_evals.each do |evaluation|
          explanations << "  - #{evaluation.evaluator_name}: #{evaluation.reason} (weight: #{evaluation.weight})"
        end
      end

      conflicting_evals = evaluations.reject { |e| e.decision == final_decision }
      if conflicting_evals.any?
        explanations << "Conflicting evaluations resolved by #{@scoring_strategy.class.name.split('::').last}:"
        conflicting_evals.each do |evaluation|
          explanations << "  - #{evaluation.evaluator_name}: suggested '#{evaluation.decision}' (weight: #{evaluation.weight})"
        end
      end

      explanations
    end

    def build_audit_payload(context:, evaluations:, decision:, confidence:, feedback:)
      timestamp = Time.now.utc.strftime("%Y-%m-%dT%H:%M:%S.%6NZ")

      payload = {
        timestamp: timestamp,
        context: context.to_h,
        feedback: feedback,
        evaluations: evaluations.map(&:to_h),
        decision: decision,
        confidence: confidence,
        scoring_strategy: @scoring_strategy.class.name,
        agent_version: DecisionAgent::VERSION
      }

      payload[:deterministic_hash] = compute_deterministic_hash(payload)
      payload
    end

    def compute_deterministic_hash(payload)
      hashable = payload.slice(:context, :evaluations, :decision, :confidence, :scoring_strategy)

      # Use fast hash (MD5) as cache key to avoid expensive canonicalization on cache hits
      # The cache key doesn't need perfect determinism, just good enough to catch duplicates
      # Use OpenSSL::Digest to avoid "Digest::Base cannot be directly inherited" on some Ruby/digest setups
      json_str = hashable.to_json
      fast_key = OpenSSL::Digest::MD5.hexdigest(json_str)

      # Fast path: check cache without lock first (unsafe read, but acceptable for cache)
      cached_hash = lookup_cached_hash(fast_key)
      return cached_hash if cached_hash

      # Cache miss - compute canonical JSON and hash
      computed_hash = compute_canonical_hash(hashable)

      # Store in cache (thread-safe, with size limit)
      cache_hash(fast_key, computed_hash)

      computed_hash
    end

    def lookup_cached_hash(fast_key)
      self.class.hash_cache[fast_key]
    end

    def compute_canonical_hash(hashable)
      canonical = canonical_json(hashable)
      OpenSSL::Digest::SHA256.hexdigest(canonical)
    end

    def cache_hash(fast_key, computed_hash)
      self.class.hash_cache_mutex.synchronize do
        # Double-check after acquiring lock (another thread may have added it)
        return self.class.hash_cache[fast_key] if self.class.hash_cache[fast_key]

        evict_cache_if_needed
        self.class.hash_cache[fast_key] = computed_hash
      end
    end

    def evict_cache_if_needed
      return unless self.class.hash_cache.size >= self.class.hash_cache_max_size

      # Remove oldest 10% of entries (simple FIFO eviction)
      keys_to_remove = self.class.hash_cache.keys.first(self.class.hash_cache_max_size / 10)
      keys_to_remove.each { |key| self.class.hash_cache.delete(key) }
    end

    # Uses RFC 8785 (JSON Canonicalization Scheme) for deterministic JSON serialization
    # This is the industry standard for cryptographic hashing of JSON data
    def canonical_json(obj)
      obj.to_json_c14n
    end
  end
end
