# Agent 安装与模型路由引导

> 本文件由 `autopilot-setup/SKILL.md` 通过 `**执行前读取**` 引用。
> 包含 Step 5.3（Agent 安装引导）和 Step 5.4（模型路由引导）。

## Step 5.3: Agent 安装引导（必须配置 Phase 1 三路 + BA Agent 关键字段）

检查 `.claude/agents/` 是否存在可用于 Phase 1 的 agent，并强制写入 4 个字段：

| 字段 | 用途 | 推荐预设 |
|------|------|---------|
| `phases.requirements.agent` | 需求分析（BA） | OMC `analyst` |
| `phases.requirements.auto_scan.agent` | 代码库扫描 | OMC `explore` (forked +Write) |
| `phases.requirements.research.agent` | 技术兼容性分析 | OMC `architect` |
| `phases.requirements.research.web_search.agent` | 联网搜索 | VoltAgent `search-specialist` (forked +Write) |

setup 结束时这四个字段不得为空，**任一为 `Explore` 即 fail-fast**（Explore 无 Write 权限，无法产出对应工件；联网搜索字段额外要求 WebSearch 工具）。

### 核心规则（配置驱动，不硬编码 agent 名）

- **不预设默认 agent**：本指南不强制写入特定 agent 名，用户从已安装的 agent 中选择；推荐表仅作展示。
- **必须分别写入 config**：四个字段每个都需独立选择（允许选同一个 agent，但运行时按文件路径精确路由）。
- **运行时强一致**：`runtime/scripts/auto-emit-agent-dispatch.sh` 按 prompt 引用的输出文件路径路由：
  - `project-context.md` / `existing-patterns.md` / `tech-constraints.md` → 校验等于 `auto_scan.agent`
  - `research-findings.md`（不含 web 前缀） → 校验等于 `research.agent`
  - `web-research-findings.md` → 校验等于 `research.web_search.agent`
  偏离即硬阻断。

### 执行流程

```
# 1. 扫描已安装 agent
installed_local   = ls .claude/agents/*.md              # 项目级
installed_user    = ls ~/.claude/agents/*.md            # 用户级
installed_plugin  = ls ${CLAUDE_PLUGIN_ROOT}/../*/agents/*.md  # 同仓库其他插件，纳入时以 `plugin:agent` 命名空间形式呈现
installed = installed_local ∪ installed_user ∪ installed_plugin
# 排除内置 Explore（只读无 Write 权限，_config_validator 硬阻断）
candidates = installed \ {Explore}

# 2. 候选为空 → 引导安装
IF candidates 为空:
  → 输出："✗ 未检测到可用于 Phase 1 的已安装 agent"
  → AskUserQuestion: "Phase 1 需要至少一个具备 Write 权限的 agent，是否现在安装？"
    选项:
    - "安装推荐 Agent" → 调用 Skill("spec-autopilot:autopilot-agents" "install")，回到第 1 步重新扫描
    - "退出 setup" → fail-fast exit 1

# 3. 三路 + BA + Phase 2-7 共 12 次 AskUserQuestion，分别选择
FOR field IN [
  ("phases.requirements.agent",                        "需求分析（BA）",        "OMC analyst"),
  ("phases.requirements.auto_scan.agent",              "代码库扫描",            "OMC explore (forked)"),
  ("phases.requirements.research.agent",               "技术兼容性分析",        "OMC architect"),
  ("phases.requirements.research.web_search.agent",    "联网搜索（需 WebSearch）", "VoltAgent search-specialist (forked)"),
  ("phases.openspec.agent",                            "OpenSpec 规划",         "OMC planner"),
  ("phases.testing.agent",                             "测试设计",              "OMC test-engineer"),
  ("phases.implementation.parallel.default_agent",     "Phase 5 默认执行 Agent", "OMC executor"),
  ("phases.implementation.review_agent",               "Phase 5 批量 Review",   "OMC code-reviewer"),
  ("phases.redteam.agent",                             "Phase 5.5 Red Team",   "OMC code-reviewer / Anthropic red-team-critic"),
  ("phases.reporting.agent",                           "Phase 6 测试报告",      "OMC qa-tester"),
  ("phases.code_review.agent",                         "Phase 6.5 Code Review","OMC code-reviewer"),
  ("phases.archive.agent",                             "Phase 7 归档",          "OMC git-master"),
]:
  IF candidates.size == 1:
    → 自动写入 candidates[0]
    → 输出："✓ {field}: {selected_agent}"
  ELSE:
    → AskUserQuestion: "选择 {role} 使用的 agent：" 选项=候选列表（推荐预设标 Recommended 排首位）
    → 写入用户选择
  → 写入 config 对应字段

# 4. 二次验证（四个字段任一为空或为 Explore → fail-fast）
FOR field IN 上述四字段:
  IF config.<field> ∈ {"", "Explore"}:
    → setup fail-fast: "{field} 无效：必须为已安装的非 Explore agent"
    → exit 1

# 5. 联网搜索字段额外校验：所选 agent frontmatter 必须包含 WebSearch + WebFetch
ws_agent = config.phases.requirements.research.web_search.agent
IF ws_agent ∉ BUILTIN_AGENTS:
  agent_md = .claude/agents/{ws_agent}.md
  IF "WebSearch" 不在 frontmatter.tools 且 不在 frontmatter.allowedTools:
    → 输出 warning："{ws_agent} 未声明 WebSearch 工具，将无法联网搜索；建议改用 search-specialist 或为该 agent fork 加上 WebSearch"
    → 不阻断（用户可能有自定义 agent）
```

### 说明

- 用户可在 setup 后通过重新运行 `/autopilot-setup` 或 `/autopilot-agents swap phase1-autoscan|phase1-research|phase1-websearch <agent>` 变更配置。
- 三路 agent 字段 + BA agent 字段**互相独立**，可以四个字段全选同一个 agent（如同一个全能 agent），但运行时仍按 dispatch 路径精确校验。
- 若 Step 5.3.5（域级 agent）/ Step 6（Schema 校验）检测到其他阶段同样缺失 agent，执行相同的"扫描 → 选择 → 写入"流程。

## Step 5.3.5: 域级 Agent 配置引导

**执行前读取**: `setup-domain-agent-guide.md`（完整映射表和安装逻辑）

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
  domain_recommendations = 按 setup-domain-agent-guide.md Section B 映射

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
