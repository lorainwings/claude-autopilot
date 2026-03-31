> **[中文版](marketplace-readiness.zh.md)** | English (default)

# parallel-harness Marketplace Readiness

> Version: v1.2.0 (GA) | Last updated: 2026-03-20

## Current Status

**GA (General Availability)** — All core modules have been implemented and tested. Ready for marketplace registration.

## Marketplace Readiness Checklist

| Requirement | Status | Notes |
|-------------|--------|-------|
| plugin.json exists | Done | Plugin configuration file ready |
| dist/ build pipeline | Done | `bash tools/build-dist.sh` |
| README.md | Done | English documentation |
| README.zh.md | Done | Chinese documentation (GA level) |
| Core runtime available | Done | All 15 runtime modules implemented |
| Unit tests passing | Done | 295 pass / 0 fail / 649 expect() |
| Skills scaffolding | Done | 4 Skills (harness / plan / dispatch / verify) |
| Engine unified entry | Done | OrchestratorRuntime full lifecycle management |
| Task Graph | Done | DAG construction, validation, dependency resolution |
| Ownership Planner | Done | Path isolation, conflict detection, fallback suggestions |
| Scheduler | Done | DAG batch scheduling, critical path priority |
| Model Router | Done | Three-tier routing, failure escalation |
| Context Packager | Done | Minimal context packing, TaskContract |
| Worker Runtime | Done | Execution controller, sandbox, timeout, retry, fallback |
| Gate System | Done | 9 gate evaluator types, blockable, extensible |
| Merge Guard | Done | Ownership / policy / interface three-layer checks |
| Governance | Done | RBAC (4 roles / 12 permissions), approval, human-in-the-loop |
| Persistence | Done | Session/Run/Audit Store, file adapter |
| EventBus | Done | 38 event types, wildcard subscriptions, persistence adapter |
| PR/CI Integration | Done | GitHub PR create/review/check/merge, CI failure parsing |
| Capabilities | Done | Skill/Hook/Instruction registration |
| GA Schemas | Done | Unified data contracts, version control |
| Operations guide | Done | operator-guide.zh.md |
| Policy guide | Done | policy-guide.zh.md |
| Integration guide | Done | integration-guide.zh.md |
| Troubleshooting guide | Done | troubleshooting.zh.md |
| Release checklist | Done | release-checklist.zh.md |
| Example documentation | Done | examples/basic-flow.zh.md |

## marketplace.json Changes

```json
{
  "$schema": "https://anthropic.com/claude-code/marketplace.schema.json",
  "name": "lorainwings-plugins",
  "description": "lorainwings Claude Code plugins",
  "owner": {
    "name": "lorainwings"
  },
  "plugins": [
    {
      "name": "spec-autopilot",
      "source": "./dist/spec-autopilot",
      "description": "Spec-driven autopilot orchestration for delivery pipelines with 8-phase workflow, 3-layer gate system, and crash recovery",
      "category": "development",
      "version": "5.1.48"
    },
    {
      "name": "parallel-harness",
      "source": "./dist/parallel-harness",
      "description": "Parallel AI engineering control-plane plugin with task-graph scheduling, file ownership isolation, cost-aware model routing, 9-gate system, RBAC governance, and audit trail",
      "category": "development",
      "version": "1.0.0"
    }
  ]
}
```

## Version Milestones

| Version | Milestone | Status |
|---------|-----------|--------|
| v0.1.0 | MVP — Core Schema + Scheduler + Router | Done |
| v0.5.0 | Beta — Worker Runtime + Gate System + Persistence | Done |
| v1.0.0 | GA — All 15 modules + 295 tests + complete documentation | Done |

## Product Positioning vs. spec-autopilot

| Dimension | spec-autopilot | parallel-harness |
|-----------|---------------|-----------------|
| Positioning | Spec-driven delivery | Parallel engineering control plane |
| Maturity | GA (v5.x) | GA (v1.0.0) |
| Core mechanism | 8-phase pipeline | Task DAG + dynamic scheduling |
| Governance | Hook scripts | RBAC + approval + policy engine |
| Target users | Process-driven teams | Complex engineering teams |
