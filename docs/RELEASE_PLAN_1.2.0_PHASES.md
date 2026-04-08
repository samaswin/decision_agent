# DecisionAgent 1.2.0 — Implementation Phases

**Companion to:** `docs/RELEASE_PLAN_1.2.0.md`
**Target Version:** 1.2.0
**Current Version:** 1.1.0
**Owner:** Core maintainers
**Status:** Draft

This document breaks the 1.2.0 release plan into sequenced, independently-shippable phases. Each phase lists concrete work items, the files expected to change, entry/exit criteria, and a phase-specific testing strategy. Every phase must pass the full CI validation checklist from `AGENTS.md` before merge: `bundle exec parallel_rspec spec`, `bundle exec rubocop`, `gem build decision_agent.gemspec`, and `bundle exec ruby scripts/run_all_examples.rb`. Phases touching `lib/**` must additionally run `bundle exec rake benchmark:all` and `benchmark:regression`.

---

## Phase 0 — Release Branch, Baseline, and Guardrails (0.5 week)

**Goal:** Establish a clean baseline so regressions introduced during 1.2.0 work can be detected early.

Work items:
- Cut `release/1.2.0` branch from `main`.
- Add an `[Unreleased]` section to `docs/CHANGELOG.md` so every subsequent PR can append notes.
- Capture baseline benchmark numbers by running `bundle exec rake benchmark:all` and committing the output under `benchmarks/baseline_1.1.0.txt`.
- Refresh coverage baseline with `COVERAGE=true bundle exec rspec` and archive `coverage.md` as `coverage_1.1.0.md` for comparison.
- Create a tracking issue per phase below and link them from the release plan.

Exit criteria:
- Branch exists, baselines committed, tracking issues filed.
- CI green on the empty release branch.

Testing strategy:
- No new tests in this phase.
- Verify CI on the new branch matches CI on `main` (same pass count, same coverage percentage within noise).

---

## Phase 1 — DMN Versioning Tag Support (1 week)

**Goal:** Close the outstanding TODO in `lib/decision_agent/dmn/versioning.rb:142` so tags are first-class.

Work items:
- Design the tag model: a tag is a named, immutable pointer to a specific version of a DMN model. Tags are unique per model.
- Extend the versioning adapter interface with `create_tag`, `get_tag`, `list_tags`, and `delete_tag`; update the in-memory adapter and any persistent adapter delivered in Phase 3.
- Remove the `_tag = tag` discard and wire the `tag:` argument through `create_version` so callers can tag at creation time, plus expose a separate `tag!(model_id, version_id, name)` API for tagging after the fact.
- Document the feature in `docs/VERSIONING.md` with a worked example, and add a runnable example under `examples/dmn_versioning_tags.rb`.
- Add a `CHANGELOG.md` entry under `[Unreleased]`.

Files expected to change:
- `lib/decision_agent/dmn/versioning.rb`
- `lib/decision_agent/versioning/**` (adapter interface + in-memory adapter)
- `spec/dmn/versioning_spec.rb`, `spec/versioning/adapter_spec.rb`
- `docs/VERSIONING.md`, `docs/CHANGELOG.md`
- `examples/dmn_versioning_tags.rb`

Testing strategy:
- Unit specs for `create_tag`/`get_tag`/`list_tags`/`delete_tag` on the in-memory adapter, covering: happy path, duplicate tag name rejection, tag pointing at a deleted version, unicode tag names, and tag on a non-existent version.
- Contract specs that run the same scenarios against every adapter via a shared examples group, so Phase 3 adapters inherit coverage for free.
- Integration spec: create model → create version v1 → tag `release-candidate` → create v2 → re-tag `release-candidate` to v2 → resolve tag → assert it returns v2.
- Determinism regression: tagging must not mutate the canonical hash of any existing version. Assert hash equality before and after tag operations.
- Run the new `examples/dmn_versioning_tags.rb` inside `scripts/run_all_examples.rb`.

Exit criteria:
- All new specs green, full suite green, RuboCop clean, example runnable, docs merged.

---

## Phase 2 — Monitoring Storage: Concrete Adapter (1 week)

**Goal:** Move monitoring storage beyond an abstract base class by shipping at least one production-ready adapter (ActiveRecord recommended; Redis acceptable as a fast follow).

Work items:
- Define a shared-examples group (`spec/support/shared/monitoring_storage_adapter.rb`) that every adapter must pass.
- Implement `DecisionAgent::Monitoring::Storage::ActiveRecordAdapter` covering `record_decision`, `record_evaluation`, `record_performance`, `record_error`, `statistics`, `time_series`, `metrics_count`, `cleanup`, and `available?`.
- Provide a Rails generator (`bin/rails g decision_agent:monitoring_migration`) producing the schema.
- Update `docs/PERSISTENT_MONITORING.md` with install, configuration, indexing guidance, and retention/cleanup notes.
- Add an example under `examples/monitoring_activerecord.rb`.

