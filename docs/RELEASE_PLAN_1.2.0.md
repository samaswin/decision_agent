# DecisionAgent Release Plan

**Target Version:** 1.2.0
**Current Version:** 1.1.0
**Planned Release Date:** 2026-05-15
**Status:** In Progress
**Release Branch:** `release/1.2.0`
**Phase Tracking:** [TRACKING_ISSUES_1.2.0.md](TRACKING_ISSUES_1.2.0.md)
**Implementation Phases:** [RELEASE_PLAN_1.2.0_PHASES.md](RELEASE_PLAN_1.2.0_PHASES.md)

## Overview

This release plan captures the gaps, defects, and incomplete areas identified in the DecisionAgent gem and defines the work required to ship version 1.2.0. The focus is on closing open TODOs, hardening adapters, completing partially-shipped features, and tightening documentation and test coverage.

## Scope Summary

Version 1.2.0 is a stability and completeness release. No breaking API changes are planned. All work must continue to satisfy the determinism, explainability, and auditability guarantees described in the README, and must pass the CI validation steps defined in AGENTS.md (RSpec, RuboCop, gem build, examples, and benchmarks).

## Identified Gaps and Fixes

### 1. Incomplete Features (Missing)

- **DMN Versioning — tag support** (`lib/decision_agent/dmn/versioning.rb:142`). The `tag` parameter is currently accepted but discarded (`_tag = tag # TODO: Implement tag functionality`). Implement tag creation, lookup, listing, and deletion, plus persistence through the versioning adapter.
- **Performance & Thread Safety roadmap items** referenced in `docs/PERFORMANCE_AND_THREAD_SAFETY.md` under "Planned for v0.3.0" are still unshipped. Re-scope these into 1.2.0 or explicitly defer them in the doc so the roadmap is not stale.
- **Monitoring storage adapters** — only the base adapter is covered by specs. Ship at least one concrete production adapter (e.g. ActiveRecord or Redis) end-to-end with documentation, or clearly mark the base adapter as abstract-only in `docs/PERSISTENT_MONITORING.md`.
- **Versioning adapter** — same pattern as monitoring storage: the abstract base raises `NotImplementedError` for every method. Provide a reference in-memory adapter and a persistent (ActiveRecord) adapter, with migration generators.
- **RBAC adapter reference implementations** — the base `RbacAdapter` raises `NotImplementedError`. Verify Devise, CanCanCan, and Pundit adapters advertised in the README are fully implemented, documented, and covered by specs.

### 2. Bugs and Defects to Fix

- Audit any remaining Web UI pages for the relative-vs-absolute asset path issue fixed in 1.1.0 to confirm no regressions slipped back in after new pages were added.
- Re-run DMN Editor null-reference audit on any JS functions added after 1.1.0 to ensure the guard pattern is consistent.
- Confirm CSV/XLSX MIME type registration added to `web/server.rb` covers all file-upload endpoints (batch testing, simulation import, replay import).

### 3. Documentation Gaps

- `docs/PERFORMANCE_AND_THREAD_SAFETY.md` still references a pre-1.0 version (v0.3.0) for planned work. Update version numbers to match the current release line.
- Add a top-level `docs/ROADMAP.md` summarising what is shipped, what is deferred, and what is planned, so gaps are discoverable without grepping.
- Ensure every feature advertised in `README.md` (Monte Carlo simulation, shadow testing, RBAC adapters, DMN editor, A/B testing) has a corresponding how-to guide under `docs/` and a runnable file under `examples/`.
- `docs/CHANGELOG.md` should grow a `[Unreleased]` section so in-flight work is visible before tagging.

### 4. Testing and Quality

- Extend specs beyond abstract `NotImplementedError` checks for monitoring storage, versioning, and RBAC adapters — add behavioural tests against at least one concrete adapter for each.
- Add an end-to-end smoke spec that boots the Web UI, serves every static asset, and exercises the DMN editor happy path, to prevent the asset/path class of bugs from recurring.
- Run `COVERAGE=true bundle exec rspec` and update `coverage.md`; target no regression vs. 1.1.0.
- Execute `bundle exec rake benchmark:all` and commit updated numbers; investigate any regressions vs. the 1.1.0 baseline.

### 5. Tooling and CI

- Confirm CI still runs on Ruby 3.0–3.3 as documented in AGENTS.md; add 3.4 if officially supported by the gem's minimum.
- Ensure `gem build decision_agent.gemspec` is clean of warnings.
- Ensure `bundle exec rubocop` passes with zero offenses after all fixes.

## Deliverables Checklist

- DMN versioning tag feature implemented, documented, and tested.
- At least one concrete monitoring storage adapter shipped with specs and docs.
- At least one concrete versioning adapter shipped with specs and docs.
- RBAC reference adapters verified, documented, and spec-covered.
- Web UI regression smoke spec added.
- `docs/ROADMAP.md` created; `docs/PERFORMANCE_AND_THREAD_SAFETY.md` version references updated.
- `docs/CHANGELOG.md` updated with a complete 1.2.0 entry.
- `VERSION` bumped to `1.2.0` and `lib/decision_agent/version.rb` updated in lockstep.
- CI green: RSpec, RuboCop, gem build, examples, benchmarks.
- Coverage report refreshed in `coverage.md`.

## Release Process

1. Cut branch `release/1.2.0` from `main`.
2. Land work items above as separate PRs referencing this plan.
3. Bump `VERSION` and `lib/decision_agent/version.rb` to `1.2.0`.
4. Finalise `docs/CHANGELOG.md` entry for 1.2.0.
5. Run the full CI validation checklist from `AGENTS.md` locally.
6. Tag `v1.2.0`, push, and publish the gem via `gem push`.
7. Announce in README badges and GitHub release notes.

## Risks

- Implementing concrete adapters for monitoring/versioning may expand scope; if time-constrained, prioritise one adapter per subsystem and defer the rest to 1.3.0 with an explicit note in the roadmap.
- Benchmark regressions from new adapter code paths — mitigate by running `benchmark:regression` before tagging.
- Web UI asset path regressions — mitigate via the new smoke spec.
