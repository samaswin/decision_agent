# frozen_string_literal: true

require "spec_helper"
require "active_record"
require "decision_agent/versioning/activerecord_adapter"
require "support/shared/versioning_adapter_tagging"

RSpec.describe DecisionAgent::Versioning::ActiveRecordAdapter do
  # Setup in-memory SQLite database for testing
  before(:all) do
    ActiveRecord::Base.establish_connection(
      adapter: "sqlite3",
      database: "file:ar_versioning_test?mode=memory&cache=shared",
      flags: SQLite3::Constants::Open::URI | SQLite3::Constants::Open::READWRITE | SQLite3::Constants::Open::CREATE,
      pool: 10,
      checkout_timeout: 10
    )

    ActiveRecord::Base.connection.execute("PRAGMA journal_mode=WAL")
    ActiveRecord::Base.connection.execute("PRAGMA busy_timeout=5000")

    ActiveRecord::Schema.define do
      create_table :rule_versions, force: true do |t|
        t.string  :rule_id,        null: false
        t.integer :version_number, null: false
        t.text    :content,        null: false
        t.string  :created_by,     null: false, default: "system"
        t.text    :changelog
        t.string  :status, null: false, default: "draft"
        t.timestamps
      end

      add_index :rule_versions, %i[rule_id version_number], unique: true, name: "idx_rv_rule_version_unique"
      add_index :rule_versions, %i[rule_id status],         name: "idx_rv_rule_status"

      create_table :rule_version_tags, force: true do |t|
        t.string :model_id,   null: false
        t.string :name,       null: false
        t.bigint :version_id, null: false
        t.timestamps
      end

      add_index :rule_version_tags, %i[model_id name], unique: true, name: "idx_rvt_model_name_unique"
      add_index :rule_version_tags, :model_id,                       name: "idx_rvt_model_id"
    end

    # rubocop:disable Lint/ConstantDefinitionInBlock
    class RuleVersion < ActiveRecord::Base
      validates :rule_id,        presence: true
      validates :version_number, presence: true, uniqueness: { scope: :rule_id }
      validates :content,        presence: true
      validates :status,         inclusion: { in: %w[draft active archived] }
      validates :created_by,     presence: true
    end

    class RuleVersionTag < ActiveRecord::Base
      validates :model_id,   presence: true
      validates :name,       presence: true
      validates :version_id, presence: true
      validates :name, uniqueness: { scope: :model_id }
    end
    # rubocop:enable Lint/ConstantDefinitionInBlock

    RuleVersion.reset_column_information
    RuleVersionTag.reset_column_information
  end

  before do
    RuleVersion.delete_all
    RuleVersionTag.delete_all
  end

  let(:adapter)   { described_class.new }
  let(:model_id)  { "model_001" }
  let(:content)   { { format: "dmn", xml: "<definitions/>" } }

  # ── Shared tagging contract ───────────────────────────────────────────────

  it_behaves_like "a versioning adapter with tag support"

  # ── create_version ────────────────────────────────────────────────────────

  describe "#create_version" do
    it "creates a version with auto-incremented version_number" do
      v = adapter.create_version(rule_id: model_id, content: content)

      expect(v[:id]).not_to be_nil
      expect(v[:rule_id]).to eq(model_id)
      expect(v[:version_number]).to eq(1)
      expect(v[:content]).to eq(content.transform_keys(&:to_s))
      expect(v[:status]).to eq("active")
    end

    it "increments version_number for each new version" do
      adapter.create_version(rule_id: model_id, content: content)
      v2 = adapter.create_version(rule_id: model_id, content: content)

      expect(v2[:version_number]).to eq(2)
    end

    it "archives previous active version when a new one is created" do
      v1 = adapter.create_version(rule_id: model_id, content: content)
      adapter.create_version(rule_id: model_id, content: content)

      v1_refreshed = adapter.get_version(version_id: v1[:id])
      expect(v1_refreshed[:status]).to eq("archived")
    end

    it "accepts draft status via metadata" do
      v = adapter.create_version(rule_id: model_id, content: content, metadata: { status: "draft" })
      expect(v[:status]).to eq("draft")
    end

    it "raises ValidationError for an invalid status" do
      expect do
        adapter.create_version(rule_id: model_id, content: content, metadata: { status: "unknown" })
      end.to raise_error(DecisionAgent::ValidationError)
    end

    it "stores created_by and changelog from metadata" do
      v = adapter.create_version(
        rule_id: model_id,
        content: content,
        metadata: { created_by: "alice", changelog: "initial release" }
      )

      expect(v[:created_by]).to eq("alice")
      expect(v[:changelog]).to eq("initial release")
    end
  end

  # ── list_versions ─────────────────────────────────────────────────────────

  describe "#list_versions" do
    it "returns versions in descending order" do
      adapter.create_version(rule_id: model_id, content: content)
      adapter.create_version(rule_id: model_id, content: content)

      versions = adapter.list_versions(rule_id: model_id)
      expect(versions.map { |v| v[:version_number] }).to eq([2, 1])
    end

    it "returns an empty array when no versions exist" do
      expect(adapter.list_versions(rule_id: "nonexistent")).to eq([])
    end

    it "respects the limit parameter" do
      3.times { adapter.create_version(rule_id: model_id, content: content) }
      expect(adapter.list_versions(rule_id: model_id, limit: 2).size).to eq(2)
    end

    it "does not mix versions across different rules" do
      adapter.create_version(rule_id: model_id, content: content)
      adapter.create_version(rule_id: "other_rule", content: content)

      expect(adapter.list_versions(rule_id: model_id).size).to eq(1)
    end
  end

  # ── get_version ───────────────────────────────────────────────────────────

  describe "#get_version" do
    it "returns the version hash for an existing version" do
      v = adapter.create_version(rule_id: model_id, content: content)
      found = adapter.get_version(version_id: v[:id])

      expect(found[:id]).to eq(v[:id])
      expect(found[:version_number]).to eq(1)
    end

    it "returns nil for a non-existent version_id" do
      expect(adapter.get_version(version_id: 999_999)).to be_nil
    end
  end

  # ── get_version_by_number ─────────────────────────────────────────────────

  describe "#get_version_by_number" do
    it "returns the correct version" do
      adapter.create_version(rule_id: model_id, content: content)
      adapter.create_version(rule_id: model_id, content: content)

      v = adapter.get_version_by_number(rule_id: model_id, version_number: 1)
      expect(v[:version_number]).to eq(1)
    end

    it "returns nil when the version_number does not exist" do
      expect(adapter.get_version_by_number(rule_id: model_id, version_number: 99)).to be_nil
    end
  end

  # ── get_active_version ────────────────────────────────────────────────────

  describe "#get_active_version" do
    it "returns the currently active version" do
      adapter.create_version(rule_id: model_id, content: content)
      v2 = adapter.create_version(rule_id: model_id, content: content)

      active = adapter.get_active_version(rule_id: model_id)
      expect(active[:id]).to eq(v2[:id])
    end

    it "returns nil when no version exists" do
      expect(adapter.get_active_version(rule_id: "ghost")).to be_nil
    end
  end

  # ── activate_version ──────────────────────────────────────────────────────

  describe "#activate_version" do
    it "activates the specified version and archives others" do
      v1 = adapter.create_version(rule_id: model_id, content: content)
      adapter.create_version(rule_id: model_id, content: content) # v2 is now active

      adapter.activate_version(version_id: v1[:id])

      expect(adapter.get_active_version(rule_id: model_id)[:id]).to eq(v1[:id])
      v2_refreshed = adapter.get_version(version_id: adapter.list_versions(rule_id: model_id).first[:id])
      expect(v2_refreshed[:status]).to eq("archived")
    end

    it "atomicity — only one active version per rule after concurrent activations" do
      v1 = adapter.create_version(rule_id: model_id, content: content)
      v2 = adapter.create_version(rule_id: model_id, content: content)

      threads = [
        Thread.new { adapter.activate_version(version_id: v1[:id]) },
        Thread.new { adapter.activate_version(version_id: v2[:id]) }
      ]
      threads.each(&:join)

      active_versions = adapter.list_versions(rule_id: model_id).select { |v| v[:status] == "active" }
      expect(active_versions.size).to eq(1)
    end
  end

  # ── delete_version ────────────────────────────────────────────────────────

  describe "#delete_version" do
    it "deletes a non-active version and returns true" do
      v1 = adapter.create_version(rule_id: model_id, content: content)
      adapter.create_version(rule_id: model_id, content: content) # v2 becomes active; v1 archived

      expect(adapter.delete_version(version_id: v1[:id])).to be true
      expect(adapter.get_version(version_id: v1[:id])).to be_nil
    end

    it "refuses to delete the active version" do
      v = adapter.create_version(rule_id: model_id, content: content)

      expect do
        adapter.delete_version(version_id: v[:id])
      end.to raise_error(DecisionAgent::ValidationError, /Cannot delete active version/)
    end

    it "raises NotFoundError for a non-existent version" do
      expect do
        adapter.delete_version(version_id: 999_999)
      end.to raise_error(DecisionAgent::NotFoundError)
    end

    it "does not cascade-delete tags pointing to the deleted version" do
      v1 = adapter.create_version(rule_id: model_id, content: content)
      v2 = adapter.create_version(rule_id: model_id, content: content) # archives v1

      adapter.create_tag(model_id: model_id, version_id: v1[:id], name: "old-release")
      adapter.delete_version(version_id: v1[:id])

      # Tag still exists — points to now-deleted version
      tag = adapter.get_tag(model_id: model_id, name: "old-release")
      expect(tag).not_to be_nil
      expect(tag[:version_id]).to eq(v1[:id])

      # Suppress unused variable warning
      _ = v2
    end
  end

  # ── list_all_versions ─────────────────────────────────────────────────────

  describe "#list_all_versions" do
    it "returns versions across all rules" do
      adapter.create_version(rule_id: "rule_a", content: content)
      adapter.create_version(rule_id: "rule_b", content: content)

      expect(adapter.list_all_versions.size).to eq(2)
    end

    it "respects the limit parameter" do
      3.times { |i| adapter.create_version(rule_id: "rule_#{i}", content: content) }
      expect(adapter.list_all_versions(limit: 2).size).to eq(2)
    end
  end
end
