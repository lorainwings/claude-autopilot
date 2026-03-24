> [English](FAQ.md) | 中文

# parallel-harness 常见问题 (FAQ)

## 基本概念

### Q: parallel-harness 和 spec-autopilot 有什么区别？

| 维度 | spec-autopilot | parallel-harness |
|------|---------------|-----------------|
| 定位 | 规范驱动交付编排 | AI 软件工程控制面 |
| 流程模型 | 8 阶段固定 pipeline | 任务图 DAG 动态调度 |
| 并行方式 | 阶段内串行 | 跨任务并行 |
| 质量控制 | 三层门禁 checkpoint | 9 类 Gate System |
| 模型使用 | 单一或人工选择 | 自动路由 + 成本控制 |

两者互补：spec-autopilot 负责规范驱动交付，parallel-harness 负责并行工程治理。

### Q: 什么时候应该使用 parallel-harness？

- 多模块多文件需要并行修改的项目
- 需要成本控制和模型路由的场景
- 需要 RBAC、审批、审计等治理能力的团队
- 需要 PR/CI 闭环集成的工作流

### Q: 最低运行要求是什么？

- Bun v1.2+
- TypeScript 5.x
- `claude` CLI（Worker 执行需要）
- `gh` CLI（GitHub PR 集成需要）

## 执行与调度

### Q: 任务是如何并行执行的？

1. 用户输入 → 意图分析 → 构建任务 DAG
2. 所有权规划 → 为每个任务分配独占文件路径
3. DAG 批次调度 → 无依赖任务可并行
4. Worker 派发 → 每个 Worker 在沙箱内执行
5. Gate 验证 → 阻断不合格输出

### Q: 冲突时会发生什么？

- **路径冲突**: 后序任务的冲突路径从独占区移到共享读
- **高风险冲突**: 标记为不可解决，触发审批流程
- **冲突率 > 30%**: 自动降级为半串行模式
- **关键路径阻塞**: 优先串行处理

### Q: Worker 执行失败怎么办？

失败会被分类为 9 种类型，每种有不同的后续动作：

| 失败类型 | 可重试 | 可升级 | 需人工 |
|---------|--------|--------|--------|
| transient_tool_failure | ✅ | - | - |
| verification_failed | ✅ | ✅ | - |
| timeout | ✅ | ✅ | - |
| permanent_policy_failure | - | - | ✅ |
| ownership_conflict | - | - | - |
| budget_exhausted | - | - | ✅ |

## 模型路由

### Q: 模型 Tier 是如何选择的？

1. 根据任务复杂度选择基础 Tier（trivial/low → tier-1, medium → tier-2, high/extreme → tier-3）
2. 高风险任务自动提升一级
3. 每次重试自动升级 Tier
4. 任务类型提示可覆盖选择

### Q: 如何控制成本？

- 设置 `budget_limit` 限制单次 Run 预算
- 低复杂度任务自动使用低成本 Tier
- 预算耗尽时自动停止执行
- 成本账本记录每次 attempt 的消耗

## Gate 系统

### Q: 哪些 Gate 是阻断性的？

默认配置下：

- **阻断性 (blocking)**: test, lint_type, security, policy, release_readiness
- **非阻断性**: review, perf, coverage, documentation

### Q: 如何跳过 Gate？

1. 通过 `RunConfig.enabled_gates` 排除特定 Gate
2. admin 角色可以通过 `gate.override` 权限覆盖 Gate 决策
3. 不建议在生产环境禁用 security 和 policy Gate

## 治理

### Q: 审批被阻断的 Run 如何恢复？

```typescript
// 方式 1: 通过 API
await runtime.approveAndResume(runId, approvalId, "admin-user");

// 方式 2: 通过控制面
POST /api/runs/{id}/approve/{approvalId}

// 方式 3: 拒绝并终止
await runtime.rejectRun(runId, approvalId, "admin-user", "原因");
```

### Q: 如何查看审计日志？

```typescript
// 查询特定 Run
const events = await runtime.getAuditLog("run_xxx");

// 通过控制面
GET /api/runs/{id}/audit
```

## PR/CI 集成

### Q: 支持哪些 Git 平台？

当前支持 GitHub（通过 `gh` CLI）。接口层 (`PRProvider`) 已抽象，可扩展支持 GitLab、Bitbucket 等。

### Q: PR 创建失败会影响 Run 结果吗？

不会。PR 创建失败会记录审计事件但不阻断 Run 结果。这是有意设计，确保核心执行不受外部集成影响。

## 故障排查

### Q: `claude CLI 不可用` 怎么办？

Worker 会返回 `warning` 状态且无产出，最终标记为 `unsupported_capability` 失败。解决方案：
1. 确认 `claude` 命令在 PATH 中可用
2. 检查 Claude CLI 配置和认证
3. 或提供自定义 `WorkerAdapter` 实现

### Q: 测试为什么找不到测试文件？

确保测试文件命名包含 `.test.ts` 或 `.spec.ts` 后缀，并位于 `tests/` 目录下。运行 `bun test` 进行验证。

### Q: 如何调试 Gate 评估？

1. 查看 Run 的 Gate 结果: `GET /api/runs/{id}/gates`
2. 检查审计日志中的 `gate_passed` / `gate_blocked` 事件
3. Gate 结论包含结构化的 findings、risk 和 required_actions
