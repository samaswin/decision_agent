# RBAC Quick Reference

Quick reference guide for configuring RBAC with different authentication systems.

## Configuration Methods

### 1. Default (Built-in)
```ruby
DecisionAgent.configure_rbac(:default)
```

### 2. Devise + CanCanCan
```ruby
DecisionAgent.configure_rbac(:devise_cancan, ability_class: Ability)
```

### 3. Pundit
```ruby
DecisionAgent.configure_rbac(:pundit)
```

### 4. Custom (Procs)
```ruby
DecisionAgent.configure_rbac(:custom,
  can_proc: ->(user, permission, resource) { user.has_permission?(permission) },
  has_role_proc: ->(user, role) { user.has_role?(role) },
  active_proc: ->(user) { user.active? }
)
```

### 5. Custom Adapter Class
```ruby
class MyAdapter < DecisionAgent::Auth::RbacAdapter
  def can?(user, permission, resource = nil)
    # Your logic
  end
end

DecisionAgent.configure_rbac do |config|
  config.adapter = MyAdapter.new
end
```

## Usage

```ruby
checker = DecisionAgent.permission_checker
checker.can?(user, :read)
checker.has_role?(user, :admin)
checker.require_permission!(user, :write)
```

## Standard Permissions

- `:read` - Read access
- `:write` - Create/modify
- `:delete` - Delete
- `:approve` - Approve changes
- `:deploy` - Deploy versions
- `:manage_users` - User management
- `:audit` - Audit logs

## See Also

- [Full Documentation](RBAC_CONFIGURATION.md)
- [Examples](../examples/rbac_configuration_examples.rb)
- [Rails Integration](../examples/rails_rbac_integration.rb)

