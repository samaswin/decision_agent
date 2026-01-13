#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "rack"
require "json"
require "decision_agent"

class RuleVersioningApp
  def initialize
    @version_manager = DecisionAgent::Versioning::VersionManager.new(
      adapter: DecisionAgent::Versioning::FileStorageAdapter.new(
        storage_path: "./data/versions"
      )
    )
  end

  def call(env)
    request = Rack::Request.new(env)
    method = request.request_method
    path = request.path_info

    cors_headers = {
      "Access-Control-Allow-Origin" => "*",
      "Access-Control-Allow-Methods" => "GET, POST, PUT, DELETE, OPTIONS",
      "Access-Control-Allow-Headers" => "Content-Type"
    }

    return [200, cors_headers, [""]] if method == "OPTIONS"

    case [method, path]
    when ["GET", "/"]
      home_page(cors_headers)
    when ["POST", %r{^/rules/([^/]+)/versions$}]
      create_version(request, $1, cors_headers)
    when ["GET", %r{^/rules/([^/]+)/versions$}]
      list_versions(request, $1, cors_headers)
    when ["GET", %r{^/rules/([^/]+)/history$}]
      get_history($1, cors_headers)
    when ["GET", %r{^/versions/([^/]+)$}]
      get_version($1, cors_headers)
    when ["POST", %r{^/versions/([^/]+)/activate$}]
      activate_version(request, $1, cors_headers)
    when ["GET", %r{^/versions/([^/]+)/compare/([^/]+)$}]
      compare_versions($1, $2, cors_headers)
    when ["POST", "/evaluate"]
      evaluate(request, cors_headers)
    when ["GET", "/health"]
      health_check(cors_headers)
    else
      [404, cors_headers.merge("Content-Type" => "application/json"), [{ error: "Not found" }.to_json]]
    end
  rescue StandardError => e
    [500, cors_headers.merge("Content-Type" => "application/json"), [{ error: "Internal error", message: e.message }.to_json]]
  end

  private

  def home_page(headers)
    response = {
      name: "Rule Versioning API",
      version: DecisionAgent::VERSION,
      endpoints: {
        rules: {
          create_version: "POST /rules/:rule_id/versions",
          list_versions: "GET /rules/:rule_id/versions",
          get_version: "GET /versions/:version_id",
          activate: "POST /versions/:version_id/activate",
          compare: "GET /versions/:v1/compare/:v2",
          history: "GET /rules/:rule_id/history"
        },
        evaluation: {
          evaluate: "POST /evaluate"
        }
      }
    }
    [200, headers.merge("Content-Type" => "application/json"), [response.to_json]]
  end

  def create_version(request, rule_id, headers)
    data = JSON.parse(request.body.read, symbolize_names: true)

    version = @version_manager.save_version(
      rule_id: rule_id,
      rule_content: data[:content],
      created_by: data[:created_by] || "api_user",
      changelog: data[:changelog]
    )

    [201, headers.merge("Content-Type" => "application/json"), [version.to_json]]
  rescue DecisionAgent::ValidationError => e
    [422, headers.merge("Content-Type" => "application/json"), [{ error: "Validation failed", message: e.message }.to_json]]
  rescue JSON::ParserError => e
    [400, headers.merge("Content-Type" => "application/json"), [{ error: "Invalid JSON", message: e.message }.to_json]]
  rescue StandardError => e
    [500, headers.merge("Content-Type" => "application/json"), [{ error: "Internal error", message: e.message }.to_json]]
  end

  def list_versions(request, rule_id, headers)
    limit = request.params["limit"]&.to_i

    versions = @version_manager.get_versions(
      rule_id: rule_id,
      limit: limit
    )

    [200, headers.merge("Content-Type" => "application/json"), [versions.to_json]]
  rescue StandardError => e
    [500, headers.merge("Content-Type" => "application/json"), [{ error: e.message }.to_json]]
  end

  def get_history(rule_id, headers)
    history = @version_manager.get_history(rule_id: rule_id)
    [200, headers.merge("Content-Type" => "application/json"), [history.to_json]]
  rescue StandardError => e
    [500, headers.merge("Content-Type" => "application/json"), [{ error: e.message }.to_json]]
  end

  def get_version(version_id, headers)
    version = @version_manager.get_version(version_id: version_id)

    if version
      [200, headers.merge("Content-Type" => "application/json"), [version.to_json]]
    else
      [404, headers.merge("Content-Type" => "application/json"), [{ error: "Version not found" }.to_json]]
    end
  rescue StandardError => e
    [500, headers.merge("Content-Type" => "application/json"), [{ error: e.message }.to_json]]
  end

  def activate_version(request, version_id, headers)
    data = request.body.read
    parsed_data = data.empty? ? {} : JSON.parse(data, symbolize_names: true)

    version = @version_manager.rollback(
      version_id: version_id,
      performed_by: parsed_data[:performed_by] || "api_user"
    )

    [200, headers.merge("Content-Type" => "application/json"), [version.to_json]]
  rescue StandardError => e
    [500, headers.merge("Content-Type" => "application/json"), [{ error: e.message }.to_json]]
  end

  def compare_versions(v1, v2, headers)
    comparison = @version_manager.compare(
      version_id_1: v1,
      version_id_2: v2
    )

    if comparison
      [200, headers.merge("Content-Type" => "application/json"), [comparison.to_json]]
    else
      [404, headers.merge("Content-Type" => "application/json"), [{ error: "One or both versions not found" }.to_json]]
    end
  rescue StandardError => e
    [500, headers.merge("Content-Type" => "application/json"), [{ error: e.message }.to_json]]
  end

  def evaluate(request, headers)
    data = JSON.parse(request.body.read, symbolize_names: true)

    active_version = @version_manager.get_active_version(
      rule_id: data[:rule_id]
    )

    unless active_version
      return [404, headers.merge("Content-Type" => "application/json"), [{ error: "No active version found for this rule" }.to_json]]
    end

    evaluator = DecisionAgent::Evaluators::JsonRuleEvaluator.new(
      rules_json: active_version[:content]
    )

    context = DecisionAgent::Context.new(data[:context] || {})
    result = evaluator.evaluate(context)

    if result
      explainability = result.metadata[:explainability] if result.metadata.is_a?(Hash)
      
      response = if explainability
        {
          success: true,
          decision: explainability[:decision] || result.decision,
          because: explainability[:because] || [],
          failed_conditions: explainability[:failed_conditions] || [],
          confidence: result.weight,
          reason: result.reason,
          version: active_version[:version_number],
          explainability: explainability
        }
      else
        {
          success: true,
          decision: result.decision,
          because: [],
          failed_conditions: [],
          confidence: result.weight,
          reason: result.reason,
          version: active_version[:version_number],
          explainability: {
            decision: result.decision,
            because: [],
            failed_conditions: []
          }
        }
      end
      [200, headers.merge("Content-Type" => "application/json"), [response.to_json]]
    else
      response = {
        success: true,
        decision: nil,
        because: [],
        failed_conditions: [],
        message: "No rules matched",
        version: active_version[:version_number],
        explainability: {
          decision: nil,
          because: [],
          failed_conditions: []
        }
      }
      [200, headers.merge("Content-Type" => "application/json"), [response.to_json]]
    end
  rescue StandardError => e
    [500, headers.merge("Content-Type" => "application/json"), [{ error: e.message }.to_json]]
  end

  def health_check(headers)
    response = {
      status: "ok",
      version: DecisionAgent::VERSION,
      timestamp: Time.now.utc.iso8601
    }
    [200, headers.merge("Content-Type" => "application/json"), [response.to_json]]
  end
