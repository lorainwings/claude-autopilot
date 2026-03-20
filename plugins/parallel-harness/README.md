# parallel-harness (v1.0.0 GA)

> Parallel AI Engineering Control-Plane Plugin for Claude Code

## What is parallel-harness?

`parallel-harness` is a Claude Code plugin that provides a **task-graph-driven parallel AI engineering platform** at commercial GA quality. It enables:

- **Task Graph Orchestration**: Decompose complex requirements into a structured DAG with dependency tracking
- **Multi-Agent Parallel Scheduling**: Execute independent tasks concurrently with strict file ownership isolation
- **Cost-Aware Model Routing**: 3-tier automatic routing with escalation, downgrade, and budget control
- **Gate System**: 9 types of blocking/non-blocking gates (test, lint, review, security, perf, coverage, policy, doc, release)
- **Policy-as-Code**: Declarative policy rules with path boundaries, budget limits, model tier caps, and approval requirements
- **Audit Trail**: Full event-level audit with timeline replay, JSON/CSV export
- **PR/CI Integration**: GitHub PR creation, review comments, CI failure analysis via `gh` CLI
- **RBAC Governance**: Role-based access control, approval workflows, human-in-the-loop

## Architecture

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

## Quick Start

```bash
# Install
claude plugin install parallel-harness@lorainwings-plugins --scope project

# Run tests
cd plugins/parallel-harness && bun test

# Build dist
make ph-build
```

## Test Coverage

- **219 tests**, 16 test files, 571 assertions
- Unit tests: schemas, engine, orchestrator, scheduler, models, workers, guards, gates, persistence, governance, capabilities, integrations
- Integration tests: end-to-end orchestrator flow

## Configuration

| File | Purpose |
|------|---------|
| `config/default-config.json` | Run configuration (concurrency, budget, gates, PR strategy) |
| `config/default-policy.json` | Policy rules (path boundaries, sensitive directories, budget limits) |
| `.claude-plugin/plugin.json` | Plugin metadata |

## Documentation

| Document | Description |
|----------|-------------|
| [Architecture](docs/architecture/overview.zh.md) | System architecture overview |
| [Operator Guide](docs/operator-guide.zh.md) | Installation, deployment, operations |
| [Policy Guide](docs/policy-guide.zh.md) | Policy rule configuration |
| [Integration Guide](docs/integration-guide.zh.md) | GitHub PR, CI, custom gates, hooks |
| [Troubleshooting](docs/troubleshooting.zh.md) | Common errors and solutions |
| [Release Checklist](docs/release-checklist.zh.md) | Pre-release verification steps |
| [Examples](docs/examples/basic-flow.zh.md) | Step-by-step flow examples |

## Relationship with spec-autopilot

| Aspect | spec-autopilot | parallel-harness |
|--------|---------------|-----------------|
| Core model | 8-phase linear pipeline | Task DAG + dynamic scheduling |
| Quality | 3-layer gate system | 9-type gate system |
| Model control | Manual routing | Automatic 3-tier routing with escalation |
| Governance | Hook-based | Policy-as-code + RBAC + approval |
| Best for | Spec-driven delivery | Complex parallel engineering |

They are complementary: `spec-autopilot` for structured delivery, `parallel-harness` for parallel orchestration with governance.

## License

MIT
