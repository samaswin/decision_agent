require "spec_helper"

RSpec.describe DecisionAgent::Auth::AccessAuditLogger do
  let(:adapter) { DecisionAgent::Auth::Audit::InMemoryAccessAdapter.new }
  let(:logger) { DecisionAgent::Auth::AccessAuditLogger.new(adapter: adapter) }

  describe "#log_authentication" do
    it "logs successful login" do
      logger.log_authentication(
        "login",
        user_id: "user123",
        email: "test@example.com",
        success: true
      )

      logs = adapter.all_logs
      expect(logs.size).to eq(1)
      expect(logs.first[:event_type]).to eq("login")
      expect(logs.first[:user_id]).to eq("user123")
      expect(logs.first[:success]).to be true
    end

    it "logs failed login" do
      logger.log_authentication(
        "login",
        user_id: nil,
        email: "test@example.com",
        success: false,
        reason: "Invalid password"
      )

      logs = adapter.all_logs
      expect(logs.size).to eq(1)
      expect(logs.first[:success]).to be false
      expect(logs.first[:reason]).to eq("Invalid password")
    end
  end

  describe "#log_permission_check" do
    it "logs permission check" do
      logger.log_permission_check(
        user_id: "user123",
        permission: :write,
        resource_type: "rule",
        resource_id: "rule456",
        granted: true
      )

      logs = adapter.all_logs
      expect(logs.size).to eq(1)
      expect(logs.first[:event_type]).to eq("permission_check")
      expect(logs.first[:permission]).to eq("write")
      expect(logs.first[:granted]).to be true
    end
  end

  describe "#log_access" do
    it "logs access event" do
      logger.log_access(
        user_id: "user123",
        action: "create",
        resource_type: "rule",
        resource_id: "rule456",
        success: true
      )

      logs = adapter.all_logs
      expect(logs.size).to eq(1)
      expect(logs.first[:event_type]).to eq("access")
      expect(logs.first[:action]).to eq("create")
    end
  end

  describe "#query" do
    before do
      logger.log_authentication("login", user_id: "user1", email: "user1@example.com", success: true)
      logger.log_authentication("login", user_id: "user2", email: "user2@example.com", success: true)
      logger.log_permission_check(user_id: "user1", permission: :write, granted: true)
    end

    it "filters by user_id" do
      logs = logger.query(user_id: "user1")
      expect(logs.size).to eq(2)
      expect(logs.all? { |log| log[:user_id] == "user1" }).to be true
    end

    it "filters by event_type" do
      logs = logger.query(event_type: "login")
      expect(logs.size).to eq(2)
      expect(logs.all? { |log| log[:event_type] == "login" }).to be true
    end

    it "filters by start_time" do
      start_time = Time.now.utc - 3600
      logger.log_authentication("login", user_id: "user3", email: "user3@example.com", success: true)

      logs = logger.query(start_time: start_time)
      expect(logs.size).to be >= 1
    end

    it "limits results" do
      logs = logger.query(limit: 2)
      expect(logs.size).to eq(2)
    end
  end
end

RSpec.describe DecisionAgent::Auth::Audit::InMemoryAccessAdapter do
  let(:adapter) { DecisionAgent::Auth::Audit::InMemoryAccessAdapter.new }

  describe "#record_access" do
    it "stores log entries" do
      adapter.record_access({ event_type: "test", user_id: "user1" })
      expect(adapter.all_logs.size).to eq(1)
    end
  end

  describe "#query_access_logs" do
    before do
      adapter.record_access({ event_type: "login", user_id: "user1", timestamp: Time.now.utc.iso8601 })
      adapter.record_access({ event_type: "logout", user_id: "user1", timestamp: Time.now.utc.iso8601 })
      adapter.record_access({ event_type: "login", user_id: "user2", timestamp: Time.now.utc.iso8601 })
    end

    it "filters by user_id" do
      logs = adapter.query_access_logs(user_id: "user1")
      expect(logs.size).to eq(2)
    end

    it "filters by event_type" do
      logs = adapter.query_access_logs(event_type: "login")
      expect(logs.size).to eq(2)
    end
  end
end

