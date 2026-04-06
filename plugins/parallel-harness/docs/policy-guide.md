> **[中文版](policy-guide.zh.md)** | English (default)

# parallel-harness Policy Configuration Guide

> Version: v1.3.1 (GA) | Last updated: 2026-03-20

## Overview

parallel-harness adopts a **Policy as Code** approach. All security, compliance, and budget constraints are declaratively configured through the `PolicyEngine`, rather than being hardcoded in business logic.

The policy configuration file is located at `config/default-policy.json`.

---

## Policy Rule Structure

Each rule contains the following fields:

```json
{
  "rule_id": "path-001",
  "name": "Block modifications to .env files",
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

| Field | Type | Description |
|-------|------|-------------|
| `rule_id` | string | Unique rule identifier (recommended format: `{category}-{number}`) |
| `name` | string | Rule name (human-readable) |
| `category` | PolicyCategory | Rule category (see below) |
| `condition` | PolicyCondition | Condition expression |
| `enforcement` | PolicyEnforcement | Action taken on violation |
| `enabled` | boolean | Whether the rule is enabled |
| `priority` | number | Priority (lower value = higher priority) |

---

## Built-in Rule Categories (PolicyCategory)

| Category | Identifier | Description |
|----------|-----------|-------------|
| Path Boundary | `path_boundary` | Restrict which paths a Worker can modify |
| Model Tier Limit | `model_tier_limit` | Restrict the highest model tier allowed |
| Network Access | `network_access` | Control network access permissions |
| Sensitive Directory | `sensitive_directory` | Protect sensitive files and directories |
| Approval Required | `approval_required` | Define actions that require manual approval |
| Max Concurrency | `max_concurrency` | Limit the number of simultaneously running Workers |
| Budget Limit | `budget_limit` | Budget threshold warnings and blocking |
| Tool Restriction | `tool_restriction` | Restrict which tools Workers can use |
| Data Classification | `data_classification` | Data sensitivity level classification controls |

---

## Condition Expression Types (PolicyCondition)

### path_match -- Path Matching

Matches file path patterns:

```json
{
  "type": "path_match",
  "params": { "pattern": ".env" }
}
```

Supported patterns:
- Exact match: `".env"`
- Prefix match: `"credentials"`
- Wildcard: `"*.key"` (supports `*` wildcard)

### budget_threshold -- Budget Threshold

Triggers when remaining budget falls below the threshold:

```json
{
  "type": "budget_threshold",
  "params": { "threshold": 1000 }
}
```

`threshold` is the remaining token budget value. The rule triggers when the budget drops below this value.

### risk_level -- Risk Level

Triggers based on task risk level:

```json
{
  "type": "risk_level",
  "params": { "min_risk": "critical" }
}
```

Risk levels from lowest to highest: `low` -> `medium` -> `high` -> `critical`.
`min_risk` specifies the minimum risk level that triggers the rule.

### model_tier -- Model Tier

Restricts model tier:

```json
{
  "type": "model_tier",
  "params": { "max_tier": "tier-3" }
}
```

### action_type -- Action Type

Matches specific action types:

```json
{
  "type": "action_type",
  "params": { "action": "autofix_push" }
}
```

### always -- Always Match

Triggers unconditionally:

```json
{
  "type": "always",
  "params": {}
}
```

---

## Enforcement Actions (PolicyEnforcement)

| Action | Identifier | Behavior |
|--------|-----------|----------|
| Block | `block` | Immediately halt execution, record the violation event |
| Warn | `warn` | Allow execution to continue, record a warning event |
| Approve | `approve` | Pause execution, await manual approval |
| Log | `log` | Record to audit log only, no impact on execution |

**Enforcement priority**: When multiple rules match the same action, they are sorted by `priority` (lower value first), and the strictest `enforcement` is applied.

---

## Default Policy Configuration

```json
{
  "version": "1.0.0",
  "rules": [
    {
      "rule_id": "path-001",
      "name": "Block modifications to .env files",
      "category": "sensitive_directory",
      "condition": { "type": "path_match", "params": { "pattern": ".env" } },
      "enforcement": "block",
      "enabled": true,
      "priority": 1
    },
    {
      "rule_id": "path-002",
      "name": "Block modifications to credentials files",
      "category": "sensitive_directory",
      "condition": { "type": "path_match", "params": { "pattern": "credentials" } },
      "enforcement": "block",
      "enabled": true,
      "priority": 1
    },
    {
      "rule_id": "budget-001",
      "name": "Low budget warning",
      "category": "budget_limit",
      "condition": { "type": "budget_threshold", "params": { "threshold": 1000 } },
      "enforcement": "warn",
      "enabled": true,
      "priority": 5
    },
    {
      "rule_id": "risk-001",
      "name": "Critical-risk tasks require approval",
      "category": "approval_required",
      "condition": { "type": "risk_level", "params": { "min_risk": "critical" } },
      "enforcement": "approve",
      "enabled": true,
      "priority": 3
    },
    {
      "rule_id": "tier-001",
      "name": "Restrict maximum model tier",
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

## Example Configurations

### Example 1: Block Modifications to Production Config

```json
{
  "rule_id": "path-003",
  "name": "Block modifications to production config",
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

### Example 2: Require Approval for Large Budget Consumption

```json
{
  "rule_id": "budget-002",
  "name": "Large budget consumption requires approval",
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

### Example 3: Restrict to Low-Cost Models

```json
{
  "rule_id": "tier-002",
  "name": "Allow tier-1 models only",
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

### Example 4: Require Approval for All High-Risk Operations

```json
{
  "rule_id": "risk-002",
  "name": "High-risk tasks require approval",
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

## Relationship Between Policies and the Gate System

Policy rules are enforced through the **Policy Gate** during the gating phase:

1. Before Worker execution: Policies are evaluated during the `pre_check` phase
2. After Worker execution: `PolicyGateEvaluator` evaluates within the Gate System
3. Before merging: `MergeGuard` performs another policy compliance check

The Policy Gate is **blocking** by default -- policy violations will halt the pipeline.

---

## Custom Policy Rules

Add new rules to the `rules` array in `default-policy.json`. Ensure that:

1. `rule_id` is globally unique
2. `category` uses a defined category
3. `condition.type` uses an implemented condition type
4. `priority` is set appropriately (1-10, lower = higher priority)
5. The rule behavior is tested and verified as expected
