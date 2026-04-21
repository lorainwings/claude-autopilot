# Phase 1 挑战代理协议

> 本文件由 `phase1-requirements.md` 1.6 节和 `phase1-supplementary.md` 引用。
> 定义多轮决策循环中自动激活的视角转换机制。
> 参考 oh-my-claudecode Deep Interview 的 Challenge Agents 设计。

## 设计理念

标准决策循环的提问方向是"收集信息以填补空白"。但某些盲区不是信息空白，而是**认知偏差**——用户和 AI 都可能锁定在某个假设上，不断在同一方向深化而忽视其他可能性。

挑战代理通过在特定轮次**自动切换提问视角**，从不同角度审视已收集的需求，发现被忽视的假设、不必要的复杂性和不稳定的核心概念。

## 三种挑战代理

### 1. 反面论证代理（Contrarian）

**激活条件**: `current_round >= config.challenge_agents.contrarian_after_round`（默认第 4 轮）且 `clarity_score < clarity_threshold` 且 `"contrarian" NOT IN challenge_agents_used`

**目的**: 挑战核心假设，暴露未被质疑的前提条件。

**提问模板**:

```
## 反面论证（Contrarian Challenge）

在前 {n-1} 轮讨论中，以下假设被视为前提但从未被质疑：

{for each assumption in rp.assumptions}
**假设**: {assumption}
**反面提问**: 如果这个假设不成立呢？具体来说：
- 这个约束是真实的还是惯例性的？
- 是否有更简单的方案不需要这个前提？
- 如果放松这个约束，解决方案会怎样改变？
{end for}

请考虑以上问题，如果某些假设确实可以放松，我们可以简化方案。
```

**提问策略**:
- 从 `rp.assumptions` 和 `rp.decisions` 中提取已做的假设
- 每个假设构造一个"如果相反呢？"的问题
- 一次只问一个假设（遵循一次一问原则）
- 选择与**最弱清晰度维度**最相关的假设优先提问

**退出**: 提问完成后，标记 `challenge_agents_used.add("contrarian")`，恢复正常决策提问流程。

---

### 2. 简化者代理（Simplifier）

**激活条件**: `current_round >= config.challenge_agents.simplifier_after_round`（默认第 6 轮）且 `len(rp.scope) > 5`（范围条目过多）且 `"simplifier" NOT IN challenge_agents_used`

**目的**: 削减不必要的复杂性，收敛到最小可行范围。

**提问模板**:

```
## 范围简化（Simplifier Challenge）

当前需求包含 {len(rp.scope)} 个范围条目，讨论已进行 {n} 轮。
让我们审视是否所有条目都是 V1 必需的。

**当前范围**:
{for i, item in enumerate(rp.scope)}
{i+1}. {item}
{end for}

**问题**: 如果只能在第一个版本实现其中 {ceil(len(scope)*0.6)} 个，你会选择哪些？
其余可以作为 V2 规划。

选择标准建议：
- 哪些是核心用户路径（无此功能则产品无价值）？
- 哪些是增值功能（有则更好，无也可用）？
- 哪些有技术依赖（必须先做才能做其他）？
```

**提问策略**:
- 仅在 scope 条目 > 5 时激活（小范围无需简化）
- 展示所有 scope 条目，要求用户做优先级排序
- 将用户排除的条目移到 `non_goals` 或标记为 "V2"
- 一次一问：只要求做一次优先级排序

**退出**: 用户完成优先级选择后，更新 `rp.scope` 和 `rp.non_goals`，标记 `challenge_agents_used.add("simplifier")`。

---

### 3. 本体论代理（Ontologist）

**激活条件**: 以下任一满足，且 `"ontologist" NOT IN challenge_agents_used`:
  - `current_round >= config.challenge_agents.ontologist_after_round`（默认第 8 轮）且 clarity 连续 2 轮波动 ≤ 5%
  - 停滞检测触发（详见下方"停滞检测集成"章节）

**目的**: 稳定核心概念。当讨论"陷入泥潭"（清晰度不再提升），通常是因为核心概念本身还不稳定——用户对同一个东西用了不同的名字，或者把不同的东西当成了同一个。

**提问模板**:

```
## 核心概念澄清（Ontologist Challenge）

讨论已进行 {n} 轮，清晰度在过去 2 轮几乎没有变化（{prev_clarity}% → {current_clarity}%）。
这通常意味着我们需要回到基本面，先稳定核心概念。

**我从当前需求中识别到以下核心实体**:

| 实体 | 类型 | 当前定义 | 疑问 |
|------|------|---------|------|
{for entity in extracted_entities}
| {entity.name} | {entity.type} | {entity.definition} | {entity.question} |
{end for}

**关键问题**: 这些实体中，哪一个是整个系统的**核心**——如果去掉它，整个需求就不成立？

请确认：
1. 以上实体列表是否完整？是否有遗漏或多余？
2. 核心实体是哪个？
3. 实体之间的关系是否正确？
```

