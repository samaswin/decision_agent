# Agent Guidelines for DecisionAgent

This document provides guidance for all AI agents working on the DecisionAgent codebase. **Read this before making changes.** Agents must follow these standards and run the prescribed validation steps for every fix or feature.

---

## Table of Contents

1. [CI Validation Steps](#ci-validation-steps)
2. [Ruby Style & Linting](#ruby-style--linting)
3. [Release & Documentation Requirements](#release--documentation-requirements)
4. [Project Standards](#project-standards)

---

## CI Validation Steps

**Agents MUST run these steps for every fix or feature** to mirror CI and catch failures locally before pushing. The CI workflow (`.github/workflows/ci.yml`) runs these jobs:

### 1. Tests (required)

```bash
# Setup parallel test databases (first time or after schema change)
bundle exec rake parallel:create

# Run tests in parallel (same as CI)
bundle exec parallel_rspec spec
```

- **Ruby versions:** CI runs on 3.0, 3.1, 3.2, 3.3. Prefer testing on 3.3 locally; ensure compatibility with 3.0+.
- **Coverage:** CI uploads coverage on Ruby 3.3. Run `COVERAGE=true bundle exec rspec` when relevant.

### 2. Lint (required)

```bash
# Run RuboCop (Ruby linter) - MUST pass before merge
bundle exec rubocop

# Check gem can be built
gem build decision_agent.gemspec
```

### 3. Examples (required)

```bash
# Run all examples (skips server/Rails examples in CI)
bundle exec ruby scripts/run_all_examples.rb
```

### 4. Benchmarks (when touching `lib/**` or `benchmarks/**`)

```bash
# Run performance benchmarks
bundle exec rake benchmark:all

# Run regression test (optional, may continue-on-error in CI)
bundle exec rake benchmark:regression
```

### Quick validation checklist

| Step          | Command                               | When required          |
|---------------|----------------------------------------|------------------------|
| Tests         | `bundle exec parallel_rspec spec`      | Every change           |
| Lint          | `bundle exec rubocop`                  | Every change           |
| Gem build     | `gem build decision_agent.gemspec`     | Every change           |
| Examples      | `bundle exec ruby scripts/run_all_examples.rb` | Every change   |
| Benchmarks    | `bundle exec rake benchmark:all`       | Changes to lib/ or benchmarks/ |

**Rule:** If CI would run it, the agent should run it for the change before completing.

---

## Ruby Style & Linting

### RuboCop configuration

The project uses [RuboCop](https://rubocop.org/) with config in `.rubocop.yml`. All Ruby code must pass `bundle exec rubocop` with no offenses.

### Style conventions (from `.rubocop.yml`)

- **String literals:** Double quotes (`"string"`)
- **Target Ruby:** 3.0+
- **Line length:** 146 (excludes spec, examples)
- **Method length:** Max 31 lines (excludes spec, examples, certain lib files)
- **Class length:** Max 322 lines (excludes spec, dashboard_server)
- **Module length:** Max 150 lines (excludes operators/helpers)
- **AbcSize:** Max 39 (excludes spec, examples, certain lib files)
- **Cyclomatic complexity:** Max 18
- **Perceived complexity:** Max 16
- **Parameter lists:** Max 6 (excludes operators/helpers)

### Ruby style guide references

- [Ruby Style Guide](https://rubystyle.guide/) – Community standard
- [RuboCop](https://docs.rubocop.org/) – Enforces style

### Common patterns

- Use `snake_case` for methods and variables, `CamelCase` for classes/modules.
- Prefer `&&` / `||` over `and` / `or` for control flow.
- Use meaningful names; avoid single-letter names except idiomatic cases (`i`, `k`, `v`, `id`, `op`).
- Prefer early returns over nested conditionals.

---

## Release & Documentation Requirements

**Every new release MUST include updates to:**

### 1. Changelog (`docs/CHANGELOG.md`)

- Follow [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
- Use [Semantic Versioning](https://semver.org/).
- Add a new `## [X.Y.Z]` section under `# Changelog` with date.
- Categorize changes: `Added`, `Changed`, `Deprecated`, `Removed`, `Fixed`, `Security`.
- Be specific: files modified, root cause, solution, business value where relevant.
- Use existing entries as templates (e.g., 1.1.0 section).

### 2. Version bump (`lib/decision_agent/version.rb`)

- Update `VERSION` to match changelog (e.g. `"1.1.1"`).
- Respect semver:
  - **MAJOR:** Incompatible API changes
  - **MINOR:** Backward-compatible new features
  - **PATCH:** Backward-compatible bug fixes

### 3. Documentation (`docs/`)

Update docs when behavior or APIs change:

| Change type      | Update docs                          |
|------------------|--------------------------------------|
| New API/feature  | Relevant `docs/*.md`, e.g. `API_CONTRACT.md`, `CODE_EXAMPLES.md` |
| Breaking change  | Changelog + any affected guides      |
| New capability   | Add or update docs under `docs/`     |
| Configuration    | `RBAC_CONFIGURATION.md`, `VERSIONING.md`, etc. |

**Docs in `docs/` include:** `API_CONTRACT.md`, `BATCH_TESTING.md`, `DMN_*.md`, `VERSIONING.md`, `SIMULATION.md`, `WEB_UI*.md`, `MONITORING_*.md`, `FEEL_REFERENCE.md`, and others. Update the ones relevant to your changes.

### Release checklist

- [ ] Changelog entry in `docs/CHANGELOG.md`
- [ ] Version bump in `lib/decision_agent/version.rb`
- [ ] Docs updated in `docs/` for any affected behavior/API
- [ ] All CI steps passing (tests, lint, examples, gem build)

---

## Project Standards

### Code organization

- **Lib:** `lib/decision_agent/` – core library
- **Specs:** `spec/` – RSpec tests
- **Examples:** `examples/` – runnable examples
- **Docs:** `docs/` – user-facing documentation
- **Benchmarks:** `benchmarks/` – performance benchmarks

### Testing

- Use RSpec.
- Prefer `parallel_rspec` for full runs.
- Add specs for new behavior; maintain or improve coverage.
- Use `parallel: false` in specs where determinism matters (e.g. Monte Carlo).

### Dependencies

- Runtime deps: `decision_agent.gemspec`
- Dev deps: `Gemfile`, `decision_agent.gemspec`
- Run `bundle install` after dependency changes.

### Git & branching

- Branch from `main`.
- Descriptive commit messages.
- Ensure CI passes before merging.

---

## Summary for Agents

1. **Before finishing any fix/feature:** Run tests, RuboCop, examples, and gem build (and benchmarks when relevant).
2. **Ruby style:** Follow RuboCop and [Ruby Style Guide](https://rubystyle.guide/).
3. **Releases:** Update changelog, version, and docs for every release.
4. **Docs:** Update `docs/` when changing behavior or APIs.

Adhering to these guidelines keeps the project consistent and CI green.
