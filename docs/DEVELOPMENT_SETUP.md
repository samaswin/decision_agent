# Development Setup Guide

This guide covers setting up the DecisionAgent development environment, including Ruby version management, testing, and development tools.

## Prerequisites

- **Ruby Version Manager**: [asdf](https://asdf-vm.com/) (recommended) or [rbenv](https://github.com/rbenv/rbenv)
- **Ruby Versions**: 3.0.7, 3.1.6, 3.2.5, 3.3.5 (for cross-version testing)
- **Bundler**: Included with Ruby or install via `gem install bundler`

## Installation

### 1. Install asdf (if not already installed)

```bash
# macOS (Homebrew)
brew install asdf

# Linux
git clone https://github.com/asdf-vm/asdf.git ~/.asdf --branch v0.14.0
echo '. "$HOME/.asdf/asdf.sh"' >> ~/.bashrc
echo '. "$HOME/.asdf/completions/asdf.bash"' >> ~/.bashrc

# Add asdf to your shell
source ~/.asdf/asdf.sh
```

### 2. Install Ruby Plugin for asdf

```bash
asdf plugin add ruby
```

### 3. Install Required Ruby Versions

```bash
asdf install ruby 3.0.7
asdf install ruby 3.1.6
asdf install ruby 3.2.5
asdf install ruby 3.3.5
```

### 4. Clone the Repository

```bash
git clone https://github.com/samaswin/decision_agent.git
cd decision_agent
```

### 5. Install Dependencies

```bash
# Set Ruby version (use any of the supported versions)
asdf local ruby 3.2.5

# Install gems
bundle install
```

### 6. Ruby version changes and Bundler

After changing Ruby version (e.g. switching with `asdf local ruby 3.3.x` or upgrading from 3.2 to 3.3):

1. **Run `bundle install`** — On Ruby 3.3, `bundle install` can update platform-specific gems in `Gemfile.lock`; re-running ensures the lockfile matches your current Ruby and platform.
2. **If you use gems with native extensions (e.g. sqlite3):** run `bundle pristine` or remove the gem cache and run `bundle install` again if you see "incompatible libruby" or load errors after changing Ruby patch version (e.g. 3.3.5 → 3.3.8).
3. **After `bundle update`:** run `bundle install` and the full test suite to confirm the lockfile and dependencies are consistent.

The project keeps `Gemfile.lock` committed and CI runs on a matrix of Ruby versions (3.0–3.3) for reproducible builds.

## Development Workflow

### Running Tests

#### Single Ruby Version

```bash
# Run all tests
bundle exec rspec

# Run specific test file
bundle exec rspec spec/path/to/test_spec.rb

# Run with documentation format
bundle exec rspec --format documentation
```

#### Parallel Test Execution

The project uses `parallel_tests` for faster test execution:

```bash
# Setup parallel test databases (first time only)
bundle exec rake parallel:create parallel:setup

# Run tests in parallel (uses all available CPU cores)
bundle exec parallel_rspec spec

# Run with specific number of processes
bundle exec parallel_rspec spec -n 4
```

#### Cross-Ruby Version Testing

Test across all supported Ruby versions automatically:

```bash
./scripts/test_all_ruby_versions.sh
```

This script will:
- Test each Ruby version (3.0.7, 3.1.6, 3.2.5, 3.3.5)
- Run `bundle install` for each version
- Execute RSpec tests with parallel execution
- Generate a summary report with pass/fail status
- Save detailed logs to `/tmp/` for troubleshooting

**Output:**
- Colored status messages for each Ruby version
- Bundle install progress
- Test execution progress
- Final summary showing:
  - Which versions passed ✅
  - Which versions failed ❌
  - Test counts and durations
  - Location of detailed log files

**Log Files:**
- `test_logs/<timestamp>/bundle_install_<version>.log` - Bundle install logs
- `test_logs/<timestamp>/rspec_<version>.log` - Full test output
- `test_logs/<timestamp>/rspec_<version>.json` - JSON test results

Logs are saved in timestamped directories (e.g., `test_logs/20260109_143022/`) so multiple test runs are preserved and not overwritten. The logs are never deleted automatically.

### Running Benchmarks

#### Single Ruby Version

```bash
# Run all benchmarks
rake benchmark:all

# Run specific benchmarks
rake benchmark:basic      # Basic decision performance
rake benchmark:threads    # Thread-safety and scalability
rake benchmark:regression # Compare against baseline

# See benchmarks/README.md for complete documentation
```

#### Cross-Ruby Version Benchmarking

Run performance benchmarks across all supported Ruby versions automatically:

```bash
./scripts/benchmark_all_ruby_versions.sh
```

This script will:
- Benchmark each Ruby version (3.0.7, 3.1.6, 3.2.5, 3.3.5)
- Run `bundle install` for each version
- Execute all performance benchmarks (`rake benchmark:all`)
- Run regression tests to compare against baselines
- Generate a summary report with results
- Save detailed logs for analysis

**Output:**
- Colored status messages for each Ruby version
- Bundle install progress
- Benchmark execution progress with key performance metrics
- Final summary showing:
  - Which versions completed successfully ✅
  - Which versions failed ❌
  - Key performance metrics (throughput, latency)
  - Location of detailed log files

**Log Files:**
- `benchmark_logs/<timestamp>/bundle_install_<version>.log` - Bundle install logs
- `benchmark_logs/<timestamp>/benchmark_<version>.log` - Full benchmark output
- `benchmarks/results/` - Benchmark result JSON files

Logs are saved in timestamped directories (e.g., `benchmark_logs/20260109_143022/`) so multiple benchmark runs are preserved and not overwritten. The logs are never deleted automatically.

### Code Coverage

The project uses SimpleCov for code coverage tracking:

```bash
# Run tests with coverage
bundle exec rspec

# View coverage report
open coverage/index.html
```

Coverage reports are automatically generated in the `coverage/` directory.

## Project Structure

```
decision_agent/
├── lib/                    # Main library code
│   └── decision_agent/    # Core modules
├── spec/                   # Test suite
├── examples/               # Example code
├── docs/                   # Documentation
├── benchmarks/             # Performance benchmarks
├── scripts/                # Utility scripts
│   ├── test_all_ruby_versions.sh  # Multi-version testing
│   └── benchmark_all_ruby_versions.sh  # Multi-version benchmarking
├── Gemfile                 # Dependencies
└── Rakefile                # Rake tasks
```

## Development Dependencies

Key development dependencies:

- **rspec** (~> 3.12) - Testing framework
- **parallel_tests** (~> 3.0) - Parallel test execution
- **simplecov** (~> 0.22) - Code coverage
- **rubocop** (~> 1.60) - Code style checker
- **benchmark-ips** - Performance benchmarking
- **benchmark_driver** - Advanced benchmarking framework
- **webmock** (~> 3.18) - HTTP request mocking

## Testing Best Practices

1. **Run tests before committing**: Always run the full test suite
2. **Test across Ruby versions**: Use `./scripts/test_all_ruby_versions.sh` before major changes
3. **Benchmark across Ruby versions**: Use `./scripts/benchmark_all_ruby_versions.sh` after performance-related changes
4. **Maintain coverage**: Keep test coverage above 85%
5. **Use parallel tests**: Significantly faster for large test suites
6. **Check for regressions**: Run benchmarks after performance-related changes

## Testing the Gem in External Projects

Before publishing a new version to RubyGems, you'll often want to test your changes in external applications. This section covers three methods for testing the gem locally in other projects.

### Method 1: Using Bundler's `path` Option (Recommended for Active Development)

This method allows you to use the local gem directly by specifying its path in the consuming project's `Gemfile`.

**Setup:**

```ruby
# In your test project's Gemfile
gem 'decision_agent', path: '/absolute/path/to/decision_agent'
```

**Usage:**

```bash
cd /path/to/your/test/project
bundle install
```

**Benefits:**
- Changes are reflected immediately without rebuilding
- Best for rapid iteration during development
- No need to rebuild the gem after each change

**Verification:**

```bash
# In your test project
bundle list | grep decision_agent
# Should show: decision_agent (x.x.x) at /absolute/path/to/decision_agent

# Or check in a Ruby console
bundle exec irb
require 'decision_agent'
DecisionAgent::VERSION
```

**Cleanup:**

```ruby
# In your test project's Gemfile, remove or comment out the path option
# gem 'decision_agent', path: '/absolute/path/to/decision_agent'
gem 'decision_agent'  # Use the published version
```

Then run `bundle install` to switch back to the published gem.

### Method 2: Using `bundle config local` (Alternative for Active Development)

This method overrides the gem source locally without modifying the `Gemfile`.

**Setup:**

```bash
# In your test project directory
bundle config local.decision_agent /absolute/path/to/decision_agent

# Verify the configuration
bundle config
```

**Usage:**

```bash
cd /path/to/your/test/project
bundle install
```

**Benefits:**
- Keep the original gem source in `Gemfile` unchanged
- Local override is only active on your machine
- Easy to toggle on/off without editing files

**Verification:**

```bash
# Check that the local override is active
bundle config | grep decision_agent
# Should show: local.decision_agent: "/absolute/path/to/decision_agent"

bundle list | grep decision_agent
# Should show the local path
```

**Cleanup:**

```bash
# Remove the local override
bundle config --delete local.decision_agent

# Reinstall to use the published gem
bundle install
```

### Method 3: Building and Installing Locally (For Final Testing)

This method tests the actual gem packaging and installation process, similar to how users will install it from RubyGems.

**Build the Gem:**

```bash
# In the decision_agent directory
gem build decision_agent.gemspec
# Creates: decision_agent-<version>.gem
```

**Install Locally:**

```bash
# Install the built gem
gem install ./decision_agent-<version>.gem

# Or install to a specific location
gem install ./decision_agent-<version>.gem --install-dir vendor/gems
```

**Usage in Test Project:**

```ruby
# In your test project's Gemfile
gem 'decision_agent', '= <version>'  # Use exact version you built
```

```bash
bundle install
```

**Benefits:**
- Tests the actual gem packaging process
- Validates gemspec configuration
- Best for pre-release validation
- Simulates the end-user installation experience

**Verification:**

```bash
# Check installed gems
gem list decision_agent
# Should show: decision_agent (<version>)

# In your test project
bundle list | grep decision_agent
# Should show: decision_agent (<version>)
```

**Cleanup:**

```bash
# Uninstall the local gem
gem uninstall decision_agent -v <version>

# Or remove all versions
gem uninstall decision_agent --all

# In your test project, update Gemfile to use published version
# Then run bundle install
```

### Best Practices

**Choose the Right Method:**
- **Active development**: Use Method 1 or 2 for immediate feedback during development
- **Pre-release testing**: Use Method 3 to validate the gem packaging before publishing
- **Team testing**: Method 1 is easier to share with team members (document the path)

**Testing Workflow:**
1. Make changes in the decision_agent repository
2. Run tests in decision_agent: `bundle exec rspec`
3. Test in external project using one of the methods above
4. Run tests in the consuming application
5. Iterate until satisfied

**Common Pitfalls:**
- **Bundler cache**: Run `bundle clean --force` in the test project if changes don't appear
- **Version conflicts**: Ensure the version in `decision_agent.gemspec` matches expectations
- **Absolute paths**: Always use absolute paths, not relative paths like `../decision_agent`
- **Gemfile.lock**: Commit `Gemfile.lock` changes only when using published versions, not local paths

**Testing Checklist:**
- [ ] Run decision_agent tests: `bundle exec rspec`
- [ ] Test in external project using local gem
- [ ] Run consuming application tests
- [ ] Verify all features work as expected
- [ ] Check for deprecation warnings
- [ ] Test edge cases and error handling

## Troubleshooting

### Ruby Version Not Detected

If the multi-version test script skips a Ruby version:

```bash
# Verify version is installed
asdf list ruby

# Reinstall if needed
asdf uninstall ruby 3.2.5
asdf install ruby 3.2.5
```

### Bundle Install Fails

```bash
# Clean bundle cache
bundle clean --force

# Reinstall gems
bundle install
```

### Parallel Tests Fail

```bash
# Reset parallel test databases
bundle exec rake parallel:drop
bundle exec rake parallel:create parallel:setup
```

### Test Failures on Specific Ruby Version

Check the detailed logs in `/tmp/rspec_<version>.log` for specific error messages.

## CI/CD Integration

The multi-Ruby version testing and benchmarking scripts are integrated into CI/CD pipelines:

### GitHub Actions

The project includes GitHub Actions workflows that automatically:
- Run tests across all Ruby versions (3.0.7, 3.1.6, 3.2.5, 3.3.5) on every PR
- Run performance benchmarks across all Ruby versions
- Upload benchmark results as artifacts
- Check for performance regressions

**Workflows:**
- `.github/workflows/ci.yml` - Main CI workflow with tests and benchmarks
- `.github/workflows/benchmark.yml` - Dedicated benchmark workflow (runs on lib/ or benchmarks/ changes)

**Example usage in custom workflows:**

```yaml
# Test all Ruby versions
- name: Test all Ruby versions
  run: ./scripts/test_all_ruby_versions.sh

# Benchmark all Ruby versions
- name: Benchmark all Ruby versions
  run: ./scripts/benchmark_all_ruby_versions.sh
```

## Additional Resources

- [Main README](../README.md) - Project overview and quick start
- [Code Examples](CODE_EXAMPLES.md) - Usage examples
- [Changelog](CHANGELOG.md) - Version history
- [Contributing Guide](../README.md#contributing) - Contribution guidelines
