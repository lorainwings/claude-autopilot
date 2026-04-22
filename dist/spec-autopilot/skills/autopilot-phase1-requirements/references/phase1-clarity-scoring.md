# Phase 1 混合清晰度评分系统

> 本文件由 `phase1-requirements.md` 1.6 节引用。定义多轮决策循环的退出条件评分机制。
> 参考 oh-my-claudecode Deep Interview 的数学化模糊度门禁 + Superpowers 的自然收敛设计。

## Contents

- 架构总览
- 评分维度
- 维度权重
- 规则引擎评分（确定性，Layer 2 级别）
- AI 补充评分（每轮末尾执行）
- 混合计算公式
- 清晰度阈值配置
- 安全阀配置
- 每轮进度展示模板
- 停滞检测
- requirement-packet.json 新增字段

## 架构总览

混合评分 = 确定性规则基础分 × 0.6 + AI 语义补充分 × 0.4

每轮决策循环结束后重新计算清晰度评分。当 `clarity_score >= clarity_threshold` 且所有决策点已澄清时，允许退出循环。

## 评分维度

| 维度 | 代码标识 | 评估内涵 |
|------|---------|---------|
| 目标清晰度 | `goal_clarity` | 主要目标是否无歧义？能否用一句话无限定词陈述？ |
| 约束清晰度 | `constraint_clarity` | 边界、限制和非目标是否清楚？有无隐含假设？ |
| 成功标准清晰度 | `criteria_clarity` | 能否写一个测试来验证成功？标准是否可测试？ |
| 上下文清晰度 | `context_clarity` | 对现有系统的理解是否足以安全修改？（棕地项目重点） |

## 维度权重

| 维度 | 绿地项目权重 | 棕地项目权重 |
|------|------------|------------|
| 目标清晰度 | 35% | 30% |
| 约束清晰度 | 25% | 20% |
| 成功标准清晰度 | 25% | 25% |
| 上下文清晰度 | 15% | 25% |

**棕地判定**：Phase 0 Auto-Scan 检测到项目有源码 + 用户需求为修改/扩展现有功能 → 棕地项目（增加 Context Clarity 权重）。否则 → 绿地项目。

## 规则引擎评分（确定性，Layer 2 级别）

> 规则分输入改为原始 prompt 而非 BA 字段：**不再**依赖 BA 产出的 `rp.*` 字段，改为对**原始用户 prompt**（Phase 0 保存到 `context/raw-user-prompt.md`）调用
> `runtime/scripts/score-raw-prompt.sh` 计算语言学特征，输出 [0,1] 标准化总分作为 `rule_score`。
> `rp.*` 结构化字段仅作为 `ai_score[i]` 的 LLM-judge 输入（语义完整性、边界灰区、可测试性、上下文耦合），不参与规则分计算。

### 原始 prompt 语言学特征（rule_score 输入）

`runtime/scripts/score-raw-prompt.sh --prompt <text>` 输出 JSON：

| 字段 | 含义 | 计算 |
|------|------|------|
| `verb_density` | 动词密度（观测指标） | 命令式动词数 / token 总数 |
| `quantifier_count` | 量化词总匹配数 | 数字 + 时间单位 + 阈值词 + `%` 的正则匹配总数 |
| `role_clarity` | 角色明确度 | 角色词（用户/管理员/访客/admin/user/guest 等）出现总次数 |
| `total_score` | 加权归一总分 | 见下方公式，[0, 1] |

总分公式（脚本内嵌）：

```
norm_verb  = min(1.0, verb_count / 4)
norm_quant = min(1.0, quantifier_count / 5)
norm_role  = min(1.0, role_clarity / 2)

total_score = 0.4 * norm_verb + 0.3 * norm_quant + 0.3 * norm_role
            ∈ [0, 1]
```

**rule_score 注入**（4 个维度共用同一原始 prompt 总分）：

