---
name: autopilot-phase5-5-redteam
description: "Use when the autopilot orchestrator has completed Phase 5 implementation and must run a Red Team adversarial critic pass before Phase 6 reporting begins, validating the implementation against attack scenarios. ONLY for autopilot orchestrator; not for direct user invocation."
user-invocable: false
---

# Autopilot Phase 5.5 — Red Team 防御性破坏

> **前置条件自检**：本 Skill 仅由 autopilot 编排主线程在 Phase 5 完成、Phase 6 启动之前派发。
> 非编排上下文请立即退出。

## Agent 配置（配置驱动，不硬编码）

Phase 5.5 的 Critic Agent **必须**从 `autopilot.config.yaml` 的 `phases.redteam.agent` 解析：

```yaml
phases:
  redteam:
    enabled: true              # 是否启用 Phase 5.5（默认 true）
    agent: ""                  # [必填] 推荐 code-reviewer 或 red-team-critic（参见配置文档）
```

### Sub-Agent 名称硬解析协议（强制）

见 CLAUDE.md §子 Agent 约束 第 10 条 + skills/autopilot-dispatch。

### 派发模式（前台 Task）

主线程**必须以前台 Task 派发本 Skill 的 Critic Agent**（`run_in_background: false` 或省略该字段）：

- 原因：Phase 6 gate 判定依赖 `blocking_reproducers` 数值。后台派发会导致主线程在 Task 未完成时推进至 Phase 6，形成 gate bypass。
- 例外：仅内部 checkpoint-writer 子任务可用 `run_in_background: true`（与其他 Phase 对齐）。

## 5 类破坏枚举

每次 Red Team 必须枚举以下 5 类，每类至少 1 个 reproducer：

| 类别 | 攻击思路 | reproducer 形式 |
|------|---------|----------------|
| **boundary** | 边界输入：空值、超长、Unicode 极端字符、负数、零、最大整数 | shell/python/ts 调用 + 断言异常 |
| **concurrency** | 并发竞态：双进程同时 write、并发 lock 获取 | `&` 后台 + flock 测试 |
| **state-pollution** | 状态污染：重复执行、跨 phase artifact 残留、断点后续跑 | 模拟 checkpoint 残留 |
| **dependency-regression** | 依赖回归：移除/降级 manifest 中依赖 | mock 依赖缺失 |
| **backward-incompat** | 向后不兼容：旧 schema/旧 envelope/旧 hook 协议 | 注入历史版本 fixture |

详细 prompt 范式见 `references/redteam-prompts.md`。

## 输出契约

### 标准 JSON 信封（Critic Agent 返回）

子 Agent 返回到主线程的信封必须遵循 autopilot 标准格式 + Phase 5.5 专用 `redteam` 字段：

```json
{
  "status": "ok|warning|blocked",
  "summary": "枚举 5 类破坏，N 个 reproducer，M 个 blocking",
  "artifacts": [
    "openspec/changes/<change_name>/context/redteam-report.json",
    "tests/generated/redteam-boundary-001.sh"
  ],
  "redteam": {
    "total_reproducers": 5,
    "blocking_reproducers": 0,
    "recommendation": "proceed_to_phase6"
  }
}
```

校验规则（`runtime/scripts/validate-json-envelope.sh` Phase 5.5 分支）：

- `status` ∈ `{ok, warning, blocked}`
- `redteam.total_reproducers` 为非负整数
- `redteam.blocking_reproducers` 为非负整数 ≤ `total_reproducers`
- `redteam.recommendation` ∈ `{proceed_to_phase6, block_until_fixed}`
- `blocking_reproducers > 0` 时 `recommendation` 必须为 `block_until_fixed`，且 `status` 必须为 `blocked`（否则信封 invalid → L2 阻断）

### 报告文件：redteam-report.json

> **契约关系**：报告 = 真源；信封 = 派生。下方 `redteam-report.json` 为 Phase 5.5 输出真源；上方 Critic Agent 返回的 JSON 信封中的 `redteam.*` 字段由本报告聚合而成，不得独立编辑。

路径：`openspec/changes/<change_name>/context/redteam-report.json`

```json
{
  "phase": 5.5,
  "generated_at": "2026-04-18T10:45:00Z",
  "categories": [
    {
      "category": "boundary",
      "reproducers": [
        {
          "id": "RT-BOUNDARY-001",
          "description": "空字符串作为 change_name 触发路径解析崩溃",
          "reproducer_path": "tests/generated/redteam-boundary-001.sh",
          "expected_failure_mode": "exit code != 0 / stack trace",
          "actual_outcome": "passed_unexpectedly | failed_as_expected | crashed",
          "blocks_phase6": true
        }
      ]
    }
  ],
  "total_reproducers": 5,
  "blocking_reproducers": 0,
  "recommendation": "proceed_to_phase6 | block_until_fixed"
}
```

### 复现脚本：tests/generated/redteam-*.sh

路径模板：`tests/generated/redteam-<category>-<id>.sh`

每个 reproducer 必须可独立执行，遵守仓库测试约定（`set -uo pipefail`、使用 `_test_helpers.sh`）。

## 阻断决策

`blocking_reproducers > 0` ⇒ `recommendation=block_until_fixed`，编排主线程拒绝进入 Phase 6。

被攻破的反例必须：
1. 由 Phase 5 重新修复
2. reproducer 转为正式测试入库 `tests/`（去掉 `generated/` 前缀）
3. 在 `docs/regression-vault/` 创建对应条目

## 与其他 Skill 的关系

| Skill | 关系 |
|------|------|
| `autopilot-risk-scanner` | risk-scanner 是常规 phase 评分；本 Skill 是激进对抗，二者互补 |
| `autopilot-gate` | Phase 6 gate 必须读取本报告，blocking_reproducers>0 时拦截 |
| Phase 6 rubric `P6-FEAT-006` | 显式校验本报告中所有 reproducer 是否已 GREEN |
