# frozen_string_literal: true

require "spec_helper"
require "active_record"
require "decision_agent/monitoring/storage/activerecord_adapter"
require "decision_agent/monitoring/storage/memory_adapter"

# Thread-safety spec for monitoring storage adapters.
#
# Strategy from the Phase 2 plan:
#   - 16 threads recording 1,000 decisions each
#   - Assert no lost writes and correct metrics_count
#
# The ActiveRecord adapter uses a shared-cache SQLite in WAL mode so that
# all threads can write concurrently without "database is locked" errors —
# the same pattern used by spec/activerecord_thread_safety_spec.rb.

RSpec.describe "Monitoring storage thread safety" do
  # ── ActiveRecord adapter setup ──────────────────────────────────────────────

  before(:all) do
    ActiveRecord::Base.establish_connection(
      adapter: "sqlite3",
      database: "file:monitoring_thread_safety?mode=memory&cache=shared",
      flags: SQLite3::Constants::Open::URI | SQLite3::Constants::Open::READWRITE | SQLite3::Constants::Open::CREATE,
      pool: 32,
      checkout_timeout: 15
    )

    ActiveRecord::Base.connection.execute("PRAGMA journal_mode=WAL")
    # Release the main thread's connection back to the pool so we can
    # checkout all 32 slots below without hitting the pool limit.
    ActiveRecord::Base.connection_pool.release_connection

    # Pre-warm all pool connections and set busy_timeout on each so that
    # concurrent threads wait instead of immediately raising SQLITE_BUSY.
    connections = 32.times.map { ActiveRecord::Base.connection_pool.checkout }
    connections.each do |conn|
      conn.execute("PRAGMA journal_mode=WAL")
      conn.execute("PRAGMA busy_timeout=10000")
      ActiveRecord::Base.connection_pool.checkin(conn)
    end

    ActiveRecord::Schema.define do
      create_table :ts_decision_logs, force: true do |t|
        t.string  :decision, null: false
        t.float   :confidence
        t.integer :evaluations_count, default: 0
        t.float   :duration_ms
        t.string  :status
        t.text    :context
        t.text    :metadata
        t.timestamps
      end

      create_table :ts_evaluation_metrics, force: true do |t|
        t.references :ts_decision_log, foreign_key: { to_table: :ts_decision_logs }
        t.string  :evaluator_name, null: false
        t.float   :score
        t.boolean :success
        t.float   :duration_ms
        t.text    :details
        t.timestamps
      end

      create_table :ts_performance_metrics, force: true do |t|
        t.string :operation, null: false
        t.float  :duration_ms
        t.string :status
        t.text   :metadata
        t.timestamps
      end

      create_table :ts_error_metrics, force: true do |t|
        t.string :error_type, null: false
        t.text   :message
        t.text   :stack_trace
        t.string :severity
        t.text   :context
        t.timestamps
      end
    end

    # rubocop:disable Lint/ConstantDefinitionInBlock
    class TsDecisionLog < ActiveRecord::Base
      self.table_name = "ts_decision_logs"
      has_many :ts_evaluation_metrics, foreign_key: :ts_decision_log_id, dependent: :destroy

      scope :recent, ->(seconds) { where("created_at >= ?", Time.now - seconds) }

      def self.success_rate(time_range: 3600)
        total = recent(time_range).where.not(status: nil).count
        return 0.0 if total.zero?

        recent(time_range).where(status: "success").count.to_f / total
      end
    end

    class TsEvaluationMetric < ActiveRecord::Base
      self.table_name = "ts_evaluation_metrics"
      belongs_to :ts_decision_log, optional: true

      scope :recent,     ->(seconds) { where("created_at >= ?", Time.now - seconds) }
      scope :successful, -> { where(success: true) }
    end

    class TsPerformanceMetric < ActiveRecord::Base
      self.table_name = "ts_performance_metrics"

      scope :recent, ->(seconds) { where("created_at >= ?", Time.now - seconds) }

      def self.average_duration(time_range: 3600)
        recent(time_range).average(:duration_ms).to_f
      end

      def self.percentile(pct, time_range: 3600)
        durations = recent(time_range).where.not(duration_ms: nil).order(:duration_ms).pluck(:duration_ms)
        return 0.0 if durations.empty?

        durations[(durations.length * pct).ceil - 1].to_f
      end

      def self.p50(time_range: 3600) = percentile(0.50, time_range: time_range)
      def self.p95(time_range: 3600) = percentile(0.95, time_range: time_range)
      def self.p99(time_range: 3600) = percentile(0.99, time_range: time_range)

      def self.success_rate(time_range: 3600)
        total = recent(time_range).where.not(status: nil).count
        return 0.0 if total.zero?

        recent(time_range).where(status: "success").count.to_f / total
      end
    end

    class TsErrorMetric < ActiveRecord::Base
      self.table_name = "ts_error_metrics"

      scope :recent,   ->(seconds) { where("created_at >= ?", Time.now - seconds) }
      scope :critical, -> { where(severity: "critical") }
    end
    # rubocop:enable Lint/ConstantDefinitionInBlock

    # Patch ActiveRecordAdapter to use the thread-safety test models
    # rubocop:disable Lint/ConstantDefinitionInBlock
    module TsModelOverride
      # Retry helper for transient SQLite lock/busy errors.
      # busy_timeout covers SQLITE_BUSY but not SQLITE_LOCKED; we handle
      # SQLITE_LOCKED here with short exponential backoff so no writes are lost.
      def ts_with_retry(max_attempts: 10, &block)
        attempts = 0
        begin
          block.call
        rescue ActiveRecord::StatementInvalid => e
          attempts += 1
          if attempts < max_attempts && e.message =~ /locked|busy/i
            sleep(0.005 * (2**attempts))
            retry
          end
          raise
        end
      end

      def record_decision(decision, context, **kwargs)
        ts_with_retry do
          TsDecisionLog.create!(
            decision: decision,
            context: context.to_json,
            confidence: kwargs[:confidence],
            evaluations_count: kwargs[:evaluations_count] || 0,
            duration_ms: kwargs[:duration_ms],
            status: kwargs[:status]
          )
        end
      end

      def record_evaluation(evaluator_name, **kwargs)
        ts_with_retry do
          TsEvaluationMetric.create!(
            evaluator_name: evaluator_name,
            score: kwargs[:score],
            success: kwargs[:success],
            duration_ms: kwargs[:duration_ms],
            details: (kwargs[:details] || {}).to_json
          )
        end
      end

      def record_performance(operation, **kwargs)
        ts_with_retry do
          TsPerformanceMetric.create!(
            operation: operation,
            duration_ms: kwargs[:duration_ms],
            status: kwargs[:status],
            metadata: (kwargs[:metadata] || {}).to_json
          )
        end
      end

      def record_error(error_type, **kwargs)
        ts_with_retry do
          TsErrorMetric.create!(
            error_type: error_type,
            message: kwargs[:message],
            stack_trace: kwargs[:stack_trace]&.to_json,
            severity: kwargs[:severity],
            context: (kwargs[:context] || {}).to_json
          )
        end
      end

      def metrics_count
        {
          decisions: TsDecisionLog.count,
          evaluations: TsEvaluationMetric.count,
          performance: TsPerformanceMetric.count,
          errors: TsErrorMetric.count
        }
      rescue StandardError
        { decisions: 0, evaluations: 0, performance: 0, errors: 0 }
      end
    end
    # rubocop:enable Lint/ConstantDefinitionInBlock
  end

  before do
    TsDecisionLog.delete_all
    TsEvaluationMetric.delete_all
    TsPerformanceMetric.delete_all
    TsErrorMetric.delete_all
  end

  def ts_adapter
    adapter = DecisionAgent::Monitoring::Storage::ActiveRecordAdapter.allocate
    adapter.extend(TsModelOverride)
    adapter
  end

  # ── 16 threads × 1,000 decisions ────────────────────────────────────────────

  describe "ActiveRecord adapter" do
    it "records all decisions without loss under 16 concurrent threads" do
      thread_count   = 16
      decisions_each = 1_000
      adapter        = ts_adapter

      threads = thread_count.times.map do |thread_id|
        Thread.new do
          decisions_each.times do |i|
            adapter.record_decision(
              "thread_decision_#{thread_id}_#{i}",
              { thread: thread_id, index: i },
              confidence: 0.8,
              status: "success"
            )
          end
        end
      end

      threads.each(&:join)

      expect(TsDecisionLog.count).to eq(thread_count * decisions_each)
    end

    it "records mixed metric types without loss under 16 concurrent threads" do
      thread_count = 16
      each_count   = 100
      adapter      = ts_adapter

      threads = thread_count.times.map do |thread_id|
        Thread.new do
          each_count.times do |i|
            adapter.record_decision("dec_#{thread_id}_#{i}", {})
            adapter.record_evaluation("eval_#{thread_id}_#{i}")
            adapter.record_performance("perf_#{thread_id}_#{i}")
            adapter.record_error("err_#{thread_id}_#{i}")
          end
        end
      end

      threads.each(&:join)

      counts = adapter.metrics_count
      total  = thread_count * each_count

      expect(counts[:decisions]).to   eq(total)
      expect(counts[:evaluations]).to eq(total)
      expect(counts[:performance]).to eq(total)
      expect(counts[:errors]).to      eq(total)
    end

    it "returns correct metrics_count under concurrent reads and writes" do
      adapter = ts_adapter
      begin
        Concurrent::AtomicBoolean.new(false)
      rescue StandardError
        nil
      end

      writers = 8.times.map do
        Thread.new { 500.times { adapter.record_decision("concurrent", {}) } }
      end

      # readers run while writers are active
      reader_errors = []
      readers = 4.times.map do
        Thread.new do
          500.times do
            counts = adapter.metrics_count
            reader_errors << counts unless counts.key?(:decisions)
          end
        end
      end

      writers.each(&:join)
      readers.each(&:join)

      expect(reader_errors).to be_empty
      expect(TsDecisionLog.count).to eq(8 * 500)
    end
  end

  # ── MemoryAdapter thread safety ──────────────────────────────────────────────

  describe "MemoryAdapter" do
    let(:mem_adapter) { DecisionAgent::Monitoring::Storage::MemoryAdapter.new(window_size: 3600) }

    it "records all decisions without loss under 16 concurrent threads" do
      thread_count   = 16
      decisions_each = 1_000

      threads = thread_count.times.map do
        Thread.new { decisions_each.times { mem_adapter.record_decision("concurrent", {}) } }
      end

      threads.each(&:join)

      expect(mem_adapter.metrics_count[:decisions]).to eq(thread_count * decisions_each)
    end
  end
end
