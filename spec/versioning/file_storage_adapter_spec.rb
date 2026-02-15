# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe DecisionAgent::Versioning::FileStorageAdapter do
  let(:storage_dir) { Dir.mktmpdir("file_storage_test") }
  let(:adapter) { described_class.new(storage_path: storage_dir) }

  after { FileUtils.rm_rf(storage_dir) }

  describe "#initialize" do
    it "creates the storage directory" do
      dir = File.join(storage_dir, "nested", "path")
      described_class.new(storage_path: dir)

      expect(Dir.exist?(dir)).to be true
    end
  end

  describe "#create_version" do
    it "creates a version with generated id and version number" do
      version = adapter.create_version(rule_id: "rule1", content: { test: true })

      expect(version[:id]).to eq("rule1_v1")
      expect(version[:rule_id]).to eq("rule1")
      expect(version[:version_number]).to eq(1)
      expect(version[:content]).to eq({ test: true })
      expect(version[:status]).to eq("active")
    end

    it "increments version number for subsequent versions" do
      adapter.create_version(rule_id: "rule1", content: { v: 1 })
      v2 = adapter.create_version(rule_id: "rule1", content: { v: 2 })

      expect(v2[:version_number]).to eq(2)
    end

    it "archives previous active version when creating new one" do
      adapter.create_version(rule_id: "rule1", content: { v: 1 })
      adapter.create_version(rule_id: "rule1", content: { v: 2 })

      versions = adapter.list_versions(rule_id: "rule1")
      statuses = versions.map { |v| v[:status] }

      expect(statuses).to contain_exactly("active", "archived")
    end

    it "persists version to disk as JSON" do
      adapter.create_version(rule_id: "rule1", content: { test: true })

      filepath = File.join(storage_dir, "rule1", "1.json")
      expect(File.exist?(filepath)).to be true

      data = JSON.parse(File.read(filepath))
      expect(data["rule_id"]).to eq("rule1")
    end

    it "validates status" do
      expect do
        adapter.create_version(rule_id: "rule1", content: { test: true }, metadata: { status: "invalid" })
      end.to raise_error(DecisionAgent::ValidationError, /Invalid status/)
    end
  end

  describe "#list_versions" do
    it "returns versions sorted by version number descending" do
      adapter.create_version(rule_id: "rule1", content: { v: 1 })
      adapter.create_version(rule_id: "rule1", content: { v: 2 })
      adapter.create_version(rule_id: "rule1", content: { v: 3 })

      versions = adapter.list_versions(rule_id: "rule1")

      expect(versions.map { |v| v[:version_number] }).to eq([3, 2, 1])
    end

    it "returns empty array for unknown rule" do
      expect(adapter.list_versions(rule_id: "unknown")).to eq([])
    end

    it "respects limit parameter" do
      3.times { |i| adapter.create_version(rule_id: "rule1", content: { v: i }) }

      versions = adapter.list_versions(rule_id: "rule1", limit: 2)

      expect(versions.size).to eq(2)
    end
  end

  describe "#list_all_versions" do
    it "returns versions across all rules" do
      adapter.create_version(rule_id: "rule1", content: { v: 1 })
      adapter.create_version(rule_id: "rule2", content: { v: 1 })

      versions = adapter.list_all_versions

      expect(versions.size).to eq(2)
    end

    it "respects limit parameter" do
      3.times { |i| adapter.create_version(rule_id: "rule#{i}", content: { v: i }) }

      versions = adapter.list_all_versions(limit: 2)

      expect(versions.size).to eq(2)
    end
  end

  describe "#get_version" do
    it "returns a specific version by id" do
      created = adapter.create_version(rule_id: "rule1", content: { test: true })

      version = adapter.get_version(version_id: created[:id])

      expect(version[:id]).to eq(created[:id])
      expect(version[:content]).to eq({ test: true })
    end

    it "returns nil for unknown version id" do
      expect(adapter.get_version(version_id: "nonexistent")).to be_nil
    end
  end

  describe "#get_version_by_number" do
    it "returns version by rule_id and version_number" do
      adapter.create_version(rule_id: "rule1", content: { v: 1 })
      adapter.create_version(rule_id: "rule1", content: { v: 2 })

      version = adapter.get_version_by_number(rule_id: "rule1", version_number: 1)

      expect(version[:version_number]).to eq(1)
    end
  end

  describe "#get_active_version" do
    it "returns the active version" do
      adapter.create_version(rule_id: "rule1", content: { v: 1 })
      adapter.create_version(rule_id: "rule1", content: { v: 2 })

      active = adapter.get_active_version(rule_id: "rule1")

      expect(active[:version_number]).to eq(2)
      expect(active[:status]).to eq("active")
    end

    it "returns nil when no versions exist" do
      expect(adapter.get_active_version(rule_id: "unknown")).to be_nil
    end
  end

  describe "#activate_version" do
    it "activates a specific version and archives others" do
      v1 = adapter.create_version(rule_id: "rule1", content: { v: 1 })
      adapter.create_version(rule_id: "rule1", content: { v: 2 })

      adapter.activate_version(version_id: v1[:id])

      active = adapter.get_active_version(rule_id: "rule1")
      expect(active[:version_number]).to eq(1)
    end

    it "raises NotFoundError for unknown version" do
      expect do
        adapter.activate_version(version_id: "nonexistent")
      end.to raise_error(DecisionAgent::NotFoundError)
    end
  end

  describe "#delete_version" do
    it "deletes an archived version" do
      adapter.create_version(rule_id: "rule1", content: { v: 1 })
      adapter.create_version(rule_id: "rule1", content: { v: 2 })

      # v1 is now archived
      result = adapter.delete_version(version_id: "rule1_v1")

      expect(result).to be true
      expect(adapter.get_version(version_id: "rule1_v1")).to be_nil
    end

    it "raises ValidationError when deleting active version" do
      adapter.create_version(rule_id: "rule1", content: { v: 1 })

      expect do
        adapter.delete_version(version_id: "rule1_v1")
      end.to raise_error(DecisionAgent::ValidationError, /Cannot delete active version/)
    end
  end

  describe "thread safety" do
    it "handles concurrent writes to different rules" do
      threads = 5.times.map do |i|
        Thread.new do
          adapter.create_version(rule_id: "rule#{i}", content: { v: 1 })
        end
      end

      threads.each(&:join)

      all_versions = adapter.list_all_versions
      expect(all_versions.size).to eq(5)
    end
  end
end
