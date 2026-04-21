# Spec-Autopilot 三大优化需求实施计划（终版）

## 调研汇总

### 搜索覆盖范围

| 类别 | 覆盖项目数 | 关键发现 |
|------|-----------|---------|
| Claude 官方 Agent | 19 个（claude-plugins-official）| code-reviewer 置信度≥80 过滤、PR审查六件套、Skill 盲评 A/B |
| 社区 Agent 集合 | 30+ 仓库，1709 个 Agent（cultofclaude.com） | wshobson/agents（33.4k stars, 182 Agent）是生产级首选 |
| Agent 效果评测 | 4 个基准 + Anthropic 官方研究 | 多 Agent 比单 Agent 高 90.2%；9 并行审查有效率 75% |
| 社区编排实践 | 6 个主流项目（OMC/gstack/superpowers/harness/ECC/zhsama） | 零项目实现自动路由器；确定性条件表是主流 |

### 各阶段最佳 Agent 推荐矩阵

基于全量调研，每个 Phase 推荐**首选 + 备选**社区 Agent：

| Phase | 首选 Agent | 来源 | 备选 Agent | 来源 |
|-------|-----------|------|-----------|------|
| **Phase 1 需求分析** | `analyst` | OMC (opus, read-only, 7步调查协议) | `spec-analyst` + `spec-orchestrator` | zhsama/claude-sub-agent |
| | | | `code-architect` | Anthropic 官方 (sonnet, 三阶段架构设计) |
| **Phase 2/3 文档/规格** | `planner` | OMC (opus, 访谈+共识协议) | `spec-architect` + `spec-planner` | zhsama/claude-sub-agent |
| | | | `code-architect` | Anthropic 官方 |
| **Phase 4 测试设计** | `test-engineer` | OMC (sonnet, TDD铁律+70/20/10金字塔) | `spec-tester` | zhsama/claude-sub-agent |
| | | | `pr-test-analyzer` | Anthropic 官方 PR toolkit |
| **Phase 5 实现** | `executor` | OMC (sonnet, 最小差异+3次升级) | `spec-developer` | zhsama/claude-sub-agent |
| | | | conductor 插件 | wshobson/agents |
| **Phase 6A 测试执行** | `verifier` | OMC (sonnet, 证据验证) | `task-completion-validator` | darcyegb/ClaudeCodeAgents |
| **Phase 6B 代码审查** | `code-reviewer` | OMC (opus, 10步+多模式+严重性评级) | `code-reviewer` | Anthropic 官方 (sonnet, ≥80置信度) |
| | | | `comprehensive-review` | wshobson/agents (architect+reviewer+security 三合一) |
| | | | `silent-failure-hunter` | Anthropic 官方 PR toolkit |
| **Phase 7 归档** | `git-master` + `writer` | OMC (sonnet/haiku) | `spec-validator` | zhsama/claude-sub-agent |

### 核心设计原则

1. **不自造 Agent** — 推荐并引导安装社区成熟 Agent
2. **灵活热交换** — 5 层优先级链，从环境变量单次实验到 Agent 文件深度定制
3. **Phase 决定角色（确定性），config 决定具体 Agent（可配置），失败决定升级（自动）**
4. **直接删除过时代码** — legacy heavy/light 兼容逻辑彻底移除

---

## 实施方案

### 阶段 A: 清理过时配置

#### A1. 删除 resolve-model-routing.sh 中的 LEGACY_MAP

**文件**: `runtime/scripts/resolve-model-routing.sh`

- 删除 `LEGACY_MAP` 字典（第 70-73 行）
- 删除全部 `LEGACY_MAP.get(...)` 调用（第 249/265/286/384 行，共 4 处）
- 无效 tier 值直接走 fallback
- 保留 `auto`（继承父会话，有效功能）
- **新增**：环境变量覆盖（最高优先级）：
  ```python
  # 环境变量覆盖（最高优先级）
  env_model = os.environ.get(f'AUTOPILOT_PHASE{phase}_MODEL')
  env_effort = os.environ.get(f'AUTOPILOT_PHASE{phase}_EFFORT')
  if env_model:
      # 直接返回，跳过所有后续逻辑
  ```

#### A2. 删除 _config_validator.py 中的 legacy 兼容

