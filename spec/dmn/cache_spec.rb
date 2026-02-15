# frozen_string_literal: true

require "spec_helper"
require "decision_agent/dmn/cache"

RSpec.describe DecisionAgent::Dmn::EvaluationCache do
  let(:cache) { described_class.new(max_model_cache_size: 3, max_result_cache_size: 3, ttl: 60) }

  describe "#cache_model / #get_model" do
    it "stores and retrieves a model" do
      cache.cache_model("model_1", { id: "model_1" })

      expect(cache.get_model("model_1")).to eq({ id: "model_1" })
    end

    it "returns nil for uncached model" do
      expect(cache.get_model("nonexistent")).to be_nil
    end

    it "tracks cache hits and misses" do
      cache.cache_model("m1", :model)
      cache.get_model("m1")
      cache.get_model("missing")

      stats = cache.statistics
      expect(stats[:model_cache_hits]).to eq(1)
      expect(stats[:model_cache_misses]).to eq(1)
    end

    it "evicts oldest model when cache is full" do
      cache.cache_model("m1", :model1)
      cache.cache_model("m2", :model2)
      cache.cache_model("m3", :model3)
      cache.cache_model("m4", :model4)

      expect(cache.get_model("m1")).to be_nil
      expect(cache.get_model("m4")).to eq(:model4)
    end

    it "expires entries after TTL" do
      short_ttl_cache = described_class.new(ttl: 1)
      short_ttl_cache.cache_model("m1", :model)

      # Entry is valid within TTL
      expect(short_ttl_cache.get_model("m1")).to eq(:model)

      # Simulate expiration by manipulating cached_at
      short_ttl_cache.model_cache["m1"][:cached_at] = Time.now.to_i - 2

      expect(short_ttl_cache.get_model("m1")).to be_nil
    end
  end

  describe "#cache_result / #get_result" do
    it "stores and retrieves a result" do
      cache.cache_result("decision_1", "ctx_hash", { output: "approve" })

      expect(cache.get_result("decision_1", "ctx_hash")).to eq({ output: "approve" })
    end

    it "returns nil for uncached result" do
      expect(cache.get_result("d1", "unknown")).to be_nil
    end

    it "tracks result cache hits and misses" do
      cache.cache_result("d1", "h1", :result)
      cache.get_result("d1", "h1")
      cache.get_result("d1", "missing")

      stats = cache.statistics
      expect(stats[:result_cache_hits]).to eq(1)
      expect(stats[:result_cache_misses]).to eq(1)
    end

    it "evicts oldest result when cache is full" do
      cache.cache_result("d1", "h1", :r1)
      cache.cache_result("d1", "h2", :r2)
      cache.cache_result("d1", "h3", :r3)
      cache.cache_result("d1", "h4", :r4)

      expect(cache.get_result("d1", "h1")).to be_nil
    end
  end

  describe "#clear" do
    it "clears all caches and resets stats" do
      cache.cache_model("m1", :model)
      cache.cache_result("d1", "h1", :result)
      cache.get_model("m1")

      cache.clear

      expect(cache.get_model("m1")).to be_nil
      stats = cache.statistics
      expect(stats[:model_cache_size]).to eq(0)
      expect(stats[:result_cache_size]).to eq(0)
    end
  end

  describe "#clear_models" do
    it "clears only model cache" do
      cache.cache_model("m1", :model)
      cache.cache_result("d1", "h1", :result)

      cache.clear_models

      expect(cache.model_cache).to be_empty
      expect(cache.result_cache).not_to be_empty
    end
  end

  describe "#clear_results" do
    it "clears only result cache" do
      cache.cache_model("m1", :model)
      cache.cache_result("d1", "h1", :result)

      cache.clear_results

      expect(cache.model_cache).not_to be_empty
      expect(cache.result_cache).to be_empty
    end
  end

  describe "#statistics" do
    it "returns cache statistics with hit rates" do
      cache.cache_model("m1", :model)
      cache.get_model("m1")
      cache.get_model("m1")
      cache.get_model("missing")

      stats = cache.statistics

      expect(stats[:model_cache_size]).to eq(1)
      expect(stats[:model_hit_rate]).to be > 0
      expect(stats).to have_key(:result_hit_rate)
    end
  end
end

RSpec.describe DecisionAgent::Dmn::FeelExpressionCache do
  let(:cache) { described_class.new(max_size: 3) }

  describe "#cache_expression / #get_expression" do
    it "stores and retrieves a parsed expression" do
      ast = { type: :number, value: 42 }
      cache.cache_expression("42", ast)

      expect(cache.get_expression("42")).to eq(ast)
    end

    it "returns nil for uncached expression" do
      expect(cache.get_expression("unknown")).to be_nil
    end

    it "tracks access count" do
      cache.cache_expression("42", { type: :number })
      3.times { cache.get_expression("42") }

      stats = cache.statistics
      expect(stats[:most_accessed].first[:count]).to eq(3)
    end

    it "evicts least recently accessed when full" do
      cache.cache_expression("a", :a)
      cache.cache_expression("b", :b)
      cache.cache_expression("c", :c)

      # Add new entry - should evict the oldest cached (first inserted)
      cache.cache_expression("d", :d)

      expect(cache.get_expression("d")).to eq(:d)
      # At least one of the original entries was evicted
      remaining = %w[a b c].count { |k| cache.get_expression(k) }
      expect(remaining).to eq(2)
    end
  end

  describe "#clear" do
    it "clears cache and resets stats" do
      cache.cache_expression("42", :ast)
      cache.get_expression("42")

      cache.clear

      expect(cache.get_expression("42")).to be_nil
      stats = cache.statistics
      expect(stats[:size]).to eq(0)
      expect(stats[:hits]).to eq(0)
    end
  end

  describe "#statistics" do
    it "returns size, hits, misses, and hit rate" do
      cache.cache_expression("a", :a)
      cache.get_expression("a")
      cache.get_expression("missing")

      stats = cache.statistics

      expect(stats[:size]).to eq(1)
      expect(stats[:hits]).to eq(1)
      expect(stats[:misses]).to eq(1)
      expect(stats[:hit_rate]).to eq(50.0)
    end
  end
end
