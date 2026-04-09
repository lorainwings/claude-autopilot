> **[中文版](admin-guide.zh.md)** | English (default)

# parallel-harness Admin Guide

> Version: v1.4.0 (GA) | Target audience: Platform administrators, organization owners

## Overview

This guide is intended for platform administrators responsible for configuring and managing the parallel-harness plugin. It covers RBAC configuration, policy management, approval workflows, budget controls, and system maintenance.

## RBAC Role Management

### Built-in Roles

| Role | Permissions | Typical User |
|------|------------|--------------|
| admin | All 12 permissions | Platform administrators |
| developer | run.create/cancel/retry/view, audit.view | Development engineers |
| reviewer | run.view, task.approve_*, gate.override, audit.view | Code reviewers |
| viewer | run.view, audit.view | Read-only observers |

### Permission List

| Permission | Description |
|-----------|-------------|
| run.create | Create a new execution Run |
| run.cancel | Cancel a running Run |
| run.retry | Retry failed tasks |
| run.view | View Run status and details |
| task.approve_model_upgrade | Approve model upgrade requests |
| task.approve_sensitive_write | Approve writes to sensitive paths |
| task.approve_autofix_push | Approve autofix pushes |
| gate.override | Override Gate blocking decisions |
| policy.manage | Manage policy rules |
| config.manage | Manage runtime configuration |
| audit.view | View audit logs |
| audit.export | Export audit reports |

### Custom Roles

```typescript
import { RBACEngine, type Role } from "parallel-harness/runtime/governance/governance";

const rbac = new RBACEngine();
rbac.addRole({
  name: "lead_developer",
  permissions: [
    "run.create", "run.cancel", "run.retry", "run.view",
    "task.approve_model_upgrade",
    "audit.view",
  ],
});
rbac.assignRole("user-123", "lead_developer");
```

## Policy Configuration

### Policy Rule Structure

Policies are defined in `config/default-policy.json`. Each rule contains:

- `rule_id`: Unique identifier
- `name`: Rule name
- `category`: Category (path_boundary/model_tier_limit/budget_limit, etc.)
- `condition`: Trigger condition
- `enforcement`: Violation action (block/warn/approve/log)

### Condition Types

| Condition Type | Description | Parameters |
|---------------|-------------|------------|
| always | Always matches | None |
| path_match | Path matching | pattern: string |
| budget_threshold | Budget threshold | threshold: number |
| risk_level | Risk level | min_risk: string |
| model_tier | Model tier | max_tier: string |
| action_type | Action type | actions: string[] |

### Example: Block Writes to Sensitive Directories

```json
{
  "rule_id": "pol-sensitive-dir",
  "name": "Block writes to sensitive directories",
  "category": "sensitive_directory",
  "condition": {
    "type": "path_match",
    "params": { "pattern": "config/secrets" }
  },
  "enforcement": "block",
  "enabled": true,
  "priority": 1
}
```

## Approval Workflow

### Auto-Approval

Configure auto-approval rules in `RunConfig.auto_approve_rules`:

- `"all"`: Auto-approve all requests
- `"execute_with_conflicts"`: Auto-approve conflict executions
- Specific action names: Exact match

### Manual Approval

Requests that do not match any auto-approval rule enter a pending state. They can be handled through:

1. **Control Plane API**: `POST /api/runs/{id}/approve/{approvalId}`
2. **Web GUI**: Approval panel on the Run details page
3. **Programmatic interface**: `runtime.approveAndResume(runId, approvalId, decidedBy)`

## Budget Controls

### Budget Configuration

```json
{
  "budget_limit": 100000,
  "max_model_tier": "tier-3"
}
```

- `budget_limit`: Maximum cost budget per Run (relative value)
- Cost calculation: `(tokens / 1000) * tier_cost_rate`
  - tier-1: 1 / tier-2: 5 / tier-3: 25

### Budget Exhaustion Behavior

- Execution stops automatically when the budget is exhausted
- It will not silently continue consuming resources
- A `budget_threshold` policy can trigger approval proactively before exhaustion

## System Maintenance

### Data Persistence

Local file persistence (`FileStore`) is used by default. Data is stored in:
- Session: `.parallel-harness/sessions/`
- Runs: `.parallel-harness/runs/`
- Audit: `.parallel-harness/audit/`

### Audit Export

```typescript
const auditTrail = new AuditTrail();
// JSON export
const jsonReport = await auditTrail.export("json", { run_id: "run_xxx" });
// CSV export
const csvReport = await auditTrail.export("csv");
```

### Event Replay

```typescript
const replay = new ReplayEngine(auditTrail);
const timeline = await replay.getReplayTimeline("run_xxx");
const resumePoint = await replay.getResumePoint("run_xxx");
```

## Control Plane API

### Endpoint List

| Method | Path | Description |
|--------|------|-------------|
| GET | /api/runs | List all Runs |
| GET | /api/runs/{id} | Get Run details |
| GET | /api/runs/{id}/audit | Get audit logs |
| GET | /api/runs/{id}/gates | Get Gate results |
| POST | /api/runs/{id}/cancel | Cancel a Run |
| POST | /api/runs/{id}/tasks/{taskId}/retry | Retry a task |
| POST | /api/runs/{id}/approve/{approvalId} | Approve an approval request |
| POST | /api/runs/{id}/reject/{approvalId} | Reject an approval request |

### Starting the Control Plane

```bash
# Via skill
# Or directly
bun run runtime/server/control-plane.ts
```

Default port: 3847

## Upgrade Guide

### v0.x to v1.0.0

1. Back up existing configuration
2. Update `package.json` version
3. Run `bun install`
4. Check `config/default-config.json` for new fields
5. Run `bun test` to verify compatibility
6. Update `schema_version` in policy files

### Data Migration

v1.0.0 introduces versioned schemas (`schema_version: "1.0.0"`). Data from older versions will be automatically upgraded on read.
