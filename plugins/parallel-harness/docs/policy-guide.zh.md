> [English](policy-guide.md) | 中文

# parallel-harness 策略配置指南

> 版本: v1.6.0 (GA) | 最后更新: 2026-04-09

## 概述

parallel-harness 采用**策略即代码**（Policy as Code）理念。所有安全、合规、预算约束通过 `PolicyEngine` 声明式配置，不在业务逻辑中硬编码。

策略配置文件位于 `config/default-policy.json`。

---

## Policy 规则结构

每条规则包含以下字段：

```json
{
  "rule_id": "path-001",
  "name": "禁止修改 .env 文件",
  "category": "sensitive_directory",
  "condition": {
    "type": "path_match",
    "params": { "pattern": ".env" }
  },
  "enforcement": "block",
  "enabled": true,
  "priority": 1
}
```

| 字段 | 类型 | 说明 |
|------|------|------|
| `rule_id` | string | 规则唯一标识（建议格式：`{类别}-{序号}`） |
| `name` | string | 规则名称（人类可读） |
| `category` | PolicyCategory | 规则类别（见下方） |
| `condition` | PolicyCondition | 条件表达式 |
| `enforcement` | PolicyEnforcement | 违规时的执行动作 |
| `enabled` | boolean | 是否启用 |
| `priority` | number | 优先级（越小越高） |

---

## 内置规则类别 (PolicyCategory)

| 类别 | 标识 | 说明 |
|------|------|------|
| 路径边界 | `path_boundary` | 限制 Worker 可修改的路径范围 |
| 模型等级上限 | `model_tier_limit` | 限制可使用的最高模型 Tier |
| 网络访问 | `network_access` | 控制网络访问权限 |
| 敏感目录 | `sensitive_directory` | 保护敏感文件和目录 |
| 需要审批 | `approval_required` | 定义需要人工审批的动作 |
| 最大并行度 | `max_concurrency` | 限制同时运行的 Worker 数 |
| 预算上限 | `budget_limit` | 预算阈值警告和阻断 |
| 工具限制 | `tool_restriction` | 限制 Worker 可使用的工具 |
| 数据分类 | `data_classification` | 数据敏感级别分类控制 |

---

## 条件表达式类型 (PolicyCondition)

### path_match — 路径匹配

匹配文件路径模式：

```json
{
  "type": "path_match",
  "params": { "pattern": ".env" }
}
```

支持的模式：
- 精确匹配：`".env"`
- 前缀匹配：`"credentials"`
- 通配符：`"*.key"`（支持 `*` 通配）

### budget_threshold — 预算阈值

当剩余预算低于阈值时触发：

```json
{
  "type": "budget_threshold",
  "params": { "threshold": 1000 }
}
```

`threshold` 为剩余 token 预算值。低于此值时触发规则。

### risk_level — 风险等级

基于任务风险等级触发：

```json
{
  "type": "risk_level",
  "params": { "min_risk": "critical" }
}
```

风险等级从低到高：`low` → `medium` → `high` → `critical`。
`min_risk` 表示触发规则的最低风险等级。

### model_tier — 模型等级

限制模型 Tier：

```json
{
  "type": "model_tier",
  "params": { "max_tier": "tier-3" }
}
```

### action_type — 动作类型

匹配特定操作类型：

```json
{
  "type": "action_type",
  "params": { "action": "autofix_push" }
}
```

### always — 始终匹配

无条件触发：

```json
{
  "type": "always",
  "params": {}
}
```

---

## 执行动作 (PolicyEnforcement)

| 动作 | 标识 | 行为 |
|------|------|------|
| 阻断 | `block` | 立即阻止执行，记录违规事件 |
| 警告 | `warn` | 允许继续执行，记录警告事件 |
| 审批 | `approve` | 暂停执行，等待人工审批 |
| 记录 | `log` | 仅记录到审计日志，不影响执行 |

**执行优先级**：当多条规则匹配同一操作时，按 `priority` 排序（越小越优先），取最严格的 `enforcement`。

---

## 默认策略配置

```json
{
  "version": "1.0.0",
  "rules": [
    {
      "rule_id": "path-001",
      "name": "禁止修改 .env 文件",
      "category": "sensitive_directory",
      "condition": { "type": "path_match", "params": { "pattern": ".env" } },
      "enforcement": "block",
      "enabled": true,
      "priority": 1
    },
    {
      "rule_id": "path-002",
      "name": "禁止修改 credentials 文件",
      "category": "sensitive_directory",
      "condition": { "type": "path_match", "params": { "pattern": "credentials" } },
      "enforcement": "block",
      "enabled": true,
      "priority": 1
    },
    {
      "rule_id": "budget-001",
      "name": "低预算警告",
      "category": "budget_limit",
      "condition": { "type": "budget_threshold", "params": { "threshold": 1000 } },
      "enforcement": "warn",
      "enabled": true,
      "priority": 5
    },
    {
      "rule_id": "risk-001",
      "name": "高风险任务需要审批",
      "category": "approval_required",
      "condition": { "type": "risk_level", "params": { "min_risk": "critical" } },
      "enforcement": "approve",
      "enabled": true,
      "priority": 3
    },
    {
      "rule_id": "tier-001",
      "name": "限制最高模型等级",
      "category": "model_tier_limit",
      "condition": { "type": "model_tier", "params": { "max_tier": "tier-3" } },
      "enforcement": "block",
      "enabled": false,
      "priority": 10
    }
  ]
}
```

---

## 示例配置

### 示例 1：禁止修改生产配置

```json
{
  "rule_id": "path-003",
  "name": "禁止修改生产环境配置",
  "category": "sensitive_directory",
  "condition": {
    "type": "path_match",
    "params": { "pattern": "config/production" }
  },
  "enforcement": "block",
  "enabled": true,
  "priority": 1
}
```

### 示例 2：大额预算消耗需审批

```json
{
  "rule_id": "budget-002",
  "name": "大额预算消耗需要审批",
  "category": "budget_limit",
  "condition": {
    "type": "budget_threshold",
    "params": { "threshold": 50000 }
  },
  "enforcement": "approve",
  "enabled": true,
  "priority": 2
}
```

### 示例 3：限制为低成本模型

```json
{
  "rule_id": "tier-002",
  "name": "仅允许 tier-1 模型",
  "category": "model_tier_limit",
  "condition": {
    "type": "model_tier",
    "params": { "max_tier": "tier-1" }
  },
  "enforcement": "block",
  "enabled": true,
  "priority": 10
}
```

### 示例 4：所有高风险操作需要审批

```json
{
  "rule_id": "risk-002",
  "name": "高风险任务需要审批",
  "category": "approval_required",
  "condition": {
    "type": "risk_level",
    "params": { "min_risk": "high" }
  },
  "enforcement": "approve",
  "enabled": true,
  "priority": 2
}
```

---

## 策略与 Gate System 的关系

策略规则通过 **Policy Gate** 在门禁阶段执行：

1. Worker 执行前：`pre_check` 阶段评估策略
2. Worker 执行后：`PolicyGateEvaluator` 在 Gate System 中评估
3. 合并前：`MergeGuard` 再次执行策略合规检查

Policy Gate 默认为 **blocking** 类型 — 策略违规将阻断流程。

---

## 自定义策略规则

在 `default-policy.json` 的 `rules` 数组中添加新规则即可。确保：

1. `rule_id` 全局唯一
2. `category` 使用已定义的类别
3. `condition.type` 使用已实现的条件类型
4. `priority` 设置合理（1-10，越小越优先）
5. 测试验证规则行为符合预期