**文件**: `runtime/scripts/_config_validator.py`

- 删除 `VALID_LEGACY_VALUES`（第 499 行）
- `auto` 加入 `VALID_TIERS = {"fast", "standard", "deep", "auto"}`
- 删除旧格式检查（第 532-535、538-544、594-598 行）
- 新增 `KNOWN_BUILTIN_AGENTS` + Agent 类型 warning（cross_ref_warnings）

#### A3. 更新 config-schema.md

**文件**: `skills/autopilot-setup/references/config-schema.md`

- Agent 默认值全部改为 `general-purpose`，注释推荐社区 Agent
- 删除 legacy heavy/light 注释块和兼容映射注释
- Phase 4 默认 model 从 `opus` 改为 `sonnet`，effort 改为 `medium`（SWE-bench 差距仅 1.3pp，有 gate 兜底）
- **新增** Phase 6B 代码审查独立模型配置节

#### A4. 清理 protocol.md / dispatch-phase-prompts.md

- 删除 heavy/light 映射表
- Agent 引用更新为 `general-purpose`，推荐社区 Agent

#### A5. 更新测试

- `test_model_routing_resolution.sh`：删除 Section B legacy 测试，修改 Section G，新增 heavy 拒绝测试 + 环境变量覆盖测试
- `test_validate_config.sh`：新增 Agent warning 测试

---

### 阶段 B: 动态 Agent 配置

#### B1. 创建 SKILL: autopilot-setup-agents

**新文件**: `skills/autopilot-setup-agents/SKILL.md`

```yaml
---
name: autopilot-setup-agents
description: "Discover, install and configure AI agents for autopilot phases from community sources (OMC, Anthropic official, wshobson/agents, etc.)."
argument-hint: "[install | list | swap <phase> <agent> | recommend | sources]"
---
```

**核心设计：Agent 市场发现 + 推荐安装 + 热交换**

```
## 操作模式

### `recommend` 模式（默认）— 展示推荐 Agent

展示基于调研的各阶段推荐 Agent 映射表，包含：
- 每个 Phase 的首选和备选 Agent
- Agent 来源（OMC / Anthropic 官方 / wshobson / zhsama）
- 模型 / 工具限制 / 适配度评估
- 安装命令

### `sources` 模式 — 展示可用的 Agent 来源

展示可安装的社区 Agent 市场：

┌──────────────────────────────────────────────────────┐
│  Agent 来源                         │ 星数  │ Agent 数 │
├──────────────────────────────────────────────────────┤
│  oh-my-claudecode (Yeachan-Heo)     │ 27.6k │ 19      │
│  wshobson/agents                    │ 33.4k │ 182     │
│  claude-plugins-official (Anthropic)│ 官方   │ 19      │
│  zhsama/claude-sub-agent            │ 572   │ 12      │
│  alirezarezvani/claude-skills       │ 10.5k │ 28      │
│  vijaythecoder/awesome-claude-agents│ 4.1k  │ 24      │
│  darcyegb/ClaudeCodeAgents          │ 652   │ 8       │
│  tech-leads-club/agent-skills       │ 2.1k  │ 安全验证 │
└──────────────────────────────────────────────────────┘

用户可选择添加市场：
  Bash('/plugin marketplace add Yeachan-Heo/oh-my-claudecode')

### `install` 模式 — 安装推荐 Agent

AskUserQuestion: "选择 Agent 安装方案："

选项:
- "安装推荐 Agent (一键安装)" →
    安装各阶段首选 Agent（来自 OMC + Anthropic 官方）：
    Phase 1: analyst (OMC)
    Phase 4: test-engineer (OMC)
    Phase 5: executor (OMC)
    Phase 6: code-reviewer (OMC) + silent-failure-hunter (Anthropic)
    Phase 7: git-master (OMC)
    
    安装方式：
    1. 检查 marketplace 是否已添加
    2. 未添加 → Bash('/plugin marketplace add Yeachan-Heo/oh-my-claudecode')
    3. 复制 Agent 定义到 .claude/agents/（或通过 plugin install）
    4. 更新 autopilot.config.yaml 各 phase 的 agent 字段

- "按阶段选择 Agent" →
    逐 Phase 展示推荐，用户每阶段可选不同来源的 Agent

- "浏览 Agent 目录" →
    打开 cultofclaude.com/agents/ 或展示分类列表
    用户手动选择安装

- "使用通用 Agent" →
    不安装，config 保持 general-purpose

### `swap` 模式 — 热交换单个 Phase 的 Agent

/autopilot-setup-agents swap phase4 test-engineer
→ 检查 .claude/agents/test-engineer.md 是否存在
→ 更新 config phases.testing.agent 字段
→ 输出新映射

### `list` 模式 — 展示当前 Phase-Agent 映射

展示完整表格：
Phase → Agent → 来源 → Model → Effort → 工具限制 → 安装状态
```

