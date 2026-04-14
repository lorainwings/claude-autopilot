# Agent 安装与模型路由引导

> 本文件由 `autopilot-setup/SKILL.md` 通过 `**执行前读取**` 引用。
> 包含 Step 5.3（Agent 安装引导）和 Step 5.4（模型路由引导）。

## Step 5.3: Agent 安装引导

检查 `.claude/agents/` 是否已安装 autopilot 推荐的专业 Agent。

**始终执行 AskUserQuestion**，不静默跳过：

```
IF .claude/agents/ 下存在 analyst.md / executor.md / code-reviewer.md 等:
  → 输出 "✓ 已检测到 {N} 个专业 Agent"
  → AskUserQuestion: "已检测到专业 Agent。是否需要更新或安装其他 Agent？"
  → 选项:
    - "保持当前 Agent (Recommended)" → 跳过
    - "更新/安装 Agent" → 调用 Skill("spec-autopilot:autopilot-agents" "install")

ELSE:
  AskUserQuestion: "autopilot 支持安装专业 Agent 以提升各阶段效果。是否安装？"
  选项:
  - "安装推荐 Agent (Recommended)" → 调用 Skill("spec-autopilot:autopilot-agents" "install")
  - "跳过，稍后手动安装" → 继续后续步骤
```

> Agent 安装是可选步骤，跳过不影响 autopilot 功能。未安装专业 Agent 时使用内置 general-purpose。

## Step 5.4: 模型路由引导

检查 config 中 `model_routing` 是否已有完整的 per-phase 配置：

```
IF config.model_routing.phases 已有 7 个 phase 配置:
  → 输出当前策略摘要
  → 跳过本步骤

ELSE:
  AskUserQuestion: "是否配置模型路由策略？（影响成本和质量）"
  选项:
  - "配置模型路由 (Recommended)" → 调用 Skill("spec-autopilot:autopilot-models")
  - "使用默认路由" → 跳过（使用 resolve-model-routing.sh 的内置默认值）
```

> 模型路由配置是可选步骤。跳过时使用内置默认路由（Phase 1/5: opus, Phase 4: sonnet, 其余: haiku）。
