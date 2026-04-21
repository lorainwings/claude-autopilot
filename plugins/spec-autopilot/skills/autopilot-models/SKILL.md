---
name: autopilot-models
description: "Use when the user wants to view or change the per-phase AI model routing strategy for autopilot — for example choosing a cost-optimized, balanced, or quality-max preset, inspecting the current routing table, or customising an individual phase's model binding."
argument-hint: "[cost | balanced | quality | custom | show]"
---

# Autopilot Models — 模型路由策略配置

配置各阶段的 AI 模型路由策略，支持预设方案和逐 Phase 自定义。

## 操作模式

根据 `$ARGUMENTS` 选择模式：

- 空 / `show` → 展示当前配置
- `cost` → 应用省钱优先策略
- `balanced` → 应用平衡策略
- `quality` → 应用质量优先策略
- `custom` → 逐 Phase 自定义

---

### `show` 模式（默认）

读取 `.claude/autopilot.config.yaml` 的 `model_routing` 节，展示当前配置：

```
当前模型路由策略:

  Phase 1 (需求分析):     {model}  [{tier}]  effort={effort}
  Phase 2 (OpenSpec):      {model}  [{tier}]  effort={effort}
  Phase 3 (FF 生成):       {model}  [{tier}]  effort={effort}
  Phase 4 (测试设计):      {model}  [{tier}]  effort={effort}
  Phase 5 (实施):          {model}  [{tier}]  effort={effort}  {escalation}
  Phase 6 (报告):          {model}  [{tier}]  effort={effort}
  Phase 7 (归档):          {model}  [{tier}]  effort={effort}

  默认子 Agent 模型: {default_subagent_model}
  Fallback 模型: {fallback_model}

模型优先级（高→低）:
  1. AUTOPILOT_PHASE{N}_MODEL 环境变量
  2. config per-phase 配置 ← 当前配置
  3. .claude/agents/*.md 中的 model frontmatter
  4. 继承主会话模型

切换策略: /autopilot-models [cost|balanced|quality|custom]
```

---

### `cost` / `balanced` / `quality` 模式

直接应用对应策略预设，无需交互。

如果 `$ARGUMENTS` 为空，通过 AskUserQuestion 选择：

```
"选择 AI 模型路由策略（影响成本和质量）："

选项:
- "Cost-Optimized (省钱优先)" →
    适合: 原型项目、个人项目
    估算: ~60% cost saving vs 纯 Opus

- "Balanced (推荐)" →
    适合: 日常开发
    估算: ~50% cost saving vs 纯 Opus

- "Quality-Max (质量优先)" →
    适合: 生产级代码、关键功能
    估算: ~20% cost saving vs 纯 Opus

- "Custom (自定义)" →
    逐 Phase 选择模型和 effort
```

#### 策略预设定义

```yaml
# ── Cost-Optimized (省钱优先) ──
# Opus 仅用于需求分析（长上下文理解不可替代），其余全部 Sonnet/Haiku
cost_optimized:
  default_subagent_model: sonnet
  fallback_model: sonnet
  phases:
    phase_1:
      tier: deep                 # 需求分析需 Opus 长上下文（MRCR 76%）
      model: opus
      effort: high
    phase_2:
      tier: fast
      model: haiku
      effort: low
    phase_3:
      tier: fast
      model: haiku
      effort: low
    phase_4:
      tier: standard             # Sonnet 编码≈Opus（SWE-bench 差 1.3pp）
      model: sonnet
      effort: medium
    phase_5:
      tier: standard
      model: sonnet
      effort: medium
    phase_6:
      tier: fast
      model: haiku
      effort: low
    phase_7:
      tier: fast
      model: haiku
      effort: low

# ── Balanced (推荐) ──
# Opus 用于需求分析和实施，Phase 5 失败自动升级
balanced:
  default_subagent_model: sonnet
  fallback_model: sonnet
  phases:
    phase_1:
      tier: deep
      model: opus
      effort: high
    phase_2:
      tier: fast
      model: haiku
      effort: low
    phase_3:
      tier: fast
      model: haiku
      effort: low
    phase_4:
      tier: standard
      model: sonnet
      effort: medium
      escalate_on_failure_to: deep
    phase_5:
      tier: deep
      model: opus
      effort: high
    phase_6:
      tier: fast
      model: haiku
      effort: low
    phase_7:
      tier: fast
      model: haiku
      effort: low

# ── Quality-Max (质量优先) ──
# Opus 用于所有需要推理的阶段
quality_max:
  default_subagent_model: sonnet
  fallback_model: sonnet
  phases:
    phase_1:
      tier: deep
      model: opus
      effort: high
    phase_2:
      tier: standard
      model: sonnet
      effort: medium
    phase_3:
      tier: standard
      model: sonnet
      effort: medium
    phase_4:
      tier: deep
      model: opus
      effort: high
    phase_5:
      tier: deep
      model: opus
      effort: high
    phase_6:
      tier: fast
      model: haiku
      effort: low
    phase_7:
      tier: fast
      model: haiku
      effort: low
```

### 应用流程

```
Step 1: 读取当前 .claude/autopilot.config.yaml
Step 2: 用选定策略的 model_routing 值替换 config 中的 model_routing 节
  保留 enabled: true
Step 3: 写入更新后的 config
Step 4: 运行 validate-config.sh 验证
Step 5: 输出结果

✓ 模型路由策略已更新: {strategy_name}

  Phase 1 (需求分析):     opus    [deep]   effort=high
  Phase 2 (OpenSpec):      haiku   [fast]   effort=low
  Phase 3 (FF 生成):       haiku   [fast]   effort=low
  Phase 4 (测试设计):      sonnet  [std]    effort=medium  ↑opus
  Phase 5 (实施):          opus    [deep]   effort=high
  Phase 6 (报告):          haiku   [fast]   effort=low
  Phase 7 (归档):          haiku   [fast]   effort=low

  单次实验覆盖: AUTOPILOT_PHASE{N}_MODEL=<model> /autopilot <需求>
```

---

### `custom` 模式

逐 Phase 通过 AskUserQuestion 选择模型和 effort：

```
对 Phase 1-7 逐个询问：

"Phase {N} ({phase_name}) 选择模型："

选项:
- "opus (深度推理，最贵)" → tier=deep, effort=high
- "sonnet (编码平衡，推荐)" → tier=standard, effort=medium
- "haiku (快速机械，最便宜)" → tier=fast, effort=low
```

完成后写入 config 并输出结果表格。

---

## Phase 6B 代码审查独立路由说明

Phase 6B（代码审查）不含 `autopilot-phase` 标记，dispatch 时传入 `critical=true`。
`resolve-model-routing.sh` 的 critical 升级逻辑自动将 fast/standard 升级到 deep/opus。

因此无论选择哪种策略，**Phase 6B 代码审查始终使用 Opus 级别模型**。
这是 P0 质量保障——代码审查是发现 memory leak/async bug 等隐藏缺陷的最后防线。

---

## 模型选择数据依据

| 场景 | 推荐模型 | 数据依据 |
|------|---------|---------|
| 需求分析 | Opus | MRCR v2 长上下文: Opus 76% vs Sonnet 18.5% |
| 测试设计 | Sonnet | SWE-bench: Sonnet 79.6% vs Opus 80.9%（仅差 1.3pp） |
| 代码实现 | Opus/Sonnet | Opus 能发现 Sonnet 遗漏的 memory leak/async bug |
| 模板操作 | Haiku | 机械性操作无需深度推理，成本低 5x |
| 代码审查 | Opus | 社区报告: Opus 级审查发现隐藏缺陷率显著高于 Sonnet |