**实体提取规则**:
- 从 `rp.goal`、`rp.scope`、`rp.acceptance_criteria` 中提取名词/概念
- 排除通用词（"系统"、"用户"、"功能"、"页面"等）
- 每个实体记录：名称、类型（数据实体/服务/UI 组件/外部依赖）、当前定义、待澄清问题

**退出**: 用户确认核心实体后，更新 `rp.assumptions`（如有新发现），标记 `challenge_agents_used.add("ontologist")`。

---

## 状态追踪

在多轮循环中维护以下状态（不持久化，仅当前会话）：

```
challenge_state = {
    "challenge_agents_used": Set(),     # 已激活的代理模式
    "prev_clarity_score": null,         # 上一轮清晰度
    "consecutive_stagnant_rounds": 0,   # 连续停滞轮数
    "entities_snapshot": []             # 上一轮提取的实体（本体论追踪用）
}
```

## 激活优先级

当同一轮中多个代理的激活条件同时满足时，按以下优先级选择（每轮最多激活 1 个）：

1. **本体论**（最高优先级）— 停滞时最需要根本性视角转换
2. **简化者** — 范围膨胀需要及时收敛
3. **反面论证** — 常规增强性提问

## 停滞检测集成

```
# 在每轮决策循环末尾（评分计算后）执行
def check_stagnation(current_clarity, challenge_state):
    if challenge_state.prev_clarity_score is not None:
        delta = abs(current_clarity - challenge_state.prev_clarity_score)
        if delta <= 0.05:
            challenge_state.consecutive_stagnant_rounds += 1
        else:
            challenge_state.consecutive_stagnant_rounds = 0

    challenge_state.prev_clarity_score = current_clarity

    if challenge_state.consecutive_stagnant_rounds >= 2:
        if "ontologist" not in challenge_state.challenge_agents_used:
            return "activate_ontologist"
        else:
            return "prompt_user_exit"
            # → AskUserQuestion: "讨论似乎停滞（清晰度波动 ≤5%），建议："
            #   1. "缩小范围继续讨论"
            #   2. "以当前清晰度推进（{clarity_pct}%）"

    return "continue"
```

## 与苏格拉底模式的关系

| 场景 | 行为 |
|------|------|
| 苏格拉底模式 OFF + 挑战代理 ON | 挑战代理在特定轮次激活，其余轮正常决策提问 |
| 苏格拉底模式 ON + 挑战代理 ON | 挑战代理在激活轮替代苏格拉底步骤，未激活轮仍执行苏格拉底 7 步 |
| 苏格拉底模式 OFF + 挑战代理 OFF | 纯决策循环，无视角转换 |
| 苏格拉底模式 ON + 挑战代理 OFF | 每轮执行苏格拉底 7 步（原有行为） |

> 挑战代理是苏格拉底模式的**超集增强**，不是替代品。苏格拉底模式的 7 步提问（挑战假设、探索替代、识别隐含需求...）仍然有效，挑战代理在此基础上增加了视角切换和停滞检测能力。

## 配置项

```yaml
# autopilot.config.yaml
phases:
  requirements:
    challenge_agents:
      enabled: true                    # 默认开启
      contrarian_after_round: 4        # 反面论证激活轮次
      simplifier_after_round: 6        # 简化者激活轮次
      simplifier_scope_threshold: 5    # scope 条目超过此数才激活简化者
      ontologist_after_round: 8        # 本体论激活轮次
```

> **向后兼容**: `challenge_agents.enabled` 默认 `true`。设为 `false` 时完全禁用挑战代理，行为回退到原有苏格拉底模式。

## 挑战代理在 requirement-packet.json 中的记录

```json
{
  "challenge_agents_activated": ["contrarian", "simplifier"],
  "challenge_insights": [
    {
      "agent": "contrarian",
      "round": 4,
      "assumption_challenged": "必须使用 WebSocket 实时通信",
      "outcome": "用户确认 SSE 也可以接受，简化了方案"
    },
    {
      "agent": "simplifier",
      "round": 7,
      "scope_before": 8,
      "scope_after": 5,
      "deferred_to_v2": ["批量导入", "数据导出", "多语言支持"]
    }
  ]
}
```

> 以上字段为可选，仅在挑战代理激活时写入。
