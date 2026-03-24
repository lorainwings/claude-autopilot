> [English](integration-guide.md) | 中文

# parallel-harness 集成指南

> 版本: v1.0.0 (GA) | 最后更新: 2026-03-20

## 概述

parallel-harness 提供多层集成接口，支持与 GitHub、CI 系统、事件总线、自定义 Gate 和 Worker 适配器的集成。

---

## GitHub PR 集成

### 前置条件

- 安装 [gh CLI](https://cli.github.com/) 并完成认证
- 确保 `gh auth status` 输出正常

### PR Provider 接口

`GitHubPRProvider` 通过 `gh` CLI 实现以下操作：

| 操作 | 方法 | gh 命令 |
|------|------|---------|
| 创建 PR | `createPR()` | `gh pr create` |
| 添加评论 | `addReviewComment()` | `gh api` |
| 设置 Check | `setCheckStatus()` | `gh api` |
| 获取 PR | `getPR()` | `gh pr view` |
| 合并 PR | `mergePR()` | `gh pr merge` |

### 创建 PR

```typescript
import { GitHubPRProvider } from "./runtime/integrations/pr-provider";

const provider = new GitHubPRProvider();
const result = await provider.createPR({
  title: "feat: 重构 utils 模块",
  body: "## 变更摘要\n- 拆分 helper 函数到独立模块\n- 添加单元测试",
  head_branch: "feature/refactor-utils",
  base_branch: "main",
  labels: ["enhancement", "parallel-harness"],
  reviewers: ["reviewer-username"],
  draft: false,
});
// result: { pr_number, pr_url, head_branch }
```

### PR Summary 渲染

`renderPRSummary()` 将 Run 结果转换为格式化的 PR 描述：

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

生成的 PR Summary 包含：
- Run 状态和耗时
- 任务完成统计
- Walkthrough（每个任务的执行情况）
- Gate 结果表格
- 成本汇总（Token 使用、预算利用率）
- 失败任务列表

### Review 评论

`renderReviewComments()` 将 Gate findings 转换为行内评论：

```typescript
import { renderReviewComments } from "./runtime/integrations/pr-provider";

const comments = renderReviewComments(gateResults, 20);
// 每条评论包含：file_path, line, body, severity
```

### PR 策略配置

在 `default-config.json` 中设置：

```json
{
  "run_config": {
    "pr_strategy": "single_pr"
  }
}
```

| 策略 | 说明 |
|------|------|
| `none` | 不创建 PR |
| `single_pr` | 所有变更合并到一个 PR |
| `stacked_pr` | 按任务组拆分多个 PR（堆叠） |

### 合并策略

支持三种合并方式：

| 策略 | 说明 |
|------|------|
| `merge` | 创建合并提交 |
| `squash` | 压缩为单个提交 |
| `rebase` | 变基合并 |

---

## CI 失败分析

### 解析 CI 日志

```typescript
import { parseCIFailure } from "./runtime/integrations/pr-provider";

const failure = parseCIFailure(rawLogContent);
// 返回：
// {
//   ci_provider: string,
//   job_name: string,
//   error_message: string,
//   affected_files: string[],
//   failure_type: "build" | "test" | "lint" | "type_check" | "deploy" | "unknown"
// }
```

支持的失败类型自动检测：
- **test**: 检测到 `FAIL` + `test`/`spec` 关键词
- **type_check**: 检测到 `error TS` 或 `type error`
- **lint**: 检测到 `lint`/`eslint`/`ruff`
- **build**: 检测到 `build`/`compile`

### Run Mapping

通过 `RunMappingRegistry` 关联 Run、Issue、PR 和 CI：

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

// 查询
const mapping = registry.getByPR(123);
const mapping = registry.getByIssue(42);
```

---

## 事件总线订阅

### 基本订阅

```typescript
import { EventBus } from "./runtime/observability/event-bus";

const bus = new EventBus();

// 订阅特定事件
bus.on("task_completed", (event) => {
  console.log(`任务完成: ${event.task_id}`);
});

// 订阅所有事件
bus.on("*", (event) => {
  console.log(`[${event.type}] ${JSON.stringify(event.payload)}`);
});
```

### 支持的事件类型

共 38 种事件类型，分为以下类别：

| 类别 | 事件 |
|------|------|
| 任务生命周期 | graph_created, task_ready, task_dispatched, task_completed, task_failed, task_retrying |
| 验证/门禁 | verification_started/passed/blocked, gate_evaluation_started, gate_passed, gate_blocked |
| 模型路由 | model_escalated, model_downgraded, downgrade_triggered |
| 批次 | batch_started, batch_completed |
| Session/Run | session_started/completed, run_created/planned/started/completed/failed/cancelled |
| 审批/治理 | approval_requested/granted/denied |
| 策略 | policy_evaluated, policy_violated |
| 所有权 | ownership_checked, ownership_violated |
| 预算 | budget_consumed, budget_exceeded |
| PR/CI | pr_created, pr_reviewed, pr_merged, ci_failure_detected |
| 人工 | human_feedback_received |

### 持久化事件

使用 `PersistentEventBusAdapter` 自动将事件写入审计日志：

```typescript
import { PersistentEventBusAdapter } from "./runtime/persistence/session-persistence";

const adapter = new PersistentEventBusAdapter(auditTrail);
adapter.connectToEventBus(eventBus);
// 所有事件自动持久化到 AuditTrail
```

---

## 自定义 Gate 实现

### 实现 SingleGateEvaluator 接口

```typescript
import type { SingleGateEvaluator, GateInput } from "./runtime/gates/gate-system";
import type { GateResult, GateType } from "./runtime/schemas/ga-schemas";

class MyCustomGateEvaluator implements SingleGateEvaluator {
  type: GateType = "review"; // 使用已有类型或扩展

  async evaluate(input: GateInput): Promise<GateResult> {
    const findings = [];

    // 自定义验证逻辑
    if (/* 你的检查条件 */) {
      findings.push({
        severity: "error",
        message: "自定义检查未通过",
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
        summary: passed ? "自定义 gate 通过" : "自定义 gate 未通过",
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

### 注册自定义 Gate

```typescript
const gateSystem = new GateSystem();
gateSystem.registerEvaluator(new MyCustomGateEvaluator());
```

### 内置 Gate 列表

| Gate | 类 | 阻断 | 层级 | 说明 |
|------|----|------|------|------|
| test | TestGateEvaluator | 是 | task, run | 测试通过率检查 |
| lint_type | LintTypeGateEvaluator | 是 | task, run | Lint 和类型检查 |
| review | ReviewGateEvaluator | 否 | task, run, pr | 代码审查 |
| security | SecurityGateEvaluator | 是 | run, pr | 安全扫描（敏感文件检测） |
| coverage | CoverageGateEvaluator | 否 | run, pr | 测试覆盖率 |
| policy | PolicyGateEvaluator | 是 | task, run | 策略合规 |
| documentation | DocumentationGateEvaluator | 否 | run, pr | 文档完整性 |
| release_readiness | ReleaseReadinessGateEvaluator | 是 | run | 发布就绪检查 |

---

## 自定义 Worker Adapter

### 实现 WorkerAdapter 接口

```typescript
import type { WorkerAdapter } from "./runtime/engine/orchestrator-runtime";
import type { WorkerInput, WorkerOutput } from "./runtime/orchestrator/role-contracts";

class MyWorkerAdapter implements WorkerAdapter {
  async execute(input: WorkerInput): Promise<WorkerOutput> {
    // 1. 将 TaskContract 转换为 Worker 可执行的指令
    const contract = input.contract;

    // 2. 执行任务（例如调用 Claude Code 子 Agent）
    // ...

    // 3. 返回结构化输出
    return {
      task_id: contract.task_id,
      status: "ok",
      summary: "任务完成",
      modified_paths: ["src/module.ts"],
      artifacts: [],
      tokens_used: 1500,
    };
  }
}
```

### Worker 能力注册

通过 `CapabilityRegistry` 注册 Worker 能力：

```typescript
import { createDefaultCapabilityRegistry } from "./runtime/workers/worker-runtime";

const registry = createDefaultCapabilityRegistry();

// 注册自定义能力
registry.register({
  id: "my_custom_capability",
  name: "自定义能力",
  description: "执行自定义操作",
  task_types: ["custom-task"],
  required_tools: ["Read", "Write", "Bash"],
  recommended_tier: "tier-2",
  applicable_phases: ["implementation"],
});
```

内置能力包括：
- **code_implementation**: 代码实现（tier-2）
- **test_writing**: 测试编写（tier-2）
- **code_review**: 代码审查（tier-3）
- **documentation**: 文档编写（tier-1）
- **lint_fix**: Lint 修复（tier-1）
- **architecture_design**: 架构设计（tier-3）

### Worker 执行控制

`WorkerExecutionController` 提供：
- **超时控制**：默认 300,000ms（5 分钟）
- **路径沙箱**：限制 Worker 可修改的文件范围
- **工具策略**：允许/禁止特定工具（默认禁止 `TaskStop`、`EnterWorktree`）
- **能力验证**：检查 TaskContract 必要字段

---

## Hook 系统

### Hook 生命周期阶段

| 阶段 | 标识 | 触发时机 |
|------|------|---------|
| 规划前 | `pre_plan` | 意图分析开始前 |
| 规划后 | `post_plan` | 任务图构建完成后 |
| 派发前 | `pre_dispatch` | Worker 派发开始前 |
| 派发后 | `post_dispatch` | Worker 执行完成后 |
| 验证前 | `pre_verify` | Gate 评估开始前 |
| 验证后 | `post_verify` | Gate 评估完成后 |
| 合并前 | `pre_merge` | Merge Guard 检查前 |
| 合并后 | `post_merge` | 合并完成后 |
| PR 前 | `pre_pr` | PR 创建前 |
| PR 后 | `post_pr` | PR 创建后 |

### 注册 Hook

```typescript
import { HookRegistry } from "./runtime/capabilities/capability-registry";

const hookRegistry = new HookRegistry();

hookRegistry.register({
  id: "my-hook",
  name: "自定义 Hook",
  phase: "post_dispatch",
  priority: 10,
  enabled: true,
  handler: async (context) => {
    // 自定义逻辑
    console.log(`Run ${context.run_id} 派发完成`);
    return { continue: true, message: "Hook 执行成功" };
  },
});
```

### Instruction Pack

通过 `InstructionRegistry` 注入上下文指令：

```typescript
import { InstructionRegistry } from "./runtime/capabilities/capability-registry";

const registry = new InstructionRegistry();

registry.register({
  id: "org-coding-standards",
  name: "组织编码规范",
  scope: { type: "org", org_id: "my-org" },
  priority: 1,
  instructions: [
    { type: "coding", content: "使用 TypeScript strict 模式" },
    { type: "testing", content: "测试覆盖率不低于 80%" },
  ],
});
```
