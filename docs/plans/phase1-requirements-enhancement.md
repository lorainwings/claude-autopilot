# Phase 1 需求分析增强 — 实施计划

> 基于 Superpowers (142k⭐) 和 oh-my-claudecode (26k⭐) 竞品分析，对 Phase 1 进行 4 项改进。

## 背景

当前 Phase 1 的讨论轮数被复杂度分路硬性封死（small=1/medium=2/large=3），缺乏持续的需求质量度量、视角转换机制和一次一问交互策略。竞品均采用**自然收敛**而非硬性轮数限制。

## 改进项

### A. 移除硬性轮数上限 → 弹性收敛

**当前**: `small: 最多 1 轮 | medium: 最多 2 轮 | large: 最多 3 轮`
**改为**: 以清晰度评分作为退出条件 + 软/硬安全阀

```
退出条件 = clarity_score >= clarity_threshold
         AND 所有决策点已澄清
         AND current_round >= min_qa_rounds

安全阀:
  - soft_warning_rounds (默认 8): 提示用户"已讨论 N 轮，当前清晰度 X%，是否继续？"
  - max_rounds (默认 15): 硬性上限，强制输出当前最佳 requirement packet
  - min_qa_rounds: 保留，作为下限（默认 1）

复杂度影响清晰度阈值（而非轮数上限）:
  - small: clarity_threshold = 0.7 (宽松)
  - medium: clarity_threshold = 0.8 (标准)
  - large: clarity_threshold = 0.85 (严格)
```

### B. 混合清晰度评分系统

**设计**: 确定性规则基础分 + AI 语义补充分，加权合并。

#### 评分维度

| 维度 | 权重(绿地) | 权重(棕地) | 规则引擎指标 | AI 补充评估 |
|------|-----------|-----------|-------------|------------|
| 目标清晰度 | 35% | 30% | goal 字段非空、含具体动词、无模糊词（"改进"/"优化"无限定词） | 目标是否无歧义、能否一句话陈述 |
| 约束清晰度 | 25% | 20% | non_goals ≥ 1 条、scope 边界词存在、无"等等"/"之类" | 边界是否清楚、约束是否完整 |
| 成功标准清晰度 | 25% | 25% | acceptance_criteria ≥ 1 条且含可测试动词+数值 | 标准是否可测试、无主观判断 |
| 上下文清晰度 | 15% | 25% | (棕地: affected_files 已识别、existing_patterns 已分析) | 对现有系统理解是否足以安全修改 |

#### 计算公式

```
# 每个维度的混合分 = 规则分 × 0.6 + AI分 × 0.4
dimension_score = rule_score × 0.6 + ai_score × 0.4

# 总清晰度 = 各维度加权和
clarity_score = Σ(dimension_score_i × weight_i)

# 模糊度（兼容 OMC 语义）
ambiguity = 1 - clarity_score
```

#### 规则分计算（确定性）

```python
def calc_goal_rule_score(requirement_packet):
    score = 0.0
    if rp.goal and len(rp.goal) > 10: score += 0.3
    if has_concrete_verb(rp.goal): score += 0.3      # 创建/迁移/修复/集成/...
    if not has_vague_qualifier(rp.goal): score += 0.2  # 无"一些"/"适当"/"合适"
    if rp.scope and len(rp.scope) >= 1: score += 0.2
    return min(score, 1.0)

def calc_constraint_rule_score(requirement_packet):
    score = 0.0
    if rp.non_goals and len(rp.non_goals) >= 1: score += 0.4
    if has_boundary_words(rp.scope): score += 0.3      # "仅限"/"不包含"/"排除"
    if not has_open_ended_words(rp.scope): score += 0.3  # 无"等等"/"之类"/"以及其他"
    return min(score, 1.0)

def calc_criteria_rule_score(requirement_packet):
    score = 0.0
    if rp.acceptance_criteria and len(rp.acceptance_criteria) >= 1: score += 0.3
    testable_count = count_testable_criteria(rp.acceptance_criteria)  # 含数值/动词
    total = len(rp.acceptance_criteria) or 1
    score += 0.4 * (testable_count / total)
    if any(has_numeric(c) for c in rp.acceptance_criteria): score += 0.3
    return min(score, 1.0)

def calc_context_rule_score(requirement_packet, is_brownfield):
    if not is_brownfield:
        return 0.8  # 绿地项目上下文自动高分
    score = 0.0
    if rp.affected_files and len(rp.affected_files) >= 1: score += 0.4
    if rp.existing_patterns: score += 0.3
    if rp.risks and any("兼容" in r or "回归" in r for r in rp.risks): score += 0.3
    return min(score, 1.0)
```

