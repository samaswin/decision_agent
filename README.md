# DecisionAgent

[![Gem Version](https://badge.fury.io/rb/decision_agent.svg)](https://badge.fury.io/rb/decision_agent)
[![CI](https://github.com/samaswin87/decision_agent/actions/workflows/ci.yml/badge.svg)](https://github.com/samaswin87/decision_agent/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE.txt)
[![Ruby](https://img.shields.io/badge/ruby-%3E%3D%202.7.0-red.svg)](https://www.ruby-lang.org)

A production-grade, deterministic, explainable, and auditable decision engine for Ruby.

**Built for regulated domains. Deterministic by design. AI-optional.**

## Why DecisionAgent?

- ✅ **Deterministic** - Same input always produces same output
- ✅ **Explainable** - Every decision includes human-readable reasoning
- ✅ **Auditable** - Reproduce any historical decision exactly
- ✅ **Framework-agnostic** - Pure Ruby, works anywhere
- ✅ **Production-ready** - Comprehensive testing, error handling, and versioning

## Installation

```bash
gem install decision_agent
```

Or add to your Gemfile:
```ruby
gem 'decision_agent'
```

## Quick Start

```ruby
require 'decision_agent'

# Define evaluator with business rules
evaluator = DecisionAgent::Evaluators::JsonRuleEvaluator.new(
  rules_json: {
    version: "1.0",
    ruleset: "approval_rules",
    rules: [{
      id: "high_value",
      if: { field: "amount", op: "gt", value: 1000 },
      then: { decision: "approve", weight: 0.9, reason: "High value transaction" }
    }]
  }
)

# Create decision agent
agent = DecisionAgent::Agent.new(evaluators: [evaluator])

# Make decision
result = agent.decide(context: { amount: 1500 })

puts result.decision      # => "approve"
puts result.confidence    # => 0.9
puts result.explanations  # => ["High value transaction"]
```

## Web UI - Visual Rule Builder

Launch the visual rule builder for non-technical users:

```bash
decision_agent web
```

Open [http://localhost:4567](http://localhost:4567) in your browser.

<img width="1622" height="820" alt="Screenshot" src="https://github.com/user-attachments/assets/687e9ff6-669a-40f9-be27-085c614392d4" />


## Key Features

### Decision Making
- **Multiple Evaluators** - Combine rule-based, ML, and custom logic
- **Conflict Resolution** - Weighted average, consensus, threshold, max weight
- **Rich Context** - Nested data, dot notation, flexible operators

### Auditability
- **Complete Audit Trails** - Every decision fully logged
- **Deterministic Replay** - Reproduce historical decisions exactly
- **Compliance Ready** - HIPAA, SOX, regulatory compliance support

### Flexibility
- **Pluggable Architecture** - Custom evaluators, scoring, audit adapters
- **Framework Agnostic** - Works with Rails, Sinatra, or standalone
- **JSON Rule DSL** - Non-technical users can write rules
- **Visual Rule Builder** - Web UI for rule management

### Production Ready
- **Comprehensive Testing** - 90%+ code coverage
- **Error Handling** - Clear, actionable error messages
- **Versioning** - Full rule version control and rollback
- **Performance** - Fast, zero external dependencies
- **Thread-Safe** - Safe for multi-threaded servers and background jobs

## Examples

```ruby
# Multiple evaluators with conflict resolution
agent = DecisionAgent::Agent.new(
  evaluators: [rule_evaluator, ml_evaluator],
  scoring_strategy: DecisionAgent::Scoring::Consensus.new(minimum_agreement: 0.7),
  audit_adapter: DecisionAgent::Audit::LoggerAdapter.new
)

# Complex rules with nested conditions
rules = {
  version: "1.0",
  ruleset: "fraud_detection",
  rules: [{
    id: "suspicious_activity",
    if: {
      all: [
        { field: "amount", op: "gt", value: 10000 },
        { any: [
          { field: "user.country", op: "in", value: ["XX", "YY"] },
          { field: "velocity", op: "gt", value: 5 }
        ]}
      ]
    },
    then: { decision: "flag_for_review", weight: 0.95, reason: "Suspicious patterns detected" }
  }]
}
```

See [examples/](examples/) for complete working examples.

## Thread-Safety Guarantees

DecisionAgent is designed to be **thread-safe and FAST** for use in multi-threaded environments:

### Performance
- **10,000+ decisions/second** throughput
- **~0.1ms average latency** per decision
- **Zero performance overhead** from thread-safety
- **Linear scalability** with thread count

### Safe Concurrent Usage
- **Agent instances** can be shared across threads safely
- **Evaluators** are immutable after initialization
- **Decisions and Evaluations** are deeply frozen
- **File storage** uses mutex-protected operations

### Best Practices
```ruby
# Safe: Reuse agent instance across threads
agent = DecisionAgent::Agent.new(evaluators: [evaluator])

Thread.new { agent.decide(context: { user_id: 1 }) }
Thread.new { agent.decide(context: { user_id: 2 }) }

# Safe: Share evaluators across agent instances
evaluator = DecisionAgent::Evaluators::JsonRuleEvaluator.new(rules_json: rules)
agent1 = DecisionAgent::Agent.new(evaluators: [evaluator])
agent2 = DecisionAgent::Agent.new(evaluators: [evaluator])
```

### What's Frozen
All data structures are deeply frozen to prevent mutation:
- Decision objects (decision, confidence, explanations, evaluations)
- Evaluation objects (decision, weight, reason, metadata)
- Context data
- Rule definitions in evaluators

This ensures safe concurrent access without race conditions.

### Performance Benchmark
Run the included benchmark to verify zero overhead:
```bash
ruby examples/thread_safe_performance.rb
```

See [THREAD_SAFETY.md](wiki/THREAD_SAFETY.md) for detailed implementation guide and [PERFORMANCE_AND_THREAD_SAFETY.md](wiki/PERFORMANCE_AND_THREAD_SAFETY.md) for detailed performance analysis.

## When to Use DecisionAgent

✅ **Perfect for:**
- Regulated industries (healthcare, finance, legal)
- Complex business rule engines
- Audit trail requirements
- Explainable AI systems
- Multi-step decision workflows

❌ **Not suitable for:**
- Simple if/else logic (use plain Ruby)
- Pure AI/ML with no rules
- Single-step validations

## Documentation

**Getting Started**
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Examples](examples/README.md)

**Core Features**
- [Versioning System](wiki/VERSIONING.md) - Version control for rules
- [Web UI](wiki/WEB_UI.md) - Visual rule builder
- [Web UI Setup](wiki/WEB_UI_SETUP.md) - Setup guide

**Performance & Thread-Safety**
- [Performance & Thread-Safety Summary](wiki/PERFORMANCE_AND_THREAD_SAFETY.md) - Benchmarks and production readiness
- [Thread-Safety Implementation](wiki/THREAD_SAFETY.md) - Technical implementation guide

**Reference**
- [API Contract](wiki/API_CONTRACT.md) - Full API reference
- [Changelog](wiki/CHANGELOG.md) - Version history

**More Resources**
- [Wiki Home](wiki/README.md) - Documentation index
- [GitHub Issues](https://github.com/samaswin87/decision_agent/issues) - Report bugs or request features

## Contributing

1. Fork the repository
2. Create a feature branch
3. Add tests (maintain 90%+ coverage)
4. Submit a pull request

## Support

- **Issues**: [GitHub Issues](https://github.com/samaswin87/decision_agent/issues)
- **Documentation**: [Wiki](wiki/README.md)
- **Examples**: [examples/](examples/)

## License

MIT License - see [LICENSE.txt](LICENSE.txt)

---

⭐ **Star this repo** if you find it useful!
