> [English](admin-guide.md) | 中文

# parallel-harness 管理员指南

> 版本: v1.8.1 (GA) | 适用角色: 平台管理员、组织所有者

## 概述

本指南面向负责配置和管理 parallel-harness 插件的平台管理员。涵盖 RBAC 配置、策略管理、审批流程、预算控制和系统维护。

## RBAC 角色管理

### 内置角色

| 角色 | 权限 | 典型使用者 |
|------|------|-----------|
| admin | 全部 12 项权限 | 平台管理员 |
| developer | run.create/cancel/retry/view, audit.view | 开发工程师 |
| reviewer | run.view, task.approve_*, gate.override, audit.view | 代码审查者 |
| viewer | run.view, audit.view | 只读观察者 |

### 权限清单

| 权限 | 说明 |
|------|------|
| run.create | 创建新的执行 Run |
| run.cancel | 取消运行中的 Run |
| run.retry | 重试失败的任务 |
| run.view | 查看 Run 状态和详情 |
| task.approve_model_upgrade | 批准模型升级请求 |
| task.approve_sensitive_write | 批准敏感路径写入 |
| task.approve_autofix_push | 批准 autofix 推送 |
| gate.override | 覆盖 Gate 阻断决策 |
| policy.manage | 管理策略规则 |
| config.manage | 管理运行时配置 |
| audit.view | 查看审计日志 |
| audit.export | 导出审计报告 |

### 自定义角色

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

## 策略配置

### 策略规则结构

策略通过 `config/default-policy.json` 定义。每条规则包含：

- `rule_id`: 唯一标识
- `name`: 规则名称
- `category`: 类别（path_boundary/model_tier_limit/budget_limit 等）
- `condition`: 触发条件
- `enforcement`: 违规动作（block/warn/approve/log）

### 条件类型

| 条件类型 | 说明 | 参数 |
|---------|------|------|
| always | 始终匹配 | 无 |
| path_match | 路径匹配 | pattern: string |
| budget_threshold | 预算阈值 | threshold: number |
| risk_level | 风险等级 | min_risk: string |
| model_tier | 模型等级 | max_tier: string |
| action_type | 动作类型 | actions: string[] |

### 示例：禁止写入敏感目录

```json
{
  "rule_id": "pol-sensitive-dir",
  "name": "禁止写入敏感目录",
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

## 审批流程

### 自动审批

在 `RunConfig.auto_approve_rules` 中配置自动审批规则：

- `"all"`: 自动批准所有请求
- `"execute_with_conflicts"`: 自动批准冲突执行
- 具体 action 名称: 精确匹配

### 人工审批

未匹配自动规则的请求将进入 pending 状态。通过以下方式处理：

1. **控制面 API**: `POST /api/runs/{id}/approve/{approvalId}`
2. **Web GUI**: Run 详情页的审批面板
3. **编程接口**: `runtime.approveAndResume(runId, approvalId, decidedBy)`

## 预算控制

### 预算配置

```json
{
  "budget_limit": 100000,
  "max_model_tier": "tier-3"
}
```

- `budget_limit`: 单次 Run 的最大成本预算（相对值）
- 成本计算: `(tokens / 1000) * tier_cost_rate`
  - tier-1: 1 / tier-2: 5 / tier-3: 25

### 预算耗尽行为

- 预算耗尽时自动停止执行
- 不会静默继续消耗
- 可通过 `budget_threshold` 策略提前触发审批

## 系统维护

### 数据持久化

默认使用本地文件持久化（`FileStore`），数据存储在：
- Session: `.parallel-harness/sessions/`
- Runs: `.parallel-harness/runs/`
- Audit: `.parallel-harness/audit/`

### 审计导出

```typescript
const auditTrail = new AuditTrail();
// JSON 导出
const jsonReport = await auditTrail.export("json", { run_id: "run_xxx" });
// CSV 导出
const csvReport = await auditTrail.export("csv");
```

### 事件回放

```typescript
const replay = new ReplayEngine(auditTrail);
const timeline = await replay.getReplayTimeline("run_xxx");
const resumePoint = await replay.getResumePoint("run_xxx");
```

## 控制面 API

### 端点列表

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | /api/runs | 获取 Run 列表 |
| GET | /api/runs/{id} | 获取 Run 详情 |
| GET | /api/runs/{id}/audit | 获取审计日志 |
| GET | /api/runs/{id}/gates | 获取 Gate 结果 |
| POST | /api/runs/{id}/cancel | 取消 Run |
| POST | /api/runs/{id}/tasks/{taskId}/retry | 重试任务 |
| POST | /api/runs/{id}/approve/{approvalId} | 批准审批 |
| POST | /api/runs/{id}/reject/{approvalId} | 拒绝审批 |

### 启动控制面

```bash
# 通过 skill 启动
# 或直接调用
bun run runtime/server/control-plane.ts
```

默认端口: 3847

## 升级指南

### v0.x → v1.0.0

1. 备份现有配置
2. 更新 `package.json` 版本
3. 运行 `bun install`
4. 检查 `config/default-config.json` 新增字段
5. 运行 `bun test` 验证兼容性
6. 更新策略文件中的 schema_version

### 数据迁移

v1.0.0 引入了版本化 schema（`schema_version: "1.0.0"`）。旧版本数据将在读取时自动升级。
