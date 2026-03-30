> **[中文版](README.zh.md)** | English (default)

# lorainwings-plugins

> A Claude Code plugin marketplace — spec-driven autopilot orchestration and parallel AI engineering control-plane.

[![spec-autopilot Tests](https://github.com/lorainwings/claude-autopilot/actions/workflows/test-spec-autopilot.yml/badge.svg)](https://github.com/lorainwings/claude-autopilot/actions/workflows/test-spec-autopilot.yml)
[![parallel-harness Tests](https://github.com/lorainwings/claude-autopilot/actions/workflows/test-parallel-harness.yml/badge.svg)](https://github.com/lorainwings/claude-autopilot/actions/workflows/test-parallel-harness.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

## Plugins

| Plugin | Version | Description |
|--------|---------|-------------|
| [spec-autopilot](plugins/spec-autopilot/) | 5.2.2 | Spec-driven autopilot orchestration for delivery pipelines — 8-phase workflow with 3-layer gate system and crash recovery |
| [parallel-harness](plugins/parallel-harness/) | 1.1.3 | Parallel AI engineering control-plane — task-graph scheduling, 9-gate system, RBAC governance, cost-aware model routing |

## Quick Install

```bash
# 1. Add marketplace
claude plugin marketplace add lorainwings/claude-autopilot

# 2. Install spec-autopilot (project-level)
claude plugin install spec-autopilot@lorainwings-plugins --scope project

# 3. Install parallel-harness (project-level)
claude plugin install parallel-harness@lorainwings-plugins --scope project

# 4. Restart Claude Code
```

## What is spec-autopilot?

**spec-autopilot** is a Claude Code plugin that automates the full software delivery lifecycle: from requirements gathering through implementation, testing, reporting, and archival.

### Key Features

- **8-Phase Pipeline** — Requirements → OpenSpec → FF Generate → Test Design → Implementation → Test Report → Archive
- **3-Layer Gate System** — TaskCreate dependencies + Hook checkpoint validation + AI checklist verification
- **Crash Recovery** — Automatic checkpoint scanning and session resume
- **Anti-Rationalization** — 16 pattern detection to prevent sub-agents from skipping work
- **TDD Cycle** — RED-GREEN-REFACTOR with deterministic L2 validation
- **Requirements Routing** — Auto-classify as Feature/Bugfix/Refactor/Chore with dynamic gate thresholds
- **Event Bus** — Real-time event streaming via `events.jsonl` + WebSocket
- **GUI V2 Dashboard** — Three-column real-time dashboard with decision_ack feedback loop
- **Parallel Execution** — Domain-level parallel agents with file ownership enforcement
- **Modular Test Suite** — 76 test files with 692+ assertions

### Architecture

```mermaid
graph TB
    subgraph "Main Thread (Orchestrator)"
        P0[Phase 0: Environment Check<br/>+ Crash Recovery]
        P1[Phase 1: Requirements<br/>Multi-round Decision Loop]
        P7[Phase 7: Summary<br/>+ User-confirmed Archive]
    end

    subgraph "Sub-Agents (via Task tool)"
        P2[Phase 2: Create OpenSpec]
        P3[Phase 3: FF Generate]
        P4[Phase 4: Test Design]
        P5[Phase 5: Implementation<br/>Serial / Parallel / TDD]
        P6[Phase 6: Test Report]
    end

    P0 --> P1
    P1 -->|Gate| P2
    P2 -->|Gate| P3
    P3 -->|Gate| P4
    P4 -->|Gate| P5
    P5 -->|Gate| P6
    P6 --> P7

    style P0 fill:#e1f5fe
    style P1 fill:#e1f5fe
    style P7 fill:#e1f5fe
    style P4 fill:#fff3e0
    style P5 fill:#fff3e0
```

## What is parallel-harness?

**parallel-harness** is a Claude Code plugin that provides a task-graph-driven parallel AI engineering platform. It enables multi-agent orchestration with strict governance, cost control, and quality gates.

### Key Features

- **Task Graph Orchestration** — Decompose complex requirements into a structured DAG with dependency tracking
- **Multi-Agent Parallel Scheduling** — Execute independent tasks concurrently with strict file ownership isolation
- **Cost-Aware Model Routing** — 3-tier automatic routing with escalation, downgrade, and budget control
- **9-Gate System** — test, lint, review, security, perf, coverage, policy, documentation, release readiness
- **Policy-as-Code** — Declarative policy rules with path boundaries, budget limits, model tier caps
- **RBAC Governance** — 4 built-in roles (admin/developer/reviewer/viewer), 12 fine-grained permissions
- **Audit Trail** — Full event-level audit with timeline replay, JSON/CSV export
- **PR/CI Integration** — GitHub PR creation, review comments, CI failure analysis via `gh` CLI
- **Session Persistence** — Memory/file dual adapters with checkpoint recovery

### Architecture

```
runtime/
├── engine/          — Unified Orchestrator Runtime (entry API)
├── orchestrator/    — Task Graph, Intent Analysis, Complexity, Ownership
├── scheduler/       — DAG Batch Scheduling
├── models/          — 3-Tier Model Router
├── session/         — Context Packing
├── verifiers/       — Verification Result Schema
├── observability/   — Event Bus (38 event types)
├── workers/         — Worker Runtime, Retry, Downgrade
├── guards/          — Merge Guard
├── gates/           — Gate System (9 gate types)
├── persistence/     — Session/Run/Audit Persistence
├── integrations/    — PR/CI Integration (GitHub)
├── governance/      — RBAC, Approval, Human-in-the-loop
├── capabilities/    — Skill/Hook/Instruction Extension Layer
└── schemas/         — GA-Level Data Contracts
```

## Documentation

### spec-autopilot

| Document | Description |
|----------|-------------|
| [Quick Start](plugins/spec-autopilot/docs/getting-started/quick-start.md) | 5-minute quick start guide |
| [Integration Guide](plugins/spec-autopilot/docs/getting-started/integration-guide.md) | Step-by-step project onboarding |
| [Configuration](plugins/spec-autopilot/docs/getting-started/configuration.md) | Complete YAML field reference |
| [Architecture](plugins/spec-autopilot/docs/architecture/overview.md) | System architecture overview |
| [Phases](plugins/spec-autopilot/docs/architecture/phases.md) | Per-phase execution guide |
| [Gates](plugins/spec-autopilot/docs/architecture/gates.md) | 3-layer gate deep dive |
| [Config Tuning](plugins/spec-autopilot/docs/operations/config-tuning-guide.md) | Per-project-type optimization |
| [Troubleshooting](plugins/spec-autopilot/docs/operations/troubleshooting.md) | Common errors and recovery |
| [Plugin README](plugins/spec-autopilot/README.md) | Full plugin documentation |
| [Changelog](plugins/spec-autopilot/CHANGELOG.md) | Version history |

> All documentation is available in both [English](plugins/spec-autopilot/docs/README.md) and [中文](plugins/spec-autopilot/docs/README.zh.md).

### parallel-harness

| Document | Description |
|----------|-------------|
| [Architecture](plugins/parallel-harness/docs/architecture/overview.md) | System architecture overview |
| [Operator Guide](plugins/parallel-harness/docs/operator-guide.md) | Installation, deployment, operations |
| [Policy Guide](plugins/parallel-harness/docs/policy-guide.md) | Policy rule configuration |
| [Integration Guide](plugins/parallel-harness/docs/integration-guide.md) | GitHub PR, CI, custom gates, hooks |
| [Admin Guide](plugins/parallel-harness/docs/admin-guide.md) | Administration and RBAC setup |
| [Troubleshooting](plugins/parallel-harness/docs/troubleshooting.md) | Common errors and solutions |
| [Examples](plugins/parallel-harness/docs/examples/basic-flow.md) | Step-by-step flow examples |
| [FAQ](plugins/parallel-harness/docs/FAQ.md) | Frequently asked questions |
| [Plugin README](plugins/parallel-harness/README.md) | Full plugin documentation |

## Requirements

- **Claude Code** CLI (v1.0.0+)
- **python3** (3.8+) — required for spec-autopilot hook scripts
- **bun** (1.0+) — required for parallel-harness runtime and tests
- **bash** (4.0+) — hook script execution
- **git** — version control integration

## Repository Structure

```
claude-autopilot/
├── .claude-plugin/          # Marketplace configuration
│   └── marketplace.json
├── .github/workflows/       # CI/CD
│   ├── test-spec-autopilot.yml
│   └── test-parallel-harness.yml
├── .githooks/               # Git hooks (pre-commit)
├── dist/                    # Built plugins (for marketplace install)
│   ├── spec-autopilot/
│   └── parallel-harness/
├── plugins/                 # Plugin source code
│   ├── spec-autopilot/
│   │   ├── skills/          # 7 Skill definitions
│   │   ├── scripts/         # Hook scripts + utilities
│   │   ├── hooks/           # Hook registration
│   │   ├── gui/             # GUI V2 dashboard (React + Tailwind)
│   │   ├── tests/           # 76 test files, 692+ assertions
│   │   └── docs/            # Full documentation (EN + ZH)
│   └── parallel-harness/
│       ├── runtime/         # 15 core modules (engine, orchestrator, scheduler, etc.)
│       ├── skills/          # Skill definitions (harness, plan, dispatch, verify)
│       ├── config/          # Default config + policy files
│       ├── tools/           # CLI tools and utilities
│       ├── tests/           # 219 tests, 499 assertions
│       └── docs/            # Full documentation
├── Makefile                 # Build, test, setup shortcuts
├── README.md                # This file
├── LICENSE                  # MIT License
├── CONTRIBUTING.md          # Contribution guidelines
└── SECURITY.md              # Security policy
```

## Contributing

We welcome contributions! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

```bash
# Clone the repository
git clone https://github.com/lorainwings/claude-autopilot.git
cd claude-autopilot

# One-time setup: activate git hooks
make setup

# Run tests
make test

# Build distribution
make build
```

## Security

For security concerns, please see [SECURITY.md](SECURITY.md).

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.