```
raw_score = score-raw-prompt.sh(raw_user_prompt).total_score
goal_rule_score        = raw_score
constraint_rule_score  = raw_score
criteria_rule_score    = raw_score
context_rule_score     = raw_score   # 棕地项目同样使用，由 ai_score 补充结构化判断
```

> 规则分对 4 维度统一注入是有意为之：原始 prompt 是单一信号源，结构化分解
> 由 `ai_score[i]` 在维度内承担。混合公式 `dimension_score = rule × 0.6 + ai × 0.4`
> 仍然为每维度提供差异化输出。

### 经验校准（fixture 基线）

| Prompt 样本 | 期望区间 |
|------------|---------|
| 模糊："做个登录" | `total_score < 0.30` |
| 明确："为电商应用添加用户登录功能：邮箱+密码、支持记住我、JWT token 24h 过期，管理员可以在后台至少查看 100 条登录记录" | `total_score > 0.55` |

回归测试见 `tests/test_clarity_score_raw_prompt.sh`。

## AI 补充评分（每轮末尾执行）

在每轮决策循环结束后，主线程执行 AI 评分。**仅评估规则引擎无法检测的语义质量**。

### 评分 Prompt 模板

```
基于以下需求包当前状态，为 4 个维度各打 0.0-1.0 分。
仅评估**语义质量**（规则引擎已评估结构完整性，你不需要重复）。

当前需求包摘要:
- 目标: {rp.goal}
- 范围: {rp.scope}
- 排除项: {rp.non_goals}
- 验收标准: {rp.acceptance_criteria}
- 已决策: {rp.decisions}
- 假设: {rp.assumptions}
- 风险: {rp.risks}

评分标准（每个维度 0.0-1.0）:

1. **goal_clarity**: 目标是否无歧义？不同人读到是否会有不同理解？
   - 0.9+: 任何工程师读到都会做同一件事
   - 0.7-0.9: 大方向一致但实现路径可能分歧
   - <0.7: 存在明显歧义或遗漏

2. **constraint_clarity**: 是否有隐含假设未被暴露？边界是否存在灰区？
   - 0.9+: 所有边界条件都已显式声明
   - 0.7-0.9: 主要边界清楚但有少量灰区
   - <0.7: 存在未暴露的重要假设

3. **criteria_clarity**: 验收标准是否可以直接转化为测试用例？是否有主观判断？
   - 0.9+: 每条标准可直接写成 assert 语句
   - 0.7-0.9: 大部分可测试但有少量需要人工判断
   - <0.7: 多条标准含主观判断（"用户体验好"、"性能提升"等）

4. **context_clarity**: 对现有系统的理解是否足够？是否有未知的耦合风险？
   - 0.9+: 影响范围完全明确，无隐藏耦合
   - 0.7-0.9: 主要依赖已识别但可能有间接影响
   - <0.7: 对现有系统理解不足以安全修改

输出严格 JSON（无其他文字）:
{"goal_clarity": 0.0, "constraint_clarity": 0.0, "criteria_clarity": 0.0, "context_clarity": 0.0}
```

### AI 评分约束

- **模型**: 使用当前上下文中的主线程模型（无需额外调用）
- **一致性**: 评分基于 requirement_packet 的结构化字段，不读取子 Agent 正文工件
- **频率**: 每轮决策循环结束时执行一次（非每个问题后）
- **失败降级**: AI 评分解析失败时，使用 `{goal: 0.5, constraints: 0.5, criteria: 0.5, context: 0.5}` 作为降级值

## 混合计算公式

```
# 每个维度的混合分
dimension_score[i] = rule_score[i] × 0.6 + ai_score[i] × 0.4

# 总清晰度（加权和）
clarity_score = Σ(dimension_score[i] × weight[i])
              = (goal_mixed × goal_weight)
              + (constraint_mixed × constraint_weight)
              + (criteria_mixed × criteria_weight)
              + (context_mixed × context_weight)

# 模糊度（互补值，兼容 OMC 语义）
ambiguity = 1 - clarity_score
```

