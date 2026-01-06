# Data Enrichment

Complete guide to REST API data enrichment for DecisionAgent.

## Table of Contents

- [Overview](#overview)
- [Quick Start](#quick-start)
- [Configuration](#configuration)
- [Usage in Rules](#usage-in-rules)
- [Caching](#caching)
- [Circuit Breaker](#circuit-breaker)
- [Error Handling](#error-handling)
- [Authentication](#authentication)
- [API Reference](#api-reference)
- [Best Practices](#best-practices)

## Overview

DecisionAgent's data enrichment feature enables rules to fetch external data during decision-making without manual context assembly. This eliminates data preparation overhead and enables real-time decision-making with live data.

### Features

- **HTTP Client** - Support for GET, POST, PUT, DELETE methods
- **Response Caching** - Configurable TTL per endpoint with multiple adapter support
- **Circuit Breaker** - Fail-fast after N failures to prevent cascading failures
- **Retry Logic** - Exponential backoff retry strategy
- **Graceful Degradation** - Fallback to cached data or default values
- **Authentication Support** - API key, OAuth2, Basic Auth
- **Request/Response Logging** - Audit trail for compliance

### Use Cases

- **Fraud Detection** - Fetch risk scores from external services
- **Credit Scoring** - Get credit bureau data in real-time
- **Dynamic Pricing** - Retrieve market data for pricing decisions
- **Compliance Checking** - Verify against regulatory databases
- **Identity Verification** - Validate user information

## Quick Start

### 1. Configure Endpoints

```ruby
require 'decision_agent'

DecisionAgent.configure_data_enrichment do |config|
  config.add_endpoint(:credit_bureau,
    url: "https://api.creditbureau.com/v1/score",
    method: :post,
    auth: { type: :api_key, header: "X-API-Key" },
    cache: { ttl: 3600, adapter: :memory },
    retry_config: { max_attempts: 3, backoff: :exponential }
  )
end
```

### 2. Set Environment Variables

```bash
# API key for authentication
export API_KEY=your_api_key_here
```

### 3. Use in Rules

```ruby
rules = {
  version: "1.0",
  ruleset: "loan_approval",
  rules: [
    {
      id: "check_credit_score",
      if: {
        field: "credit_score",
        op: "fetch_from_api",
        value: {
          endpoint: "credit_bureau",
          params: { ssn: "{{customer.ssn}}" },
          mapping: { score: "credit_score" }
        }
      },
      then: {
        decision: "approve",
        weight: 0.8,
        reason: "Credit score verified"
      }
    }
  ]
}
```

### 4. Make Decisions

```ruby
agent = DecisionAgent::Agent.new(evaluators: [evaluator])
context = { customer: { ssn: "123-45-6789" } }
decision = agent.decide(context: context)
```

## Configuration

### Basic Endpoint Configuration

```ruby
DecisionAgent.configure_data_enrichment do |config|
  config.add_endpoint(:my_endpoint,
    url: "https://api.example.com/data",
    method: :get
  )
end
```

### Advanced Configuration

```ruby
DecisionAgent.configure_data_enrichment do |config|
  # Set default values
  config.default_timeout = 10
  config.default_retry = { max_attempts: 5, backoff: :exponential }
  config.default_cache = { ttl: 7200, adapter: :memory }

  # Add endpoint with full configuration
  config.add_endpoint(:credit_bureau,
    url: "https://api.creditbureau.com/v1/score",
    method: :post,
    auth: {
      type: :api_key,
      header: "X-API-Key",
      secret_key: "CREDIT_BUREAU_API_KEY"
    },
    cache: {
      ttl: 3600,
      adapter: :memory
    },
    retry_config: {
      max_attempts: 3,
      backoff: :exponential
    },
    timeout: 5,
    headers: {
      "Content-Type" => "application/json",
      "User-Agent" => "DecisionAgent/1.0"
    }
  )
end
```

### Configuration Options

- **url** (required) - Base URL for the endpoint
- **method** (optional) - HTTP method (:get, :post, :put, :delete), default: :get
- **auth** (optional) - Authentication configuration (see [Authentication](#authentication))
- **cache** (optional) - Cache configuration (see [Caching](#caching))
- **retry_config** (optional) - Retry configuration
- **timeout** (optional) - Request timeout in seconds, default: 5
- **headers** (optional) - Default headers to include in requests
- **rate_limit** (optional) - Rate limiting configuration (future enhancement)

## Usage in Rules

### Basic Usage

The `fetch_from_api` operator fetches data from a configured endpoint and enriches the context:

```ruby
{
  field: "credit_score",
  op: "fetch_from_api",
  value: {
    endpoint: "credit_bureau",
    params: { ssn: "{{customer.ssn}}" },
    mapping: { score: "credit_score" }
  }
}
```

### Template Parameters

Use `{{path}}` syntax to reference context values in parameters:

```ruby
{
  endpoint: "fraud_check",
  params: {
    user_id: "{{user.id}}",
    amount: "{{transaction.amount}}",
    timestamp: "{{transaction.timestamp}}"
  }
}
```

### Response Mapping

Map API response fields to context fields:

```ruby
{
  endpoint: "credit_bureau",
  params: { ssn: "{{customer.ssn}}" },
  mapping: {
    score: "credit_score",
    risk_level: "risk_level",
    last_updated: "credit_last_updated"
  }
}
```

### Combined with Other Operators

Use fetched data in subsequent conditions:

```ruby
{
  all: [
    {
      field: "credit_score",
      op: "fetch_from_api",
      value: {
        endpoint: "credit_bureau",
        params: { ssn: "{{customer.ssn}}" },
        mapping: { score: "credit_score" }
      }
    },
    {
      field: "credit_score",
      op: "gte",
      value: 700
    }
  ]
}
```

## Caching

### Cache Configuration

```ruby
config.add_endpoint(:my_endpoint,
  url: "https://api.example.com/data",
  cache: {
    ttl: 3600,        # Cache for 1 hour
    adapter: :memory  # Use in-memory cache
  }
)
```

### Cache Adapters

- **:memory** (default) - In-memory cache, fast but not persistent
- **:redis** (future) - Redis-backed cache for distributed systems

### Cache Behavior

- Responses are cached by default
- Cache keys are generated from endpoint name and request parameters
- Cache TTL is configurable per endpoint
- Cache can be cleared manually or automatically on expiration

### Disable Caching

```ruby
# In rule usage (future enhancement)
{
  field: "data",
  op: "fetch_from_api",
  value: {
    endpoint: "my_endpoint",
    use_cache: false
  }
}
```

## Circuit Breaker

The circuit breaker pattern prevents cascading failures by opening the circuit after N failures.

### Configuration

```ruby
# Global circuit breaker (applies to all endpoints)
client = DecisionAgent::DataEnrichment::Client.new(
  config: config,
  circuit_breaker: DecisionAgent::DataEnrichment::CircuitBreaker.new(
    failure_threshold: 5,  # Open after 5 failures
    timeout: 60,           # Stay open for 60 seconds
    success_threshold: 2   # Close after 2 successful calls
  )
)

DecisionAgent.data_enrichment_client = client
```

### Circuit States

- **CLOSED** - Normal operation, requests are executed
- **OPEN** - Circuit is open, requests fail fast
- **HALF_OPEN** - Testing if service has recovered

### Behavior

- Circuit opens after `failure_threshold` failures
- Circuit stays open for `timeout` seconds
- Circuit moves to HALF_OPEN state after timeout
- Circuit closes after `success_threshold` successful calls in HALF_OPEN state
- Falls back to cached data when circuit is open (if available)

## Error Handling

### Error Types

- **RequestError** - Client or server error (4xx, 5xx)
- **TimeoutError** - Request timeout
- **NetworkError** - Network connectivity issues
- **CircuitOpenError** - Circuit breaker is open

### Graceful Degradation

When an error occurs:

1. **Circuit breaker open** - Return cached data if available
2. **Timeout** - Return cached data if available, otherwise false
3. **Network error** - Return cached data if available, otherwise false
4. **Server error** - Return cached data if available, otherwise false

### Error Handling in Rules

The `fetch_from_api` operator returns `false` on error, allowing rules to handle failures gracefully:

```ruby
{
  any: [
    {
      field: "credit_score",
      op: "fetch_from_api",
      value: { endpoint: "credit_bureau", params: {} }
    },
    {
      field: "fallback_score",
      op: "present"
    }
  ]
}
```

## Authentication

### API Key Authentication

```ruby
config.add_endpoint(:my_endpoint,
  url: "https://api.example.com/data",
  auth: {
    type: :api_key,
    header: "X-API-Key",
    secret_key: "MY_API_KEY"  # Environment variable name
  }
)
```

Set environment variable:
```bash
export MY_API_KEY=your_api_key_here
```

### Basic Authentication

```ruby
config.add_endpoint(:my_endpoint,
  url: "https://api.example.com/data",
  auth: {
    type: :basic,
    username_key: "API_USERNAME",
    password_key: "API_PASSWORD"
  }
)
```

Set environment variables:
```bash
export API_USERNAME=your_username
export API_PASSWORD=your_password
```

### Bearer Token Authentication

```ruby
config.add_endpoint(:my_endpoint,
  url: "https://api.example.com/data",
  auth: {
    type: :bearer,
    token_key: "API_TOKEN"
  }
)
```

Set environment variable:
```bash
export API_TOKEN=your_token_here
```

### OAuth2 (Future Enhancement)

OAuth2 support is planned for future releases.

## API Reference

### DecisionAgent.configure_data_enrichment

Configure data enrichment endpoints.

```ruby
DecisionAgent.configure_data_enrichment do |config|
  config.add_endpoint(:endpoint_name, options)
end
```

### DecisionAgent.data_enrichment_client

Get the configured data enrichment client.

```ruby
client = DecisionAgent.data_enrichment_client
client.fetch(:endpoint_name, params: {})
```

### Config#add_endpoint

Add or update an endpoint configuration.

```ruby
config.add_endpoint(name, url:, method: :get, auth: nil, cache: nil, retry_config: nil, timeout: nil, headers: {}, rate_limit: nil)
```

### Client#fetch

Fetch data from a configured endpoint.

```ruby
client.fetch(endpoint_name, params: {}, use_cache: true)
```

### Client#clear_cache

Clear cache for an endpoint or all endpoints.

```ruby
client.clear_cache(:endpoint_name)  # Clear specific endpoint
client.clear_cache                  # Clear all caches
```

## Best Practices

### 1. Use Appropriate Cache TTLs

- **Static data** - Long TTL (24 hours)
- **Semi-static data** - Medium TTL (1 hour)
- **Dynamic data** - Short TTL (5 minutes) or no cache

### 2. Configure Circuit Breakers

Set appropriate thresholds based on your reliability requirements:

```ruby
circuit_breaker = DecisionAgent::DataEnrichment::CircuitBreaker.new(
  failure_threshold: 5,   # Tolerate 5 failures
  timeout: 60,            # Wait 60 seconds before retry
  success_threshold: 2    # Require 2 successes to close
)
```

### 3. Handle Errors Gracefully

Always provide fallback logic in your rules:

```ruby
{
  any: [
    { field: "external_data", op: "fetch_from_api", value: { endpoint: "external" } },
    { field: "fallback", op: "present" }
  ]
}
```

### 4. Use Template Parameters

Leverage template parameters to pass context values:

```ruby
params: {
  user_id: "{{user.id}}",
  amount: "{{transaction.amount}}"
}
```

### 5. Monitor Performance

Monitor cache hit rates and API response times:

```ruby
cache_stats = cache_adapter.stats
circuit_state = circuit_breaker.state
```

### 6. Secure API Keys

- Store API keys in environment variables
- Never commit keys to version control
- Use secrets management in production (AWS Secrets Manager, HashiCorp Vault, etc.)

### 7. Set Appropriate Timeouts

Set timeouts based on expected API response times:

```ruby
config.add_endpoint(:slow_api,
  url: "https://api.example.com/slow",
  timeout: 30  # Allow 30 seconds for slow APIs
)
```

## Limitations and Future Enhancements

### Current Limitations

- Redis cache adapter not yet implemented
- Rate limiting not yet implemented
- OAuth2 authentication not yet implemented
- Request signing not yet implemented

### Planned Enhancements

- **Redis Cache Adapter** - Distributed caching
- **Rate Limiting** - Per-endpoint rate limits
- **OAuth2 Support** - Full OAuth2 flow
- **Request Signing** - HMAC request signing
- **GraphQL Support** - GraphQL query support
- **Database Integration** - Direct database queries
- **Message Queue Integration** - Kafka, RabbitMQ support

## Examples

### Credit Score Check

```ruby
DecisionAgent.configure_data_enrichment do |config|
  config.add_endpoint(:credit_bureau,
    url: "https://api.creditbureau.com/v1/score",
    method: :post,
    auth: { type: :api_key, header: "X-API-Key" },
    cache: { ttl: 3600 },
    timeout: 5
  )
end

rules = {
  rules: [{
    id: "check_credit",
    if: {
      field: "credit_score",
      op: "fetch_from_api",
      value: {
        endpoint: "credit_bureau",
        params: { ssn: "{{customer.ssn}}" },
        mapping: { score: "credit_score" }
      }
    },
    then: { decision: "approve", weight: 0.8 }
  }]
}
```

### Fraud Detection

```ruby
DecisionAgent.configure_data_enrichment do |config|
  config.add_endpoint(:fraud_service,
    url: "https://api.fraudservice.com/check",
    method: :post,
    auth: { type: :bearer, token_key: "FRAUD_SERVICE_TOKEN" },
    cache: { ttl: 300 },  # 5 minutes cache
    timeout: 3
  )
end

rules = {
  rules: [{
    id: "fraud_check",
    if: {
      all: [
        {
          field: "fraud_score",
          op: "fetch_from_api",
          value: {
            endpoint: "fraud_service",
            params: {
              user_id: "{{user.id}}",
              amount: "{{transaction.amount}}",
              ip_address: "{{transaction.ip}}"
            },
            mapping: { risk_score: "fraud_score" }
          }
        },
        {
          field: "fraud_score",
          op: "lt",
          value: 0.5
        }
      ]
    },
    then: { decision: "approve", weight: 0.9 }
  }]
}
```

## Troubleshooting

### Common Issues

#### 1. "Unknown endpoint" Error

**Problem:** Endpoint not configured.

**Solution:** Ensure endpoint is configured before use:

```ruby
DecisionAgent.configure_data_enrichment do |config|
  config.add_endpoint(:my_endpoint, url: "https://api.example.com")
end
```

#### 2. "Secret not found" Error

**Problem:** Environment variable not set.

**Solution:** Set the required environment variable:

```bash
export API_KEY=your_key_here
```

#### 3. Circuit Breaker Always Open

**Problem:** Too many failures or incorrect configuration.

**Solution:** Check API availability and adjust circuit breaker settings:

```ruby
circuit_breaker = DecisionAgent::DataEnrichment::CircuitBreaker.new(
  failure_threshold: 10,  # Increase threshold
  timeout: 120            # Increase timeout
)
```

#### 4. Cache Not Working

**Problem:** Cache TTL set to 0 or caching disabled.

**Solution:** Configure cache with appropriate TTL:

```ruby
cache: { ttl: 3600, adapter: :memory }
```

## See Also

- [API Contract](API_CONTRACT.md) - API documentation
- [Monitoring and Analytics](MONITORING_AND_ANALYTICS.md) - Monitoring setup
- [Best Practices](DMN_BEST_PRACTICES.md) - Rule design best practices

