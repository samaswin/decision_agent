namespace :decision_agent do
  namespace :ab_testing do
    desc "List all A/B tests"
    task list: :environment do
      require "decision_agent/ab_testing/ab_test_manager"

      manager = DecisionAgent::ABTesting::ABTestManager.new(
        storage_adapter: DecisionAgent::ABTesting::Storage::ActiveRecordAdapter.new
      )

      tests = manager.list_tests
      puts "\n📊 A/B Tests (Total: #{tests.size})\n"
      puts "=" * 80

      if tests.empty?
        puts "No A/B tests found."
      else
        tests.each do |test|
          puts "\nID: #{test.id}"
          puts "Name: #{test.name}"
          puts "Status: #{test.status}"
          puts "Champion Version: #{test.champion_version_id}"
          puts "Challenger Version: #{test.challenger_version_id}"
          puts "Traffic Split: #{test.traffic_split[:champion]}% / #{test.traffic_split[:challenger]}%"
          puts "Start Date: #{test.start_date}"
          puts "End Date: #{test.end_date || 'N/A'}"
          puts "-" * 80
        end
      end
    end

    desc "Show A/B test results - Usage: rake decision_agent:ab_testing:results[test_id]"
    task :results, [:test_id] => :environment do |_t, args|
      require "decision_agent/ab_testing/ab_test_manager"

      test_id = args[:test_id]
      raise "Test ID is required. Usage: rake decision_agent:ab_testing:results[123]" unless test_id

      manager = DecisionAgent::ABTesting::ABTestManager.new(
        storage_adapter: DecisionAgent::ABTesting::Storage::ActiveRecordAdapter.new
      )

      results = manager.get_results(test_id)

      puts "\n📊 A/B Test Results"
      puts "=" * 80
      puts "\nTest: #{results[:test][:name]}"
      puts "Status: #{results[:test][:status]}"
      puts "Total Assignments: #{results[:total_assignments]}"
      puts ""

      puts "🏆 Champion (Version #{results[:test][:champion_version_id]})"
      puts "  Assignments: #{results[:champion][:total_assignments]}"
      puts "  Decisions Recorded: #{results[:champion][:decisions_recorded]}"
      if results[:champion][:avg_confidence]
        puts "  Avg Confidence: #{results[:champion][:avg_confidence]}"
        puts "  Min/Max Confidence: #{results[:champion][:min_confidence]} / #{results[:champion][:max_confidence]}"
      end
      puts ""

      puts "🆕 Challenger (Version #{results[:test][:challenger_version_id]})"
      puts "  Assignments: #{results[:challenger][:total_assignments]}"
      puts "  Decisions Recorded: #{results[:challenger][:decisions_recorded]}"
      if results[:challenger][:avg_confidence]
        puts "  Avg Confidence: #{results[:challenger][:avg_confidence]}"
        puts "  Min/Max Confidence: #{results[:challenger][:min_confidence]} / #{results[:challenger][:max_confidence]}"
      end
      puts ""

      if results[:comparison][:statistical_significance] == "insufficient_data"
        puts "⚠️  Insufficient data for statistical comparison"
      else
        puts "📈 Statistical Comparison"
        puts "  Improvement: #{results[:comparison][:improvement_percentage]}%"
        puts "  Winner: #{results[:comparison][:winner]}"
        puts "  Statistical Significance: #{results[:comparison][:statistical_significance]}"
        puts "  Confidence Level: #{(results[:comparison][:confidence_level] * 100).round(0)}%"
        puts ""
        puts "💡 Recommendation: #{results[:comparison][:recommendation]}"
      end

      puts "=" * 80
    end

    desc "Start an A/B test - Usage: rake decision_agent:ab_testing:start[test_id]"
    task :start, [:test_id] => :environment do |_t, args|
      require "decision_agent/ab_testing/ab_test_manager"

      test_id = args[:test_id]
      raise "Test ID is required. Usage: rake decision_agent:ab_testing:start[123]" unless test_id

      manager = DecisionAgent::ABTesting::ABTestManager.new(
        storage_adapter: DecisionAgent::ABTesting::Storage::ActiveRecordAdapter.new
      )

      manager.start_test(test_id)
      puts "✅ A/B test #{test_id} started successfully!"
    end

    desc "Complete an A/B test - Usage: rake decision_agent:ab_testing:complete[test_id]"
    task :complete, [:test_id] => :environment do |_t, args|
      require "decision_agent/ab_testing/ab_test_manager"

      test_id = args[:test_id]
      raise "Test ID is required. Usage: rake decision_agent:ab_testing:complete[123]" unless test_id

      manager = DecisionAgent::ABTesting::ABTestManager.new(
        storage_adapter: DecisionAgent::ABTesting::Storage::ActiveRecordAdapter.new
      )

      manager.complete_test(test_id)
      puts "✅ A/B test #{test_id} completed successfully!"
    end

    desc "Cancel an A/B test - Usage: rake decision_agent:ab_testing:cancel[test_id]"
    task :cancel, [:test_id] => :environment do |_t, args|
      require "decision_agent/ab_testing/ab_test_manager"

      test_id = args[:test_id]
      raise "Test ID is required. Usage: rake decision_agent:ab_testing:cancel[123]" unless test_id

      manager = DecisionAgent::ABTesting::ABTestManager.new(
        storage_adapter: DecisionAgent::ABTesting::Storage::ActiveRecordAdapter.new
      )

      manager.cancel_test(test_id)
      puts "✅ A/B test #{test_id} cancelled successfully!"
    end

    desc "Create a new A/B test - Usage: rake decision_agent:ab_testing:create[name,champion_id,challenger_id,split]"
    task :create, %i[name champion_id challenger_id split] => :environment do |_t, args|
      require "decision_agent/ab_testing/ab_test_manager"

      name = args[:name]
      champion_id = args[:champion_id]
      challenger_id = args[:challenger_id]
      split = args[:split] || "90,10"

      unless name && champion_id && challenger_id
        raise "Missing arguments. Usage: rake decision_agent:ab_testing:create[name,champion_id,challenger_id,split]"
      end

      champion_pct, challenger_pct = split.split(",").map(&:to_i)

      manager = DecisionAgent::ABTesting::ABTestManager.new(
        storage_adapter: DecisionAgent::ABTesting::Storage::ActiveRecordAdapter.new
      )

      test = manager.create_test(
        name: name,
        champion_version_id: champion_id,
        challenger_version_id: challenger_id,
        traffic_split: { champion: champion_pct, challenger: challenger_pct }
      )

      puts "✅ A/B test created successfully!"
      puts "   ID: #{test.id}"
      puts "   Name: #{test.name}"
      puts "   Status: #{test.status}"
    end

    desc "Show active A/B tests"
    task active: :environment do
      require "decision_agent/ab_testing/ab_test_manager"

      manager = DecisionAgent::ABTesting::ABTestManager.new(
        storage_adapter: DecisionAgent::ABTesting::Storage::ActiveRecordAdapter.new
      )

      tests = manager.active_tests
      puts "\n🔄 Active A/B Tests (Total: #{tests.size})\n"
      puts "=" * 80

      if tests.empty?
        puts "No active A/B tests found."
      else
        tests.each do |test|
          puts "\nID: #{test.id}"
          puts "Name: #{test.name}"
          puts "Champion vs Challenger: #{test.champion_version_id} vs #{test.challenger_version_id}"
          puts "Traffic Split: #{test.traffic_split[:champion]}% / #{test.traffic_split[:challenger]}%"
          puts "-" * 80
        end
      end
    end
  end
end