end

if __FILE__ == $PROGRAM_NAME
  require "rack/handler/webrick"
  
  puts "Starting Rule Versioning API on http://localhost:4567"
  puts "Press Ctrl+C to stop"
  
  Rack::Handler::WEBrick.run(
    RuleVersioningApp.new,
    Port: 4567,
    Host: "0.0.0.0"
  )
end

__END__

# 1. Create a version
curl -X POST http://localhost:4567/rules/approval_001/versions \
  -H "Content-Type: application/json" \
  -d '{
    "content": {
      "version": "1.0",
      "ruleset": "approval",
      "rules": [{
        "id": "rule_1",
        "if": {"field": "amount", "op": "lt", "value": 1000},
        "then": {"decision": "approve", "weight": 0.9, "reason": "Low amount"}
      }]
    },
    "created_by": "john@example.com",
    "changelog": "Initial version"
  }'

# 2. List versions
curl http://localhost:4567/rules/approval_001/versions

# 3. Get history
curl http://localhost:4567/rules/approval_001/history

# 4. Get specific version
curl http://localhost:4567/versions/approval_001_v1

# 5. Activate version (rollback)
curl -X POST http://localhost:4567/versions/approval_001_v1/activate \
  -H "Content-Type: application/json" \
  -d '{"performed_by": "admin@example.com"}'

# 6. Compare versions
curl http://localhost:4567/versions/approval_001_v1/compare/approval_001_v2

# 7. Evaluate with active version
curl -X POST http://localhost:4567/evaluate \
  -H "Content-Type: application/json" \
  -d '{
    "rule_id": "approval_001",
    "context": {
      "amount": 500,
      "user_type": "premium"
    }
  }'

# 8. Health check
curl http://localhost:4567/health
