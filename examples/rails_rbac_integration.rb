#!/usr/bin/env ruby
# frozen_string_literal: true

# Example: Integrating decision_agent RBAC with an existing Rails application
# This shows how to configure decision_agent to work with your existing auth system

# ============================================================================
# In your Rails application, add this to config/initializers/decision_agent.rb
# ============================================================================

=begin
# config/initializers/decision_agent.rb

require 'decision_agent'

# Option 1: If you're using Devise + CanCanCan
if defined?(CanCan::Ability)
  DecisionAgent.configure_rbac(:devise_cancan, ability_class: Ability)
end

# Option 2: If you're using Pundit
if defined?(Pundit)
  DecisionAgent.configure_rbac(:pundit)
end

# Option 3: If you're using a custom auth system
# DecisionAgent.configure_rbac(:custom,
#   can_proc: ->(user, permission, resource) {
#     # Your custom permission logic
#     user.has_permission?(permission)
#   },
#   has_role_proc: ->(user, role) {
#     # Your custom role logic
#     user.has_role?(role)
#   },
#   active_proc: ->(user) {
#     # Your custom active check
#     user.active?
#   }
# )

# Option 4: If you want to create a custom adapter class
# class MyAppRbacAdapter < DecisionAgent::Auth::RbacAdapter
#   def can?(user, permission, resource = nil)
#     # Your implementation
#   end
#
#   def has_role?(user, role)
#     # Your implementation
#   end
#
#   def active?(user)
#     # Your implementation
#   end
# end
#
# DecisionAgent.configure_rbac do |config|
#   config.adapter = MyAppRbacAdapter.new
# end
=end

# ============================================================================
# In your Rails controllers
# ============================================================================

=begin
# app/controllers/application_controller.rb
class ApplicationController < ActionController::Base
  # Your existing auth setup (Devise, etc.)
  # before_action :authenticate_user!

  protected

  def decision_agent_permission_checker
    DecisionAgent.permission_checker
  end

  def require_decision_agent_permission!(permission, resource = nil)
    checker = decision_agent_permission_checker
    unless checker.can?(current_user, permission, resource)
      raise DecisionAgent::PermissionDeniedError, "Permission denied: #{permission}"
    end
  end
end

# app/controllers/rules_controller.rb
class RulesController < ApplicationController
  before_action :authenticate_user! # Your existing auth
  before_action :set_rule, only: [:show, :edit, :update, :destroy]

  def index
    require_decision_agent_permission!(:read)
    @rules = Rule.all
  end

  def show
    require_decision_agent_permission!(:read, @rule)
  end

  def new
    require_decision_agent_permission!(:write)
    @rule = Rule.new
  end

  def create
    require_decision_agent_permission!(:write)
    @rule = Rule.new(rule_params)
    if @rule.save
      redirect_to @rule, notice: 'Rule created successfully.'
    else
      render :new
    end
  end

  def update
    require_decision_agent_permission!(:write, @rule)
    if @rule.update(rule_params)
      redirect_to @rule, notice: 'Rule updated successfully.'
    else
      render :edit
    end
  end

  def destroy
    require_decision_agent_permission!(:delete, @rule)
    @rule.destroy
    redirect_to rules_path, notice: 'Rule deleted successfully.'
  end

  private

  def set_rule
    @rule = Rule.find(params[:id])
  end

  def rule_params
    params.require(:rule).permit(:name, :description, :ruleset)
  end
end
=end

# ============================================================================
# Integration with Rack middleware (for Sinatra, etc.)
# ============================================================================

=begin
# In your config.ru or Sinatra app
require 'decision_agent'

# Configure RBAC
DecisionAgent.configure_rbac(:custom,
  can_proc: ->(user, permission, resource) {
    # Your custom logic
    user && user.has_permission?(permission)
  }
)

# Use in your routes
get '/rules' do
  user = current_user # Your auth method
  checker = DecisionAgent.permission_checker
  
  unless checker.can?(user, :read)
    status 403
    return { error: 'Permission denied' }.to_json
  end
  
  # Your logic here
  { rules: [] }.to_json
end
=end

puts "Rails integration examples (commented out)"
puts "See the comments above for integration patterns"

