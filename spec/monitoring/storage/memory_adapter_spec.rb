# frozen_string_literal: true

require "spec_helper"
require "decision_agent/monitoring/storage/memory_adapter"

RSpec.describe DecisionAgent::Monitoring::Storage::MemoryAdapter do
  let(:adapter) { described_class.new(window_size: 3600) }

  describe ".available?" do
    it "is always available" do
      expect(described_class.available?).to be true
    end
  end

  describe "#record_decision" do
    it "stores decision in memory" do
      expect do
        adapter.record_decision(
          "approve_loan",
          { user_id: 123, amount: 10_000 },
          confidence: 0.85,
          evaluations_count: 3,
          duration_ms: 45.5,
          status: "success"
        )
      end.to change { adapter.metrics_count[:decisions] }.by(1)
    end
  end

  describe "#record_evaluation" do
    it "stores evaluation in memory" do
      expect do
        adapter.record_evaluation(
          "CreditScoreEvaluator",
          score: 0.92,
          success: true,
          duration_ms: 12.3,
          details: { credit_score: 750 }
        )
      end.to change { adapter.metrics_count[:evaluations] }.by(1)
    end
  end

  describe "#record_performance" do
    it "stores performance metric in memory" do
      expect do
        adapter.record_performance(
          "database_query",
          duration_ms: 150.5,
          status: "success",
          metadata: { query: "SELECT * FROM users" }
        )
      end.to change { adapter.metrics_count[:performance] }.by(1)
    end
  end

  describe "#record_error" do
    it "stores error in memory" do
      expect do
        adapter.record_error(
          "ArgumentError",
          message: "Invalid input",
          stack_trace: ["line 1", "line 2"],
          severity: "medium",
          context: { input: "bad_value" }
        )
      end.to change { adapter.metrics_count[:errors] }.by(1)
    end
  end

  describe "#statistics" do
    before do
      # Create test data
      5.times do |i|
        adapter.record_decision(
          "decision_#{i}",
          { index: i },
          confidence: 0.5 + (i * 0.05),
          evaluations_count: 2,
          duration_ms: 100,
          status: i.even? ? "success" : "failure"
        )
      end

      3.times do |i|
        adapter.record_evaluation(
          "Evaluator#{i}",
          score: 0.8 + (i * 0.05),
          success: true
        )
      end

      6.times do |i|
        adapter.record_performance(
          "operation",
          duration_ms: 100 + (i * 20),
          status: "success"
        )
      end

      2.times do
        adapter.record_error("RuntimeError", severity: "critical")
      end
    end

    it "returns comprehensive statistics" do
      stats = adapter.statistics(time_range: 3600)

      expect(stats[:decisions][:total]).to eq(5)
      expect(stats[:decisions][:average_confidence]).to be_within(0.01).of(0.6)
      expect(stats[:decisions][:success_rate]).to eq(0.6) # 3 out of 5

      expect(stats[:evaluations][:total]).to eq(3)
      expect(stats[:evaluations][:average_score]).to be_within(0.01).of(0.85)

      expect(stats[:performance][:total]).to eq(6)
      expect(stats[:performance][:average_duration_ms]).to eq(150.0)
      expect(stats[:performance][:success_rate]).to eq(1.0)

      expect(stats[:errors][:total]).to eq(2)
      expect(stats[:errors][:critical_count]).to eq(2)
    end

    it "filters by time range" do
      # Record an old metric that should be filtered out
      adapter.instance_variable_get(:@metrics)[:decisions] << {
        decision: "old_decision",
        confidence: 0.5,
        timestamp: Time.now - 7200 # 2 hours ago
      }

      stats = adapter.statistics(time_range: 3600) # Last hour only

      expect(stats[:decisions][:total]).to eq(5) # Doesn't include the old one
    end
  end

  describe "#time_series" do
    before do
      # Create metrics at different times
      now = Time.now
      adapter.instance_variable_get(:@metrics)[:decisions] << { timestamp: now - 120 }
      adapter.instance_variable_get(:@metrics)[:decisions] << { timestamp: now - 70 }
      adapter.instance_variable_get(:@metrics)[:decisions] << { timestamp: now - 10 }
    end

    it "groups metrics into time buckets" do
      series = adapter.time_series(:decisions, bucket_size: 60, time_range: 200)

      expect(series[:timestamps]).to be_an(Array)
      expect(series[:data]).to be_an(Array)
      expect(series[:data].sum).to eq(3) # All 3 metrics
    end

    it "uses correct bucket size" do
      series = adapter.time_series(:decisions, bucket_size: 60, time_range: 200)

      # Metrics should be grouped into 60-second buckets
      expect(series[:data].max).to be <= 2 # No bucket should have more than 2
    end
  end

  describe "#metrics_count" do
    before do
      adapter.record_decision("test", {}, confidence: 0.8)
      adapter.record_decision("test2", {}, confidence: 0.9)
      adapter.record_evaluation("eval1", score: 0.85)
      adapter.record_performance("perf1", duration_ms: 100)
      adapter.record_error("Error1")
    end

    it "returns count for each metric type" do
      counts = adapter.metrics_count

      expect(counts[:decisions]).to eq(2)
      expect(counts[:evaluations]).to eq(1)
      expect(counts[:performance]).to eq(1)
      expect(counts[:errors]).to eq(1)
    end
  end

  describe "#cleanup" do
    let(:long_window_adapter) { described_class.new(window_size: 30 * 24 * 3_600) } # 30 day window

    before do
      now = Time.now

      # Add old metrics (8 days ago) to adapter with long window
      long_window_adapter.instance_variable_get(:@metrics)[:decisions] << {
        decision: "old",
        timestamp: now - (8 * 24 * 3600)
      }
      long_window_adapter.instance_variable_get(:@metrics)[:evaluations] << {
        evaluator_name: "old",
        timestamp: now - (8 * 24 * 3600)
      }

      # Add recent metrics
      long_window_adapter.record_decision("recent", {}, confidence: 0.8)
      long_window_adapter.record_evaluation("recent", score: 0.9)
    end

    it "removes old metrics and returns count" do
      count = long_window_adapter.cleanup(older_than: 7 * 24 * 3600) # 7 days

      expect(count).to eq(2) # 2 old metrics removed
      expect(long_window_adapter.metrics_count[:decisions]).to eq(1) # Only recent one
      expect(long_window_adapter.metrics_count[:evaluations]).to eq(1)
    end
  end

  describe "window-based cleanup" do
    let(:short_window_adapter) { described_class.new(window_size: 60) } # 1 minute window

    it "automatically removes metrics older than window_size" do
      now = Time.now

      # Add old metric
      short_window_adapter.instance_variable_get(:@metrics)[:decisions] << {
        decision: "old",
        timestamp: now - 120 # 2 minutes ago
      }

      # Add new metric (this should trigger cleanup)
      short_window_adapter.record_decision("new", {}, confidence: 0.8)

      # Only the new metric should remain
      expect(short_window_adapter.metrics_count[:decisions]).to eq(1)
    end
  end

  describe "thread safety" do
    it "handles concurrent writes" do
      threads = 10.times.map do
        Thread.new do
          100.times do |i|
            adapter.record_decision("concurrent_#{i}", {}, confidence: 0.8)
          end
        end
      end

      threads.each(&:join)

      expect(adapter.metrics_count[:decisions]).to eq(1000)
    end
  end
end
