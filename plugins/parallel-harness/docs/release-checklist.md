> **[中文版](release-checklist.zh.md)** | English (default)

# parallel-harness Release Checklist

> Version: v1.4.0 (GA) | Last updated: 2026-03-20

## Code Checks

- [ ] All runtime modules compile successfully (`bunx tsc --noEmit`)
- [ ] No TypeScript strict-mode errors
- [ ] All public APIs have JSDoc comments
- [ ] No leftover `console.log` debug statements (`console.error` for error logging is allowed)
- [ ] All TODO/FIXME items have been addressed or tracked in issues
- [ ] No hardcoded secrets, tokens, or absolute paths
- [ ] Schema version matches the `SCHEMA_VERSION` constant (current: `"1.0.0"`)
- [ ] `package.json` version matches the release version
- [ ] `generateId()` prefix naming conventions are consistent (run_, plan_, att_, gate_, appr_, evt_, hfb_, fb_)
- [ ] All state machine transition paths are documented

## Test Checks

- [ ] `bun test tests/unit/` all passing
- [ ] Test count >= 216 (current baseline)
- [ ] 0 failing tests
- [ ] Each runtime module has a corresponding test file
- [ ] Happy path test coverage is complete
- [ ] Critical failure path test coverage:
  - [ ] Timeout handling
  - [ ] Budget exhaustion
  - [ ] Ownership conflicts
  - [ ] Policy blocking
  - [ ] Gate blocking
  - [ ] Retry escalation
  - [ ] Fallback triggers
- [ ] Edge case tests:
  - [ ] Empty task graph
  - [ ] Single-task graph
  - [ ] All-conflicting tasks
  - [ ] Zero budget

## Documentation Checks

- [ ] README.zh.md version number updated
- [ ] README.md (English) version number updated
- [ ] CLAUDE.md version number and test baseline updated
- [ ] Operations guide (docs/operator-guide.zh.md)
- [ ] Policy configuration guide (docs/policy-guide.zh.md)
- [ ] Integration guide (docs/integration-guide.zh.md)
- [ ] Troubleshooting (docs/troubleshooting.zh.md)
- [ ] Basic flow examples (docs/examples/basic-flow.zh.md)
- [ ] Marketplace readiness (docs/marketplace-readiness.zh.md) status updated
- [ ] All Skills have complete SKILL.md documentation
- [ ] Architecture diagram includes all 15 runtime modules

## Configuration Checks

- [ ] `config/default-config.json` parameters are reasonable
  - [ ] `max_concurrency` <= 10
  - [ ] `budget_limit` has a sensible default
  - [ ] `enabled_gates` includes required blocking gates (test, lint_type, policy)
  - [ ] `timeout_ms` >= 60000
- [ ] `config/default-policy.json` rules are complete
  - [ ] Sensitive file protection rules are enabled (.env, credentials)
  - [ ] Budget warning rules are enabled
  - [ ] High-risk approval rules are enabled
- [ ] Gate default contract configuration is reasonable
  - [ ] Blocking gates: test, lint_type, security, policy, release_readiness
  - [ ] Non-blocking gates: review, perf, coverage, documentation
  - [ ] Thresholds are set to reasonable values

## Compatibility Checks

- [ ] Runs correctly on Bun >= 1.0
- [ ] Compiles with TypeScript >= 5.0
- [ ] Tested on macOS / Linux platforms
- [ ] Compatible with latest Claude Code CLI version
- [ ] gh CLI >= 2.0 integration tested (if PR features are enabled)
- [ ] No dependencies on Node.js-specific APIs (pure Bun runtime)
- [ ] No hardcoded platform-specific path separators
- [ ] Schema version is backward compatible (or has a migration strategy)

## Build and Distribution Checks

- [ ] `bash tools/build-dist.sh` builds successfully
- [ ] dist/ directory contains all required files
- [ ] plugin.json is configured correctly
- [ ] No node_modules included in dist
- [ ] No test files included in dist
- [ ] No .env or secret files included in dist

## Security Checks

- [ ] SecurityGateEvaluator sensitive file pattern list is complete
- [ ] Tool policy defaults forbid dangerous operations (TaskStop, EnterWorktree)
- [ ] RBAC permission boundaries are appropriate
- [ ] Audit logs cover all critical operations
- [ ] No plaintext secret storage
- [ ] `secret_ref` uses references rather than plaintext values

## Final Pre-Release Confirmation

- [ ] Version number is consistent across three locations: package.json, README.zh.md, SCHEMA_VERSION
- [ ] CHANGELOG or commit history contains a summary of changes for this version
- [ ] Git tag created (e.g., `v1.0.0`)
- [ ] marketplace.json version number updated
- [ ] Relevant team members notified
