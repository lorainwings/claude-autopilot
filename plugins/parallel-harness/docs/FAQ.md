> **[中文版](FAQ.zh.md)** | English (default)

# parallel-harness FAQ

## Basic Concepts

### Q: What is the difference between parallel-harness and spec-autopilot?

| Dimension | spec-autopilot | parallel-harness |
|-----------|---------------|-----------------|
| Purpose | Spec-driven delivery orchestration | AI software engineering control plane |
| Process Model | Fixed 8-phase pipeline | Dynamic DAG-based task scheduling |
| Parallelism | Serial within phases | Cross-task parallelism |
| Quality Control | 3-layer gate checkpoint | 9-type Gate System |
| Model Usage | Single or manually selected | Automatic routing + cost control |

They are complementary: spec-autopilot handles spec-driven delivery, while parallel-harness handles parallel engineering governance.

### Q: When should I use parallel-harness?

- Projects requiring parallel modifications across multiple modules and files
- Scenarios needing cost control and model routing
- Teams requiring RBAC, approval workflows, and audit capabilities
- Workflows needing PR/CI closed-loop integration

### Q: What are the minimum requirements?

- Bun v1.2+
- TypeScript 5.x
- `claude` CLI (required for Worker execution)
- `gh` CLI (required for GitHub PR integration)

## Execution and Scheduling

### Q: How are tasks executed in parallel?

1. User input -> Intent analysis -> Build task DAG
2. Ownership planning -> Assign exclusive file paths to each task
3. DAG batch scheduling -> Tasks without dependencies can run in parallel
4. Worker dispatch -> Each Worker executes within its sandbox
5. Gate verification -> Block non-conforming outputs

### Q: What happens when conflicts occur?

- **Path conflicts**: Conflicting paths of subsequent tasks are moved from exclusive to shared-read
- **High-risk conflicts**: Marked as unresolvable, triggering the approval workflow
- **Conflict rate > 30%**: Automatic downgrade to semi-serial mode
- **Critical path blocked**: Prioritized serial processing

### Q: What happens when a Worker execution fails?

Failures are classified into 9 types, each with different follow-up actions:

| Failure Type | Retryable | Escalatable | Needs Human |
|-------------|-----------|-------------|-------------|
| transient_tool_failure | Yes | - | - |
| verification_failed | Yes | Yes | - |
| timeout | Yes | Yes | - |
| permanent_policy_failure | - | - | Yes |
| ownership_conflict | - | - | - |
| budget_exhausted | - | - | Yes |

## Model Routing

### Q: How is the model tier selected?

1. Base tier is chosen based on task complexity (trivial/low -> tier-1, medium -> tier-2, high/extreme -> tier-3)
2. High-risk tasks are automatically promoted one tier
3. Each retry automatically escalates the tier
4. Task type hints can override the selection

### Q: How do I control costs?

- Set `budget_limit` to cap the budget for a single Run
- Low-complexity tasks automatically use lower-cost tiers
- Execution stops automatically when the budget is exhausted
- The cost ledger records consumption for each attempt

## Gate System

### Q: Which Gates are blocking?

Under the default configuration:

- **Blocking**: test, lint_type, security, policy, release_readiness
- **Non-blocking**: review, perf, coverage, documentation

### Q: How do I skip a Gate?

1. Exclude specific Gates via `RunConfig.enabled_gates`
2. The admin role can override Gate decisions using the `gate.override` permission
3. Disabling security and policy Gates in production is not recommended

## Governance

### Q: How do I resume a Run blocked by approval?

```typescript
// Method 1: Via API
await runtime.approveAndResume(runId, approvalId, "admin-user");

// Method 2: Via control plane
POST /api/runs/{id}/approve/{approvalId}

// Method 3: Reject and terminate
await runtime.rejectRun(runId, approvalId, "admin-user", "reason");
```

### Q: How do I view audit logs?

```typescript
// Query a specific Run
const events = await runtime.getAuditLog("run_xxx");

// Via control plane
GET /api/runs/{id}/audit
```

## PR/CI Integration

### Q: Which Git platforms are supported?

Currently GitHub is supported (via `gh` CLI). The interface layer (`PRProvider`) is abstracted and can be extended to support GitLab, Bitbucket, and others.

### Q: Does a PR creation failure affect the Run result?

No. A PR creation failure is recorded as an audit event but does not block the Run result. This is by design, ensuring that core execution is not affected by external integration failures.

## Troubleshooting

### Q: What do I do about `claude CLI 不可用`?

The Worker will return a `warning` status with no output and will ultimately be marked as an `unsupported_capability` failure. Solutions:
1. Verify that the `claude` command is available in your PATH
2. Check Claude CLI configuration and authentication
3. Or provide a custom `WorkerAdapter` implementation

### Q: Why can't the tests find test files?

Ensure test files are named with a `.test.ts` or `.spec.ts` suffix and are located under the `tests/` directory. Run `bun test` to verify.

### Q: How do I debug Gate evaluation?

1. View the Run's Gate results: `GET /api/runs/{id}/gates`
2. Check `gate_passed` / `gate_blocked` events in the audit log
3. Gate conclusions contain structured findings, risk assessments, and required_actions
