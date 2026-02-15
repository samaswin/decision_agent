# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe DecisionAgent::Versioning::VersionManager do
  let(:storage_dir) { Dir.mktmpdir("version_manager_test") }
  let(:adapter) { DecisionAgent::Versioning::FileStorageAdapter.new(storage_path: storage_dir) }
  let(:manager) { described_class.new(adapter: adapter) }

  after { FileUtils.rm_rf(storage_dir) }

  describe "#save_version" do
    it "saves a new version" do
      version = manager.save_version(rule_id: "rule1", rule_content: { decision: "approve" })

      expect(version[:rule_id]).to eq("rule1")
      expect(version[:version_number]).to eq(1)
      expect(version[:content]).to eq({ decision: "approve" })
      expect(version[:status]).to eq("active")
    end

    it "increments version number" do
      manager.save_version(rule_id: "rule1", rule_content: { v: 1 })
      v2 = manager.save_version(rule_id: "rule1", rule_content: { v: 2 })

      expect(v2[:version_number]).to eq(2)
    end

    it "records created_by and changelog" do
      version = manager.save_version(
        rule_id: "rule1",
        rule_content: { test: true },
        created_by: "alice",
        changelog: "Initial version"
      )

      expect(version[:created_by]).to eq("alice")
      expect(version[:changelog]).to eq("Initial version")
    end

    it "auto-generates changelog when not provided" do
      version = manager.save_version(rule_id: "rule1", rule_content: { test: true })

      expect(version[:changelog]).to match(/Version \d+/)
    end

    it "raises ValidationError for nil content" do
      expect do
        manager.save_version(rule_id: "rule1", rule_content: nil)
      end.to raise_error(DecisionAgent::ValidationError, /cannot be nil/)
    end

    it "raises ValidationError for non-Hash content" do
      expect do
        manager.save_version(rule_id: "rule1", rule_content: "string")
      end.to raise_error(DecisionAgent::ValidationError, /must be a Hash/)
    end

    it "raises ValidationError for empty Hash content" do
      expect do
        manager.save_version(rule_id: "rule1", rule_content: {})
      end.to raise_error(DecisionAgent::ValidationError, /cannot be empty/)
    end
  end

  describe "#get_versions" do
    it "returns versions for a rule sorted by version number descending" do
      manager.save_version(rule_id: "rule1", rule_content: { v: 1 })
      manager.save_version(rule_id: "rule1", rule_content: { v: 2 })

      versions = manager.get_versions(rule_id: "rule1")

      expect(versions.size).to eq(2)
      expect(versions.first[:version_number]).to eq(2)
    end

    it "returns empty array for unknown rule" do
      expect(manager.get_versions(rule_id: "unknown")).to eq([])
    end

    it "respects limit parameter" do
      3.times { |i| manager.save_version(rule_id: "rule1", rule_content: { v: i }) }

      versions = manager.get_versions(rule_id: "rule1", limit: 2)

      expect(versions.size).to eq(2)
    end
  end

  describe "#list_all_versions" do
    it "returns versions across all rules" do
      manager.save_version(rule_id: "rule1", rule_content: { v: 1 })
      manager.save_version(rule_id: "rule2", rule_content: { v: 1 })

      versions = manager.list_all_versions

      expect(versions.size).to eq(2)
    end
  end

  describe "#get_version" do
    it "returns a specific version by id" do
      saved = manager.save_version(rule_id: "rule1", rule_content: { test: true })

      version = manager.get_version(version_id: saved[:id])

      expect(version[:id]).to eq(saved[:id])
    end

    it "returns nil for unknown version id" do
      expect(manager.get_version(version_id: "nonexistent")).to be_nil
    end
  end

  describe "#get_active_version" do
    it "returns the active version for a rule" do
      manager.save_version(rule_id: "rule1", rule_content: { v: 1 })
      manager.save_version(rule_id: "rule1", rule_content: { v: 2 })

      active = manager.get_active_version(rule_id: "rule1")

      expect(active[:version_number]).to eq(2)
      expect(active[:status]).to eq("active")
    end

    it "returns nil when no versions exist" do
      expect(manager.get_active_version(rule_id: "unknown")).to be_nil
    end
  end

  describe "#rollback" do
    it "activates a previous version" do
      v1 = manager.save_version(rule_id: "rule1", rule_content: { v: 1 })
      manager.save_version(rule_id: "rule1", rule_content: { v: 2 })

      manager.rollback(version_id: v1[:id])

      active = manager.get_active_version(rule_id: "rule1")
      expect(active[:version_number]).to eq(1)
    end
  end

  describe "#compare" do
    it "compares two versions" do
      v1 = manager.save_version(rule_id: "rule1", rule_content: { decision: "approve" })
      v2 = manager.save_version(rule_id: "rule1", rule_content: { decision: "reject" })

      comparison = manager.compare(version_id_1: v1[:id], version_id_2: v2[:id])

      expect(comparison[:version_1][:id]).to eq(v1[:id])
      expect(comparison[:version_2][:id]).to eq(v2[:id])
      expect(comparison).to have_key(:differences)
    end
  end

  describe "#get_history" do
    it "returns history with statistics" do
      manager.save_version(rule_id: "rule1", rule_content: { v: 1 })
      manager.save_version(rule_id: "rule1", rule_content: { v: 2 })

      history = manager.get_history(rule_id: "rule1")

      expect(history[:rule_id]).to eq("rule1")
      expect(history[:total_versions]).to eq(2)
      expect(history[:active_version]).not_to be_nil
      expect(history[:versions].size).to eq(2)
    end
  end

  describe "#delete_version" do
    it "deletes an archived version" do
      manager.save_version(rule_id: "rule1", rule_content: { v: 1 })
      manager.save_version(rule_id: "rule1", rule_content: { v: 2 })

      # v1 is now archived, can be deleted
      v1 = manager.get_versions(rule_id: "rule1").find { |v| v[:version_number] == 1 }
      result = manager.delete_version(version_id: v1[:id])

      expect(result).to be true
      expect(manager.get_versions(rule_id: "rule1").size).to eq(1)
    end

    it "raises ValidationError when deleting an active version" do
      v1 = manager.save_version(rule_id: "rule1", rule_content: { v: 1 })

      expect do
        manager.delete_version(version_id: v1[:id])
      end.to raise_error(DecisionAgent::ValidationError, /Cannot delete active version/)
    end
  end
end