#### AI 补充评分（每轮末尾执行）

在每轮决策循环结束后，主线程根据当前 requirement_packet 的累积状态进行 AI 评分：

```
为以下 4 个维度各打 0.0-1.0 分（关注规则引擎无法检测的语义质量）:
1. 目标清晰度: 目标是否无歧义？能否被不同人一致理解？
2. 约束清晰度: 是否有隐含假设未被暴露？边界是否存在灰区？
3. 成功标准清晰度: 验收标准是否可以直接转化为测试用例？是否有主观判断？
4. 上下文清晰度: 对现有系统的理解是否足够？是否有未知的耦合风险？

输出 JSON: {"goal": 0.8, "constraints": 0.7, "criteria": 0.9, "context": 0.6}
```

#### 每轮进度展示

```
Round {n} | Clarity: {clarity_pct}% | Target: {threshold_pct}% | Gap: {gap_pct}%
  目标: ████████░░ 82%  约束: ██████░░░░ 65%  标准: █████████░ 90%  上下文: ███████░░░ 72%
  最弱维度: 约束清晰度 → 下一轮重点追问
```

### C. 挑战代理机制

在多轮决策循环中，按轮次自动激活不同提问视角（每种只激活一次）：

| 代理模式 | 激活条件 | 提问方向 | 触发后恢复 |
|---------|---------|---------|-----------|
| **反面论证** (Contrarian) | 第 4 轮+，且 clarity < threshold | 挑战核心假设："如果这个约束不存在呢？""这个需求真的必要吗？" | 恢复正常决策提问 |
| **简化者** (Simplifier) | 第 6 轮+，且 scope 条目 > 5 | 削减复杂度："最小可行版本是什么？""哪些可以推迟到 V2？" | 恢复正常决策提问 |
| **本体论** (Ontologist) | 第 8 轮+，且 clarity 连续 2 轮波动 ≤ 5% | 稳定核心概念："这个功能的本质是什么？""核心实体是哪些？" | 恢复正常决策提问 |

**状态追踪**：在循环中维护 `challenge_agents_used: Set<string>`，每种模式使用后加入集合，防止重复。

**停滞检测**（第 3 轮起生效）：
```
IF current_round >= 3:
    delta = abs(clarity_score - prev_clarity_score)
    IF delta <= 0.05 AND consecutive_stagnant_rounds >= 2:
        # 触发本体论模式（如未使用过），否则提示用户
        IF "ontologist" NOT IN challenge_agents_used:
            ACTIVATE ontologist mode
        ELSE:
            AskUserQuestion: "讨论似乎停滞（清晰度波动 ≤5%），建议: 1. 缩小范围继续 2. 以当前清晰度推进"
```

### D. 一次一问原则

**改动**：
- **Small**: 保持合并 2-3 个决策点为一次（快速路径，不变）
- **Medium/Large**: 改为每次 AskUserQuestion **只包含 1 个决策点**

**优先级选择算法**：
```
# 每轮选择与最弱清晰度维度最相关的 1 个未决策点
weakest_dimension = min(dimensions, key=lambda d: d.score)
next_question = select_most_relevant_decision_point(
    undecided_points, weakest_dimension
)
```