#### B2. Agent 适配层（仅适配不兼容的社区 Agent）

**不创建全新 Agent**，仅对不兼容的部分做最小化适配：

**适配 1**: OMC `analyst` → Phase 1 兼容
- 问题：`disallowedTools: Write, Edit`，但 Phase 1 需要 Write 调研产出文件
- 方案：在 `autopilot-setup-agents` 安装时，fork 一份 `analyst.md` 到 `.claude/agents/`，移除 `disallowedTools` 中的 `Write`
- 文件名保持 `analyst.md`，仅修改 frontmatter

**适配 2**: OMC `planner` → Phase 2/3 兼容
- 问题：原设计偏交互式计划，不是文档生成器
- 方案：保持原版 planner，Phase 2/3 dispatch 的 prompt 已包含 OpenSpec 文档生成指令，叠加即可。如果效果不好，可回退到 `general-purpose`

**其他 Agent 无需适配**，可直接使用。

#### B3. 更新 autopilot-setup 集成

**文件**: `skills/autopilot-setup/SKILL.md`

Step 5 后添加轻量引导：
```
### Step 5.3: Agent 安装引导
  已安装专业 Agent → "✓ 检测到 {N} 个专业 Agent"
  未安装 → AskUserQuestion:
    - "安装推荐 Agent (推荐)" → Skill("autopilot-setup-agents")
    - "跳过" → config 保持 general-purpose
```

#### B4. 5 层灵活性架构

| 层级 | 机制 | 粒度 | 生效 | 用途 |
|------|------|------|------|------|
| 1 | `AUTOPILOT_PHASE{N}_AGENT` 环境变量 | 单 Phase | 单次运行 | 实验/调试 |
| 2 | `/autopilot-setup-agents swap` 命令 | 单 Phase | 即时持久 | 快速切换 |
| 3 | config `phases.{phase}.agent` 字段 | 单 Phase | 编辑即生效 | 持久配置 |
| 4 | `.claude/agents/*.md` 文件替换 | Agent 定义 | 编辑即生效 | 深度定制 |
| 5 | Plugin marketplace 安装新 Agent | Agent 来源 | 安装即可用 | 扩展 Agent 库 |

#### B5. 测试

**新文件**: `tests/test_agent_setup.sh`
- 验证 `/autopilot-setup-agents list` 输出正确的映射
- 验证 `/autopilot-setup-agents swap` 正确更新 config
- 验证环境变量覆盖生效

---

### 阶段 C: 增强模型路由

#### C1. 创建 SKILL: autopilot-setup-model-router

**新文件**: `skills/autopilot-setup-model-router/SKILL.md`

```yaml
---
name: autopilot-setup-model-router
description: "Configure per-phase AI model routing strategy. Supports cost/balanced/quality presets and custom per-phase configuration."
argument-hint: "[cost | balanced | quality | custom | show]"
---
```

核心流程：
```
Step 1: 读取当前 model_routing 配置，展示摘要

Step 2: AskUserQuestion 选择策略

  选项:
  - "Cost-Optimized (省钱优先)" →
      Phase 1: opus | Phase 2-3: haiku | Phase 4: sonnet
      Phase 5: sonnet | Phase 6A: haiku | Phase 6B: sonnet | Phase 7: haiku
      估算: ~60% cost saving

  - "Balanced (推荐)" →
      Phase 1: opus | Phase 2-3: haiku | Phase 4: sonnet
      Phase 5: sonnet→opus(失败升级) | Phase 6A: haiku | Phase 6B: sonnet | Phase 7: haiku
      估算: ~50% cost saving

  - "Quality-Max (质量优先)" →
      Phase 1: opus | Phase 2-3: sonnet | Phase 4: opus
      Phase 5: opus | Phase 6A: haiku | Phase 6B: opus | Phase 7: haiku
      估算: ~20% cost saving

  - "Custom (自定义)" → 逐 Phase 选择 model + effort

Step 3: 写入 config model_routing 节
Step 4: 输出映射表 + 优先级说明
```

