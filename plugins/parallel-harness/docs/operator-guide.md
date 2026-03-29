> **[中文版](operator-guide.zh.md)** | English (default)

# parallel-harness Operator Guide

> Version: v1.1.2 (GA) | Last updated: 2026-03-20

## Installation and Deployment

### Prerequisites

- **Bun** >= 1.0 (runtime environment)
- **Claude Code** CLI (host platform)
- **gh CLI** (optional, required for GitHub PR/CI integration)
- **Node.js** >= 18 (only for TypeScript type checking)

### Installation Methods

**Method 1: Claude Code Plugin Marketplace**

```bash
claude plugin install parallel-harness@lorainwings-plugins --scope project
```

**Method 2: Manual Installation (Development)**

```bash
cd plugins/parallel-harness
bun install
```

**Method 3: Build Distribution Package**

```bash
bash tools/build-dist.sh
# Output: dist/parallel-harness/
```

### Verifying the Installation

```bash
# Run the test suite
bun test tests/unit/

# Type checking
bunx tsc --noEmit
```

Expected result: `219 pass / 0 fail`.

---

## Configuration Files

### default-config.json

Located at `config/default-config.json`, controls runtime behavior:

```json
{
  "$schema": "./run-config-schema.json",
  "version": "1.0.0",
  "run_config": {
    "max_concurrency": 5,
    "high_risk_max_concurrency": 2,
    "prioritize_critical_path": true,
    "budget_limit": 100000,
    "max_model_tier": "tier-3",
    "enabled_gates": ["test", "lint_type", "review", "policy"],
    "auto_approve_rules": [],
    "timeout_ms": 600000,
    "pr_strategy": "single_pr",
    "enable_autofix": false
  },
  "gate_overrides": {},
  "connector_configs": [],
  "instructions": {
    "org_level": [],
    "repo_level": []
  }
}
```

**Key Parameters**:

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `max_concurrency` | number | 5 | Maximum number of concurrent Workers globally |
| `high_risk_max_concurrency` | number | 2 | Maximum concurrency for high-risk tasks |
| `prioritize_critical_path` | boolean | true | Whether to prioritize scheduling critical path tasks |
| `budget_limit` | number | 100000 | Budget cap (relative value, in token units) |
| `max_model_tier` | string | "tier-3" | Highest model tier allowed |
| `enabled_gates` | string[] | 4 items | Enabled gate types |
| `auto_approve_rules` | string[] | [] | Auto-approval rules (empty = all require manual approval) |
| `timeout_ms` | number | 600000 | Single Run timeout (milliseconds) |
| `pr_strategy` | string | "single_pr" | PR strategy: none / single_pr / stacked_pr |
| `enable_autofix` | boolean | false | Whether to enable automatic fix pushes |

### default-policy.json

Located at `config/default-policy.json`, defines security and compliance policy rules. See the [Policy Configuration Guide](policy-guide.md) for details.

---

## Day-to-Day Operations

### Viewing Run Status

The complete lifecycle of a Run is managed by `RunStore`. Within a Claude Code session, you can check status with:

```
/harness check the status of the current run
```

**Run State Machine**:

```
pending → planned → awaiting_approval → scheduled → running → verifying → succeeded/failed/blocked
```

Each state transition is recorded in the `StatusTransition` list, which includes:
- `from`: Original state
- `to`: New state
- `reason`: Reason for the transition
- `timestamp`: Timestamp
- `actor`: Trigger source (optional)

### Audit Logs

All critical actions are recorded via `AuditTrail`. 32 audit event types are supported:

- **Run lifecycle**: run_created, run_planned, run_started, run_completed, run_failed, run_cancelled
- **Task lifecycle**: task_dispatched, task_completed, task_failed, task_retried
- **Worker**: worker_started, worker_completed, worker_failed
- **Model routing**: model_routed, model_escalated, model_downgraded
- **Verification/Gates**: verification_started/passed/blocked, gate_passed, gate_blocked
- **Policy**: policy_evaluated, policy_violated
- **Approval**: approval_requested, approval_decided
- **Ownership**: ownership_checked, ownership_violated
- **Budget**: budget_consumed, budget_exceeded
- **PR/CI**: pr_created, pr_reviewed, pr_merged
- **Human feedback**: human_feedback
- **Configuration changes**: config_changed

**Querying Audit Logs**:

```typescript
// Query by Run
const events = await auditTrail.query({ run_id: "run_xxx" });

// Query by time range
const events = await auditTrail.query({
  from: "2026-03-20T00:00:00Z",
  to: "2026-03-20T23:59:59Z"
});

// Get Run timeline
const timeline = await auditTrail.getTimeline("run_xxx");
```

**Exporting Audit Logs**:

```typescript
// JSON format
const json = await auditTrail.export("json", { run_id: "run_xxx" });

// CSV format
const csv = await auditTrail.export("csv");
```

### Budget Monitoring

Budget is tracked via `CostLedger`. After each Worker execution completes, the following is recorded:
- `task_id`: Associated task
- `model_tier`: Model tier used
- `tokens_used`: Token consumption
- `cost`: Cost (relative value)

**Model Tier Cost Baseline**:

| Tier | Cost per 1K Tokens | Max Context Budget | Max Retries |
|------|--------------------|--------------------|-------------|
| tier-1 | 1 | 16,000 | 3 |
| tier-2 | 5 | 64,000 | 2 |
| tier-3 | 25 | 200,000 | 1 |

**Behavior when budget is exhausted**: Execution stops automatically and does not silently continue. A `budget_exceeded` audit event is triggered.

---

## Troubleshooting Workflow

### 1. Check Event Logs

Start by reviewing recent events through EventBus:

```typescript
const events = eventBus.getEventLog({ graph_id: "xxx" });
```

### 2. Review State Transition History

Inspect the `status_history` of a Run or Task Attempt:

```typescript
const execution = await runStore.getExecution("run_xxx");
// execution.status_history contains the complete transition chain
```

### 3. Inspect Gate Results

Gate results contain a detailed findings list:

```typescript
// Each GateResult contains:
// - passed: whether the gate passed
// - blocking: whether this is a blocking gate
// - conclusion.findings: list of specific findings
// - conclusion.required_actions: mandatory fixes
// - conclusion.suggested_patches: suggested patches
```

### 4. Check Downgrade Trigger Conditions

See the [Troubleshooting Guide](troubleshooting.md) for the complete troubleshooting workflow.

---

## Logging and Monitoring

### EventBus Event Stream

EventBus supports:
- **Subscribe by type**: `eventBus.on("task_completed", handler)`
- **Wildcard subscription**: `eventBus.on("*", handler)` -- receives all events
- **Event log**: Automatically retains the most recent 10,000 events
- **Persistence adapter**: `PersistentEventBusAdapter` automatically writes events to AuditTrail

### Persistence Adapters

Two persistence adapters are available:

| Adapter | Class | Use Case |
|---------|-------|----------|
| In-memory | `LocalMemoryStore` | Development/testing |
| File system | `FileStore` | Production, data persisted to JSON files |

File storage path format: `{basePath}/{id}.json`

### Checkpoint Recovery

Checkpoint recovery is supported via `ReplayEngine`:

```typescript
const replayEngine = new ReplayEngine(auditTrail);

// Get the resume point
const resumePoint = await replayEngine.getResumePoint("run_xxx");
// resumePoint.completed_tasks: list of completed tasks
// resumePoint.last_completed_task_id: last completed task
```
