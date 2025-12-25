# frozen_string_literal: true

namespace :decision_agent do
  namespace :monitoring do
    desc "Cleanup old monitoring metrics (default: older than 30 days)"
    task cleanup: :environment do
      older_than = ENV.fetch("OLDER_THAN", 30 * 24 * 3600).to_i # Default: 30 days

      puts "Cleaning up metrics older than #{older_than / 86_400} days..."

      count = 0
      count += DecisionLog.where("created_at < ?", Time.now - older_than).delete_all
      count += EvaluationMetric.where("created_at < ?", Time.now - older_than).delete_all
      count += PerformanceMetric.where("created_at < ?", Time.now - older_than).delete_all
      count += ErrorMetric.where("created_at < ?", Time.now - older_than).delete_all

      puts "Deleted #{count} old metric records"
    end

    desc "Show monitoring statistics"
    task stats: :environment do
      time_range = ENV.fetch("TIME_RANGE", 3600).to_i # Default: 1 hour

      puts "\n=== Decision Agent Monitoring Statistics ==="
      puts "Time range: Last #{time_range / 3600.0} hours\n\n"

      decisions = DecisionLog.recent(time_range)
      evaluations = EvaluationMetric.recent(time_range)
      performance = PerformanceMetric.recent(time_range)
      errors = ErrorMetric.recent(time_range)

      puts "Decisions:"
      puts "  Total: #{decisions.count}"
      puts "  Average confidence: #{decisions.average(:confidence)&.round(4) || 'N/A'}"
      puts "  Success rate: #{(DecisionLog.success_rate(time_range: time_range) * 100).round(2)}%"
      puts "  By decision: #{decisions.group(:decision).count}"

      puts "\nEvaluations:"
      puts "  Total: #{evaluations.count}"
      puts "  By evaluator: #{evaluations.group(:evaluator_name).count}"

      puts "\nPerformance:"
      puts "  Total operations: #{performance.count}"
      puts "  Average duration: #{performance.average_duration(time_range: time_range)&.round(2) || 'N/A'} ms"
      puts "  P95 latency: #{performance.p95(time_range: time_range).round(2)} ms"
      puts "  P99 latency: #{performance.p99(time_range: time_range).round(2)} ms"
      puts "  Success rate: #{(performance.success_rate(time_range: time_range) * 100).round(2)}%"

      puts "\nErrors:"
      puts "  Total: #{errors.count}"
      puts "  By type: #{errors.group(:error_type).count}"
      puts "  By severity: #{errors.group(:severity).count}"
      puts "  Critical: #{errors.critical.count}"

      puts "\n=== End of Statistics ===\n"
    end

    desc "Archive old metrics to JSON file"
    task :archive, [:output_file] => :environment do |_t, args|
      output_file = args[:output_file] || "metrics_archive_#{Time.now.to_i}.json"
      older_than = ENV.fetch("OLDER_THAN", 30 * 24 * 3600).to_i
      cutoff_time = Time.now - older_than

      puts "Archiving metrics older than #{older_than / 86_400} days to #{output_file}..."

      archive_data = {
        archived_at: Time.now.iso8601,
        cutoff_time: cutoff_time.iso8601,
        decisions: DecisionLog.where("created_at < ?", cutoff_time).map do |d|
          {
            decision: d.decision,
            confidence: d.confidence,
            context: d.parsed_context,
            status: d.status,
            created_at: d.created_at.iso8601
          }
        end,
        evaluations: EvaluationMetric.where("created_at < ?", cutoff_time).map do |e|
          {
            evaluator_name: e.evaluator_name,
            score: e.score,
            success: e.success,
            details: e.parsed_details,
            created_at: e.created_at.iso8601
          }
        end,
        performance: PerformanceMetric.where("created_at < ?", cutoff_time).map do |p|
          {
            operation: p.operation,
            duration_ms: p.duration_ms,
            status: p.status,
            metadata: p.parsed_metadata,
            created_at: p.created_at.iso8601
          }
        end,
        errors: ErrorMetric.where("created_at < ?", cutoff_time).map do |e|
          {
            error_type: e.error_type,
            message: e.message,
            severity: e.severity,
            context: e.parsed_context,
            created_at: e.created_at.iso8601
          }
        end
      }

      File.write(output_file, JSON.pretty_generate(archive_data))

      total = archive_data.values.sum { |v| v.is_a?(Array) ? v.size : 0 }
      puts "Archived #{total} metrics to #{output_file}"
      puts "Run 'rake decision_agent:monitoring:cleanup' to delete these records from the database"
    end
  end
end
