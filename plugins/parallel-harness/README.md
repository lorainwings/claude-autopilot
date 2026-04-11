> **[中文版](README.zh.md)** | English (default)

# parallel-harness v1.6.0 <!-- x-release-please-version -->

> Parallel AI Engineering Control-Plane Plugin for Claude Code

[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](../../LICENSE)

## What is parallel-harness?

`parallel-harness` is a Claude Code plugin that provides a **task-graph-driven parallel AI engineering platform** at commercial GA quality. It enables:

- **Task Graph Orchestration**: Decompose complex requirements into a structured DAG with dependency tracking and cycle detection
- **Multi-Agent Parallel Scheduling**: Execute independent tasks concurrently with strict file ownership isolation
- **Cost-Aware Model Routing**: 3-tier automatic routing (tier-1/tier-2/tier-3) with escalation, downgrade, and budget control
- **9-Gate Quality System**: test, lint_type, review, security, performance, coverage, policy, documentation, release_readiness
- **Policy-as-Code**: Declarative policy rules with path boundaries, budget limits, model tier caps, and approval requirements
- **RBAC Governance**: 4 built-in roles (admin/developer/reviewer/viewer), 12 fine-grained permissions
- **Audit Trail**: Full event-level audit with timeline replay, JSON/CSV export
- **PR/CI Integration**: GitHub PR creation, review comments, CI failure analysis via `gh` CLI
- **Session Persistence**: Memory/File dual-adapter with checkpoint recovery

## Quick Start

### Install via Marketplace

```bash
claude plugin install parallel-harness@lorainwings-plugins --scope project
```

### Manual Install (Development)

```bash
cd plugins/parallel-harness
bun install
```

### Usage

Use the `/harness` command in Claude Code to start the main orchestration flow:

```
User: /harness Split all helper functions in utils.ts into separate modules
```

The `/harness` skill shells into `runtime/scripts/execute-harness.ts`, which then runs the TypeScript runtime as the source of truth. During worker execution, the runtime explicitly invokes the selected stage skill in nested Claude sessions using namespaced skill commands such as:

1. `/parallel-harness:harness-dispatch` — worker dispatch / owned-file implementation
2. `/parallel-harness:harness-verify` — verification / gate-oriented review

## Actual Skill Observability

Real plugin sessions now capture `Skill` tool invocations through Claude hooks, instead of relying only on transcript wording.

- Source of truth: `.parallel-harness/data/plugin-observability/sessions/<session>/skill-events.jsonl`
- Raw hook evidence: `.parallel-harness/data/plugin-observability/sessions/<session>/raw/hooks.jsonl`
- Recorded lifecycle: `PreToolUse(Skill)` request + `PostToolUse(Skill)` completion + `PostToolUseFailure(Skill)` failure
- Phase hinting: `parallel-harness:harness-plan` / `harness-dispatch` / `harness-verify` are tagged as `planning` / `dispatch` / `verification`
- Status line: on session start, the plugin auto-installs a local `statusLine` bridge and shows the latest skill as `[harness] skill harness-plan`. If the user already has a custom statusLine configured (at project or user scope), the harness bridge chains with it instead of replacing it.

This closes the gap where `/harness` could conceptually use sub-skills without producing deterministic evidence in actual plugin execution.

## Architecture

```
runtime/
├── engine/          — Unified Orchestrator Runtime (entry API)         [GA]
├── orchestrator/    — Task Graph, Intent Analysis, Complexity, Ownership [GA]
├── scheduler/       — DAG Batch Scheduling                             [GA]
├── models/          — 3-Tier Model Router                              [GA]
├── session/         — Context Packing                                  [GA]
├── verifiers/       — Verification Result Schema                       [GA]
├── observability/   — Event Bus (38 event types)                       [GA]
├── workers/         — Worker Runtime, Retry, Downgrade                 [GA]
├── guards/          — Merge Guard (4-layer checking)                   [GA]
├── gates/           — Gate System (9 gate types)                       [GA]
├── persistence/     — Session/Run/Audit Persistence                    [GA]
├── integrations/    — PR/CI Integration (GitHub only)                  [Beta]
├── governance/      — RBAC, Approval, Human-in-the-loop                [GA]
├── lifecycle/       — Skill Lifecycle Runtime, Registry, Phase Inference [GA]
├── capabilities/    — Skill/Hook/Instruction Extension Layer           [Beta]
└── schemas/         — GA-Level Data Contracts                          [GA]
```

> **Maturity**: GA = production-ready, fully tested; Beta = functional but interfaces may change

### Data Flow

```mermaid
graph LR
    A[User Intent] --> B[Intent Analyzer]
    B --> C[Task Graph Builder]
    C --> D["TaskGraph (DAG)"]
    D --> E[Ownership Planner]
    E --> F[Scheduler]
    F --> G["SchedulePlan (batches)"]
    G --> H[Context Packager]
    H --> I[Model Router]
    I --> J[Worker Runtime]
    J --> K[Gate System]
    K --> L[Merge Guard]
    L --> M[PR Provider]
    M --> N[Result Synthesizer]
    N --> O[QualityReport]
```

## Four Role Boundaries

| Role | Can Do | Cannot Do |
|------|--------|-----------|
| **Planner** | Analyze intent, build graph, assign ownership | Modify code directly |
| **Worker** | Implement task within ownership scope | Modify out-of-scope files, skip tests |
| **Verifier/Gate** | Independently verify results, block non-compliant output | Modify code, lower standards |
| **Synthesizer** | Synthesize decisions, generate reports | Re-execute tasks |

## State Machines

