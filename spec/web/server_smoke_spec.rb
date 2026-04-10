# frozen_string_literal: true

require "spec_helper"
require "rack/test"
require "tempfile"
require_relative "../../lib/decision_agent/web/server"

# Every routed HTML page the server serves
UI_PAGES = {
  "/" => "index",
  "/testing/batch" => "batch testing",
  "/simulation" => "simulation dashboard",
  "/simulation/replay" => "simulation replay",
  "/simulation/whatif" => "simulation what-if",
  "/simulation/impact" => "simulation impact",
  "/simulation/shadow" => "simulation shadow",
  "/auth/login" => "login",
  "/auth/users" => "user management",
  "/dmn/editor" => "DMN editor"
}.freeze

# Every asset referenced by <link> or <script src> across all HTML pages
LINKED_ASSETS = {
  "/styles.css" => "text/css",
  "/app.js" => "application/javascript",
  "/dmn-editor.css" => "text/css",
  "/dmn-editor.js" => "application/javascript",
  "/sample_rules.json" => "application/json",
  "/sample_batch.csv" => "text/csv",
  "/sample_replay.csv" => "text/csv",
  "/sample_shadow.csv" => "text/csv",
  "/sample_impact.csv" => "text/csv",
  "/sample_whatif.csv" => "text/csv"
}.freeze

RSpec.describe "Web UI smoke" do
  include Rack::Test::Methods

  let(:app) { DecisionAgent::Web::Server }

  describe "HTML pages" do
    UI_PAGES.each do |path, label|
      it "GET #{path} (#{label}) returns 200 with text/html" do
        get path
        expect(last_response.status).to eq(200),
                                        "Expected 200 for #{path}, got #{last_response.status}: #{last_response.body[0, 120]}"
        expect(last_response.content_type).to include("text/html"),
                                              "Expected text/html for #{path}, got #{last_response.content_type}"
      end
    end
  end

  describe "linked assets" do
    LINKED_ASSETS.each do |path, expected_type|
      it "GET #{path} returns 200 with #{expected_type}" do
        get path
        expect(last_response.status).to eq(200),
                                        "Asset #{path} returned #{last_response.status} (expected 200)"
        expect(last_response.content_type).to include(expected_type),
                                              "Asset #{path}: expected Content-Type #{expected_type}, got #{last_response.content_type}"
      end
    end
  end

  describe "JS null-guard static analysis (dmn-editor.js)" do
    let(:js_path) { File.join(DecisionAgent::Web::Server::PUBLIC_FOLDER, "dmn-editor.js") }
    let(:js_lines) { File.read(js_path).lines }

    # Returns lines that access a state property without a preceding null guard.
    # Looks back up to 40 lines for an `if (!state.<field>` guard.
    # Guard lines themselves (if (!state.currentX ...) are skipped.
    def unguarded_accesses(lines, field_re, guard_re)
      lines.each_with_index.filter_map do |line, i|
        # Skip optional chaining (already safe)
        next if line.match?(/state\.#{field_re}\?\./)
        # Skip assignments (state.currentX = ...)
        next if line.match?(/state\.#{field_re}\s*=[^=]/)
        # Skip lines that ARE guard conditions themselves
        next if line.match?(/if\s*\(.*!state\.#{field_re}\b/)
        # Only flag direct property access (state.currentX.something)
        next unless line.match?(/state\.#{field_re}\.[a-zA-Z_]/)

        look_back = lines[[0, i - 40].max...i].join
        guarded = look_back.match?(/if\s*\(.*!state\.#{guard_re}\b/)
        guarded ? nil : "  Line #{i + 1}: #{line.strip}"
      end
    end

    it "every state.currentModel property access is preceded by a null guard" do
      bad = unguarded_accesses(js_lines, "currentModel", "currentModel")
      expect(bad).to be_empty,
                     "Unguarded state.currentModel accesses in dmn-editor.js:\n#{bad.join("\n")}"
    end

    it "every state.currentDecision property access is preceded by a null guard" do
      bad = unguarded_accesses(js_lines, "currentDecision", "currentDecision")
      expect(bad).to be_empty,
                     "Unguarded state.currentDecision accesses in dmn-editor.js:\n#{bad.join("\n")}"
    end
  end

  describe "batch import endpoint MIME validation" do
    def write_temp_file(content, suffix)
      tmp = Tempfile.new(["smoke_upload", suffix])
      tmp.write(content)
      tmp.rewind
      tmp
    end

    it "rejects uploads with unsupported file extensions" do
      tmp = write_temp_file("bad content", ".txt")
      upload = Rack::Test::UploadedFile.new(tmp.path, "text/plain", true, original_filename: "scenarios.txt")
      post "/api/testing/batch/import", { file: upload }
      tmp.close
      tmp.unlink
      expect(last_response.status).to eq(422)
      body = JSON.parse(last_response.body)
      expect(body["error"]).to match(/unsupported file type/i)
    end

    it "accepts .csv uploads without a type-rejection error" do
      csv_content = "input.age,input.income,expected.decision\n30,50000,approve"
      tmp = write_temp_file(csv_content, ".csv")
      upload = Rack::Test::UploadedFile.new(tmp.path, "text/csv", false, original_filename: "scenarios.csv")
      post "/api/testing/batch/import", { file: upload }
      tmp.close
      tmp.unlink
      # 201 on success, 422 with import-level errors — neither is a type rejection
      body = JSON.parse(last_response.body)
      expect(body["error"].to_s).not_to match(/unsupported file type/i)
    end
  end
end
