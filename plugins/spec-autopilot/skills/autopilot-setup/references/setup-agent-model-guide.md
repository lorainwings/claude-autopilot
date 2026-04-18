# Agent 安装与模型路由引导

> 本文件由 `autopilot-setup/SKILL.md` 通过 `**执行前读取**` 引用。
> 包含 Step 5.3（Agent 安装引导）和 Step 5.4（模型路由引导）。

## Step 5.3: Agent 安装引导（必须配置 Phase 1 关键字段）

检查 `.claude/agents/` 是否存在可用于 Phase 1 的 agent，并强制写入 `phases.requirements.agent` / `phases.requirements.research.agent`。setup 结束时这两个字段不得为空，否则 fail-fast。

### 核心规则（配置驱动，不硬编码 agent 名）

- **不预设默认 agent**：本指南不指定任何特定 agent 名作为默认值。用户从已安装的 agent 中选择。
- **必须写入 config**：setup 完成后 `phases.requirements.agent` 与 `phases.requirements.research.agent` 必须有非空、非 `Explore` 的值。
- **运行时强一致**：`runtime/scripts/auto-emit-agent-dispatch.sh` 读取此 config 并校验 dispatch 的 `subagent_type` 必须完全等于配置值，偏离即硬阻断。

### 执行流程

```
# 1. 扫描已安装 agent
installed = ls .claude/agents/*.md (项目级) ∪ ls ~/.claude/agents/*.md (用户级)
# 排除内置 Explore（只读无 Write 权限，_config_validator 硬阻断）
candidates = installed \ {Explore}

# 2. 分支
IF candidates 为空:
  → 输出："✗ 未检测到可用于 Phase 1 的已安装 agent"
  → AskUserQuestion: "Phase 1 需要至少一个具备 Write 权限的 agent，是否现在安装？"
    选项:
    - "安装推荐 Agent" → 调用 Skill("spec-autopilot:autopilot-agents" "install")，回到第 1 步重新扫描
    - "退出 setup" → fail-fast exit 1

ELIF candidates.size == 1:
  → selected_agent = candidates[0]
  → 输出："✓ 将使用已安装的 agent: {selected_agent}"

ELSE (多个候选):
  → AskUserQuestion: "选择 Phase 1 使用的 agent（用于需求分析 + 技术调研 + 联网搜索）："
    选项: candidates 列表（按名称排序；展示来源与评分）
  → selected_agent = 用户选择

# 3. 写入 config（必须）
config.phases.requirements.agent = selected_agent
config.phases.requirements.research.agent = selected_agent

# 4. 二次验证
IF config.phases.requirements.agent ∈ {"", "Explore"}:
  → setup fail-fast: "phases.requirements.agent 无效"
  → exit 1
IF config.phases.requirements.research.agent ∈ {"", "Explore"}:
  → setup fail-fast: "phases.requirements.research.agent 无效"
  → exit 1
```

### 说明

- 用户可在 setup 后通过重新运行 `/autopilot-setup` 或 `/autopilot-agents swap` 变更配置；变更会被运行时立即采纳。
- `phases.requirements.agent` 和 `phases.requirements.research.agent` **可以不同**（如分析用 `planner`，调研用 `analyst`），但运行时校验 dispatch 必须与各自字段完全一致。
- 若 Step 5.3.5（域级 agent）/ Step 6（Schema 校验）检测到其他阶段同样缺失 agent，执行相同的"扫描 → 选择 → 写入"流程。

## Step 5.3.5: 域级 Agent 配置引导

**执行前读取**: `references/setup-domain-agent-guide.md`（完整映射表和安装逻辑）

利用 Step 1 检测到的项目结构，自动推荐域级专业 Agent 以提升 Phase 5 并行执行质量。

**始终执行 AskUserQuestion**（除非 Wizard 预设指定 skip/recommended），不静默跳过：

```
IF Wizard domain_agents_strategy == "skip":
  → 输出 "跳过域 Agent 配置（Relaxed 模式）"
  → 继续 Step 5.4

IF Wizard domain_agents_strategy == "recommended":
  → 直接安装所有检测到域的推荐 Agent（不弹 AskUserQuestion）
  → 继续 Step 5.4

# 标准流程（domain_agents_strategy == "ask" 或无 Wizard）
IF 检测到至少一个项目域（backend_dir/frontend_dir/node_dir 非空，或扩展扫描发现额外目录）:

  # 生成推荐列表
  domain_recommendations = 按 references/setup-domain-agent-guide.md Section B 映射

  展示推荐表格:
  "检测到 {N} 个项目域，推荐配置域级专业 Agent（提升 Phase 5 并行执行质量）："

  ╔══════════════════╦═══════════════════════╦════════════╦══════╗
  ║ 域路径前缀        ║ 推荐 Agent            ║ 来源       ║ 评分 ║
  ╠══════════════════╬═══════════════════════╬════════════╬══════╣
  {for each domain in domain_recommendations}
  ║ {prefix}         ║ {agent}               ║ {source}   ║{score}║
  {end for}
  ╚══════════════════╩═══════════════════════╩════════════╩══════╝

  AskUserQuestion:
  选项:
  - "安装推荐域 Agent (Recommended)" →
      对每个 detected_domain:
        1. 安装推荐 agent（Section C 安装机制）
        2. 更新 config domain_agents[prefix].agent = recommended_agent

  - "使用与 Phase 5 相同的 Agent" →
      对每个 detected_domain:
        config domain_agents[prefix].agent = default_agent

  - "自定义配置" →
      逐域 AskUserQuestion 选择 agent

  - "跳过域 Agent 配置" →
      保持 general-purpose

ELSE:
  → 输出 "单域项目，跳过域级 Agent 配置"
```

> 域级 Agent 配置是可选步骤。未安装时使用 default_agent (fallback)。

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