## 清晰度阈值配置

```yaml
# autopilot.config.yaml
phases:
  requirements:
    clarity_threshold: 0.80        # 默认退出阈值
    clarity_threshold_overrides:   # 按复杂度覆盖
      small: 0.70                  # 宽松——简单需求无需过度澄清
      medium: 0.80                 # 标准
      large: 0.85                  # 严格——复杂需求需要更高清晰度
```

**阈值选择逻辑**:
```
threshold = config.phases.requirements.clarity_threshold_overrides[complexity]
          || config.phases.requirements.clarity_threshold
          || 0.80
```

## 安全阀配置

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `min_qa_rounds` | 1 | 最低轮数下限（保留原有语义） |
| `soft_warning_rounds` | 8 | 软提醒轮次：提示用户当前清晰度，询问是否继续 |
| `max_rounds` | 15 | 硬性上限：强制结束，以当前最佳状态输出 |

### 安全阀行为

```
IF current_round == soft_warning_rounds:
    AskUserQuestion:
      question: "已讨论 {n} 轮，当前清晰度 {clarity_pct}%（目标 {threshold_pct}%）。"
      options:
        - "继续讨论，提升清晰度"
        - "以当前清晰度推进（可能有遗漏风险）"
    IF 用户选择"以当前清晰度推进":
        EXIT LOOP（即使 clarity < threshold）

IF current_round >= max_rounds:
    输出: "[WARN] 已达最大讨论轮数 {max_rounds}，以当前清晰度 {clarity_pct}% 强制推进"
    EXIT LOOP（无论 clarity 值）
```

## 每轮进度展示模板

每轮决策循环结束后，在 AskUserQuestion 前输出以下进度信息：

```
Round {n} | Clarity: {clarity_pct}% | Target: {threshold_pct}% | Gap: {gap_pct}%
  目标: ████████░░ 82%  约束: ██████░░░░ 65%  标准: █████████░ 90%  上下文: ███████░░░ 72%
  最弱维度: 约束清晰度 → 下一轮重点追问
```

**进度条生成规则**:
- 10 格宽度，每格代表 10%
- `█` = 已达成，`░` = 未达成
- 百分比 = `round(dimension_score × 100)`

## 停滞检测

从第 3 轮起生效。检测讨论是否在原地打转。

```
IF current_round >= 3:
    delta = abs(clarity_score - prev_clarity_score)
    IF delta <= 0.05:
        consecutive_stagnant_rounds += 1
    ELSE:
        consecutive_stagnant_rounds = 0

    IF consecutive_stagnant_rounds >= 2:
        # 停滞超过 2 轮 → 触发干预
        # 1. 优先激活本体论挑战代理（如未使用过）
        # 2. 已使用过 → 提示用户选择缩小范围或以当前清晰度推进
        # 停滞干预的完整协议（激活顺序、降级选项、用户提示措辞）
        # 参见 SKILL.md references 表中 phase1-challenge-agents.md 的"停滞检测集成"章节。
```

## requirement-packet.json 新增字段

Phase 1 checkpoint 写入时，在 requirement-packet.json 中新增以下可选字段：

```json
{
  "clarity_score": 0.85,
  "clarity_breakdown": {
    "goal_clarity": {"rule": 0.9, "ai": 0.8, "mixed": 0.86, "weight": 0.35},
    "constraint_clarity": {"rule": 0.7, "ai": 0.75, "mixed": 0.72, "weight": 0.25},
    "criteria_clarity": {"rule": 0.85, "ai": 0.9, "mixed": 0.87, "weight": 0.25},
    "context_clarity": {"rule": 0.8, "ai": 0.85, "mixed": 0.82, "weight": 0.15}
  },
  "discussion_rounds": 5,
  "challenge_agents_activated": ["contrarian"],
  "stagnation_detected": false
}
```

> **向后兼容**: 以上所有字段为可选。未启用评分系统时不写入，后续 Phase 不依赖这些字段。
