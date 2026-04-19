---
name: autopilot-phase5.5-redteam
description: "[ONLY for autopilot orchestrator] Phase 5.5 Red Team Critic Agent injected between Phase 5 (Implement) and Phase 6 (Report). Enumerates 5 attack categories, generates executable reproducers, and writes redteam-report.json + tests/generated/redteam-*.sh."
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
    agent: ""                  # [必填] 推荐 OMC "code-reviewer" 或 Anthropic 官方 "red-team-critic"
```

### Sub-Agent 名称硬解析协议（强制）

1. 派发前主线程必须将 `config.phases.redteam.agent` 读取为字面量字符串
2. 调用 `bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/validate-agent-registry.sh "<resolved_name>"` 校验
3. 失败（exit 1）或字段为空 → 立即返回 blocked 信封，不派发
4. `_config_validator.py` 硬阻断该字段值为 `"Explore"`（Red Team 需 Write 反例文件到 `tests/generated/`，Explore 只读）
5. `auto-emit-agent-dispatch.sh` 的 Phase ≥ 2 兜底规则同样阻断 `subagent_type == Explore`

> 禁止将 `config.phases.redteam.agent` 字面量直接传入 Task —— LLM 看到字面量会启发式选 `general-purpose`，导致预设身份丢失。

### 派发模式（前台 Task）

主线程**必须以前台 Task 派发本 Skill 的 Critic Agent**（`run_in_background: false` 或省略该字段）：

- 原因：Phase 6 gate 判定依赖 `blocking_reproducers` 数值。后台派发会导致主线程在 Task 未完成时推进至 Phase 6，形成 gate bypass。
- 例外：仅内部 checkpoint-writer 子任务可用 `run_in_background: true`（与其他 Phase 对齐）。

## 阶段定位

| Phase | 名称 | 角色 |
|------|------|------|
| 5 | Implement | 实现产出 |
| **5.5** | **Red Team** | **本 Skill — 主动尝试破坏 Phase 5 产物** |
| 6 | Report | 测试报告 + 代码评审 + 质量扫描 |

> **注意**：Phase 5.5 是文档 phase 序号约定（运行时 phase 字段允许浮点 5.5），
> 主 SKILL (`skills/autopilot/SKILL.md`) 的 phase 序列变更需由编排合并方完成，
> 本 Skill 不直接修改主 SKILL，相关合并在主返回信封 `merge_hints` 中提示。

## 设计哲学

借鉴 **Cursor Vuln Hunter** 的"激进对抗"模式：
- 不是评分，而是**主动制造可执行反例**
- 任何无法被反例攻破的实现才被认为是稳健的
- 反例自动追加到 `tests/generated/redteam-*.sh`，形成回归网

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

### `openspec/changes/<change_name>/context/redteam-report.json`

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

### `tests/generated/redteam-<category>-<id>.sh`

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