**Run State Machine**:
```mermaid
graph TB
    P[pending] --> PL[planned] --> AA[awaiting_approval] --> SC[scheduled] --> RN[running] --> VR[verifying]
    VR --> OK[succeeded]
    VR --> FL[failed]
    VR --> BK[blocked]
```

**Task Attempt State Machine**:
```mermaid
graph TB
    P[pending] --> PC[pre_check] --> EX[executing] --> PO[post_check]
    PO --> OK[succeeded]
    PO --> FL[failed]
    PO --> TO[timed_out]
```

## Downgrade Strategies

| Condition | Downgrade Action |
|-----------|-----------------|
| Conflict rate > 30% | Auto-downgrade to semi-serial |
| Gate blocks >= 3 consecutive | Downgrade to serial + tier-3 |
| Critical path blocked > 2 rounds | Prioritize serial processing |

## Configuration

| File | Purpose |
|------|---------|
| `config/default-config.json` | Run configuration (concurrency, budget, gates, PR strategy) |
| `config/default-policy.json` | Policy rules (path boundaries, sensitive directories, budget limits) |
| `config/run-config-schema.json` | JSON Schema for run configuration |
| `config/policy-schema.json` | JSON Schema for policy rules |

### Run Configuration

```json
{
  "run_config": {
    "max_concurrency": 5,
    "high_risk_max_concurrency": 2,
    "budget_limit": 100000,
    "max_model_tier": "tier-3",
    "enabled_gates": ["test", "lint_type", "review", "policy"],
    "pr_strategy": "single_pr"
  }
}
```

### Policy Configuration

See the [Policy Guide](docs/policy-guide.md) for full policy rule configuration.

## Test Coverage

```
295 pass / 0 fail / 649 expect() calls
13 test files covering all runtime modules
```

Test coverage includes:
- Task graph building and DAG validation
- Ownership planning and conflict detection
- Scheduler batch generation
- Model routing and escalation strategy
- Context packing
- 9-type Gate evaluators
- Merge Guard 4-layer checking
- RBAC permission verification
- Approval workflows
- Session/Run persistence
- AuditTrail recording and querying
- PR summary rendering
- CI failure parsing
- EventBus pub/sub
- Worker execution controller

### Run Tests

```bash
cd plugins/parallel-harness && bun test
```

### Build Distribution

```bash
make ph-build
```

## Documentation

| Document | Description |
|----------|-------------|
| [Architecture Overview](docs/architecture/overview.md) | System architecture, layers, data flow |
| [Operator Guide](docs/operator-guide.md) | Installation, configuration, daily operations |
| [Admin Guide](docs/admin-guide.md) | RBAC management, approval workflows, budget control |
| [Policy Guide](docs/policy-guide.md) | Policy rule configuration and enforcement |
| [Integration Guide](docs/integration-guide.md) | GitHub PR/CI, EventBus, custom gates, hooks |
| [Troubleshooting](docs/troubleshooting.md) | Common errors and solutions |
| [FAQ](docs/FAQ.md) | Frequently asked questions |
| [Security & Compliance](docs/security-compliance.md) | Security architecture and compliance checklist |
| [Marketplace Readiness](docs/marketplace-readiness.md) | Marketplace integration checklist |
| [Release Checklist](docs/release-checklist.md) | Pre-release verification steps |
| [Capability Registry](docs/capabilities/capability-registry.md) | Skill/Hook/Instruction extension system |
| [Basic Flow Examples](docs/examples/basic-flow.md) | Step-by-step usage examples |

> All documentation is available in both [English](docs/README.md) and [中文](docs/README.zh.md).

## Relationship with spec-autopilot

The two plugins are **complementary**, not replacements:

| Aspect | spec-autopilot | parallel-harness |
|--------|---------------|-----------------|
| Core model | 8-phase linear pipeline | Task DAG + dynamic scheduling |
| Scheduling | Sequential by phase | Parallel by dependency |
| Quality | 3-layer gate system | 9-type gate system |
| Model control | Manual routing | Automatic 3-tier routing with escalation |
| Governance | Hook scripts | RBAC + approval + policy engine |
| Best for | Spec-driven delivery workflows | Complex multi-module parallel engineering |

**Guidelines**:
- Clear process, phased delivery → `spec-autopilot`
- Complex engineering, multi-agent parallel, governance-first → `parallel-harness`

## Version Info

- **Version**: 1.6.0 (GA) <!-- x-release-please-version -->
- **Schema Version**: 1.0.0
- **Runtime**: Bun
- **Language**: TypeScript
- **Tests**: 295 pass / 0 fail / 649 expect()

## Capabilities Maturity

| Capability | Status | Notes |
|-----------|--------|-------|
| Task Graph + DAG Scheduling | GA | Ownership-aware batch scheduling |
| Model Router (3-tier) | GA | Cost-aware routing with tier constraints |
| Gate System (9 gate types) | GA | Hard/signal classification, blocking semantics |
| Execution Proxy + Attestation | GA | tool_calls, diff_ref, sandbox enforcement |
| Context Packager | GA | Occupancy threshold, role-aware sorting, retry offset |
| Persistence (Session/Run/Audit) | GA | File-backed stores with flush |
| RBAC + Approval Workflow | GA | Role-based access, cross-process resume |
| Stage Contracts | Beta | Domain-grouped delivery contracts in RunPlan |
| retryTask | Beta | Single-task retry with downstream safety check |
| Trusted Execution Plane | Beta | baseline_commit capture, path_check sandbox |
| PR/CI Integration | GA | GitHub provider with repo_root binding |
| Worktree Sandbox | Planned | Full git worktree isolation for workers |

## License

MIT
