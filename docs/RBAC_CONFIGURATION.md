# RBAC Configuration Guide

The Decision Agent gem provides a flexible, configurable RBAC (Role-Based Access Control) system that can integrate with **any** existing authentication and authorization system in your project.

## Overview

The RBAC system uses an **adapter pattern** that allows you to:
- Use the built-in RBAC system (default)
- Integrate with Devise + CanCanCan
- Integrate with Pundit
- Create custom adapters for any authentication system
- Use simple proc-based configuration for quick integration

## Quick Start

### Default Configuration (Built-in RBAC)

If you don't have an existing auth system, use the default:

```ruby
require 'decision_agent'

# Default configuration (no setup needed)
DecisionAgent.configure_rbac(:default)

# Use with built-in User model
user = DecisionAgent::Auth::User.new(
  email: "admin@example.com",
  password: "password123",
  roles: [:admin]
)

checker = DecisionAgent.permission_checker
checker.can?(user, :read)  # => true
checker.can?(user, :write)  # => true
```

### Custom Configuration

Configure RBAC to work with your existing auth system:

```ruby
# In config/initializers/decision_agent.rb (Rails)
DecisionAgent.configure_rbac(:custom,
  can_proc: ->(user, permission, resource) {
    user.has_permission?(permission)
  },
  has_role_proc: ->(user, role) {
    user.has_role?(role)
  },
  active_proc: ->(user) {
    user.active?
  }
)
```

## Adapter Types

### 1. Default Adapter

Uses the built-in `DecisionAgent::Auth::User` model and role system.

```ruby
DecisionAgent.configure_rbac(:default)
```

**Use when:**
- You don't have an existing auth system
- You want a simple, self-contained solution
- You're building a new application

### 2. Devise + CanCanCan Adapter

Integrates with Devise (authentication) and CanCanCan (authorization).

```ruby
# In config/initializers/decision_agent.rb
DecisionAgent.configure_rbac(:devise_cancan, ability_class: Ability)
```

**Requirements:**
- Devise gem installed
- CanCanCan gem installed
- `Ability` class defined

**Example Ability class:**
```ruby
class Ability
  include CanCan::Ability

  def initialize(user)
    user ||= User.new
    if user.admin?
      can :manage, :all
    elsif user.editor?
      can [:read, :create, :update], Rule
    else
      can :read, Rule
    end
  end
end
```

**Usage:**
```ruby
# In your controllers
class RulesController < ApplicationController
  before_action :authenticate_user!

  def show
    checker = DecisionAgent.permission_checker
    unless checker.can?(current_user, :read)
      raise DecisionAgent::PermissionDeniedError
    end
    # ...
  end
end
```

### 3. Pundit Adapter

Integrates with Pundit authorization.

```ruby
DecisionAgent.configure_rbac(:pundit)
```

**Requirements:**
- Pundit gem installed
- Policy classes defined (e.g., `RulePolicy`)

**Example Policy:**
```ruby
class RulePolicy < ApplicationPolicy
  def show?
    user.present?
  end

  def create?
    user.admin? || user.editor?
  end

  def destroy?
    user.admin?
  end
end
```

**Usage:**
```ruby
rule = Rule.find(params[:id])
checker = DecisionAgent.permission_checker
checker.can?(current_user, :read, rule)  # Uses RulePolicy#show?
```

### 4. Custom Adapter (Procs)

Most flexible option - provide your own logic via procs.

```ruby
DecisionAgent.configure_rbac(:custom,
  can_proc: ->(user, permission, resource) {
    # Your custom permission logic
    return false unless user
    return false unless user.active?
    
    # Example: Check against permissions table
    user.permissions.include?(permission.to_sym)
  },
  has_role_proc: ->(user, role) {
    # Your custom role logic
    user.roles.any? { |r| r.name == role.to_s }
  },
  active_proc: ->(user) {
    # Your custom active check
    user.active? && !user.suspended?
  },
  user_id_proc: ->(user) {
    # Optional: Custom user ID extraction
    user.id
  },
  user_email_proc: ->(user) {
    # Optional: Custom email extraction
    user.email
  }
)
```

**Use when:**
- You have a custom auth system
- You need fine-grained control
- You want to integrate with any gem or custom code

### 5. Custom Adapter Class

For complex logic, create your own adapter class.

```ruby
class MyAppRbacAdapter < DecisionAgent::Auth::RbacAdapter
  def initialize(user_model_class:)
    @user_model_class = user_model_class
  end

  def can?(user, permission, resource = nil)
    return false unless user
    return false unless active?(user)

    # Your complex permission logic
    user_permissions = fetch_user_permissions(user)
    user_permissions.include?(permission.to_sym)
  end

  def has_role?(user, role)
    return false unless user
    return false unless active?(user)

    user_roles = fetch_user_roles(user)
    user_roles.include?(role.to_sym)
  end

  def active?(user)
    return false unless user
    user.active? && !user.suspended?
  end

  private

  def fetch_user_permissions(user)
    # Query your database, cache, etc.
    @user_model_class.find(user.id).permissions.pluck(:name).map(&:to_sym)
  end

  def fetch_user_roles(user)
    @user_model_class.find(user.id).roles.pluck(:name).map(&:to_sym)
  end
end

# Configure it
DecisionAgent.configure_rbac do |config|
  config.adapter = MyAppRbacAdapter.new(user_model_class: User)
end
```

## Permission Mapping

Decision Agent uses these standard permissions:
- `:read` - Read access to rules and versions
- `:write` - Create and modify rules
- `:delete` - Delete rules and versions
- `:approve` - Approve rule changes
- `:deploy` - Deploy rule versions
- `:manage_users` - Manage users and roles
- `:audit` - Access audit logs

