# Persistent Monitoring Storage

DecisionAgent supports persistent database storage for monitoring metrics, enabling long-term analytics and historical analysis beyond the default in-memory storage.

## Features

- **Persistent Storage**: Store decision logs, evaluations, performance metrics, and errors in a database
- **Auto-Detection**: Automatically uses database storage when models are available, falls back to in-memory
- **Flexible Configuration**: Choose between database, memory, or custom storage adapters
- **ActiveRecord Integration**: Works seamlessly with Rails applications
- **Database Agnostic**: Supports PostgreSQL, MySQL, SQLite via ActiveRecord
- **Rake Tasks**: Built-in tasks for cleanup, archival, and statistics
- **Historical Analytics**: Query metrics beyond the default 1-hour window

## Installation (Rails)

### 1. Generate Models and Migrations

Run the generator with the `--monitoring` flag:

```bash
rails generate decision_agent:install --monitoring
```

This creates:
- **Models**: `DecisionLog`, `EvaluationMetric`, `PerformanceMetric`, `ErrorMetric`
- **Migration**: Database tables with proper indexes
- **Rake Tasks**: Cleanup and stats tasks

### 2. Run Migrations

```bash
rails db:migrate
```

### 3. Verify Installation

```ruby
# Check if models are available
DecisionLog # => DecisionLog(id: integer, decision: string, ...)

# Metrics collector will auto-detect and use database storage
collector = DecisionAgent::Monitoring::MetricsCollector.new
collector.storage_adapter # => DecisionAgent::Monitoring::Storage::ActiveRecordAdapter
```

## Database Schema

### decision_logs

| Column | Type | Description |
|--------|------|-------------|
| id | integer | Primary key |
| decision | string | Decision made |
| confidence | float | Confidence score (0-1) |
| evaluations_count | integer | Number of evaluations |
| duration_ms | float | Decision duration in milliseconds |
| status | string | success, failure, error |
| context | text (JSON) | Decision context |
| metadata | text (JSON) | Additional metadata |
| created_at | datetime | Timestamp |

**Indexes**: decision, status, confidence, created_at, [decision, created_at], [status, created_at]

### evaluation_metrics

| Column | Type | Description |
|--------|------|-------------|
| id | integer | Primary key |
| decision_log_id | integer | Foreign key to decision_logs |
| evaluator_name | string | Name of evaluator |
| score | float | Evaluation score |
| success | boolean | Evaluation succeeded |
| duration_ms | float | Evaluation duration |
| details | text (JSON) | Additional details |
| created_at | datetime | Timestamp |

**Indexes**: evaluator_name, success, created_at, [evaluator_name, created_at]

### performance_metrics

| Column | Type | Description |
|--------|------|-------------|
| id | integer | Primary key |
| operation | string | Operation name |
| duration_ms | float | Operation duration |
| status | string | success, failure, error |
| metadata | text (JSON) | Additional metadata |
| created_at | datetime | Timestamp |

**Indexes**: operation, status, duration_ms, created_at, [operation, created_at]

### error_metrics

| Column | Type | Description |
|--------|------|-------------|
| id | integer | Primary key |
| error_type | string | Error class name |
| message | text | Error message |
| stack_trace | text (JSON) | Stack trace array |
| severity | string | low, medium, high, critical |
| context | text (JSON) | Error context |
| created_at | datetime | Timestamp |

**Indexes**: error_type, severity, created_at, [error_type, created_at]

## Configuration

### Storage Adapter Options

```ruby
# Auto-detect (default): Uses database if available, else memory
collector = DecisionAgent::Monitoring::MetricsCollector.new(storage: :auto)

# Force database storage
collector = DecisionAgent::Monitoring::MetricsCollector.new(storage: :activerecord)
collector = DecisionAgent::Monitoring::MetricsCollector.new(storage: :database)

# Force in-memory storage
collector = DecisionAgent::Monitoring::MetricsCollector.new(storage: :memory, window_size: 3600)

# Custom adapter
custom_adapter = MyCustomAdapter.new
collector = DecisionAgent::Monitoring::MetricsCollector.new(storage: custom_adapter)
```

