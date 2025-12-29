#!/usr/bin/env ruby
# frozen_string_literal: true

# Examples of configuring RBAC with different authentication/authorization systems
# This demonstrates how to integrate decision_agent with any existing auth system

require_relative "../lib/decision_agent"

# ============================================================================
# Example 1: Default Built-in RBAC (no external dependencies)
# ============================================================================
puts "=" * 80
puts "Example 1: Default Built-in RBAC"
puts "=" * 80

DecisionAgent.configure_rbac(:default)

# Use the built-in User model
user = DecisionAgent::Auth::User.new(
  email: "admin@example.com",
  password: "password123",
  roles: [:admin]
)

checker = DecisionAgent.permission_checker
puts "Can admin read? #{checker.can?(user, :read)}"
puts "Can admin write? #{checker.can?(user, :write)}"
puts "Can admin manage_users? #{checker.can?(user, :manage_users)}"
puts

# ============================================================================
# Example 2: Devise + CanCanCan Integration
# ============================================================================
puts "=" * 80
puts "Example 2: Devise + CanCanCan Integration"
puts "=" * 80

# Assuming you have Devise User model and CanCanCan Ability class
# Uncomment and adapt to your actual setup:

=begin
# In your Rails app, configure like this:
DecisionAgent.configure_rbac(:devise_cancan, ability_class: Ability)

# Your User model (from Devise) might look like:
# class User < ApplicationRecord
#   devise :database_authenticatable, :registerable, ...
#   has_many :roles
# end

# Your Ability class (from CanCanCan) might look like:
# class Ability
#   include CanCan::Ability
#   def initialize(user)
#     user ||= User.new
#     if user.admin?
#       can :manage, :all
#     elsif user.editor?
#       can [:read, :create, :update], Rule
#     else
#       can :read, Rule
#     end
#   end
# end

# Usage in your app:
# current_user = User.find(session[:user_id])
# checker = DecisionAgent.permission_checker
# if checker.can?(current_user, :read)
#   # Allow access
# end
=end

puts "Devise + CanCanCan example (commented out - uncomment and adapt to your setup)"
puts

# ============================================================================
# Example 3: Pundit Integration
# ============================================================================
puts "=" * 80
puts "Example 3: Pundit Integration"
puts "=" * 80

=begin
# In your Rails app with Pundit:
DecisionAgent.configure_rbac(:pundit)

# Your Pundit policy might look like:
# class RulePolicy < ApplicationPolicy
#   def show?
#     user.present?
#   end
#
#   def create?
#     user.admin? || user.editor?
#   end
#
#   def destroy?
#     user.admin?
#   end
# end

# Usage:
# current_user = User.find(session[:user_id])
# rule = Rule.find(params[:id])
# checker = DecisionAgent.permission_checker
# if checker.can?(current_user, :read, rule)
#   # Allow access
# end
=end

puts "Pundit example (commented out - uncomment and adapt to your setup)"
puts

# ============================================================================
# Example 4: Custom Adapter with Procs (Most Flexible)
# ============================================================================
puts "=" * 80
puts "Example 4: Custom Adapter with Procs"
puts "=" * 80

# Example: Custom User model with different structure
class CustomUser
  attr_reader :id, :email, :permissions, :enabled

  def initialize(id:, email:, permissions: [], enabled: true)
    @id = id
    @email = email
    @permissions = Array(permissions)
    @enabled = enabled
  end

  def has_permission?(perm)
    @permissions.include?(perm.to_sym)
  end
end

# Configure with custom procs
DecisionAgent.configure_rbac(:custom,
  can_proc: ->(user, permission, resource) {
    user.is_a?(CustomUser) && user.enabled && user.has_permission?(permission)
  },
  has_role_proc: ->(user, role) {
    # If your system doesn't use roles, return false or implement your logic
    false
  },
  active_proc: ->(user) {
    user.is_a?(CustomUser) ? user.enabled : true
  },
  user_id_proc: ->(user) {
    user.respond_to?(:id) ? user.id : nil
  },
  user_email_proc: ->(user) {
    user.respond_to?(:email) ? user.email : nil
  }
)

custom_user = CustomUser.new(
  id: 1,
  email: "user@example.com",
  permissions: [:read, :write],
  enabled: true
)

checker = DecisionAgent.permission_checker
puts "Can custom user read? #{checker.can?(custom_user, :read)}"
puts "Can custom user delete? #{checker.can?(custom_user, :delete)}"
puts "Is custom user active? #{checker.active?(custom_user)}"
puts "User ID: #{checker.user_id(custom_user)}"
puts "User Email: #{checker.user_email(custom_user)}"
puts

# ============================================================================
# Example 5: Custom Adapter Class (For Complex Logic)
# ============================================================================
puts "=" * 80
puts "Example 5: Custom Adapter Class"
puts "=" * 80

