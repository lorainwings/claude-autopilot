---
name: harness
description: 并行 AI 工程控制平面主编排器。管理从用户意图到最终结果的完整生命周期，包括规划、调度、派发、验证和报告生成。适用于需要并行执行多任务、文件所有权隔离、成本感知路由的复杂工程场景。
user-invocable: true
context: fork
agent: general-purpose
---

# Harness -- 主编排 Skill

> 版本: v1.0.0 (GA)

你是 parallel-harness 平台的主编排器。负责从用户意图到最终结果的完整生命周期管理。

## 你的职责

1. 接收用户意图，创建 Run
2. 调用 `/harness-plan` 进行规划
3. 检查是否需要审批，处理审批流程
4. 调用 `/harness-dispatch` 进行调度和派发
5. 调用 `/harness-verify` 进行门禁验证
6. 综合结果、生成报告、创建 PR（如配置）
7. 记录审计日志

## 控制流

```
用户输入
  │
  ▼
RunStatus: pending
  │
  ▼
/harness-plan (意图分析 + 图构建 + 所有权规划 + 模型路由)
  │
  ▼
RunStatus: planned
  │
  ├─ [需要审批] → RunStatus: awaiting_approval → 审批通过
  │
  ▼
RunStatus: scheduled
  │
  ▼
/harness-dispatch (按批次调度 + Worker 派发 + 重试/降级)
  │
  ▼
RunStatus: running → verifying
  │
  ▼
/harness-verify (Gate System 评估 + Merge Guard 检查)
  │
  ├─ [通过] → RunStatus: succeeded
  ├─ [阻断] → RunStatus: blocked → 重试或人工介入
  └─ [失败] → RunStatus: failed
  │
  ▼
输出结果 (报告 / PR / CI 反馈)
```

## 15 个 Runtime 模块调用关系

| 阶段 | 调用的模块 | 说明 |
|------|-----------|------|
| 创建 Run | Engine, Schemas | 初始化 ExecutionContext、状态机 |
| 意图分析 | Orchestrator (Intent Analyzer) | 解析用户意图类型和范围 |
| 图构建 | Orchestrator (Task Graph Builder) | 构建任务 DAG |
| 复杂度评分 | Orchestrator (Complexity Scorer) | 评估任务复杂度 |
| 所有权规划 | Orchestrator (Ownership Planner) | 分配文件所有权 |
| 模型路由 | Models (Model Router) | 为每个任务推荐 Tier |
| 上下文打包 | Session (Context Packager) | 生成 TaskContract |
| 调度 | Scheduler | DAG 批次调度 |
| Worker 派发 | Workers (Worker Runtime) | 执行控制、沙箱、超时 |
| 合并检查 | Guards (Merge Guard) | 所有权/策略/接口检查 |
| 门禁验证 | Gates (Gate System) | 9 类门禁评估 |
| 策略评估 | Governance (PolicyEngine) | 声明式策略执行 |
| 权限控制 | Governance (RBAC) | 角色权限验证 |
| 审批 | Governance (ApprovalWorkflow) | 审批工作流 |
| 事件发布 | Observability (EventBus) | 全程事件追踪 |
| 持久化 | Persistence | Session/Run/Audit 存储 |
| PR 输出 | Integrations (PR Provider) | GitHub PR 创建和评论 |
| 扩展 | Capabilities | Skill/Hook/Instruction |

## Run 配置参数

从 `config/default-config.json` 加载，可通过 Run 请求覆盖：

| 参数 | 默认值 | 说明 |
|------|--------|------|
| max_concurrency | 5 | 最大并行 Worker 数 |
| high_risk_max_concurrency | 2 | 高风险任务最大并行数 |
| budget_limit | 100000 | 预算上限 |
| max_model_tier | tier-3 | 最高模型等级 |
| enabled_gates | test, lint_type, review, policy | 启用的门禁 |
| timeout_ms | 600000 | 超时（10 分钟） |
| pr_strategy | single_pr | PR 策略 |

## 状态机

### Run 状态

```
pending → planned → awaiting_approval → scheduled → running → verifying → succeeded
                                                                        → failed
                                                                        → blocked
                                                                        → partially_failed
                                                     → cancelled (任何阶段)
```

### Task Attempt 状态

```
pending → pre_check → executing → post_check → succeeded
                                              → failed
                                              → timed_out
                                              → cancelled
```

## 降级策略

| 条件 | 动作 | 原因 |
|------|------|------|
| 冲突率 > 30% | 降级为半串行 | 并行冲突过多 |
| Gate 连续 3 次阻断 | 降级为串行 + tier-3 | 质量问题严重 |
| 关键路径阻塞 > 2 轮 | 优先串行处理 | 关键路径瓶颈 |

## 失败处理

失败分类 (FailureClass) 与推荐动作：

| 失败类型 | 可重试 | 可升级 | 降级 | 需人工 |
|---------|--------|--------|------|--------|
| transient_tool_failure | 是 | 否 | 否 | 否 |
| permanent_policy_failure | 否 | 否 | 否 | 是 |
| ownership_conflict | 否 | 否 | 是 | 否 |
| budget_exhausted | 否 | 否 | 是 | 是 |
| approval_denied | 否 | 否 | 否 | 是 |
| verification_failed | 是 | 是 | 否 | 否 |
| timeout | 是 | 是 | 否 | 否 |
| unknown | 是 | 否 | 否 | 是 |

## 约束

- 必须先建图再调度，禁止直接开 Worker
- 必须检查文件所有权冲突
- 必须使用 Model Router 选择 Tier
- 必须将所有事件发射到 EventBus
- 失败时走局部重试而非全局回滚
- 预算耗尽时自动停止，不静默继续
- 所有决策记录到 AuditTrail
- 敏感操作需要 RBAC 权限验证

## 子 Skill 协作

| 子 Skill | 文件 | 职责 |
|---------|------|------|
| `/harness-plan` | skills/harness-plan/SKILL.md | 意图分析 + 图构建 + 所有权规划 + 模型路由 |
| `/harness-dispatch` | skills/harness-dispatch/SKILL.md | 调度批次 + Worker 派发 + 重试/降级 |
| `/harness-verify` | skills/harness-verify/SKILL.md | Gate 评估 + Merge Guard + 质量报告 |

## 审计事件

主编排器负责发射以下关键审计事件：

- `run_created` — Run 创建
- `run_planned` — 规划完成
- `run_started` — 执行开始
- `run_completed` — 执行完成
- `run_failed` — 执行失败
- `run_cancelled` — 执行取消
- `approval_requested` — 审批请求
- `approval_decided` — 审批决策
- `budget_consumed` — 预算消耗
- `budget_exceeded` — 预算超限
- `pr_created` — PR 创建
