# Example 2: Rails Integration with ActiveRecord
#
# This example demonstrates how to use DecisionAgent versioning
# in a Rails application with ActiveRecord models.
#
# Setup:
#   1. Add to Gemfile: gem 'decision_agent'
#   2. Run: rails generate decision_agent:install
#   3. Run: rails db:migrate
#
# Then use in your Rails app:

# ========================================
# In a Rails Controller (e.g., RulesController)
# ========================================

class RulesController < ApplicationController
  before_action :authenticate_user!  # Your auth method

  # GET /rules
  def index
    @rules = Rule.active.includes(:rule_versions)
  end

  # GET /rules/:id
  def show
    @rule = Rule.find_by!(rule_id: params[:id])
    @active_version = @rule.active_version
    @version_history = @rule.versions.limit(10)
  end

  # POST /rules
  def create
    @rule = Rule.new(rule_params)

    if @rule.save
      # Create initial version
      version = @rule.create_version(
        content: params[:rule_content],
        created_by: current_user.email,
        changelog: "Initial version"
      )

      render json: { rule: @rule, version: version }, status: :created
    else
      render json: { errors: @rule.errors }, status: :unprocessable_entity
    end
  end

  # PATCH /rules/:id/versions
  def create_version
    @rule = Rule.find_by!(rule_id: params[:id])

    version = @rule.create_version(
      content: params[:rule_content],
      created_by: current_user.email,
      changelog: params[:changelog] || "Updated rules"
    )

    render json: version, status: :created
  rescue DecisionAgent::ValidationError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # GET /rules/:id/versions
  def versions
    @rule = Rule.find_by!(rule_id: params[:id])
    @versions = @rule.versions.page(params[:page])

    render json: @versions
  end

  # GET /rules/:id/versions/:version_id
  def show_version
    @version = RuleVersion.find(params[:version_id])
    render json: @version
  end

  # POST /rules/:id/versions/:version_id/activate
  def activate_version
    @version = RuleVersion.find(params[:version_id])

    @version.activate!

    # Log the rollback
    Rails.logger.info("Rule #{@version.rule_id} rolled back to v#{@version.version_number} by #{current_user.email}")

    render json: @version
  end

  # GET /rules/:id/versions/:v1/compare/:v2
  def compare_versions
    v1 = RuleVersion.find(params[:version_id_1])
    v2 = RuleVersion.find(params[:version_id_2])

    comparison = v1.compare_with(v2)

    render json: comparison
  end

  private

  def rule_params
    params.require(:rule).permit(:rule_id, :ruleset, :description, :status)
  end
end

# ========================================
# In routes.rb
# ========================================

Rails.application.routes.draw do
  resources :rules, param: :rule_id do
    member do
      get 'versions', to: 'rules#versions'
      post 'versions', to: 'rules#create_version'

      get 'versions/:version_id', to: 'rules#show_version', as: :version
      post 'versions/:version_id/activate', to: 'rules#activate_version'
      get 'versions/:version_id_1/compare/:version_id_2', to: 'rules#compare_versions'
    end
  end
end

# ========================================
# Usage in Rails Console
# ========================================

# Create a rule
rule = Rule.create!(
  rule_id: 'approval_rules_001',
  ruleset: 'approval',
  description: 'Approval decision rules'
)

# Define rule content
content = {
  version: "1.0",
  ruleset: "approval",
  rules: [
    {
      id: "auto_approve",
      if: { field: "amount", op: "lt", value: 1000 },
      then: { decision: "approve", weight: 0.9, reason: "Low amount" }
    }
  ]
}

# Create initial version
v1 = rule.create_version(
  content: content,
  created_by: "admin@example.com",
  changelog: "Initial approval rules"
)

# Update the rule
content[:rules].first[:if][:value] = 5000  # Change threshold
v2 = rule.create_version(
  content: content,
  created_by: "manager@example.com",
  changelog: "Increased approval threshold"
)

# Get version history
rule.versions.each do |version|
  puts "v#{version.version_number}: #{version.changelog} by #{version.created_by}"
end

# Get active version
active = rule.active_version
puts "Active version: v#{active.version_number}"

# Rollback
old_version = rule.versions.find_by(version_number: 1)
old_version.activate!

# Compare versions
comparison = v1.compare_with(v2)
puts "Changes: #{comparison[:differences]}"

# ========================================
# Advanced: Using VersionManager Directly
# ========================================

# The VersionManager will auto-detect ActiveRecord and use it
manager = DecisionAgent::Versioning::VersionManager.new

# Save version (works with ActiveRecord backend)
version = manager.save_version(
  rule_id: "approval_rules_001",
  rule_content: content,
  created_by: "system",
  changelog: "Automated update"
)

# Get history
history = manager.get_history(rule_id: "approval_rules_001")
puts "Total versions: #{history[:total_versions]}"

# ========================================
# In a Service Object
# ========================================

class RuleVersioningService
  def initialize(rule)
    @rule = rule
    @manager = DecisionAgent::Versioning::VersionManager.new
  end

  def create_version_from_ui(rule_content, user, changelog = nil)
    @manager.save_version(
      rule_id: @rule.rule_id,
      rule_content: rule_content,
      created_by: user.email,
      changelog: changelog || generate_changelog(rule_content)
    )
  end

  def rollback_to_version(version_id, user)
    @manager.rollback(
      version_id: version_id,
      performed_by: user.email
    )

    # Send notification
    NotificationMailer.rule_rollback(@rule, user).deliver_later
  end

  def audit_trail
    @manager.get_history(rule_id: @rule.rule_id)
  end

  private

  def generate_changelog(content)
    "Updated with #{content[:rules].length} rules"
  end
end

# Usage:
# service = RuleVersioningService.new(rule)
# service.create_version_from_ui(rule_content, current_user, "Updated thresholds")
# service.rollback_to_version(version_id, current_user)

# ========================================
# In a Background Job
# ========================================

class RuleVersionCleanupJob < ApplicationJob
  queue_as :default

  def perform(rule_id, keep_last: 50)
    rule = Rule.find_by!(rule_id: rule_id)

    # Keep only the last N versions
    old_versions = rule.versions
                       .where(status: 'archived')
                       .order(version_number: :desc)
                       .offset(keep_last)

    count = old_versions.destroy_all.count
    Rails.logger.info("Cleaned up #{count} old versions for rule #{rule_id}")
  end
end

# Schedule:
# RuleVersionCleanupJob.perform_later("approval_rules_001", keep_last: 100)
