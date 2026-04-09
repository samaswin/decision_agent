#!/usr/bin/env ruby
# frozen_string_literal: true

# DMN Versioning Tags Example
#
# Demonstrates the tag support added in DecisionAgent 1.2.0:
#
#   • Tag a version at creation time (tag: keyword)
#   • Tag a version after the fact with tag_dmn!
#   • Re-point a tag to a newer version
#   • Resolve a tag to its version
#   • List and delete tags
#   • Verify that tagging never mutates the canonical content hash

require "bundler/setup"
require "tmpdir"
require "decision_agent"
require "decision_agent/dmn/versioning"
require "decision_agent/dmn/model"
require "decision_agent/versioning/file_storage_adapter"
require "decision_agent/versioning/version_manager"

puts "=" * 60
puts "DecisionAgent 1.2.0 — DMN Versioning Tag Support"
puts "=" * 60
puts

# ── Setup ──────────────────────────────────────────────────────────────────

# Use a temporary directory so this example leaves no files behind
storage_dir = Dir.mktmpdir("decision_agent_tags_example")
at_exit { FileUtils.rm_rf(storage_dir) }

adapter         = DecisionAgent::Versioning::FileStorageAdapter.new(storage_path: storage_dir)
version_manager = DecisionAgent::Versioning::VersionManager.new(adapter: adapter)
dmn_manager     = DecisionAgent::Dmn::DmnVersionManager.new(version_manager: version_manager)

# Build a minimal DMN model
model = DecisionAgent::Dmn::Model.new(id: "loan_eligibility", name: "Loan Eligibility")

# ── Step 1: Save v1 and tag at creation time ───────────────────────────────

puts "Step 1: Save version 1 and apply the 'draft' tag at creation time"
v1 = dmn_manager.save_dmn_version(model: model, changelog: "Initial draft", tag: "draft")
puts "  Version #{v1[:version_number]} created (id: #{v1[:id]})"

tag = dmn_manager.get_dmn_tag(model_id: model.id, name: "draft")
puts "  Tag 'draft' → #{tag[:version_id]}"
puts

# ── Step 2: Save v2 and tag after the fact ─────────────────────────────────

puts "Step 2: Save version 2 (no tag at creation), then apply 'release-candidate' after"
v2 = dmn_manager.save_dmn_version(model: model, changelog: "Revised eligibility rules")
puts "  Version #{v2[:version_number]} created (id: #{v2[:id]})"

dmn_manager.tag_dmn!(model_id: model.id, version_id: v2[:id], name: "release-candidate")
tag = dmn_manager.get_dmn_tag(model_id: model.id, name: "release-candidate")
puts "  Tag 'release-candidate' → #{tag[:version_id]}"
puts

# ── Step 3: Re-point a tag to v3 ──────────────────────────────────────────

puts "Step 3: Save version 3 and re-point 'release-candidate'"
v3 = dmn_manager.save_dmn_version(model: model, changelog: "Fixed edge-case rule")
puts "  Version #{v3[:version_number]} created (id: #{v3[:id]})"

dmn_manager.tag_dmn!(model_id: model.id, version_id: v3[:id], name: "release-candidate")
tag = dmn_manager.get_dmn_tag(model_id: model.id, name: "release-candidate")
puts "  Tag 'release-candidate' now → #{tag[:version_id]} (expected: #{v3[:id]})"
raise "Tag did not re-point correctly" unless tag[:version_id] == v3[:id]
puts

# ── Step 4: List all tags ──────────────────────────────────────────────────

puts "Step 4: List all tags for the model"
tags = dmn_manager.list_dmn_tags(model_id: model.id)
tags.each do |t|
  puts "  [#{t[:name]}] → #{t[:version_id]}"
end
puts

# ── Step 5: Delete a tag ───────────────────────────────────────────────────

puts "Step 5: Delete the 'draft' tag"
deleted = dmn_manager.delete_dmn_tag(model_id: model.id, name: "draft")
puts "  Deleted: #{deleted}"
puts "  Tags remaining: #{dmn_manager.list_dmn_tags(model_id: model.id).map { |t| t[:name] }.inspect}"
puts

# ── Step 6: Determinism check ──────────────────────────────────────────────

puts "Step 6: Verify tagging does not mutate the canonical version content"
content_before = adapter.get_version(version_id: v3[:id])[:content]
dmn_manager.tag_dmn!(model_id: model.id, version_id: v3[:id], name: "final")
content_after = adapter.get_version(version_id: v3[:id])[:content]

if content_before == content_after
  puts "  Content hash unchanged — determinism OK"
else
  raise "FAIL: tagging mutated version content!"
end
puts

puts "=" * 60
puts "All tag operations completed successfully!"
puts "=" * 60