Files expected to change:
- `lib/decision_agent/monitoring/storage/active_record_adapter.rb` (new)
- `lib/decision_agent/generators/**` (new generator + template)
- `spec/monitoring/storage/active_record_adapter_spec.rb` (new)
- `spec/support/shared/monitoring_storage_adapter.rb` (new)
- `docs/PERSISTENT_MONITORING.md`, `docs/CHANGELOG.md`
- `examples/monitoring_activerecord.rb`

Testing strategy:
- Unit specs against the in-memory SQLite configuration already used by `spec/activerecord_thread_safety_spec.rb`.
- Run the shared-examples group against both the abstract base (asserting `NotImplementedError`) and the ActiveRecord adapter (asserting real behaviour) so we keep the contract in lockstep.
- Thread-safety spec: 16 threads recording 1,000 decisions each; assert no lost writes and correct `metrics_count`.
- Cleanup spec: insert records older than the retention window; assert `cleanup` removes only the expected rows.
- Performance spec: assert `record_decision` P95 under a target (e.g. 5 ms in-memory SQLite); add to `benchmarks/` so regressions surface in `benchmark:regression`.

Exit criteria:
- New adapter passes shared contract, thread-safety, cleanup, and performance specs.
- Generator produces a clean migration on a fresh Rails app.
- Docs and example merged.

---

## Phase 3 — Versioning: Concrete Adapter + RBAC Verification (1 week)

**Goal:** Mirror Phase 2 for the versioning subsystem and harden RBAC adapter coverage.

Work items:
- Implement `DecisionAgent::Versioning::ActiveRecordAdapter` with full CRUD (`create_version`, `list_versions`, `get_version`, `get_version_by_number`, `get_active_version`, `activate_version`, `delete_version`, plus the new tag methods from Phase 1).
- Add a Rails generator for the versioning schema.
- Audit the Devise, CanCanCan, and Pundit RBAC adapters referenced in `README.md`. For each: confirm the implementation file exists, confirm spec coverage beyond `NotImplementedError`, and add end-to-end specs using a stub user/role model.
- Update `docs/RBAC_CONFIGURATION.md` with a matrix showing which adapters are shipped, which are reference-only, and how to plug in a custom one.

Files expected to change:
- `lib/decision_agent/versioning/active_record_adapter.rb` (new)
- `lib/decision_agent/generators/**`
- `lib/decision_agent/auth/**` (fill gaps if any)
- `spec/versioning/active_record_adapter_spec.rb` (new)
- `spec/auth/devise_adapter_spec.rb`, `spec/auth/cancancan_adapter_spec.rb`, `spec/auth/pundit_adapter_spec.rb` (new or expanded)
- `docs/VERSIONING.md`, `docs/RBAC_CONFIGURATION.md`, `docs/CHANGELOG.md`

Testing strategy:
- Versioning adapter: reuse Phase 1 shared examples; add specs for `activate_version` atomicity (only one active version at a time under concurrent callers), `delete_version` refusing to delete the active version, and tag cascade on version deletion.
- RBAC adapters: scenario specs for each permission in the RBAC matrix (`read`, `write`, `execute`, `approve`, `audit`, plus the role checks) with stub users representing each of the 5 default roles.
- Negative tests: assert that an unauthenticated user receives a clear error, not a `NotImplementedError`.
- Integration spec: decision flow where a Viewer can read but cannot approve, and an Approver can approve but cannot edit rules.

Exit criteria:
- Concrete versioning adapter and all three RBAC adapters have behavioural specs that go beyond abstract contract checks.

---

## Phase 4 — Web UI Hardening (0.5 week)

**Goal:** Prevent recurrence of the 1.1.0 asset-path and DMN editor null-reference class of bugs.

Work items:
- Sweep `lib/decision_agent/web/public/**/*.html` for any remaining relative CSS/JS references; convert to absolute paths.
- Sweep `lib/decision_agent/web/public/**/*.js` for any new functions introduced after 1.1.0 that access `state.currentModel` or `state.currentDecision` without null checks; apply the guard pattern.
- Confirm CSV/XLSX MIME types cover every upload endpoint (batch testing, simulation import, replay import); add any missing registrations.
- Add a request-level smoke spec that boots the Rack app, GETs every page under `web/public/`, follows every `<link>` and `<script src>`, and asserts HTTP 200 with the expected `Content-Type`.

Files expected to change:
- `lib/decision_agent/web/public/**`
- `lib/decision_agent/web/server.rb`
- `spec/web/server_smoke_spec.rb` (new)

Testing strategy:
- Asset smoke spec: parametrised over every HTML file under `web/public/`; fails loudly if any referenced asset 404s or has the wrong MIME type.
- JS null-guard spec: lightweight JSDOM-style test (or a ruby-parser regex check) that asserts every call site accessing `state.currentModel.id` or `state.currentDecision.id` is preceded by a guard. A static-analysis spec is acceptable here because we do not ship a JS runtime in CI.
- Manual regression pass on the DMN editor happy path (documented in the PR description): create model → add decision → add input/output → add rule → save → download XML.

Exit criteria:
- Smoke spec green, no relative asset paths remaining, no unguarded `state.currentModel.id` access.

