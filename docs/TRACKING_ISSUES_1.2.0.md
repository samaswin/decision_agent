# DecisionAgent 1.2.0 — Phase Tracking Issues

**Created:** 2026-04-08
**Release branch:** `release/1.2.0`
**Companion:** [RELEASE_PLAN_1.2.0_PHASES.md](RELEASE_PLAN_1.2.0_PHASES.md)

> These issues should be filed in GitHub and their URLs added below.
> `gh issue create` requires GitHub CLI or web UI access.

---

## Issue List

| Phase | Title | Issue | Status |
|-------|-------|-------|--------|
| 0 | Release Branch, Baseline, and Guardrails | — | ✅ Done |
| 1 | DMN Versioning Tag Support | — | Open |
| 2 | Monitoring Storage: Concrete Adapter | — | Open |
| 3 | Versioning: Concrete Adapter + RBAC Verification | — | Open |
| 4 | Web UI Hardening | — | Open |
| 5 | Documentation and Roadmap Cleanup | — | Open |
| 6 | Release Candidate, Benchmarking, and Tagging | — | Open |

---

## Issue Templates

### Phase 1 — DMN Versioning Tag Support

**Title:** `[1.2.0 Phase 1] DMN Versioning Tag Support`

**Body:**
```
## Goal
Close the outstanding TODO in `lib/decision_agent/dmn/versioning.rb:142` so tags are first-class.

## Work Items
- [ ] Design the tag model (named, immutable pointer to a specific version)
- [ ] Extend versioning adapter interface with `create_tag`, `get_tag`, `list_tags`, `delete_tag`
- [ ] Update in-memory adapter and any persistent adapter (Phase 3)
- [ ] Wire `tag:` argument through `create_version`; expose `tag!(model_id, version_id, name)`
- [ ] Document in `docs/VERSIONING.md` with a worked example
- [ ] Add `examples/dmn_versioning_tags.rb`
- [ ] Add `[Unreleased]` CHANGELOG entry

## Files Expected to Change
- `lib/decision_agent/dmn/versioning.rb`
- `lib/decision_agent/versioning/**`
- `spec/dmn/versioning_spec.rb`, `spec/versioning/adapter_spec.rb`
- `docs/VERSIONING.md`, `docs/CHANGELOG.md`
- `examples/dmn_versioning_tags.rb`

## Exit Criteria
All new specs green, full suite green, RuboCop clean, example runnable, docs merged.

Related: RELEASE_PLAN_1.2.0_PHASES.md
```

---

### Phase 2 — Monitoring Storage: Concrete Adapter

**Title:** `[1.2.0 Phase 2] Monitoring Storage: Concrete ActiveRecord Adapter`

**Body:**
```
## Goal
Move monitoring storage beyond the abstract base class by shipping a production-ready ActiveRecord adapter.

## Work Items
- [ ] Define shared-examples group (`spec/support/shared/monitoring_storage_adapter.rb`)
- [ ] Implement `DecisionAgent::Monitoring::Storage::ActiveRecordAdapter`
  - `record_decision`, `record_evaluation`, `record_performance`, `record_error`
  - `statistics`, `time_series`, `metrics_count`, `cleanup`, `available?`
- [ ] Rails generator: `bin/rails g decision_agent:monitoring_migration`
- [ ] Update `docs/PERSISTENT_MONITORING.md`
- [ ] Add `examples/monitoring_activerecord.rb`

## Files Expected to Change
- `lib/decision_agent/monitoring/storage/active_record_adapter.rb` (new)
- `lib/decision_agent/generators/**` (new)
- `spec/monitoring/storage/active_record_adapter_spec.rb` (new)
- `spec/support/shared/monitoring_storage_adapter.rb` (new)
- `docs/PERSISTENT_MONITORING.md`, `docs/CHANGELOG.md`
- `examples/monitoring_activerecord.rb`

## Exit Criteria
Adapter passes shared contract, thread-safety, cleanup, and performance specs. Generator produces a clean migration. Docs and example merged.

Related: RELEASE_PLAN_1.2.0_PHASES.md
```

---

### Phase 3 — Versioning: Concrete Adapter + RBAC Verification

**Title:** `[1.2.0 Phase 3] Versioning Concrete Adapter + RBAC Adapter Verification`

**Body:**
```
## Goal
Mirror Phase 2 for versioning and harden RBAC adapter coverage.

## Work Items
- [ ] Implement `DecisionAgent::Versioning::ActiveRecordAdapter` (full CRUD + tag methods from Phase 1)
- [ ] Rails generator for versioning schema
- [ ] Audit Devise, CanCanCan, and Pundit RBAC adapters
- [ ] Add end-to-end RBAC specs with stub user/role model
- [ ] Update `docs/RBAC_CONFIGURATION.md` with adapter matrix

## Files Expected to Change
- `lib/decision_agent/versioning/active_record_adapter.rb` (new)
- `lib/decision_agent/generators/**`
- `lib/decision_agent/auth/**`
- `spec/versioning/active_record_adapter_spec.rb` (new)
- `spec/auth/devise_adapter_spec.rb`, `spec/auth/cancancan_adapter_spec.rb`, `spec/auth/pundit_adapter_spec.rb`
- `docs/VERSIONING.md`, `docs/RBAC_CONFIGURATION.md`, `docs/CHANGELOG.md`

## Exit Criteria
Concrete versioning adapter and all three RBAC adapters have behavioural specs beyond abstract contract checks.

Related: RELEASE_PLAN_1.2.0_PHASES.md
```

---

### Phase 4 — Web UI Hardening

**Title:** `[1.2.0 Phase 4] Web UI Hardening`

**Body:**
```
## Goal
Prevent recurrence of the 1.1.0 asset-path and DMN editor null-reference class of bugs.

## Work Items
- [ ] Sweep `lib/decision_agent/web/public/**/*.html` for remaining relative CSS/JS references
- [ ] Sweep `lib/decision_agent/web/public/**/*.js` for unguarded `state.currentModel`/`state.currentDecision` access
- [ ] Confirm CSV/XLSX MIME types cover all upload endpoints
- [ ] Add request-level smoke spec (`spec/web/server_smoke_spec.rb`)

## Files Expected to Change
- `lib/decision_agent/web/public/**`
- `lib/decision_agent/web/server.rb`
- `spec/web/server_smoke_spec.rb` (new)

## Exit Criteria
Smoke spec green, no relative asset paths, no unguarded `state.currentModel.id` access.

Related: RELEASE_PLAN_1.2.0_PHASES.md
```

---

### Phase 5 — Documentation and Roadmap Cleanup

**Title:** `[1.2.0 Phase 5] Documentation and Roadmap Cleanup`

**Body:**
```
## Goal
Remove stale references and make the state of every feature discoverable.

## Work Items
- [ ] Update `docs/PERFORMANCE_AND_THREAD_SAFETY.md` (remove v0.3.0 references)
- [ ] Create `docs/ROADMAP.md` (Shipped / In Progress / Deferred)
- [ ] Audit every feature claim in `README.md`; file issues or defer in ROADMAP.md
- [ ] Consolidate `[Unreleased]` CHANGELOG entries from Phases 1–4

## Files Expected to Change
- `docs/ROADMAP.md` (new)
- `docs/PERFORMANCE_AND_THREAD_SAFETY.md`
- `docs/CHANGELOG.md`
- `README.md`

## Exit Criteria
No stale version references, ROADMAP.md merged, README/docs/examples matrix consistent.

Related: RELEASE_PLAN_1.2.0_PHASES.md
```

---

### Phase 6 — Release Candidate, Benchmarking, and Tagging

**Title:** `[1.2.0 Phase 6] Release Candidate, Benchmarking, and Tagging`

**Body:**
```
## Goal
Freeze, validate, and ship 1.2.0.

## Work Items
- [ ] Bump `VERSION` to `1.2.0` and `lib/decision_agent/version.rb`
- [ ] Finalise `docs/CHANGELOG.md` with `[1.2.0] - 2026-05-15` entry
- [ ] Run full CI on Ruby 3.0, 3.1, 3.2, 3.3 — confirm green
- [ ] Run `rake benchmark:all` + `benchmark:regression`; compare vs `benchmarks/baseline_1.1.0.txt`; investigate any >5% regression
- [ ] Refresh `coverage.md`; confirm no drop vs Phase 0 baseline (86.28%)
- [ ] Tag `v1.2.0`, push, `gem build`, `gem push`, draft GitHub release notes
- [ ] Post-publish smoke install from RubyGems

## Exit Criteria
Gem published, release notes live, benchmarks and coverage archived, all tracking issues closed.

Related: RELEASE_PLAN_1.2.0_PHASES.md
```
