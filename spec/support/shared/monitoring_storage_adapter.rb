# frozen_string_literal: true

# Shared examples for the monitoring storage adapter contract.
#
# Two groups are provided:
#
#   1. "a concrete monitoring storage adapter"
#      Include in specs for any fully-implemented adapter (MemoryAdapter,
#      ActiveRecordAdapter, etc.) to assert the behavioural contract.
#      Requires `adapter` to be defined in the including describe block.
#
#   2. "an abstract monitoring storage adapter"
#      Include in the BaseAdapter spec to assert that every method raises
#      NotImplementedError, keeping the abstract interface in lockstep with
#      this shared contract.
#
# Usage:
#
#   RSpec.describe DecisionAgent::Monitoring::Storage::ActiveRecordAdapter do
#     let(:adapter) { described_class.new }
#     it_behaves_like "a concrete monitoring storage adapter"
#   end
#
#   RSpec.describe DecisionAgent::Monitoring::Storage::BaseAdapter do
#     it_behaves_like "an abstract monitoring storage adapter"
#   end

# ── Concrete contract ────────────────────────────────────────────────────────

RSpec.shared_examples "a concrete monitoring storage adapter" do
  # ── available? ──────────────────────────────────────────────────────────────

  describe ".available?" do
    it "returns true" do
      expect(described_class.available?).to be_truthy
    end
  end

  # ── record_decision ─────────────────────────────────────────────────────────

  describe "#record_decision" do
    it "increases the decisions count by 1" do
      expect { adapter.record_decision("approve", { user_id: 1 }, confidence: 0.9, status: "success") }
        .to change { adapter.metrics_count[:decisions] }.by(1)
    end

    it "accepts optional keyword arguments without raising" do
      expect { adapter.record_decision("approve", {}) }.not_to raise_error
    end
  end

  # ── record_evaluation ───────────────────────────────────────────────────────

  describe "#record_evaluation" do
    it "increases the evaluations count by 1" do
      expect { adapter.record_evaluation("FraudDetector", score: 0.85, success: true) }
        .to change { adapter.metrics_count[:evaluations] }.by(1)
    end

    it "accepts a bare evaluator name without raising" do
      expect { adapter.record_evaluation("MinimalEval") }.not_to raise_error
    end
  end

  # ── record_performance ──────────────────────────────────────────────────────

  describe "#record_performance" do
    it "increases the performance count by 1" do
      expect { adapter.record_performance("api_call", duration_ms: 42.0, status: "success") }
        .to change { adapter.metrics_count[:performance] }.by(1)
    end

    it "accepts a bare operation name without raising" do
      expect { adapter.record_performance("minimal_op") }.not_to raise_error
    end
  end

  # ── record_error ────────────────────────────────────────────────────────────

  describe "#record_error" do
    it "increases the errors count by 1" do
      expect { adapter.record_error("RuntimeError", severity: "critical") }
        .to change { adapter.metrics_count[:errors] }.by(1)
    end

    it "accepts a bare error type without raising" do
      expect { adapter.record_error("MinimalError") }.not_to raise_error
    end
  end

  # ── metrics_count ───────────────────────────────────────────────────────────

  describe "#metrics_count" do
    it "returns a hash with all four metric type keys" do
      counts = adapter.metrics_count

      expect(counts).to include(:decisions, :evaluations, :performance, :errors)
    end

    it "returns non-negative integers for every key" do
      counts = adapter.metrics_count

      counts.each_value { |v| expect(v).to be >= 0 }
    end
  end

  # ── statistics ──────────────────────────────────────────────────────────────

  describe "#statistics" do
    before do
      adapter.record_decision("decide", {}, confidence: 0.8, status: "success")
      adapter.record_evaluation("Eval", score: 0.9, success: true)
      adapter.record_performance("op", duration_ms: 10.0, status: "success")
      adapter.record_error("Err", severity: "low")
    end

    it "returns a hash with the four top-level keys" do
      stats = adapter.statistics(time_range: 3600)

      expect(stats).to include(:decisions, :evaluations, :performance, :errors)
    end

    it "reports at least one decision" do
      stats = adapter.statistics(time_range: 3600)

      expect(stats[:decisions][:total]).to be >= 1
    end

    it "reports at least one evaluation" do
      stats = adapter.statistics(time_range: 3600)

      expect(stats[:evaluations][:total]).to be >= 1
    end

    it "reports at least one performance metric" do
      stats = adapter.statistics(time_range: 3600)

      expect(stats[:performance][:total]).to be >= 1
    end

    it "reports at least one error" do
      stats = adapter.statistics(time_range: 3600)

      expect(stats[:errors][:total]).to be >= 1
    end
  end

  # ── time_series ─────────────────────────────────────────────────────────────

  describe "#time_series" do
    before do
      adapter.record_decision("decide", {})
      adapter.record_evaluation("Eval")
      adapter.record_performance("op")
      adapter.record_error("Err")
    end

    %i[decisions evaluations performance errors].each do |metric|
      it "returns :timestamps and :data arrays for #{metric}" do
        series = adapter.time_series(metric, bucket_size: 60, time_range: 3600)

        expect(series[:timestamps]).to be_an(Array)
        expect(series[:data]).to be_an(Array)
        expect(series[:timestamps].length).to eq(series[:data].length)
      end
    end

    it "returns empty arrays for an unknown metric type" do
      series = adapter.time_series(:unknown_metric, bucket_size: 60, time_range: 3600)

      expect(series[:timestamps]).to eq([])
      expect(series[:data]).to eq([])
    end
  end

  # ── cleanup ─────────────────────────────────────────────────────────────────

  describe "#cleanup" do
    it "returns a non-negative integer" do
      count = adapter.cleanup(older_than: 0)

      expect(count).to be_a(Integer)
      expect(count).to be >= 0
    end
  end
end

# ── Abstract contract ────────────────────────────────────────────────────────

RSpec.shared_examples "an abstract monitoring storage adapter" do
  let(:abstract_adapter) { described_class.new }

  it "raises NotImplementedError for #record_decision" do
    expect { abstract_adapter.record_decision("approve", {}) }.to raise_error(NotImplementedError)
  end

  it "raises NotImplementedError for #record_evaluation" do
    expect { abstract_adapter.record_evaluation("eval") }.to raise_error(NotImplementedError)
  end

  it "raises NotImplementedError for #record_performance" do
    expect { abstract_adapter.record_performance("op") }.to raise_error(NotImplementedError)
  end

  it "raises NotImplementedError for #record_error" do
    expect { abstract_adapter.record_error("Err") }.to raise_error(NotImplementedError)
  end

  it "raises NotImplementedError for #statistics" do
    expect { abstract_adapter.statistics }.to raise_error(NotImplementedError)
  end

  it "raises NotImplementedError for #time_series" do
    expect { abstract_adapter.time_series(:decisions) }.to raise_error(NotImplementedError)
  end

  it "raises NotImplementedError for #metrics_count" do
    expect { abstract_adapter.metrics_count }.to raise_error(NotImplementedError)
  end

  it "raises NotImplementedError for #cleanup" do
    expect { abstract_adapter.cleanup(older_than: 3600) }.to raise_error(NotImplementedError)
  end

  it "raises NotImplementedError for .available?" do
    expect { described_class.available? }.to raise_error(NotImplementedError)
  end
end
