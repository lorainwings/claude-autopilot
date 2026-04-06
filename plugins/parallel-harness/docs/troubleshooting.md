> **[中文版](troubleshooting.zh.md)** | English (default)

# parallel-harness Troubleshooting

> Version: v1.3.1 (GA) | Last Updated: 2026-03-20

## Common Errors and Solutions

### 1. TaskContract Missing Required Fields

**Error messages**:
```
Error: TaskContract 缺少 task_id
Error: TaskContract 缺少 goal
Error: TaskContract 缺少 allowed_paths
```

**Cause**: The `TaskContract` received by the Worker is incomplete. Every contract must contain `task_id`, `goal`, and `allowed_paths`.

**Solution**:
1. Check that the contract output by `Context Packager` is complete
2. Confirm that the correct TaskNode is passed when calling `buildTaskContract()`
3. Verify that the OwnershipPlan has paths assigned to the task

### 2. Worker Execution Timeout

**Error message**:
```
Error: Worker 执行超时 (300000ms)
```

**Cause**: Worker execution time exceeded the configured timeout limit.

**Solution**:
1. Increase the timeout: adjust `timeout_ms` in `default-config.json`
2. Split large tasks into smaller subtasks
3. Check whether the task is stuck on a specific tool call
4. Consider using a higher-tier model (tier-3 typically completes complex tasks faster)

### 3. gh CLI Not Installed or Not Authenticated

**Error message**:
```
Error: gh pr create 失败:
```

**Cause**: GitHub CLI is not installed or OAuth authentication is not complete.

**Solution**:
```bash
# Install gh
brew install gh  # macOS

# Authenticate
gh auth login

# Verify
gh auth status
```

### 4. DAG Contains Cycles

**Error message**:
```
Error: 任务图存在循环依赖
```

**Cause**: The Task Graph Builder constructed a dependency graph with cycles.

**Solution**:
1. Check the `depends_on` relationships between tasks
2. Remove circular dependencies
3. Consider merging circularly dependent tasks into a single task

---

## State Machine Transition Errors

### Run State Transition Issues

**Valid Run state transition paths**:

```
pending → planned → awaiting_approval → scheduled → running → verifying → succeeded
                                                                        → failed
                                                                        → blocked
                                                      → cancelled (can be triggered at any stage)
```

**Common issues**:

| Symptom | Cause | Solution |
|---------|-------|----------|
| Stuck at `pending` | Intent analysis failed | Check whether user input is parseable |
| Stuck at `planned` | Waiting for approval | Check for pending approval requests |
| Stuck at `awaiting_approval` | Approval not processed | Manually approve or configure `auto_approve_rules` |
| Stuck at `running` | Worker unresponsive | Check timeout settings, review Worker logs |
| Goes directly to `failed` | Failed during planning stage | Check the failure reason in `status_history` |

**Viewing status history**:

Every RunExecution and TaskAttempt records a complete `status_history`:

```typescript
// Each status transition includes:
{
  from: "running",
  to: "failed",
  reason: "Worker execution failed: type check error",
  timestamp: "2026-03-20T10:30:00Z",
  actor: "system"
}
```

### Task Attempt State Transitions

**Valid Attempt transition paths**:

```
pending → pre_check → executing → post_check → succeeded
                                              → failed
                    → failed (pre_check failure)
                                              → timed_out
                                              → cancelled
```

**Pre-Check items** (5 categories):

| Check Type | Identifier | Description |
|-----------|-----------|-------------|
| Ownership | `ownership` | Verifies the task has permission to modify target files |
| Policy | `policy` | Evaluates whether policy rules allow execution |
| Budget | `budget` | Checks whether remaining budget is sufficient |
| Approval | `approval` | Checks whether approval is required and has been granted |
| Capability | `capability` | Checks whether the Worker has the required capabilities |

---

## Policy Block Troubleshooting

### Policy Gate Blocks

**Symptom**: The policy gate in Gate results did not pass, blocking execution.

**Troubleshooting steps**:

1. **Review Gate conclusions**: Check the specific findings in `GateResult.conclusion.findings`

2. **Review matched rules**:
   ```typescript
   // PolicyViolation includes:
   {
     rule_id: "path-001",
     category: "sensitive_directory",
     severity: "critical",
     message: "Modified a sensitive file: .env",
     blocked: true
   }
   ```

3. **Verify rule configuration**: Check the configuration for the corresponding `rule_id` in `config/default-policy.json`

4. **Choose a resolution**:
   - Modify the task to avoid touching restricted resources
   - Adjust the rule's `enforcement` (e.g., change from `block` to `warn`)
   - Disable the specific rule (set `enabled: false`)
   - Request an admin role override (requires `gate.override` permission)

### Security Gate Blocks

**Symptom**: Security gate detected modification of sensitive files.

