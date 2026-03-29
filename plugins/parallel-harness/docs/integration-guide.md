> **[中文版](integration-guide.zh.md)** | English (default)

# parallel-harness Integration Guide

> Version: v1.1.2 (GA) | Last Updated: 2026-03-20

## Overview

parallel-harness provides multi-layer integration interfaces, supporting integration with GitHub, CI systems, event buses, custom Gates, and Worker adapters.

---

## GitHub PR Integration

### Prerequisites

- Install [gh CLI](https://cli.github.com/) and complete authentication
- Verify that `gh auth status` outputs correctly

### PR Provider Interface

`GitHubPRProvider` implements the following operations via the `gh` CLI:

| Operation | Method | gh Command |
|-----------|--------|------------|
| Create PR | `createPR()` | `gh pr create` |
| Add Comment | `addReviewComment()` | `gh api` |
| Set Check | `setCheckStatus()` | `gh api` |
| Get PR | `getPR()` | `gh pr view` |
| Merge PR | `mergePR()` | `gh pr merge` |

### Creating a PR

```typescript
import { GitHubPRProvider } from "./runtime/integrations/pr-provider";

const provider = new GitHubPRProvider();
const result = await provider.createPR({
  title: "feat: refactor utils module",
  body: "## Change Summary\n- Split helper functions into separate modules\n- Add unit tests",
  head_branch: "feature/refactor-utils",
  base_branch: "main",
  labels: ["enhancement", "parallel-harness"],
  reviewers: ["reviewer-username"],
  draft: false,
});
// result: { pr_number, pr_url, head_branch }
```

### PR Summary Rendering

`renderPRSummary()` converts Run results into a formatted PR description:

```typescript
import { renderPRSummary } from "./runtime/integrations/pr-provider";

const summary = renderPRSummary(runResult, runPlan, gateResults, {
  include_walkthrough: true,
  include_gate_results: true,
  include_cost_summary: true,
  include_file_changes: true,
  max_findings: 20,
});
```

The generated PR Summary includes:
- Run status and duration
- Task completion statistics
- Walkthrough (execution details per task)
- Gate results table
- Cost summary (token usage, budget utilization)
- Failed task list

### Review Comments

`renderReviewComments()` converts Gate findings into inline comments:

```typescript
import { renderReviewComments } from "./runtime/integrations/pr-provider";

const comments = renderReviewComments(gateResults, 20);
// Each comment includes: file_path, line, body, severity
```

### PR Strategy Configuration

Set in `default-config.json`:

```json
{
  "run_config": {
    "pr_strategy": "single_pr"
  }
}
```

| Strategy | Description |
|----------|-------------|
| `none` | Do not create a PR |
| `single_pr` | Merge all changes into a single PR |
| `stacked_pr` | Split into multiple PRs by task group (stacked) |

### Merge Strategy

Three merge methods are supported:

| Strategy | Description |
|----------|-------------|
| `merge` | Create a merge commit |
| `squash` | Squash into a single commit |
| `rebase` | Rebase merge |

---

## CI Failure Analysis

### Parsing CI Logs

```typescript
import { parseCIFailure } from "./runtime/integrations/pr-provider";

const failure = parseCIFailure(rawLogContent);
// Returns:
// {
//   ci_provider: string,
//   job_name: string,
//   error_message: string,
//   affected_files: string[],
//   failure_type: "build" | "test" | "lint" | "type_check" | "deploy" | "unknown"
// }
```

Supported failure type auto-detection:
- **test**: Detects `FAIL` + `test`/`spec` keywords
- **type_check**: Detects `error TS` or `type error`
- **lint**: Detects `lint`/`eslint`/`ruff`
- **build**: Detects `build`/`compile`

### Run Mapping

Associate Runs, Issues, PRs, and CI via `RunMappingRegistry`:

```typescript
import { RunMappingRegistry } from "./runtime/integrations/pr-provider";

const registry = new RunMappingRegistry();
registry.register({
  run_id: "run_xxx",
  issue_number: 42,
  pr_number: 123,
  branch_name: "feature/xxx",
  created_at: new Date().toISOString(),
});

// Query
const mapping = registry.getByPR(123);
const mapping = registry.getByIssue(42);
```

---

## Event Bus Subscription

### Basic Subscription

```typescript
import { EventBus } from "./runtime/observability/event-bus";

const bus = new EventBus();

// Subscribe to a specific event
bus.on("task_completed", (event) => {
  console.log(`Task completed: ${event.task_id}`);
});

// Subscribe to all events
bus.on("*", (event) => {
  console.log(`[${event.type}] ${JSON.stringify(event.payload)}`);
});
```

### Supported Event Types

38 event types in total, grouped into the following categories:

| Category | Events |
|----------|--------|
| Task Lifecycle | graph_created, task_ready, task_dispatched, task_completed, task_failed, task_retrying |
| Verification/Gate | verification_started/passed/blocked, gate_evaluation_started, gate_passed, gate_blocked |
| Model Routing | model_escalated, model_downgraded, downgrade_triggered |
| Batch | batch_started, batch_completed |
| Session/Run | session_started/completed, run_created/planned/started/completed/failed/cancelled |
| Approval/Governance | approval_requested/granted/denied |
| Policy | policy_evaluated, policy_violated |
| Ownership | ownership_checked, ownership_violated |
| Budget | budget_consumed, budget_exceeded |
| PR/CI | pr_created, pr_reviewed, pr_merged, ci_failure_detected |
| Human | human_feedback_received |

### Persisted Events

Use `PersistentEventBusAdapter` to automatically write events to the audit log:

```typescript
import { PersistentEventBusAdapter } from "./runtime/persistence/session-persistence";

const adapter = new PersistentEventBusAdapter(auditTrail);
adapter.connectToEventBus(eventBus);
// All events are automatically persisted to AuditTrail
```

---

## Custom Gate Implementation

### Implementing the SingleGateEvaluator Interface

```typescript
import type { SingleGateEvaluator, GateInput } from "./runtime/gates/gate-system";
import type { GateResult, GateType } from "./runtime/schemas/ga-schemas";

class MyCustomGateEvaluator implements SingleGateEvaluator {
  type: GateType = "review"; // Use an existing type or extend

  async evaluate(input: GateInput): Promise<GateResult> {
    const findings = [];

    // Custom validation logic
    if (/* your check condition */) {
      findings.push({
        severity: "error",
        message: "Custom check failed",
        file_path: "path/to/file.ts",
        line: 42,
      });
    }

    const passed = findings.filter(
      f => f.severity === "error" || f.severity === "critical"
    ).length <= input.contract.thresholds.max_errors;

    return {
      schema_version: "1.0.0",
      gate_id: generateId("gate"),
      gate_type: this.type,
      gate_level: input.level,
      run_id: input.ctx.run_id,
      task_id: input.task?.id,
      passed,
      blocking: input.contract.blocking,
      conclusion: {
        summary: passed ? "Custom gate passed" : "Custom gate failed",
        findings,
        risk: "low",
        required_actions: [],
        suggested_patches: [],
      },
      evaluated_at: new Date().toISOString(),
    };
  }
}
```

### Registering a Custom Gate

```typescript
const gateSystem = new GateSystem();
gateSystem.registerEvaluator(new MyCustomGateEvaluator());
```

### Built-in Gates

| Gate | Class | Blocking | Level | Description |
|------|-------|----------|-------|-------------|
| test | TestGateEvaluator | Yes | task, run | Test pass rate check |
| lint_type | LintTypeGateEvaluator | Yes | task, run | Lint and type checking |
| review | ReviewGateEvaluator | No | task, run, pr | Code review |
| security | SecurityGateEvaluator | Yes | run, pr | Security scan (sensitive file detection) |
| coverage | CoverageGateEvaluator | No | run, pr | Test coverage |
| policy | PolicyGateEvaluator | Yes | task, run | Policy compliance |
| documentation | DocumentationGateEvaluator | No | run, pr | Documentation completeness |
| release_readiness | ReleaseReadinessGateEvaluator | Yes | run | Release readiness check |

---

## Custom Worker Adapter

### Implementing the WorkerAdapter Interface

```typescript
import type { WorkerAdapter } from "./runtime/engine/orchestrator-runtime";
import type { WorkerInput, WorkerOutput } from "./runtime/orchestrator/role-contracts";

class MyWorkerAdapter implements WorkerAdapter {
  async execute(input: WorkerInput): Promise<WorkerOutput> {
    // 1. Convert TaskContract into Worker-executable instructions
    const contract = input.contract;

    // 2. Execute the task (e.g., invoke a Claude Code sub-agent)
    // ...

    // 3. Return structured output
    return {
      task_id: contract.task_id,
      status: "ok",
      summary: "Task completed",
      modified_paths: ["src/module.ts"],
      artifacts: [],
      tokens_used: 1500,
    };
  }
}
```

### Worker Capability Registration

Register Worker capabilities via `CapabilityRegistry`:

```typescript
import { createDefaultCapabilityRegistry } from "./runtime/workers/worker-runtime";

const registry = createDefaultCapabilityRegistry();

// Register a custom capability
registry.register({
  id: "my_custom_capability",
  name: "Custom Capability",
  description: "Performs custom operations",
  task_types: ["custom-task"],
  required_tools: ["Read", "Write", "Bash"],
  recommended_tier: "tier-2",
  applicable_phases: ["implementation"],
});
```

Built-in capabilities include:
- **code_implementation**: Code implementation (tier-2)
- **test_writing**: Test writing (tier-2)
- **code_review**: Code review (tier-3)
- **documentation**: Documentation writing (tier-1)
- **lint_fix**: Lint fix (tier-1)
- **architecture_design**: Architecture design (tier-3)

### Worker Execution Control

`WorkerExecutionController` provides:
- **Timeout control**: Default 300,000ms (5 minutes)
- **Path sandboxing**: Restricts the files a Worker can modify
- **Tool policy**: Allow/deny specific tools (denies `TaskStop` and `EnterWorktree` by default)
- **Capability validation**: Verifies required TaskContract fields

---

## Hook System

### Hook Lifecycle Phases

| Phase | Identifier | Trigger Point |
|-------|-----------|---------------|
| Pre-plan | `pre_plan` | Before intent analysis begins |
| Post-plan | `post_plan` | After task graph construction completes |
| Pre-dispatch | `pre_dispatch` | Before Worker dispatch begins |
| Post-dispatch | `post_dispatch` | After Worker execution completes |
| Pre-verify | `pre_verify` | Before Gate evaluation begins |
| Post-verify | `post_verify` | After Gate evaluation completes |
| Pre-merge | `pre_merge` | Before Merge Guard check |
| Post-merge | `post_merge` | After merge completes |
| Pre-PR | `pre_pr` | Before PR creation |
| Post-PR | `post_pr` | After PR creation |

### Registering a Hook

```typescript
import { HookRegistry } from "./runtime/capabilities/capability-registry";

const hookRegistry = new HookRegistry();

hookRegistry.register({
  id: "my-hook",
  name: "Custom Hook",
  phase: "post_dispatch",
  priority: 10,
  enabled: true,
  handler: async (context) => {
    // Custom logic
    console.log(`Run ${context.run_id} dispatch completed`);
    return { continue: true, message: "Hook executed successfully" };
  },
});
```

### Instruction Pack

Inject context instructions via `InstructionRegistry`:

```typescript
import { InstructionRegistry } from "./runtime/capabilities/capability-registry";

const registry = new InstructionRegistry();

registry.register({
  id: "org-coding-standards",
  name: "Organization Coding Standards",
  scope: { type: "org", org_id: "my-org" },
  priority: 1,
  instructions: [
    { type: "coding", content: "Use TypeScript strict mode" },
    { type: "testing", content: "Test coverage must be at least 80%" },
  ],
});
```
