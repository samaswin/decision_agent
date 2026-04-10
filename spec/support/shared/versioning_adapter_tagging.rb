# frozen_string_literal: true

# Shared examples for the versioning adapter tagging contract.
# Include these in any concrete adapter spec so Phase 3+ adapters inherit
# full coverage for free:
#
#   RSpec.describe MyAdapter do
#     let(:adapter) { described_class.new(...) }
#     let(:model_id) { "model_001" }
#     let(:content)  { { format: "dmn", xml: "<definitions/>" } }
#
#     it_behaves_like "a versioning adapter with tag support"
#   end
#
# The shared group assumes `adapter`, `model_id`, and `content` are defined
# in the including describe block via `let`.

RSpec.shared_examples "a versioning adapter with tag support" do
  let(:version1) { adapter.create_version(rule_id: model_id, content: content, metadata: { created_by: "test" }) }
  let(:version2) { adapter.create_version(rule_id: model_id, content: content, metadata: { created_by: "test" }) }

  # ── create_tag ─────────────────────────────────────────────────────────────

  describe "#create_tag" do
    it "returns a tag hash with the correct fields" do
      v = version1
      tag = adapter.create_tag(model_id: model_id, version_id: v[:id], name: "stable")

      expect(tag[:name]).to eq("stable")
      expect(tag[:version_id]).to eq(v[:id])
      expect(tag[:created_at]).not_to be_nil
    end

    it "re-points an existing tag to a new version (no duplicate)" do
      v1 = version1
      v2 = version2

      adapter.create_tag(model_id: model_id, version_id: v1[:id], name: "latest")
      adapter.create_tag(model_id: model_id, version_id: v2[:id], name: "latest")

      tag = adapter.get_tag(model_id: model_id, name: "latest")
      expect(tag[:version_id]).to eq(v2[:id])
      expect(adapter.list_tags(model_id: model_id).size).to eq(1)
    end

    it "raises ValidationError for a blank tag name" do
      v = version1
      expect { adapter.create_tag(model_id: model_id, version_id: v[:id], name: "") }
        .to raise_error(DecisionAgent::ValidationError)
    end

    it "raises NotFoundError when version_id does not exist" do
      expect { adapter.create_tag(model_id: model_id, version_id: "nonexistent_v99", name: "bad") }
        .to raise_error(DecisionAgent::NotFoundError)
    end

    it "accepts unicode tag names" do
      v = version1
      tag = adapter.create_tag(model_id: model_id, version_id: v[:id], name: "リリース候補")
      expect(tag[:name]).to eq("リリース候補")
    end

    it "creates a tag on a non-existent model_id" do
      v = adapter.create_version(rule_id: "other_model", content: content, metadata: {})
      tag = adapter.create_tag(model_id: "other_model", version_id: v[:id], name: "v1")
      expect(tag[:name]).to eq("v1")
    end
  end

  # ── get_tag ────────────────────────────────────────────────────────────────

  describe "#get_tag" do
    it "returns the tag hash for an existing tag" do
      v = version1
      adapter.create_tag(model_id: model_id, version_id: v[:id], name: "rc1")

      tag = adapter.get_tag(model_id: model_id, name: "rc1")
      expect(tag).not_to be_nil
      expect(tag[:name]).to eq("rc1")
      expect(tag[:version_id]).to eq(v[:id])
    end

    it "returns nil for a tag that does not exist" do
      expect(adapter.get_tag(model_id: model_id, name: "ghost")).to be_nil
    end

    it "returns the tag even when the version it points to has been deleted" do
      v1 = version1
      version2
      adapter.create_tag(model_id: model_id, version_id: v1[:id], name: "old-rc")
      # v2 is active; deactivate v1 so it can be deleted (it was archived on v2 creation)
      adapter.delete_version(version_id: v1[:id])

      # Tag still exists, it just points to a deleted version
      tag = adapter.get_tag(model_id: model_id, name: "old-rc")
      expect(tag).not_to be_nil
      expect(tag[:version_id]).to eq(v1[:id])
    end
  end

  # ── list_tags ──────────────────────────────────────────────────────────────

  describe "#list_tags" do
    it "returns an empty array when no tags exist" do
      expect(adapter.list_tags(model_id: model_id)).to eq([])
    end

    it "returns all tags sorted by name" do
      v = version1
      adapter.create_tag(model_id: model_id, version_id: v[:id], name: "zebra")
      adapter.create_tag(model_id: model_id, version_id: v[:id], name: "alpha")
      adapter.create_tag(model_id: model_id, version_id: v[:id], name: "beta")

      names = adapter.list_tags(model_id: model_id).map { |t| t[:name] }
      expect(names).to eq(%w[alpha beta zebra])
    end

    it "does not mix tags across different models" do
      v = version1
      adapter.create_tag(model_id: model_id, version_id: v[:id], name: "shared-name")

      other_v = adapter.create_version(rule_id: "other_model", content: content, metadata: {})
      adapter.create_tag(model_id: "other_model", version_id: other_v[:id], name: "other-tag")

      expect(adapter.list_tags(model_id: model_id).map { |t| t[:name] }).to eq(["shared-name"])
    end
  end

  # ── delete_tag ─────────────────────────────────────────────────────────────

  describe "#delete_tag" do
    it "returns true and removes the tag" do
      v = version1
      adapter.create_tag(model_id: model_id, version_id: v[:id], name: "to-remove")

      result = adapter.delete_tag(model_id: model_id, name: "to-remove")
      expect(result).to be true
      expect(adapter.get_tag(model_id: model_id, name: "to-remove")).to be_nil
    end

    it "returns false when the tag does not exist" do
      expect(adapter.delete_tag(model_id: model_id, name: "phantom")).to be false
    end

    it "only deletes the named tag, leaving others intact" do
      v = version1
      adapter.create_tag(model_id: model_id, version_id: v[:id], name: "keep")
      adapter.create_tag(model_id: model_id, version_id: v[:id], name: "remove")

      adapter.delete_tag(model_id: model_id, name: "remove")

      expect(adapter.get_tag(model_id: model_id, name: "keep")).not_to be_nil
      expect(adapter.get_tag(model_id: model_id, name: "remove")).to be_nil
    end
  end

  # ── determinism regression ─────────────────────────────────────────────────

  describe "determinism regression" do
    it "tagging does not mutate the content of any existing version" do
      v1 = adapter.create_version(rule_id: model_id, content: content, metadata: {})
      content_before = adapter.get_version(version_id: v1[:id])[:content]

      adapter.create_tag(model_id: model_id, version_id: v1[:id], name: "immutable-test")

      content_after = adapter.get_version(version_id: v1[:id])[:content]
      expect(content_after).to eq(content_before)
    end
  end
end
