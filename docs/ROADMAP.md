# DecisionAgent Roadmap

**Current release:** 1.2.0 (branch `release/1.2.0`)
**Previous release:** 1.1.0
**Last updated:** 2026-04-09

This document records what has shipped, what is in flight, and what has been explicitly deferred. Every entry links to the authoritative doc, spec, or tracking issue.

---

## Shipped

Features below are merged on the `release/1.2.0` branch and covered by the `[Unreleased]` section of [CHANGELOG.md](CHANGELOG.md).

| Feature | Phase | Docs | Example |
|---------|-------|------|---------|
| Release branch, baseline benchmarks, coverage baseline, phase tracking issues | Phase 0 | — | — |
| DMN versioning tag support (`create_tag`, `get_tag`, `list_tags`, `delete_tag`, `tag!`) | Phase 1 | [VERSIONING.md](VERSIONING.md) | [dmn_versioning_tags.rb](../examples/dmn_versioning_tags.rb) |
| Monitoring storage: `ActiveRecordAdapter` (PostgreSQL, MySQL, SQLite) | Phase 2 | [PERSISTENT_MONITORING.md](PERSISTENT_MONITORING.md) | [monitoring_activerecord.rb](../examples/monitoring_activerecord.rb) |
| Rails generator `decision_agent:monitoring_migration` | Phase 2 | [PERSISTENT_MONITORING.md](PERSISTENT_MONITORING.md) | — |
| Versioning: `ActiveRecordAdapter` with full CRUD + tag support | Phase 3 | [VERSIONING.md](VERSIONING.md) | — |
| Rails generator `decision_agent:versioning_migration` | Phase 3 | [VERSIONING.md](VERSIONING.md) | — |
| RBAC adapters: Devise, CanCanCan, Pundit — fully implemented and spec-covered | Phase 3 | [RBAC_CONFIGURATION.md](RBAC_CONFIGURATION.md) | [rbac_configuration_examples.rb](../examples/rbac_configuration_examples.rb) |
| Web UI: absolute asset paths, null-guards in `dmn-editor.js`, MIME validation on upload endpoints | Phase 4 | [WEB_UI.md](WEB_UI.md) | — |
| Web UI smoke spec (`spec/web/server_smoke_spec.rb`) and JS null-guard static-analysis spec | Phase 4 | — | — |
| Documentation and roadmap cleanup (this document) | Phase 5 | [ROADMAP.md](ROADMAP.md) | — |

### Previously Shipped (v1.1.0 and earlier)

| Feature | Docs | Example |
|---------|------|---------|
| Core decision engine with multiple evaluators and conflict resolution | [API_CONTRACT.md](API_CONTRACT.md) | [basic_usage.rb](../examples/basic_usage.rb) |
| Explainability layer (`because`, `failed_conditions`, `explainability`) | [EXPLAINABILITY.md](EXPLAINABILITY.md) | [explainability_example.rb](../examples/explainability_example.rb) |
| JSON Rule DSL with advanced operators | [ADVANCED_OPERATORS.md](ADVANCED_OPERATORS.md) | [advanced_operators_performance.rb](../examples/advanced_operators_performance.rb) |
| DMN 1.3 support with full FEEL expression language | [DMN_GUIDE.md](DMN_GUIDE.md) | [examples/dmn/](../examples/dmn/) |
| Version control for rules (in-memory and file-backed adapters) | [VERSIONING.md](VERSIONING.md) | [01_basic_versioning.rb](../examples/01_basic_versioning.rb) |
| Simulation: historical replay, what-if, impact analysis, shadow testing, Monte Carlo | [SIMULATION.md](SIMULATION.md) | [simulation_example.rb](../examples/simulation_example.rb) |
| Batch testing with CSV/Excel import, coverage analysis, resume | [BATCH_TESTING.md](BATCH_TESTING.md) | [08_batch_testing.rb](../examples/08_batch_testing.rb) |
| A/B testing with statistical significance | [AB_TESTING.md](AB_TESTING.md) | [07_ab_testing.rb](../examples/07_ab_testing.rb) |
| Role-based access control (built-in user system + adapter interface) | [RBAC_CONFIGURATION.md](RBAC_CONFIGURATION.md) | [rbac_configuration_examples.rb](../examples/rbac_configuration_examples.rb) |
| Real-time monitoring dashboard with WebSocket updates | [MONITORING_AND_ANALYTICS.md](MONITORING_AND_ANALYTICS.md) | [05_monitoring_and_analytics.rb](../examples/05_monitoring_and_analytics.rb) |
| Prometheus metrics export and Grafana integration | [MONITORING_AND_ANALYTICS.md](MONITORING_AND_ANALYTICS.md) | — |
| Persistent monitoring storage (base adapter + memory adapter) | [PERSISTENT_MONITORING.md](PERSISTENT_MONITORING.md) | [06_persistent_monitoring.rb](../examples/06_persistent_monitoring.rb) |
| Web UI visual rule builder and DMN modeler | [WEB_UI.md](WEB_UI.md) | [04_rails_web_ui_integration.rb](../examples/04_rails_web_ui_integration.rb) |
| Thread-safety via deep freezing (zero overhead) | [THREAD_SAFETY.md](THREAD_SAFETY.md) | [thread_safe_performance.rb](../examples/thread_safe_performance.rb) |
| Web UI asset path fix and DMN null-reference fix (v1.1.0 patch) | — | — |

---

## In Progress

| Feature | Phase | Target release | Owner |
|---------|-------|---------------|-------|
| Phase 6: Release candidate validation, final benchmarks, gem publish | Phase 6 | 1.2.0 | Release manager |

---

## Deferred (post-1.2.0)

These items were considered for 1.2.0 but explicitly deferred. They are candidates for a future minor or patch release.

| Feature | Original target | Notes |
|---------|----------------|-------|
| ReadWriteLock for `FileAdapter` (concurrent reads, lock on writes) | v0.3.0 | Low priority while `ActiveRecordAdapter` covers high-throughput use cases. See [PERFORMANCE_AND_THREAD_SAFETY.md](PERFORMANCE_AND_THREAD_SAFETY.md). |
| Redis monitoring adapter | 1.2.0 fast-follow | Phase 2 shipped ActiveRecord; Redis is a lower-priority alternative for cache-only metrics. |
| Documentation lint CI step (assert all `docs/*.md` relative links resolve) | Phase 5 | Useful quality gate; deferred to avoid blocking 1.2.0 timeline. |
| README/feature matrix spec (assert each feature appears in `docs/` and `examples/`) | Phase 5 | Deferred; manual audit completed in Phase 5. |

---

## Notes

- The [CHANGELOG.md](CHANGELOG.md) is the authoritative record of what changed and when.
- The [RELEASE_PLAN_1.2.0_PHASES.md](RELEASE_PLAN_1.2.0_PHASES.md) document contains the full per-phase work items, exit criteria, and testing strategy.
- Benchmark baselines are archived under `benchmarks/`. Run `bundle exec rake benchmark:regression` to compare against the 1.1.0 baseline.
