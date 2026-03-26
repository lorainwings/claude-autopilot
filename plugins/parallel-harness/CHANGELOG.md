# Changelog

All notable changes to parallel-harness will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/), and this project adheres to [Semantic Versioning](https://semver.org/).

## [1.1.1](https://github.com/lorainwings/claude-autopilot/compare/parallel-harness-v1.1.0...parallel-harness-v1.1.1) (2026-03-26)


### Fixed

* **parallel-harness:** plugin.json schema 合规性修复 ([1084796](https://github.com/lorainwings/claude-autopilot/commit/108479669a59616ecdd170b73e4cd5386696f946))

## [1.1.0](https://github.com/lorainwings/claude-autopilot/compare/parallel-harness-v1.0.4...parallel-harness-v1.1.0) (2026-03-26)


### Added

* 🎸 add parallel-harness plugin ([5461cd4](https://github.com/lorainwings/claude-autopilot/commit/5461cd44c1cd321ac9835ee101e39020c6c69455))
* parallel-harness 全面接入插件市场 — gitignore + rebase + dist + CI + Makefile ([ce2f3ea](https://github.com/lorainwings/claude-autopilot/commit/ce2f3ea6faf459fe122ced1a2da74536274db8bb))


### Fixed

* codex 审核 2 项缺陷修复 — general 域路径推断 + 回归测试补齐 ([7871ef1](https://github.com/lorainwings/claude-autopilot/commit/7871ef1a96b4951cf4d4315d6a25c559340838d9))
* codex 审核 2 项缺陷修复 — 审批恢复真正解阻 + 泛化意图越界修复 ([4838258](https://github.com/lorainwings/claude-autopilot/commit/4838258ccec7fd469a2f49589deccc08c10edf35))
* codex 审核 4 项缺陷修复 — 市场索引 + CI 护栏 + 发版纪律 + 文档口径 ([b811bbc](https://github.com/lorainwings/claude-autopilot/commit/b811bbc57dbb93cd9e9ec409ec6d8dea4c1229c7))
* codex 审核 5 项缺陷修复 — task 审批 checkpoint + CP 读模型接通 + 泛化意图 + worker 字段 + RBAC cancel ([3bf6342](https://github.com/lorainwings/claude-autopilot/commit/3bf63422a69c2776d2c0efd728a8fc529c7f33d7))
* codex 审核 8 项缺陷修复 — fail-closed gate + 持久化 durable + RBAC 执法 + PR/CI 闭环 ([d75b01a](https://github.com/lorainwings/claude-autopilot/commit/d75b01a86381a03eb2ffbac9c8a2734827d7f224))
* GUI typecheck 修复 + parallel-harness CHANGELOG 补充 ([84d36bd](https://github.com/lorainwings/claude-autopilot/commit/84d36bd530840e013f3bdf09461a060c54a6f403))
* parallel-harness plugin.json manifest 格式修复 — Claude Code 插件安装兼容 ([24e8320](https://github.com/lorainwings/claude-autopilot/commit/24e8320044222fb7faa4d3c55c11965958ea6bae))
* parallel-harness 版本 bump 1.0.1 → 1.0.2 — 一次性同步所有版本位置 + dist ([878c98c](https://github.com/lorainwings/claude-autopilot/commit/878c98c565492ecd88faed2647b7f87e79b48cdb))
* parallel-harness 版本 bump 1.0.2 → 1.0.3 + dist 重建 ([dd35fbc](https://github.com/lorainwings/claude-autopilot/commit/dd35fbc8c5f9893ed3d48c2557abb9aedeae08d5))
* parallel-harness 版本 bump 1.0.3 → 1.0.4 ([137a577](https://github.com/lorainwings/claude-autopilot/commit/137a577a6c7f724ac65b7e15793537c5fe7cdd72))
* parallel-harness 版本同步 plugin.json/marketplace + dist 重建 ([5240491](https://github.com/lorainwings/claude-autopilot/commit/5240491a741b98bf1b314e8f8bc7725841d48f28))
* plugin.json manifest 格式修复 — author 改为对象 + dependencies 改为数组 ([cf6dc2a](https://github.com/lorainwings/claude-autopilot/commit/cf6dc2ae133ef29b80747b8930ff7f4182206ded))
* release-discipline CI 死循环修复 + parallel-harness 版本同步 ([c52b4dc](https://github.com/lorainwings/claude-autopilot/commit/c52b4dc191ac10e3e09d0d7b0cb7df844ea8e673))
* ruff format _phase_graph.py + 补提未跟踪文件 ([3590554](https://github.com/lorainwings/claude-autopilot/commit/35905549d23bcd5da032f8cdb174b50c34c935a8))
* 评估报告 11 项问题全量修复 — P0 执行可信度 + P1 治理闭环 + P2 文档对齐 ([7fff378](https://github.com/lorainwings/claude-autopilot/commit/7fff378fc8fd929ba87a9acb8d7b7bcc21c680cb))

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
