# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "decision_agent/dmn/versioning"
require "decision_agent/dmn/model"
require "decision_agent/versioning/file_storage_adapter"
require "decision_agent/versioning/version_manager"
require_relative "../support/shared/versioning_adapter_tagging"

RSpec.describe DecisionAgent::Dmn::DmnVersionManager do
  let(:temp_dir) { Dir.mktmpdir }
  let(:adapter) { DecisionAgent::Versioning::FileStorageAdapter.new(storage_path: temp_dir) }
  let(:version_manager) { DecisionAgent::Versioning::VersionManager.new(adapter: adapter) }
  let(:dmn_manager) { described_class.new(version_manager: version_manager) }

  let(:model) do
    DecisionAgent::Dmn::Model.new(id: "loan_eligibility", name: "Loan Eligibility")
  end

  after { FileUtils.rm_rf(temp_dir) }

  # ── integration: tag at creation time ──────────────────────────────────────

  describe "#save_dmn_version with tag:" do
    it "applies a tag to the newly created version" do
      dmn_manager.save_dmn_version(model: model, tag: "initial-release")

      tag = dmn_manager.get_dmn_tag(model_id: model.id, name: "initial-release")
      expect(tag).not_to be_nil
      expect(tag[:name]).to eq("initial-release")
    end

    it "does not create a tag when tag: is not given" do
      dmn_manager.save_dmn_version(model: model)
      expect(dmn_manager.list_dmn_tags(model_id: model.id)).to be_empty
    end
  end

  # ── integration: tag! (tag after the fact) ─────────────────────────────────

  describe "#tag_dmn!" do
    it "creates a tag pointing to a specific version" do
      version = dmn_manager.save_dmn_version(model: model)
      dmn_manager.tag_dmn!(model_id: model.id, version_id: version[:id], name: "release-candidate")

      tag = dmn_manager.get_dmn_tag(model_id: model.id, name: "release-candidate")
      expect(tag[:version_id]).to eq(version[:id])
    end

    it "re-points an existing tag to a newer version" do
      v1 = dmn_manager.save_dmn_version(model: model)
      dmn_manager.tag_dmn!(model_id: model.id, version_id: v1[:id], name: "release-candidate")

      v2 = dmn_manager.save_dmn_version(model: model)
      dmn_manager.tag_dmn!(model_id: model.id, version_id: v2[:id], name: "release-candidate")

      tag = dmn_manager.get_dmn_tag(model_id: model.id, name: "release-candidate")
      expect(tag[:version_id]).to eq(v2[:id])
    end
  end

  # ── integration: resolve tag ───────────────────────────────────────────────

  describe "#get_dmn_tag" do
    it "returns nil for a non-existent tag" do
      expect(dmn_manager.get_dmn_tag(model_id: model.id, name: "ghost")).to be_nil
    end

    it "returns the tag hash for a known tag" do
      version = dmn_manager.save_dmn_version(model: model)
      dmn_manager.tag_dmn!(model_id: model.id, version_id: version[:id], name: "stable")

      tag = dmn_manager.get_dmn_tag(model_id: model.id, name: "stable")
      expect(tag[:name]).to eq("stable")
      expect(tag[:version_id]).to eq(version[:id])
    end
  end

  # ── integration: list tags ─────────────────────────────────────────────────

  describe "#list_dmn_tags" do
    it "returns an empty array when no tags have been created" do
      expect(dmn_manager.list_dmn_tags(model_id: model.id)).to be_empty
    end

    it "returns all tags for the model sorted by name" do
      version = dmn_manager.save_dmn_version(model: model)
      dmn_manager.tag_dmn!(model_id: model.id, version_id: version[:id], name: "zebra")
      dmn_manager.tag_dmn!(model_id: model.id, version_id: version[:id], name: "alpha")

      names = dmn_manager.list_dmn_tags(model_id: model.id).map { |t| t[:name] }
      expect(names).to eq(%w[alpha zebra])
    end
  end

  # ── integration: delete tag ────────────────────────────────────────────────

  describe "#delete_dmn_tag" do
    it "returns true and removes the tag" do
      version = dmn_manager.save_dmn_version(model: model)
      dmn_manager.tag_dmn!(model_id: model.id, version_id: version[:id], name: "to-drop")

      expect(dmn_manager.delete_dmn_tag(model_id: model.id, name: "to-drop")).to be true
      expect(dmn_manager.get_dmn_tag(model_id: model.id, name: "to-drop")).to be_nil
    end

    it "returns false when the tag does not exist" do
      expect(dmn_manager.delete_dmn_tag(model_id: model.id, name: "phantom")).to be false
    end
  end

  # ── integration: full lifecycle ────────────────────────────────────────────

  describe "full tag lifecycle" do
    it "create model → v1 → tag rc → create v2 → re-tag rc → resolve to v2" do
      # Create model and first version
      v1 = dmn_manager.save_dmn_version(model: model, changelog: "Initial version")

      # Tag v1 as release-candidate
      dmn_manager.tag_dmn!(model_id: model.id, version_id: v1[:id], name: "release-candidate")
      expect(dmn_manager.get_dmn_tag(model_id: model.id, name: "release-candidate")[:version_id]).to eq(v1[:id])

      # Create v2
      v2 = dmn_manager.save_dmn_version(model: model, changelog: "Revised version")

      # Re-point release-candidate to v2
      dmn_manager.tag_dmn!(model_id: model.id, version_id: v2[:id], name: "release-candidate")

      # Resolve tag — must return v2
      tag = dmn_manager.get_dmn_tag(model_id: model.id, name: "release-candidate")
      expect(tag[:version_id]).to eq(v2[:id])

      # Only one tag with that name should exist
      all_tags = dmn_manager.list_dmn_tags(model_id: model.id)
      rc_tags = all_tags.select { |t| t[:name] == "release-candidate" }
      expect(rc_tags.size).to eq(1)
    end
  end

  # ── determinism regression ─────────────────────────────────────────────────

  describe "determinism regression" do
    it "tagging does not change the content hash of any saved version" do
      version = dmn_manager.save_dmn_version(model: model)
      content_before = adapter.get_version(version_id: version[:id])[:content]

      dmn_manager.tag_dmn!(model_id: model.id, version_id: version[:id], name: "immutability-check")

      content_after = adapter.get_version(version_id: version[:id])[:content]
      expect(content_after).to eq(content_before)
    end
  end
end

# ── FileStorageAdapter contract tests for tag support ──────────────────────

RSpec.describe DecisionAgent::Versioning::FileStorageAdapter do
  let(:temp_dir) { Dir.mktmpdir }
  let(:adapter) { described_class.new(storage_path: temp_dir) }
  let(:model_id) { "contract_model_001" }
  let(:content) { { format: "dmn", xml: "<definitions/>" } }

  after { FileUtils.rm_rf(temp_dir) }

  it_behaves_like "a versioning adapter with tag support"
end
