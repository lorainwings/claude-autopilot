# Changelog

All notable changes to parallel-harness will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/), and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.0.4] - 2026-03-25

### Added
- 中文产品概览文档 (product-overview.zh.md)

### Fixed
- package.json 版本与 plugin.json 同步到 1.0.4

## [1.0.3] - 2026-03-24

### Added
- Full bilingual documentation (12 English + 12 Chinese docs)
- Orchestrator runtime enhanced error handling and recovery
- Gate system improvements for parallel verification
- Worker runtime retry and degradation enhancements
- PR provider integration improvements
- Task graph builder dependency validation
- Session persistence checkpoint recovery
- Control plane dashboard updates

### Fixed
- Version metadata sync across all plugin files
- Dist build alignment with source changes

## [1.0.0] - 2025-03-23

### Added
- **Task Graph Orchestration**: DAG-based task decomposition with dependency tracking and cycle detection
- **Parallel Worker Dispatch**: Multi-agent concurrent execution with file ownership isolation
- **Cost-Aware Model Routing**: 3-tier automatic model selection (tier-1/tier-2/tier-3) with escalation and downgrade policies
- **9-Gate Quality System**: test, lint_type, review, security, performance, coverage, policy, documentation, release_readiness
- **RBAC Governance**: 4 built-in roles (admin/developer/reviewer/viewer), 12 fine-grained permissions
- **Policy-as-Code Engine**: Declarative policy rules with path boundaries, budget limits, model tier caps
- **Audit Trail**: Full event-level audit with timeline replay, JSON/CSV export
- **PR/CI Integration**: GitHub PR creation, review comments, CI failure analysis via gh CLI
- **Session Persistence**: Memory/File dual-adapter with checkpoint recovery
- **Merge Guard**: 4-layer checking (ownership, conflicts, policy, contracts)
- **EventBus Observability**: 38 event types with pub/sub and wildcard subscriptions
- **Control Plane API**: HTTP API (port 9800) with embedded dashboard
- **4 Skills**: /harness (main), /harness-plan, /harness-dispatch, /harness-verify
- **Comprehensive Test Suite**: 219 tests, 499 assertions, 0 failures
- **12 Documentation Files**: Architecture, operator guide, admin guide, policy guide, integration guide, troubleshooting, FAQ, security, marketplace readiness, release checklist, capabilities, examples
