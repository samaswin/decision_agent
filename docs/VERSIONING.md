# Rule Versioning System

DecisionAgent includes a comprehensive versioning system for tracking rule changes, enabling rollbacks, and comparing versions. The system is **framework-agnostic** and supports both Rails (with ActiveRecord) and standalone deployments.

## Table of Contents

- [Features](#features)
- [Architecture](#architecture)
- [Installation](#installation)
- [Usage](#usage)
- [DMN Versioning](#dmn-versioning)
- [Status Management](#status-management)
- [Thread Safety & Concurrency](#thread-safety--concurrency)
- [Web UI](#web-ui)
- [API Reference](#api-reference)
- [Storage Adapters](#storage-adapters)
- [Integration Examples](#integration-examples)
- [Error Handling](#error-handling)
- [Performance Considerations](#performance-considerations)

## Features

✅ **Auto-versioning** - Automatically create versions on every rule save
✅ **Version History** - List all versions for a rule with metadata
✅ **Version Comparison** - Diff two versions to see changes
✅ **Rollback** - Activate any previous version
✅ **Framework-Agnostic** - Works with Rails, Rack, or any Ruby framework
✅ **Pluggable Storage** - File-based or database-backed storage
✅ **Audit Trail** - Track who made changes and when
✅ **Web UI** - Visual interface for version management
✅ **DMN Support** - Version DMN decision models alongside JSON rules
✅ **Status Management** - Draft, active, and archived statuses
✅ **Thread-Safe** - Safe for concurrent access with proper locking
✅ **A/B Testing Integration** - Seamlessly works with A/B testing features

## Architecture

The versioning system uses the **Adapter Pattern** to support different storage backends:

```
┌─────────────────────┐
│  VersionManager     │  High-level API
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│  Adapter (Base)     │  Abstract interface
└──────────┬──────────┘
           │
     ┌─────┴─────┐
     ▼           ▼
┌──────────┐  ┌────────────────┐
│ File     │  │ ActiveRecord   │  Concrete adapters
│ Storage  │  │ (Rails)        │
└──────────┘  └────────────────┘
```

### Components

1. **VersionManager** - High-level service for version operations
2. **Adapter** - Abstract base for storage backends
3. **FileStorageAdapter** - JSON file-based storage (default)
4. **ActiveRecordAdapter** - Database storage for Rails apps
5. **Web UI** - Visual rule builder with version history

## Installation

### For Standalone / Rack Apps

No additional setup required! The gem uses file-based storage by default.

```ruby
require 'decision_agent'

manager = DecisionAgent::Versioning::VersionManager.new
# Versions are stored in ./versions/ directory
```

### For Rails Apps

1. **Run the generator** to install models and migrations:

```bash
rails generate decision_agent:install
```

This creates:
- `app/models/rule.rb`
- `app/models/rule_version.rb`
- `db/migrate/[timestamp]_create_decision_agent_tables.rb`

2. **Run migrations**:

```bash
rails db:migrate
```

3. **Use the models**:

```ruby
# The VersionManager will auto-detect ActiveRecord
manager = DecisionAgent::Versioning::VersionManager.new

# Or use models directly
rule = Rule.create!(
  rule_id: 'approval_001',
  ruleset: 'approval',
  description: 'Approval rules'
)

rule.create_version(
  content: { /* rule JSON */ },
  created_by: 'admin'
)
```

## Usage

### Basic Version Management

```ruby
require 'decision_agent'

manager = DecisionAgent::Versioning::VersionManager.new

# Save a new version
rule_content = {
  version: "1.0",
  ruleset: "approval",
  rules: [
    {
      id: "high_value",
      if: { field: "amount", op: "gt", value: 1000 },
      then: { decision: "approve", weight: 0.9, reason: "High value transaction" }
    }
  ]
}

version = manager.save_version(
  rule_id: "approval_001",
  rule_content: rule_content,
  created_by: "admin",
  changelog: "Added high value rule"
)
# => {
#   id: "approval_001_v1",
#   rule_id: "approval_001",
#   version_number: 1,
#   content: { ... },
#   created_by: "admin",
#   created_at: "2025-01-15T10:30:00Z",
#   changelog: "Added high value rule",
#   status: "active"
# }
```

### List Versions

```ruby
# Get all versions for a rule
versions = manager.get_versions(rule_id: "approval_001")

# Limit results
recent_versions = manager.get_versions(rule_id: "approval_001", limit: 5)
```

### Get Specific Version

```ruby
# By version ID
version = manager.get_version(version_id: "approval_001_v1")

# By rule_id and version number
version = manager.adapter.get_version_by_number(
  rule_id: "approval_001",
  version_number: 2
)

# Get active version
active = manager.get_active_version(rule_id: "approval_001")
```

### Rollback to Previous Version

```ruby
# Rollback to a specific version
rolled_back = manager.rollback(
  version_id: "approval_001_v3",
  performed_by: "admin"
)

# This activates v3 and creates a new version documenting the rollback
```

### Compare Versions

```ruby
comparison = manager.compare(
  version_id_1: "approval_001_v1",
  version_id_2: "approval_001_v2"
)

# => {
#   version_1: { ... },
#   version_2: { ... },
#   differences: {
#     added: [...],
#     removed: [...],
#     changed: { field: { old: "value1", new: "value2" } }
#   }
# }
```

### Version History with Metadata

```ruby
history = manager.get_history(rule_id: "approval_001")

# => {
#   rule_id: "approval_001",
#   total_versions: 5,
#   active_version: { ... },
#   versions: [ ... ],
#   created_at: "2025-01-15T10:30:00Z",
#   updated_at: "2025-01-15T14:45:00Z"
# }
```

### Delete Version

```ruby
# Delete a non-active version
deleted = manager.delete_version(version_id: "approval_001_v2")
# => true

# Note: Active versions cannot be deleted
# You must activate another version first
```

## Web UI

The Rack web server includes a visual interface for version management.

### Start the Server

```bash
# Command line
decision_agent web

# Or programmatically
DecisionAgent::Web::Server.start!(port: 4567)
```

Visit `http://localhost:4567` to access the rule builder with version features.

## DMN Versioning

DecisionAgent supports versioning for DMN (Decision Model and Notation) models alongside JSON rules. This allows you to track changes to complex decision tables and models.

### Basic DMN Versioning

```ruby
require 'decision_agent'

# Create a DMN version manager
dmn_manager = DecisionAgent::Dmn::DmnVersionManager.new

# Parse a DMN model
parser = DecisionAgent::Dmn::Parser.new
model = parser.parse(dmn_xml_string)

# Save a version
version = dmn_manager.save_dmn_version(
  model: model,
  created_by: "analyst",
  changelog: "Updated approval thresholds"
)

# Get all versions of a DMN model
versions = dmn_manager.get_dmn_versions(model_id: model.id)

# Get a specific DMN version
dmn_version = dmn_manager.get_dmn_version(version_id: version[:version_id])
# => {
#   version_id: "...",
#   model: <Dmn::Model>,
#   created_at: "...",
#   created_by: "analyst",
#   changelog: "...",
#   is_active: true
# }

# Rollback to a previous DMN version
rolled_back_model = dmn_manager.rollback_dmn(
  version_id: version[:version_id],
  performed_by: "admin"
)

# Compare two DMN versions
comparison = dmn_manager.compare_dmn_versions(
  version_id_1: version1[:version_id],
  version_id_2: version2[:version_id]
)
# => {
#   version_1: { ... },
#   version_2: { ... },
#   differences: { ... },
#   model_diff: {
#     name_changed: false,
#     namespace_changed: false,
#     decisions_added: ["new_decision"],
#     decisions_removed: [],
#     decisions_modified: ["existing_decision"]
#   },
#   model_1: { id: "...", name: "...", decisions: 5 },
#   model_2: { id: "...", name: "...", decisions: 6 }
# }
```

### Using Model Extensions

DMN models can be extended with versioning methods:

```ruby
# After parsing a DMN model
model = parser.parse(dmn_xml_string)

# Extend with versioning support
model.extend(DecisionAgent::Dmn::ModelVersioning)

# Save version directly on the model
version = model.save_version(
  created_by: "analyst",
  changelog: "Updated decision table"
)

# Load a specific version
loaded_model = model.load_version(version_id)
```

### DMN Version Storage

DMN versions are stored with a special format marker:

```ruby
{
  format: "dmn",
  xml: "<dmn:definitions>...</dmn:definitions>",
  name: "Loan Approval",
  namespace: "http://example.com/dmn"
}
```

This allows the system to distinguish DMN models from JSON rules and apply appropriate parsing logic.

## Status Management

Versions support three statuses to manage their lifecycle:

### Status Types

- **`draft`** - Work in progress, not yet active
- **`active`** - Currently in use for decision-making
- **`archived`** - Historical version, no longer active

### Creating Versions with Status

```ruby
# Create a draft version
draft_version = manager.save_version(
  rule_id: "approval_001",
  rule_content: content,
  created_by: "developer",
  changelog: "WIP: Testing new rules"
)
# Status defaults to "active" unless specified in metadata

# To create a draft, you need to use the adapter directly
# or modify the version after creation
```

### Activating Versions

```ruby
# Activate a specific version (deactivates others)
active_version = manager.rollback(
  version_id: "approval_001_v3",
  performed_by: "admin"
)

# This automatically:
# 1. Deactivates all other versions for the rule
# 2. Sets the specified version to "active"
# 3. Sets other versions to "archived"
```

### Status Validation

The system validates status values:

```ruby
# Invalid status will raise ValidationError
begin
  # This would fail if status validation is in place
  manager.adapter.create_version(
    rule_id: "test",
    content: {},
    metadata: { status: "invalid_status" }
  )
rescue DecisionAgent::ValidationError => e
  puts e.message
  # => "Invalid status 'invalid_status'. Must be one of: draft, active, archived"
end
```

## Thread Safety & Concurrency

The versioning system is designed to be thread-safe and handle concurrent access:

### File Storage Concurrency

The `FileStorageAdapter` uses per-rule mutexes to ensure thread safety:

```ruby
# Multiple threads can safely create versions for different rules
# in parallel, but operations on the same rule are serialized

Thread.new do
  manager.save_version(rule_id: "rule_1", rule_content: content1)
end

Thread.new do
  manager.save_version(rule_id: "rule_2", rule_content: content2)
end
# These can run concurrently

Thread.new do
  manager.save_version(rule_id: "rule_1", rule_content: content3)
end
# This will wait for the first rule_1 operation to complete
```

**Features:**
- Per-rule locking allows parallel processing of different rules
- Atomic file writes prevent corruption
- Version index for O(1) lookups
- Handles deadlocks and recursive locks gracefully

### ActiveRecord Concurrency

The `ActiveRecordAdapter` uses database transactions with pessimistic locking:

```ruby
# Uses SELECT ... FOR UPDATE to lock rows
# Ensures only one thread can calculate version numbers at a time
# Prevents race conditions in high-concurrency scenarios
```

**Features:**
- Database-level locking via transactions
- Pessimistic locking prevents race conditions
- `update_all` for efficient bulk status updates
- Thread-safe version number generation

### Best Practices for Concurrency

1. **Use appropriate adapter for your use case:**
   - File storage: Good for low to medium concurrency
   - ActiveRecord: Recommended for high-concurrency production

2. **Avoid long-running operations in version creation:**
   ```ruby
   # Good: Fast version creation
   manager.save_version(rule_id: "test", rule_content: content)
   
   # Bad: Heavy computation before versioning
   heavy_computation
   manager.save_version(rule_id: "test", rule_content: content)
   ```

3. **Handle errors gracefully:**
   ```ruby
   begin
     version = manager.save_version(rule_id: "test", rule_content: content)
   rescue DecisionAgent::ValidationError => e
     # Handle validation errors
   rescue StandardError => e
     # Handle other errors (lock timeouts, etc.)
   end
   ```

### Web UI Features

1. **Save Version** - Save current rules as a new version
   - Enter "Created By" name
   - Add changelog description
   - Auto-increments version number

2. **Version History** - View all versions in a table
   - Version number
   - Created by
   - Timestamp
   - Status (active/draft/archived)
   - Changelog

3. **Load Version** - Load any previous version into the editor

4. **Rollback** - Activate a previous version
   - Deactivates current active version
   - Creates audit trail

5. **Compare** - Side-by-side diff of two versions
   - Visual comparison
   - Change summary (added/removed/changed)

## API Reference

### VersionManager

#### `#save_version(rule_id:, rule_content:, created_by: 'system', changelog: nil)`

Save a new version of a rule.

**Parameters:**
- `rule_id` (String) - Unique identifier for the rule
- `rule_content` (Hash) - Rule definition
- `created_by` (String) - User creating the version (default: 'system')
- `changelog` (String) - Description of changes (auto-generated if nil)

**Returns:** Hash with version details

**Raises:**
- `ValidationError` if rule_content is invalid

---

#### `#get_versions(rule_id:, limit: nil)`

Get all versions for a rule.

**Parameters:**
- `rule_id` (String) - Rule identifier
- `limit` (Integer, nil) - Optional limit

**Returns:** Array of version hashes

---

#### `#get_version(version_id:)`

Get a specific version by ID.

**Parameters:**
- `version_id` (String) - Version identifier

**Returns:** Version hash or nil

---

#### `#get_active_version(rule_id:)`

Get the currently active version.

**Parameters:**
- `rule_id` (String) - Rule identifier

**Returns:** Active version hash or nil

---

#### `#rollback(version_id:, performed_by: 'system')`

Rollback to a previous version.

**Parameters:**
- `version_id` (String) - Version to activate
- `performed_by` (String) - User performing rollback

**Returns:** Activated version hash

**Note:** Creates a new version documenting the rollback

---

#### `#compare(version_id_1:, version_id_2:)`

Compare two versions.

**Parameters:**
- `version_id_1` (String) - First version ID
- `version_id_2` (String) - Second version ID

**Returns:** Comparison hash with differences

---

#### `#get_history(rule_id:)`

Get complete history with metadata.

**Parameters:**
- `rule_id` (String) - Rule identifier

**Returns:** History hash with stats and versions

---

#### `#delete_version(version_id:)`

Delete a specific version.

**Parameters:**
- `version_id` (String, Integer) - Version identifier

**Returns:** Boolean - true if deleted successfully

**Raises:**
- `NotFoundError` if version doesn't exist
- `ValidationError` if trying to delete an active version

**Note:** Active versions cannot be deleted. Activate another version first.

---

### Adapter Methods

#### `#get_version_by_number(rule_id:, version_number:)`

Get a version by rule ID and version number.

**Parameters:**
- `rule_id` (String) - Rule identifier
- `version_number` (Integer) - Version number

**Returns:** Version hash or nil

**Example:**
```ruby
version = manager.adapter.get_version_by_number(
  rule_id: "approval_001",
  version_number: 3
)
```

## Storage Adapters

### FileStorageAdapter (Default)

Stores versions as JSON files in a directory structure.

```ruby
adapter = DecisionAgent::Versioning::FileStorageAdapter.new(
  storage_path: "./versions"  # default
)

manager = DecisionAgent::Versioning::VersionManager.new(adapter: adapter)
```

**Directory Structure:**
```
versions/
├── approval_001/
│   ├── 1.json
│   ├── 2.json
│   └── 3.json
└── content_moderation/
    ├── 1.json
    └── 2.json
```

**Pros:**
- No database required
- Simple setup
- Easy to backup
- Human-readable files

**Cons:**
- Not suitable for high concurrency
- Limited querying capabilities

### ActiveRecordAdapter (Rails)

Uses database storage via ActiveRecord.

```ruby
# Auto-detected when Rails is present
manager = DecisionAgent::Versioning::VersionManager.new
```

**Database Schema:**

```ruby
create_table :rules do |t|
  t.string :rule_id, null: false, index: { unique: true }
  t.string :ruleset, null: false
  t.text :description
  t.string :status, default: 'active'
  t.timestamps
end

create_table :rule_versions do |t|
  t.string :rule_id, null: false, index: true
  t.integer :version_number, null: false
  t.text :content, null: false
  t.string :created_by, null: false
  t.text :changelog
  t.string :status, null: false, default: 'draft'
  t.timestamps
end
```

**Pros:**
- Production-ready
- Supports concurrency
- Advanced querying
- Transactions

**Cons:**
- Requires database setup
- Rails dependency for ActiveRecord adapter

### Custom Adapters

Create custom adapters by inheriting from `DecisionAgent::Versioning::Adapter`:

```ruby
class RedisAdapter < DecisionAgent::Versioning::Adapter
  def create_version(rule_id:, content:, metadata: {})
    # Your implementation
  end

  def list_versions(rule_id:, limit: nil)
    # Your implementation
  end

  # ... implement other methods
end

manager = DecisionAgent::Versioning::VersionManager.new(
  adapter: RedisAdapter.new
)
```

## HTTP API Endpoints

When using the Rack web server:

### `POST /api/versions`

Create a new version.

```bash
curl -X POST http://localhost:4567/api/versions \
  -H "Content-Type: application/json" \
  -d '{
    "rule_id": "approval_001",
    "content": { "version": "1.0", "rules": [...] },
    "created_by": "admin",
    "changelog": "Initial version"
  }'
```

### `GET /api/rules/:rule_id/versions`

List versions for a rule.

```bash
curl http://localhost:4567/api/rules/approval_001/versions?limit=10
```

### `GET /api/rules/:rule_id/history`

Get version history with metadata.

```bash
curl http://localhost:4567/api/rules/approval_001/history
```

### `GET /api/versions/:version_id`

Get a specific version.

```bash
curl http://localhost:4567/api/versions/approval_001_v1
```

### `POST /api/versions/:version_id/activate`

Activate a version (rollback).

```bash
curl -X POST http://localhost:4567/api/versions/approval_001_v3/activate \
  -H "Content-Type: application/json" \
  -d '{ "performed_by": "admin" }'
```

### `GET /api/versions/:id1/compare/:id2`

Compare two versions.

```bash
curl http://localhost:4567/api/versions/approval_001_v1/compare/approval_001_v2
```

## Integration Examples

### With A/B Testing

Versioning integrates seamlessly with A/B testing:

```ruby
require 'decision_agent'

# Create version manager
version_manager = DecisionAgent::Versioning::VersionManager.new

# Create A/B test manager (uses versioning internally)
ab_test_manager = DecisionAgent::ABTesting::ABTestManager.new(
  version_manager: version_manager
)

# Create different rule versions for A/B testing
version_a = version_manager.save_version(
  rule_id: "recommendation_001",
  rule_content: variant_a_rules,
  created_by: "data_team",
  changelog: "Variant A: Conservative recommendations"
)

version_b = version_manager.save_version(
  rule_id: "recommendation_001",
  rule_content: variant_b_rules,
  created_by: "data_team",
  changelog: "Variant B: Aggressive recommendations"
)

# Create A/B test using version IDs
ab_test = ab_test_manager.create_test(
  name: "Recommendation Strategy Test",
  variants: [
    { name: "conservative", version_id: version_a[:id] },
    { name: "aggressive", version_id: version_b[:id] }
  ]
)

# The ABTestingAgent automatically loads the correct version
# based on user assignment
```

### With Rails Models

```ruby
# In your Rails app
class ApprovalRule < ApplicationRecord
  has_many :rule_versions, foreign_key: :rule_id, primary_key: :rule_id
  
  def current_version
    rule_versions.active.first
  end
  
  def create_new_version(content:, created_by:)
    version_manager = DecisionAgent::Versioning::VersionManager.new
    version_manager.save_version(
      rule_id: rule_id,
      rule_content: content,
      created_by: created_by,
      changelog: "Updated via Rails interface"
    )
  end
end

# Usage
rule = ApprovalRule.find_by(rule_id: "approval_001")
version = rule.create_new_version(
  content: new_rules,
  created_by: current_user.email
)
```

### With Rack

```ruby
require 'rack'
require 'decision_agent'

manager = DecisionAgent::Versioning::VersionManager.new

# In your Rack app's call method
if env['REQUEST_METHOD'] == 'POST' && env['PATH_INFO'] =~ %r{^/rules/([^/]+)/versions$}
  rule_id = $1
  request = Rack::Request.new(env)
  data = JSON.parse(request.body.read)
  
  version = manager.save_version(
    rule_id: rule_id,
    rule_content: data['content'],
    created_by: data['created_by'] || 'api',
    changelog: data['changelog']
  )
  
  [200, {'Content-Type' => 'application/json'}, [version.to_json]]
elsif env['REQUEST_METHOD'] == 'GET' && env['PATH_INFO'] =~ %r{^/rules/([^/]+)/versions$}
  rule_id = $1
  
  versions = manager.get_versions(rule_id: params[:rule_id])
  versions.to_json
end
```

## Error Handling

The versioning system raises specific errors that should be handled:

### Error Types

```ruby
# ValidationError - Invalid input or operation
begin
  manager.save_version(
    rule_id: "test",
    rule_content: nil  # Invalid: content cannot be nil
  )
rescue DecisionAgent::ValidationError => e
  puts "Validation failed: #{e.message}"
end

# NotFoundError - Version or resource not found
begin
  manager.get_version(version_id: "nonexistent_v1")
rescue DecisionAgent::NotFoundError => e
  puts "Version not found: #{e.message}"
end

# ConfigurationError - Adapter configuration issues
begin
  # Trying to use ActiveRecord adapter without Rails
  adapter = DecisionAgent::Versioning::ActiveRecordAdapter.new
rescue DecisionAgent::ConfigurationError => e
  puts "Configuration error: #{e.message}"
end
```

### Common Error Scenarios

**1. Deleting Active Version:**
```ruby
begin
  manager.delete_version(version_id: active_version_id)
rescue DecisionAgent::ValidationError => e
  # Must activate another version first
  manager.rollback(version_id: another_version_id)
  manager.delete_version(version_id: active_version_id)
end
```

**2. Invalid Rule Content:**
```ruby
begin
  manager.save_version(
    rule_id: "test",
    rule_content: "not a hash"  # Must be a Hash
  )
rescue DecisionAgent::ValidationError => e
  puts "Invalid content: #{e.message}"
end
```

**3. Concurrent Access Issues:**
```ruby
# File storage handles this automatically with locks
# ActiveRecord handles this with transactions

# If you encounter lock timeouts, retry with exponential backoff
retries = 0
begin
  version = manager.save_version(rule_id: "test", rule_content: content)
rescue StandardError => e
  retries += 1
  if retries < 3
    sleep(2 ** retries)  # Exponential backoff
    retry
  else
    raise
  end
end
```

## Performance Considerations

### File Storage Performance

**Optimizations:**
- Per-rule mutexes allow parallel processing
- Version index cache for O(1) lookups
- Atomic file writes prevent corruption
- Efficient directory scanning with glob patterns

**Limitations:**
- Not ideal for very high concurrency (>100 concurrent writes)
- File I/O can be slower than database operations
- Index must be rebuilt on startup (fast for <50k versions)

**When to Use:**
- Development and testing
- Low to medium traffic applications
- When you want simple, file-based storage
- No database available

### ActiveRecord Performance

**Optimizations:**
- Database indexes on `rule_id` and `version_number`
- Efficient bulk updates with `update_all`
- Transaction-based locking prevents race conditions
- Query optimization with proper indexes

**Database Indexes:**
```ruby
# Recommended indexes for performance
add_index :rule_versions, :rule_id
add_index :rule_versions, [:rule_id, :version_number], unique: true
add_index :rule_versions, [:rule_id, :status]
```

**When to Use:**
- Production applications
- High-concurrency scenarios
- When you need advanced querying
- Integration with existing Rails apps

### Caching Strategies

```ruby
# Cache active versions in your application
class VersionCache
  def initialize(version_manager)
    @version_manager = version_manager
    @cache = {}
    @cache_mutex = Mutex.new
  end
  
  def get_active_version(rule_id)
    @cache_mutex.synchronize do
      @cache[rule_id] ||= @version_manager.get_active_version(rule_id: rule_id)
    end
  end
  
  def invalidate(rule_id)
    @cache_mutex.synchronize do
      @cache.delete(rule_id)
    end
  end
end

# Use cache in your application
cache = VersionCache.new(version_manager)

# Fast lookup
active_version = cache.get_active_version("approval_001")

# Invalidate on version changes
manager.save_version(rule_id: "approval_001", rule_content: content)
cache.invalidate("approval_001")
```

### Bulk Operations

```ruby
# For bulk version creation, consider batching
rule_contents.each_slice(100) do |batch|
  batch.each do |rule_id, content|
    manager.save_version(rule_id: rule_id, rule_content: content)
  end
end
```

## Best Practices

1. **Use Meaningful Changelogs** - Document what changed and why
   ```ruby
   manager.save_version(
     rule_id: "approval_001",
     rule_content: content,
     changelog: "Increased approval threshold from $1000 to $5000 per compliance review"
   )
   ```

2. **Track Who Made Changes** - Always specify `created_by`
   ```ruby
   manager.save_version(
     rule_id: "approval_001",
     rule_content: content,
     created_by: current_user.email
   )
   ```

3. **Version Before Deployment** - Create versions before deploying to production

4. **Regular Backups** - For file storage, backup the `versions/` directory

5. **Test Rollbacks** - Verify rollback functionality in staging

6. **Use Status Field** - Leverage draft/active/archived statuses
   - `draft` - Work in progress
   - `active` - Currently in use
   - `archived` - Historical version

7. **Handle Errors Gracefully** - Always wrap version operations in error handling
   ```ruby
   begin
     version = manager.save_version(...)
   rescue DecisionAgent::ValidationError, DecisionAgent::NotFoundError => e
     # Handle expected errors
   end
   ```

8. **Cache Active Versions** - For high-traffic applications, cache active versions
   ```ruby
   # Cache active version lookups to reduce database/file I/O
   active_version = cache.fetch("rule:#{rule_id}:active") do
     manager.get_active_version(rule_id: rule_id)
   end
   ```

9. **Use Appropriate Adapter** - Choose the right storage adapter for your use case
   - File storage: Development, low-medium traffic
   - ActiveRecord: Production, high traffic, Rails apps

10. **Monitor Version Growth** - Periodically archive old versions
    ```ruby
    # Archive versions older than 1 year
    old_versions = manager.get_versions(rule_id: rule_id)
                          .select { |v| v[:created_at] < 1.year.ago }
    
    old_versions.each do |version|
      # Mark as archived if not already
      # Consider moving to cold storage for very old versions
    end
    ```

## Troubleshooting

### Versions Not Persisting

**File Storage:**
- Check directory permissions for `./versions/`
- Verify disk space

**ActiveRecord:**
- Run migrations: `rails db:migrate`
- Check database connectivity

### Auto-Detection Not Working

Explicitly specify an adapter:

```ruby
# Force file storage
adapter = DecisionAgent::Versioning::FileStorageAdapter.new
manager = DecisionAgent::Versioning::VersionManager.new(adapter: adapter)

# Force ActiveRecord (requires Rails + models)
adapter = DecisionAgent::Versioning::ActiveRecordAdapter.new
manager = DecisionAgent::Versioning::VersionManager.new(adapter: adapter)
```

### Version Index Out of Sync (File Storage)

If the version index becomes out of sync:

```ruby
# Rebuild the index by reinitializing the adapter
adapter = DecisionAgent::Versioning::FileStorageAdapter.new
# The index is automatically rebuilt on initialization
```

### Database Lock Timeouts (ActiveRecord)

If you encounter lock timeouts in high-concurrency scenarios:

```ruby
# Increase lock timeout in your database configuration
# PostgreSQL:
# SET lock_timeout = '5s';

# Or use optimistic locking for read-heavy scenarios
# (requires additional implementation)
```

### DMN Version Parsing Errors

If DMN versions fail to parse:

```ruby
begin
  dmn_version = dmn_manager.get_dmn_version(version_id: version_id)
rescue => e
  # Check if the version content is valid DMN XML
  version = version_manager.get_version(version_id: version_id)
  if version[:content][:format] == "dmn"
    # Validate XML structure
    # May need to fix corrupted DMN content
  end
end
```

## License

Part of DecisionAgent gem - MIT License