#### C2. Phase 6B 代码审查独立模型路由（P0）

**文件**: `runtime/scripts/resolve-model-routing.sh`

Phase 6B 代码审查不含 `autopilot-phase` 标记，当前无独立 model routing。

方案：在 dispatch-phase-prompts.md 的 Phase 6 路径 B 中：
- 调用 `resolve-model-routing.sh` 时传入 `critical=true`
- 现有逻辑（第 350-352 行）自动升级到 `deep/opus`
- 或在 config 中新增 `phases.code_review.model` 独立配置

#### C3. 预设关联模型策略

在 `autopilot-setup/SKILL.md` 预设映射中：
- `strict` → `quality_max`
- `moderate` → `balanced`
- `relaxed` → `cost_optimized`

#### C4. 更新 config-schema.md 模型文档

- 每个 Phase 添加模型选择理由注释
- 添加策略名称注释
- 文档化优先级链（环境变量 > config > agent frontmatter > 继承）
- 新增 Phase 6B 独立配置

#### C5. 更新 wizard 完成输出

```
✓ autopilot 配置已生成: .claude/autopilot.config.yaml
  预设: {preset_name} | 模式: {default_mode} | TDD: {on/off}
  Agent: {agent_summary} | 模型策略: {model_strategy}

  快速开始: /autopilot <需求描述>
  调整 Agent: /autopilot-setup-agents [install|list|swap|recommend]
  调整模型: /autopilot-setup-model-router [cost|balanced|quality]
```

---

## 涉及文件清单

### 修改文件
| 文件 | 改动 |
|------|------|
| `runtime/scripts/resolve-model-routing.sh` | 删除 LEGACY_MAP + 新增环境变量覆盖 |
| `runtime/scripts/_config_validator.py` | 删除 legacy 兼容 + Agent 类型 warning |
| `skills/autopilot-setup/references/config-schema.md` | 默认值修正 + 删除 legacy + Phase 4 降级 + Phase 6B 独立配置 + 模型文档 |
| `skills/autopilot/references/protocol.md` | 删除 heavy/light 映射 |
| `skills/autopilot-dispatch/references/dispatch-phase-prompts.md` | Agent 引用更新 + Phase 6B 独立路由 |
| `skills/autopilot-setup/SKILL.md` | Step 5.3/5.4 引导 + 预设关联 + 输出更新 |
| `tests/test_model_routing_resolution.sh` | 删除 Section B + 新增拒绝测试 + 环境变量测试 |
| `tests/test_validate_config.sh` | Agent warning + legacy 拒绝测试 |

### 新增文件
| 文件 | 内容 |
|------|------|
| `skills/autopilot-setup-agents/SKILL.md` | Agent 发现/安装/热交换 SKILL |
| `skills/autopilot-setup-model-router/SKILL.md` | 模型路由策略配置 SKILL |
| `tests/test_agent_setup.sh` | Agent 安装/交换验证 |

---

## 验证计划

每阶段完成后：`bash tests/run_all.sh && bash tools/build-dist.sh`

---

## 风险缓解

| 风险 | 缓解 |
|------|------|
| 删除 legacy 破坏旧 config | validator 报错含明确迁移指引（`heavy` → `deep`） |
| 社区 Agent 质量不稳定 | 推荐经过实战验证的 Agent（OMC 27.6k stars、Anthropic 官方）；用户可随时 swap 回 general-purpose |
| Agent 不兼容 dispatch 协议 | dispatch prompt 是叠加的，Agent system prompt 不替换阶段指令；已验证 OMC test-engineer/executor/code-reviewer 兼容 |
| Phase 4 降级影响质量 | 硬性 gate 兜底（min_test_count + coverage + 金字塔），不达标自动升级 |
| Phase 6B 独立路由增加复杂度 | 复用现有 `critical=true` 升级逻辑，改动最小 |