这意味着 medium/large 的讨论轮数会自然增加（每个决策点 1 轮），但结合改进 A 的弹性机制，当清晰度达标后自动退出，不会无限循环。

## 影响文件清单

| 文件 | 变更类型 | 变更内容 |
|------|---------|---------|
| `references/phase1-requirements.md` | 重写 1.6 节 | 多轮循环逻辑重写：移除硬性轮数上限，引入清晰度评分退出条件 |
| `references/phase1-requirements-detail.md` | 修改分路策略表 + 1.6 详细流程 | 删除"最多 N 轮"描述，添加清晰度评分计算、挑战代理、一次一问逻辑 |
| `references/phase1-supplementary.md` | 扩展苏格拉底模式 | 将挑战代理作为苏格拉底模式的超集，保留 7 步流程但加入视角切换 |
| `skills/autopilot-phase1-requirements/SKILL.md` | 更新概要流程 | 步骤 5.5/7 描述更新，添加清晰度评分和挑战代理概要 |
| `skills/autopilot/SKILL.md` | 微调 Phase 1 描述 | 更新 Phase 1 关键约束摘要 |
| `references/config-schema.md` | 新增配置项 | `clarity_threshold`、`soft_warning_rounds`、`max_rounds` 等 |

**新增文件**:
| 文件 | 用途 |
|------|------|
| `references/phase1-clarity-scoring.md` | 混合评分系统完整定义（规则分计算 + AI 评分 prompt + 加权公式） |
| `references/phase1-challenge-agents.md` | 挑战代理的完整协议（3 种模式 + 停滞检测 + 提问模板） |

## 配置项变更

```yaml
# autopilot.config.yaml 新增/修改项
phases:
  requirements:
    min_qa_rounds: 1           # 保留，最低轮数下限
    # max_qa_rounds: 删除（被 max_rounds 替代）
    max_rounds: 15             # 新增：硬性安全阀（默认 15）
    soft_warning_rounds: 8     # 新增：软性提醒轮次（默认 8）
    clarity_threshold: 0.80    # 新增：清晰度退出阈值（默认 0.80）
    clarity_threshold_overrides:  # 新增：按复杂度覆盖
      small: 0.70
      medium: 0.80
      large: 0.85
    challenge_agents:            # 新增：挑战代理配置
      enabled: true              # 默认开启
      contrarian_after_round: 4
      simplifier_after_round: 6
      ontologist_after_round: 8
    one_question_per_round: true # 新增：Medium/Large 一次一问（默认 true）
```

## 向后兼容

1. 新配置项全部有默认值，不修改 config 时行为变化：
   - 旧行为：small=1轮/medium=2轮/large=3轮 硬性上限
   - 新行为：清晰度达标即退出，soft=8轮/hard=15轮安全阀
   - **注意**：simple 需求通常 1-2 轮清晰度即达 0.7，不会显著增加交互
2. `min_qa_rounds` 保留，语义不变
3. 苏格拉底模式保留，挑战代理作为其超集集成
4. requirement-packet.json schema 不变，仅新增可选字段 `clarity_score`

## 实施顺序

1. **新建** `references/phase1-clarity-scoring.md` — 评分系统定义
2. **新建** `references/phase1-challenge-agents.md` — 挑战代理协议
3. **修改** `references/phase1-requirements.md` 1.6 节 — 核心循环逻辑
4. **修改** `references/phase1-requirements-detail.md` 分路策略表 + 1.6 详细流程
5. **修改** `references/phase1-supplementary.md` — 集成挑战代理
6. **修改** `skills/autopilot-phase1-requirements/SKILL.md` — 概要更新
7. **修改** `skills/autopilot/SKILL.md` — Phase 1 描述微调
8. **修改** `references/config-schema.md` — 新增配置项
9. **运行测试** `make test` 确保无回归