**Detection patterns**:
- `.env` files
- `credentials` (case-insensitive)
- `secret` (case-insensitive)
- `password` (case-insensitive)
- `.pem` files
- `.key` files
- `token` (case-insensitive)
- `apikey` (case-insensitive)

**Solution**:
1. Confirm the modification is necessary
2. Ensure the file does not contain plaintext secrets
3. If the modification is truly needed, have an admin role override the gate

---

## Budget Exhaustion Handling

### Symptoms

- `budget_exceeded` audit event triggered
- Run state transitions to `failed` with reason `budget_exhausted`
- `remaining_budget <= 0` in CostLedger

### Failure Classification

The FailureClass for budget exhaustion is `budget_exhausted`, with the following recommended actions:
- **retry**: No (no automatic retry)
- **escalate**: No
- **downgrade**: Yes (downgrade strategy)
- **human**: Yes (human intervention required)

### Solutions

1. **Increase the budget**: Raise `budget_limit` in `default-config.json`

2. **Reduce costs**:
   - Limit the maximum model tier (e.g., set `max_model_tier: "tier-2"`)
   - Reduce concurrency (lower `max_concurrency`)
   - Simplify tasks (reduce task count or complexity)

3. **Review cost distribution**:
   ```typescript
   // CostLedger.tier_distribution shows consumption by tier:
   {
     "tier-1": { tokens: 5000, cost: 5, count: 3 },
     "tier-2": { tokens: 30000, cost: 150, count: 5 },
     "tier-3": { tokens: 80000, cost: 2000, count: 2 }
   }
   ```

4. **Optimization strategies**:
   - Force tier-1 for simple tasks
   - Reduce unnecessary retries (retries automatically escalate tiers, increasing costs)

---

## Ownership Conflict Resolution

### Symptoms

- Merge Guard reports `ownership_violations`
- Worker throws `Worker 修改了沙箱外的路径` error
- Multiple Workers modifying the same file causes `file_conflicts`

### Ownership Violation Types

| Violation Type | Description | Severity |
|---------------|-------------|----------|
| Out-of-bounds write | Worker modified files outside `allowed_paths` | critical |
| Shared path conflict | Multiple Workers modified the same file simultaneously | high |
| Forbidden path access | Worker modified files in `forbidden_paths` | critical |

### Troubleshooting Steps

1. **Review OwnershipPlan**:
   ```typescript
   // Each OwnershipAssignment includes:
   {
     task_id: "task_1",
     exclusive_paths: ["src/module-a/**"],
     shared_read_paths: ["src/shared/**"],
     forbidden_paths: [".env", "config/production/**"]
   }
   ```

2. **Review MergeGuard results**:
   - `ownership_violations`: List of ownership violations
   - `file_conflicts`: List of file conflicts
   - `blocking_reasons`: Blocking reasons

3. **Solutions**:
   - **Split tasks**: Distribute conflicting file modifications across different tasks
   - **Serialize**: Set conflicting tasks as dependencies and execute sequentially
   - **Manual downgrade**: Trigger the `downgrade_triggered` event to downgrade to semi-serial mode

### Downgrade Trigger Conditions

Conditions for automatic system downgrade (from `decideDowngrade()`):

| Condition | Downgrade Strategy |
|-----------|-------------------|
| Conflict rate > 30% | `serialize` (semi-serial) |
| Gate blocked 3 consecutive times | `serialize` + tier-3 |
| Critical path blocked | `serialize` (prioritized processing) |

---

## Other Common Issues

### EventBus Event Loss

**Cause**: The EventBus retains the most recent 10,000 events by default. Older events are discarded when this limit is exceeded.

**Solution**:
1. Connect a `PersistentEventBusAdapter` to persist events to the AuditTrail
2. Increase the `maxLogSize` parameter

### Gate Evaluator Not Registered

**Symptom**: A specific gate type does not appear in evaluation results.

**Troubleshooting**:
```typescript
// Check registered evaluators
const types = gateSystem.getRegisteredTypes();
// Default registered: test, lint_type, review, security, coverage, policy, documentation, release_readiness
```

Note: The `perf` gate has no default evaluator implementation and must be registered manually.

### RBAC Insufficient Permissions

**Symptom**: Operation is denied.

**Built-in role permission table**:

| Permission | admin | developer | reviewer | viewer |
|-----------|-------|-----------|----------|--------|
| run.create | o | o | - | - |
| run.cancel | o | o | - | - |
| run.retry | o | o | - | - |
| run.view | o | o | o | o |
| task.approve_model_upgrade | o | - | o | - |
| task.approve_sensitive_write | o | - | o | - |
| task.approve_autofix_push | o | - | - | - |
| gate.override | o | - | o | - |
| policy.manage | o | - | - | - |
| config.manage | o | - | - | - |
| audit.view | o | o | o | o |
| audit.export | o | - | - | - |

Note: Actors of type `system` and `ci` automatically receive all permissions.