---

## Phase 5 — Documentation and Roadmap Cleanup (0.5 week)

**Goal:** Remove stale references and make the state of every feature discoverable.

Work items:
- Update `docs/PERFORMANCE_AND_THREAD_SAFETY.md` so the "Planned for v0.3.0" section reflects the real 1.x roadmap.
- Create `docs/ROADMAP.md` with three sections: Shipped, In Progress, Deferred. Each entry links to the relevant doc/spec/issue.
- Audit every feature claim in `README.md`. For each bullet, confirm there is a matching `docs/*.md` guide and a runnable `examples/*` script. File issues for any gaps and either fix them in this phase or mark them as deferred in `ROADMAP.md`.
- Ensure every PR from Phases 1–4 has appended a `[Unreleased]` note; consolidate into the final `[1.2.0] - 2026-05-15` entry at release time.

Files expected to change:
- `docs/ROADMAP.md` (new)
- `docs/PERFORMANCE_AND_THREAD_SAFETY.md`
- `docs/CHANGELOG.md`
- `README.md` (if any claim is walked back)

Testing strategy:
- Documentation lint: add a CI step (or a spec) that parses every `docs/*.md` for relative links and asserts they resolve to real files.
- README/feature matrix check: a small spec that reads `README.md`'s "Key Features" section and asserts each feature name appears at least once in `docs/` and once in `examples/`.

Exit criteria:
- No stale version references, `ROADMAP.md` merged, README/docs/examples matrix consistent.

---

## Phase 6 — Release Candidate, Benchmarking, and Tagging (0.5 week)

**Goal:** Freeze, validate, and ship 1.2.0.

Work items:
- Bump `VERSION` to `1.2.0` and `lib/decision_agent/version.rb` to match.
- Finalise `docs/CHANGELOG.md` with a complete `[1.2.0]` entry.
- Run the full CI validation checklist locally on Ruby 3.3, and confirm CI green on 3.0, 3.1, 3.2, 3.3.
- Run `bundle exec rake benchmark:all` and `benchmark:regression`; compare against `benchmarks/baseline_1.1.0.txt`. Investigate any regression over 5%.
- Refresh `coverage.md` with the final `COVERAGE=true bundle exec rspec` run; confirm no drop vs. Phase 0 baseline.
- Tag `v1.2.0`, push, `gem build decision_agent.gemspec`, `gem push`, and draft the GitHub release notes from the changelog entry.

Testing strategy:
- Full suite: `bundle exec parallel_rspec spec` on all supported Ruby versions in CI.
- Examples: `bundle exec ruby scripts/run_all_examples.rb` on the release candidate.
- Benchmarks: `bundle exec rake benchmark:all` and `benchmark:regression` with results archived under `benchmarks/1.2.0.txt`.
- Smoke install: in a clean sandbox, `gem install decision_agent-1.2.0.gem`, require the library, run the quick-start snippet from the README, and assert the expected output.
- Post-publish: within 24 hours, install from RubyGems in a fresh environment and re-run the quick-start snippet to catch any packaging gaps.

Exit criteria:
- Gem published to RubyGems, release notes live, baseline benchmarks and coverage archived, tracking issues closed.

---

## Cross-Phase Testing Strategy

- **Shared examples everywhere.** Adapter contracts (monitoring storage, versioning, RBAC) live in `spec/support/shared/` and are reused across every concrete adapter so behaviour stays in lockstep.
- **Determinism invariants.** Any change under `lib/decision_agent/` must include at least one spec asserting that identical inputs produce bit-identical decisions and canonical hashes, protecting the core product guarantee.
- **Thread-safety invariants.** Any new adapter or mutable cache must have a stress spec modelled on `spec/activerecord_thread_safety_spec.rb`.
- **Coverage floor.** No phase may ship if total line coverage drops below the Phase 0 baseline.
- **Benchmark floor.** No phase touching `lib/**` may ship with a greater-than-5% regression on any metric in `benchmark:all` without an explicit, documented justification in the PR.
- **Example smoke.** Every new user-visible feature ships with a runnable `examples/*.rb` script that is exercised by `scripts/run_all_examples.rb` in CI.
- **Security and privacy.** Any new HTTP endpoints added by Phase 4 must have authz specs asserting that unauthenticated and insufficiently-privileged callers receive 401/403 rather than leaking data.

## Timeline (indicative)

| Phase | Duration | Owner |
|-------|----------|-------|
| 0 — Baseline | 0.5 wk | Release manager |
| 1 — DMN tags | 1.0 wk | DMN maintainer |
| 2 — Monitoring adapter | 1.0 wk | Observability maintainer |
| 3 — Versioning adapter + RBAC | 1.0 wk | Platform maintainer |
| 4 — Web UI hardening | 0.5 wk | Frontend maintainer |
| 5 — Docs & roadmap | 0.5 wk | Docs lead |
| 6 — RC & release | 0.5 wk | Release manager |

**Total:** ~5 weeks wall-clock with serial execution; Phases 2, 3, and 4 can run in parallel to compress to ~3.5 weeks.