### Dashboard Server with Database Storage

```ruby
# MetricsCollector auto-detects database availability
collector = DecisionAgent::Monitoring::MetricsCollector.new

# DashboardServer automatically uses collector's storage
server = DecisionAgent::Monitoring::DashboardServer.new(
  metrics_collector: collector,
  port: 4568
)

server.start
# Dashboard will query database for historical metrics
```

## Querying Metrics

### Using ActiveRecord Models

```ruby
# Recent decisions (last hour)
DecisionLog.recent(3600)

# Successful decisions
DecisionLog.successful

# Low confidence decisions
DecisionLog.low_confidence(0.5)

# Decisions by type
DecisionLog.by_decision("approve_payment").count

# Success rate
DecisionLog.success_rate(time_range: 3600)
```

### Using MetricsCollector

```ruby
collector = DecisionAgent::Monitoring::MetricsCollector.new

# Get statistics (automatically queries database)
stats = collector.statistics(time_range: 3600)

# Time series data
series = collector.time_series(
  metric_type: :decisions,
  bucket_size: 60,
  time_range: 3600
)

# Metrics count
counts = collector.metrics_count
# => { decisions: 1523, evaluations: 4521, performance: 892, errors: 12 }
```

## Rake Tasks

### Cleanup Old Metrics

```bash
# Delete metrics older than 30 days (default)
rake decision_agent:monitoring:cleanup

# Delete metrics older than 7 days
OLDER_THAN=604800 rake decision_agent:monitoring:cleanup

# Delete metrics older than 90 days
OLDER_THAN=7776000 rake decision_agent:monitoring:cleanup
```

### View Statistics

```bash
# Show stats for last hour (default)
rake decision_agent:monitoring:stats

# Show stats for last 24 hours
TIME_RANGE=86400 rake decision_agent:monitoring:stats
```

### Archive to JSON

```bash
# Archive metrics older than 30 days to JSON
rake decision_agent:monitoring:archive

# Specify output file
rake decision_agent:monitoring:archive[metrics_2024.json]

# Archive metrics older than 60 days
OLDER_THAN=5184000 rake decision_agent:monitoring:archive
```

## Programmatic Cleanup

```ruby
collector = DecisionAgent::Monitoring::MetricsCollector.new

# Cleanup metrics older than 7 days
count = collector.cleanup_old_metrics_from_storage(older_than: 7 * 24 * 3600)
puts "Deleted #{count} old metrics"
```

## Performance Considerations

### Indexes

The migration creates comprehensive indexes for common query patterns:

```ruby
# Optimized queries
DecisionLog.where(decision: "approve").recent(3600) # Uses [decision, created_at] index
PerformanceMetric.where(status: "success").recent(3600) # Uses [status, created_at] index
ErrorMetric.where(severity: "critical").recent(3600) # Uses [severity, created_at] index
```

### PostgreSQL Optimizations

The migration includes PostgreSQL-specific partial indexes for recent data:

```sql
CREATE INDEX index_decision_logs_on_recent
ON decision_logs (created_at DESC)
WHERE created_at >= NOW() - INTERVAL '7 days';
```

### Database Partitioning (Optional)

For large-scale deployments, consider table partitioning by time:

```ruby
# Example: Partition decision_logs by month
execute <<-SQL
  CREATE TABLE decision_logs_partitioned (LIKE decision_logs INCLUDING ALL)
  PARTITION BY RANGE (created_at);

  CREATE TABLE decision_logs_2024_01 PARTITION OF decision_logs_partitioned
  FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');
SQL
```

### Memory vs Database Storage

