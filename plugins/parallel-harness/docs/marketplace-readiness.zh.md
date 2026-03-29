> [English](marketplace-readiness.md) | 中文

# parallel-harness 市场接入准备

> 版本: v1.1.2 (GA) | 最后更新: 2026-03-20

## 当前状态

**GA（正式发布）** — 所有核心模块已实现并通过测试，可以注册到 marketplace。

## 市场接入条件检查

| 条件 | 状态 | 说明 |
|------|------|------|
| plugin.json 存在 | 已完成 | 插件配置文件就绪 |
| dist/ 构建链路 | 已完成 | `bash tools/build-dist.sh` |
| README.md | 已完成 | 英文说明文档 |
| README.zh.md | 已完成 | 中文说明文档（GA 级） |
| 核心运行时可用 | 已完成 | 15 个 runtime 模块全部实现 |
| 单元测试通过 | 已完成 | 219 pass / 0 fail / 499 expect() |
| Skills 骨架 | 已完成 | 4 个 Skill（harness / plan / dispatch / verify） |
| Engine 统一入口 | 已完成 | OrchestratorRuntime 完整生命周期管理 |
| Task Graph | 已完成 | DAG 构建、验证、依赖解析 |
| Ownership Planner | 已完成 | 路径隔离、冲突检测、降级建议 |
| Scheduler | 已完成 | DAG 批次调度、关键路径优先 |
| Model Router | 已完成 | 三层 Tier 路由、失败升级 |
| Context Packager | 已完成 | 最小上下文包、TaskContract |
| Worker Runtime | 已完成 | 执行控制器、沙箱、超时、重试、降级 |
| Gate System | 已完成 | 9 类门禁评估器、可阻断、可扩展 |
| Merge Guard | 已完成 | 所有权/策略/接口三层检查 |
| Governance | 已完成 | RBAC（4 角色/12 权限）、审批、人工介入 |
| Persistence | 已完成 | Session/Run/Audit Store、文件适配器 |
| EventBus | 已完成 | 38 种事件类型、通配订阅、持久化适配 |
| PR/CI Integration | 已完成 | GitHub PR 创建/Review/Check/Merge、CI 失败解析 |
| Capabilities | 已完成 | Skill/Hook/Instruction 注册 |
| GA Schemas | 已完成 | 统一数据契约、版本控制 |
| 运维文档 | 已完成 | operator-guide.zh.md |
| 策略文档 | 已完成 | policy-guide.zh.md |
| 集成文档 | 已完成 | integration-guide.zh.md |
| 故障排查文档 | 已完成 | troubleshooting.zh.md |
| 发布检查清单 | 已完成 | release-checklist.zh.md |
| 示例文档 | 已完成 | examples/basic-flow.zh.md |

## marketplace.json 变更

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

## 版本里程碑

| 版本 | 里程碑 | 状态 |
|------|--------|------|
| v0.1.0 | MVP — 核心 Schema + 调度器 + 路由器 | 已完成 |
| v0.5.0 | Beta — Worker Runtime + Gate System + Persistence | 已完成 |
| v1.0.0 | GA — 全部 15 模块 + 219 测试 + 完整文档 | 已完成 |

## 与 spec-autopilot 产品定位

| 维度 | spec-autopilot | parallel-harness |
|------|---------------|-----------------|
| 定位 | 规范驱动交付 | 并行工程控制面 |
| 成熟度 | GA (v5.x) | GA (v1.0.0) |
| 核心机制 | 8 阶段流水线 | 任务 DAG + 动态调度 |
| 治理 | Hook 脚本 | RBAC + 审批 + 策略引擎 |
| 目标用户 | 流程驱动团队 | 复杂工程团队 |