When integrating with other systems, you may need to map these permissions to your system's actions.

### CanCanCan Mapping

The `DeviseCanCanAdapter` automatically maps permissions:
- `:read` → `:read`
- `:write` → `:create`
- `:delete` → `:destroy`
- `:approve` → `:approve`
- `:deploy` → `:deploy`
- `:manage_users` → `:manage`
- `:audit` → `:read`

### Pundit Mapping

The `PunditAdapter` maps permissions to policy methods:
- `:read` → `show?`
- `:write` → `create?`
- `:delete` → `destroy?`
- `:approve` → `approve?`
- `:deploy` → `deploy?`
- `:manage_users` → `manage?`
- `:audit` → `audit?`

## Usage Examples

### In Rails Controllers

```ruby
class ApplicationController < ActionController::Base
  protected

  def require_decision_agent_permission!(permission, resource = nil)
    checker = DecisionAgent.permission_checker
    unless checker.can?(current_user, permission, resource)
      raise DecisionAgent::PermissionDeniedError, "Permission denied: #{permission}"
    end
  end
end

class RulesController < ApplicationController
  before_action :authenticate_user!

  def show
    require_decision_agent_permission!(:read, @rule)
    # ...
  end

  def create
    require_decision_agent_permission!(:write)
    # ...
  end
end
```

### In Sinatra/Rack Apps

```ruby
require 'decision_agent'

# Configure RBAC
DecisionAgent.configure_rbac(:custom,
  can_proc: ->(user, permission, resource) {
    user && user.has_permission?(permission)
  }
)

get '/rules' do
  user = current_user # Your auth method
  checker = DecisionAgent.permission_checker
  
  unless checker.can?(user, :read)
    status 403
    return { error: 'Permission denied' }.to_json
  end
  
  { rules: [] }.to_json
end
```

### With Web UI

The Decision Agent Web UI automatically uses the configured RBAC adapter:

```ruby
require 'decision_agent'
require 'decision_agent/web'

# Configure RBAC
DecisionAgent.configure_rbac(:devise_cancan, ability_class: Ability)

# Start web server
DecisionAgent::Web::Server.run!
```

## Integration Examples

### Devise + Rolify

```ruby
DecisionAgent.configure_rbac(:custom,
  can_proc: ->(user, permission, resource) {
    return false unless user
    return false unless user.active?

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
    user.has_role?(role)
  },
  active_proc: ->(user) {
    user.active?
  }
)
```

### Simple Hash-Based Permissions

```ruby
DecisionAgent.configure_rbac(:custom,
  can_proc: ->(user, permission, resource) {
    return false unless user
    user.permissions_hash[permission.to_sym] == true
  },
  has_role_proc: ->(user, role) {
    user.permissions_hash[:roles]&.include?(role.to_sym)
  },
  active_proc: ->(user) {
    user.permissions_hash[:active] != false
  }
)
```

## API Reference

### `DecisionAgent.configure_rbac(adapter_type, **options)`

Configure the RBAC adapter.

**Parameters:**
- `adapter_type` (Symbol): `:default`, `:devise_cancan`, `:pundit`, or `:custom`
- `options` (Hash): Adapter-specific options

**Returns:** `RbacConfig` instance

**Example:**
```ruby
DecisionAgent.configure_rbac(:custom, can_proc: ->(u, p, r) { ... })
```

### `DecisionAgent.configure_rbac { |config| ... }`

Configure using a block.

**Example:**
```ruby
DecisionAgent.configure_rbac do |config|
  config.adapter = MyCustomAdapter.new
end
```

### `DecisionAgent.permission_checker`

Get the configured permission checker instance.

**Returns:** `PermissionChecker` instance

**Example:**
```ruby
checker = DecisionAgent.permission_checker
checker.can?(user, :read)
```

### `PermissionChecker#can?(user, permission, resource = nil)`

Check if a user has a permission.

**Returns:** `true` or `false`

### `PermissionChecker#has_role?(user, role)`

Check if a user has a role.

**Returns:** `true` or `false`

### `PermissionChecker#active?(user)`

Check if a user is active.

**Returns:** `true` or `false`

### `PermissionChecker#require_permission!(user, permission, resource = nil)`

Require a permission, raise `PermissionDeniedError` if not granted.

**Raises:** `PermissionDeniedError`

### `PermissionChecker#require_role!(user, role)`

Require a role, raise `PermissionDeniedError` if not granted.

**Raises:** `PermissionDeniedError`

## Best Practices

1. **Configure early**: Set up RBAC in an initializer (Rails) or at app startup
2. **Use consistent patterns**: Stick to one adapter type per application
3. **Handle nil users**: Always check for `nil` users in custom adapters
4. **Cache when appropriate**: For database-heavy permission checks, consider caching
5. **Test your adapter**: Write tests for your custom adapter logic
6. **Document your mapping**: If permissions map to different actions, document it

## Troubleshooting

### Permission checks always return false

- Verify your adapter is correctly configured
- Check that `active?` returns `true` for your users
- Ensure your permission logic matches the expected format
- Use `puts` or logging to debug your custom procs

### Integration with existing auth not working

- Verify your User model has the expected methods
- Check that your adapter's `can?` method is being called
- Ensure the user object is the correct type expected by your adapter

### Web UI not respecting permissions

- Make sure RBAC is configured before starting the web server
- Verify the `PermissionChecker` is using the correct adapter
- Check that your authentication middleware is setting `current_user` correctly

## See Also

- [Examples](../examples/rbac_configuration_examples.rb) - Complete working examples
- [Rails Integration](../examples/rails_rbac_integration.rb) - Rails-specific examples
- [API Contract](API_CONTRACT.md) - Full API documentation

