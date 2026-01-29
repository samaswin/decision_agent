require "simplecov"
SimpleCov.start do
  add_filter "/spec/"
  add_filter "/examples/"
end

require "decision_agent"

# Load ActiveRecord for thread-safety and integration tests
begin
  require "active_record"
  require "sqlite3"
  require "decision_agent/versioning/activerecord_adapter"
rescue LoadError
  # ActiveRecord is optional - tests will be skipped if not available
end

# Store original value for cleanup
# rubocop:disable Style/GlobalVars
$original_disable_webui_permissions = nil
# rubocop:enable Style/GlobalVars

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.example_status_persistence_file_path = "spec/examples.txt"
  config.disable_monkey_patching!
  config.warnings = true

  config.default_formatter = "doc" if config.files_to_run.one?

  config.order = :random
  Kernel.srand config.seed

  # Ensure permissions are enabled for tests
  config.before(:suite) do
    # rubocop:disable Style/GlobalVars
    $original_disable_webui_permissions = ENV.fetch("DISABLE_WEBUI_PERMISSIONS", nil)
    # rubocop:enable Style/GlobalVars
    ENV["DISABLE_WEBUI_PERMISSIONS"] = "false"

    # Use memory storage for MetricsCollector in tests to avoid "no such table" stderr
    # (decision_logs/error_metrics exist only when monitoring migration is run)
    if defined?(DecisionAgent::Monitoring::MetricsCollector)
      mod = Module.new do
        def initialize(window_size: 3600, storage: :memory, cleanup_threshold: 100)
          super
        end
      end
      DecisionAgent::Monitoring::MetricsCollector.prepend(mod)
    end
  end

  config.after(:suite) do
    # rubocop:disable Style/GlobalVars
    if $original_disable_webui_permissions
      ENV["DISABLE_WEBUI_PERMISSIONS"] = $original_disable_webui_permissions
    else
      ENV.delete("DISABLE_WEBUI_PERMISSIONS")
    end
    # rubocop:enable Style/GlobalVars
  end
end