| Feature | Memory Storage | Database Storage |
|---------|---------------|------------------|
| Persistence | ❌ Lost on restart | ✅ Persistent |
| Retention | 1 hour default | Unlimited (with cleanup) |
| Query Performance | ⚡ Very fast | 🚀 Fast (with indexes) |
| Historical Analysis | ❌ Limited | ✅ Full history |
| Scalability | Limited by RAM | ✅ Scales with DB |
| Dependencies | None | ActiveRecord + DB |
| Setup Complexity | None | Requires migration |

## Custom Storage Adapters

Implement the `BaseAdapter` interface for custom storage backends:

```ruby
class RedisAdapter < DecisionAgent::Monitoring::Storage::BaseAdapter
  def initialize(redis_client)
    @redis = redis_client
  end

  def record_decision(decision, context, **options)
    @redis.lpush("decisions", {
      decision: decision,
      context: context,
      timestamp: Time.now
    }.to_json)
  end

  def statistics(time_range: 3600)
    # Implement statistics logic
  end

  # Implement other required methods...

  def self.available?
    defined?(Redis)
  end
end

# Use custom adapter
collector = DecisionAgent::Monitoring::MetricsCollector.new(
  storage: RedisAdapter.new(Redis.new)
)
```

## Migration Guide

### From In-Memory to Database Storage

1. **Install monitoring tables**:
   ```bash
   rails generate decision_agent:install --monitoring
   rails db:migrate
   ```

2. **No code changes required**: MetricsCollector auto-detects database availability

3. **Verify**:
   ```ruby
   collector = DecisionAgent::Monitoring::MetricsCollector.new
   collector.storage_adapter.class.name
   # => "DecisionAgent::Monitoring::Storage::ActiveRecordAdapter"
   ```

### From Database Back to Memory

```ruby
# Explicitly use memory storage
collector = DecisionAgent::Monitoring::MetricsCollector.new(
  storage: :memory,
  window_size: 3600
)
```

## Troubleshooting

### Models Not Found Error

```
Missing required models: DecisionLog, EvaluationMetric, PerformanceMetric, ErrorMetric
```

**Solution**: Run the generator with `--monitoring` flag:
```bash
rails generate decision_agent:install --monitoring
rails db:migrate
```

### Adapter Not Available

If `storage: :activerecord` raises an error:

```ruby
# Check if ActiveRecord is loaded
defined?(ActiveRecord) # => should be "constant"

# Check if models exist
defined?(::DecisionLog) # => should be "constant"

# Force memory storage as fallback
collector = DecisionAgent::Monitoring::MetricsCollector.new(storage: :memory)
```

### Slow Queries

1. **Check indexes**:
   ```ruby
   ActiveRecord::Base.connection.indexes(:decision_logs)
   ```

2. **Add missing indexes**:
   ```ruby
   add_index :decision_logs, [:decision, :status, :created_at]
   ```

3. **Use EXPLAIN**:
   ```ruby
   DecisionLog.recent(3600).explain
   ```

## Best Practices

1. **Regular Cleanup**: Schedule cleanup tasks to prevent unbounded growth
   ```ruby
   # config/schedule.rb (with whenever gem)
   every 1.day, at: '2:00 am' do
     rake 'decision_agent:monitoring:cleanup'
   end
   ```

2. **Archive Before Cleanup**: Archive old data before deletion
   ```bash
   rake decision_agent:monitoring:archive
   rake decision_agent:monitoring:cleanup
   ```

3. **Monitor Database Size**: Track table sizes
   ```sql
   SELECT pg_size_pretty(pg_total_relation_size('decision_logs'));
   ```

4. **Use Appropriate Time Ranges**: Query only what you need
   ```ruby
   # Good: Query last hour
   DecisionLog.recent(3600)

   # Avoid: Loading all records
   DecisionLog.all
   ```

5. **Leverage Database Features**: Use database-specific optimizations (partitioning, materialized views, etc.)

## Example Application

See `examples/06_persistent_monitoring.rb` for a complete example demonstrating:
- Database-backed metrics collection
- Real-time monitoring with persistence
- Querying historical data
- Cleanup and archival
- Dashboard integration
