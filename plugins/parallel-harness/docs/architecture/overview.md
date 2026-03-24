> **[中文版](overview.zh.md)** | English (default)

# parallel-harness Architecture Overview

## 1. System Purpose

`parallel-harness` is a Claude Code plugin that provides a task-graph-driven parallel AI engineering control plane.

Core design principles:
- Build the graph first, then schedule, then verify
- Separate implementation from verification
- Cost-aware automatic model routing
- Minimal context packages
- Strict file ownership isolation

## 2. Architecture Layers

```
┌─────────────────────────────────────────────┐
│             用户意图 (User Intent)           │
└───────────────┬─────────────────────────────┘
                ▼
┌─────────────────────────────────────────────┐
│  编排层 (Orchestrator)                       │
│  ┌──────────────┐  ┌────────────────────┐   │
│  │Intent Analyzer│  │Task Graph Builder  │   │
│  └──────┬───────┘  └────────┬───────────┘   │
│         ▼                   ▼               │
│  ┌──────────────┐  ┌────────────────────┐   │
│  │Complexity    │  │Ownership Planner   │   │
│  │Scorer        │  │                    │   │
│  └──────────────┘  └────────────────────┘   │
└───────────────┬─────────────────────────────┘
                ▼
┌─────────────────────────────────────────────┐
│  调度层 (Scheduler)                          │
│  ┌──────────────┐  ┌────────────────────┐   │
│  │Scheduler MVP │  │Worker Dispatch     │   │
│  └──────┬───────┘  └────────┬───────────┘   │
│         ▼                   ▼               │
│  ┌──────────────┐  ┌────────────────────┐   │
│  │Retry Manager │  │Downgrade Manager   │   │
│  └──────────────┘  └────────────────────┘   │
└───────────────┬─────────────────────────────┘
                ▼
┌─────────────────────────────────────────────┐
│  模型路由层 (Model Router)                   │
│  ┌──────────────┐  ┌────────────────────┐   │
│  │Model Router  │  │Escalation Policy   │   │
│  └──────────────┘  └────────────────────┘   │
└───────────────┬─────────────────────────────┘
                ▼
┌─────────────────────────────────────────────┐
│  上下文层 (Context)                          │
│  ┌──────────────┐  ┌────────────────────┐   │
│  │Context       │  │Task Contract       │   │
│  │Packager      │  │Builder             │   │
│  └──────────────┘  └────────────────────┘   │
└───────────────┬─────────────────────────────┘
                ▼
┌─────────────────────────────────────────────┐
│  Worker 执行层                               │
│  ┌────────┐  ┌────────┐  ┌────────┐        │
│  │Worker 1│  │Worker 2│  │Worker N│        │
│  └────┬───┘  └────┬───┘  └────┬───┘        │
└───────┼───────────┼───────────┼─────────────┘
        ▼           ▼           ▼
┌─────────────────────────────────────────────┐
│  验证层 (Verifier Swarm)                     │
│  ┌─────────┐ ┌─────────┐ ┌─────────┐       │
│  │Test     │ │Review   │ │Security │       │
│  │Verifier │ │Verifier │ │Verifier │       │
│  └────┬────┘ └────┬────┘ └────┬────┘       │
│       └──────┬────┘───────────┘             │
│              ▼                              │
│  ┌──────────────────────┐                   │
│  │Result Synthesizer    │                   │
│  └──────────────────────┘                   │
└───────────────┬─────────────────────────────┘
                ▼
┌─────────────────────────────────────────────┐
│  可观测性层 (Observability)                   │
│  ┌──────────┐  ┌────────────┐               │
│  │Event Bus │  │Metrics     │               │
│  └──────────┘  └────────────┘               │
└─────────────────────────────────────────────┘
```

## 3. Core Data Flow

```
User Input -> Intent Analyzer -> IntentAnalysis
IntentAnalysis -> Task Graph Builder -> TaskGraph (DAG)
TaskGraph -> Ownership Planner -> OwnershipPlan
TaskGraph -> Scheduler -> SchedulePlan (batches)
TaskNode + OwnershipAssignment -> Context Packager -> ContextPack
TaskNode + Complexity -> Model Router -> RoutingResult
ContextPack + RoutingResult -> TaskContract
TaskContract -> Worker -> WorkerOutput
WorkerOutput -> Verifier Swarm -> VerificationResult
VerificationResult -> Result Synthesizer -> SynthesizerOutput
```

## 4. Four First-Class Roles (Enhanced from BMAD-METHOD)

| Role | Responsibility | Input | Output |
|------|---------------|-------|--------|
| Planner | Understand intent, build task graph | User intent + project context | TaskGraph |
| Worker | Execute specific tasks | TaskContract | WorkerOutput |
| Verifier | Independently verify results | Task + WorkerOutput | VerificationResult |
| Synthesizer | Aggregate all results | All outputs + verifications | SynthesizerOutput |

## 5. Model Tier Strategy (Enhanced from claude-code-switch)

| Tier | Use Case | Context Budget | Cost |
|------|----------|---------------|------|
| tier-1 | search, format, rename, lint-fix | 16K | Low |
| tier-2 | implementation, test, general review | 64K | Medium |
| tier-3 | planning, design, critical review | 200K | High |

Automatic routing rules:
- Base tier is selected based on task complexity
- High-risk tasks are escalated by one tier
- Each retry escalates by one tier
- tier-3 is the ceiling

## 6. MVP Scope

Implemented (v0.1.0):
- Task Graph Schema (complete type definitions)
- Intent Analyzer (rule-based intent analysis)
- Task Graph Builder (DAG construction + cycle detection + critical path)
- Complexity Scorer (multi-dimensional complexity scoring)
- Ownership Planner (path isolation + conflict detection + boundary enforcement)
- Context Packager (minimal context packages + automatic summarization)
- Model Router (3-tier automatic routing + escalation strategy)
- Scheduler MVP (dependency-based batch scheduling)
- Event Bus (observability infrastructure)
- Role Contracts (standard interfaces for all four roles)
- Verifier Result Schema (unified verification result structure)

Interfaces reserved (for future implementation):
- Worker Dispatch (actual dispatch to Claude Code sub-agents)
- Merge Guard (pre-merge conflict detection)
- Retry Manager (local retry strategy execution)
- Downgrade Manager (automatic fallback to serial execution)
- Verifier implementations (test/review/security/perf)
- Result Synthesizer implementation
- Observability Server (HTTP/WS service)
- GUI dashboard
- CI/PR integration