# Create your own adapter class
class MyProjectAdapter < DecisionAgent::Auth::RbacAdapter
  def initialize(user_model_class:)
    @user_model_class = user_model_class
  end

  def can?(user, permission, resource = nil)
    return false unless user
    return false unless active?(user)

    # Your custom permission logic here
    # Example: Check against a permissions table
    user_permissions = fetch_user_permissions(user)
    user_permissions.include?(permission.to_sym)
  end

  def has_role?(user, role)
    return false unless user
    return false unless active?(user)

    # Your custom role logic here
    user_roles = fetch_user_roles(user)
    user_roles.include?(role.to_sym)
  end

  def active?(user)
    return false unless user
    # Check if user is active based on your model
    user.respond_to?(:active?) ? user.active? : true
  end

  private

  def fetch_user_permissions(user)
    # Example: Query your permissions table
    # @user_model_class.find(user.id).permissions.pluck(:name).map(&:to_sym)
    # For demo, return empty array
    []
  end

  def fetch_user_roles(user)
    # Example: Query your roles table
    # @user_model_class.find(user.id).roles.pluck(:name).map(&:to_sym)
    # For demo, return empty array
    []
  end
end

# Configure with your custom adapter
DecisionAgent.configure_rbac do |config|
  config.adapter = MyProjectAdapter.new(user_model_class: CustomUser)
end

puts "Custom adapter class configured"
puts "You can now use DecisionAgent.permission_checker with your custom logic"
puts

# ============================================================================
# Example 6: Integration with Existing Rails App (Devise + Rolify)
# ============================================================================
puts "=" * 80
puts "Example 6: Devise + Rolify Integration"
puts "=" * 80

=begin
# If you're using Devise + Rolify for roles:
# Gemfile: gem 'devise', gem 'rolify'

# Your User model:
# class User < ApplicationRecord
#   devise :database_authenticatable, ...
#   rolify
# end

# Configure decision_agent:
DecisionAgent.configure_rbac(:custom,
  can_proc: ->(user, permission, resource) {
    return false unless user
    return false unless user.active?

    # Map permissions to roles
    permission_to_roles = {
      read: [:admin, :editor, :viewer],
      write: [:admin, :editor],
      delete: [:admin],
      approve: [:admin, :approver],
      deploy: [:admin],
      manage_users: [:admin],
      audit: [:admin, :auditor]
    }

    required_roles = permission_to_roles[permission.to_sym] || []
    required_roles.any? { |role| user.has_role?(role) }
  },
  has_role_proc: ->(user, role) {
    user.respond_to?(:has_role?) ? user.has_role?(role) : false
  },
  active_proc: ->(user) {
    user.respond_to?(:active?) ? user.active? : true
  }
)

# Usage in your Rails controllers:
# class RulesController < ApplicationController
#   before_action :authenticate_user!
#
#   def show
#     checker = DecisionAgent.permission_checker
#     unless checker.can?(current_user, :read)
#       raise DecisionAgent::PermissionDeniedError
#     end
#     # ... rest of action
#   end
# end
=end

puts "Devise + Rolify example (commented out - uncomment and adapt to your setup)"
puts

# ============================================================================
# Example 7: Simple Hash-Based Permission System
# ============================================================================
puts "=" * 80
puts "Example 7: Simple Hash-Based Permission System"
puts "=" * 80

# If you have a simple hash-based permission system
class SimpleUser
  attr_reader :id, :email, :permissions_hash

  def initialize(id:, email:, permissions_hash: {})
    @id = id
    @email = email
    @permissions_hash = permissions_hash
  end
end

DecisionAgent.configure_rbac(:custom,
  can_proc: ->(user, permission, resource) {
    return false unless user.is_a?(SimpleUser)
    # Check permissions hash
    user.permissions_hash[permission.to_sym] == true
  },
  has_role_proc: ->(user, role) {
    # If you store roles in permissions_hash
    user.is_a?(SimpleUser) && user.permissions_hash[:roles]&.include?(role.to_sym)
  },
  active_proc: ->(user) {
    user.is_a?(SimpleUser) ? (user.permissions_hash[:active] != false) : true
  }
)

simple_user = SimpleUser.new(
  id: 2,
  email: "simple@example.com",
  permissions_hash: {
    read: true,
    write: true,
    delete: false,
    active: true
  }
)

checker = DecisionAgent.permission_checker
puts "Can simple user read? #{checker.can?(simple_user, :read)}"
puts "Can simple user write? #{checker.can?(simple_user, :write)}"
puts "Can simple user delete? #{checker.can?(simple_user, :delete)}"
puts

puts "=" * 80
puts "All examples completed!"
puts "=" * 80
puts
puts "Key Points:"
puts "1. Use :default for built-in RBAC (no dependencies)"
puts "2. Use :devise_cancan for Devise + CanCanCan integration"
puts "3. Use :pundit for Pundit integration"
puts "4. Use :custom with procs for maximum flexibility"
puts "5. Create your own adapter class for complex logic"
puts "6. The adapter pattern works with ANY authentication system!"
puts

