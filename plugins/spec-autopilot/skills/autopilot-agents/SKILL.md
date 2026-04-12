---
name: autopilot-agents
description: "Discover, install and configure AI agents for autopilot phases from community sources (OMC, Anthropic official, VoltAgent, etc.). Supports install/list/swap/recommend/sources modes."
argument-hint: "[install | list | swap <phase> <agent> | recommend | sources]"
---

# Autopilot Agents — Agent 发现/安装/热交换

从社区来源（≥1000 stars）发现、安装和配置各阶段的专业 AI Agent。

## 操作模式

根据 `$ARGUMENTS` 选择模式：

- 空 / `recommend` → 展示推荐
- `sources` → 展示可用来源
- `install` → 安装 Agent
- `swap <phase> <agent>` → 热交换
- `list` → 查看当前映射

---

### `recommend` 模式（默认）

展示基于调研评分的各阶段推荐 Agent 映射表：

```
╔══════════╦═══════════════════╦════════╦═══════╦══════╦═══════════════════════════════════╗
║ Phase    ║ 推荐 Agent        ║ 来源   ║ Model ║ 评分 ║ 选择理由                          ║
╠══════════╬═══════════════════╬════════╬═══════╬══════╬═══════════════════════════════════╣
║ Phase 1  ║ analyst           ║ OMC    ║ opus  ║ 9/10 ║ 7步调查协议+Read-Only+Opus 推理   ║
║ Phase 2  ║ planner           ║ OMC    ║ opus  ║ 9/10 ║ 访谈→计划→确认+共识协议            ║
║ Phase 3  ║ writer            ║ OMC    ║ haiku ║ 8/10 ║ Haiku 成本最优+模板化精确执行      ║
║ Phase 4  ║ test-engineer     ║ OMC    ║ sonnet║ 9/10 ║ TDD铁律+70/20/10金字塔            ║
║ Phase 5  ║ executor          ║ OMC    ║ sonnet║ 9/10 ║ 最小差异+3次升级+lsp 验证          ║
║ Phase 6A ║ qa-tester         ║ OMC    ║ sonnet║ 8/10 ║ tmux 行为验证+5阶段协议            ║
║ Phase 6B ║ code-reviewer     ║ OMC    ║ opus  ║10/10 ║ 强制Read-Only+10步审查+严重性分级  ║
║ Phase 7  ║ git-master        ║ OMC    ║ sonnet║ 8/10 ║ 原子提交+commit style 检测         ║
╚══════════╩═══════════════════╩════════╩═══════╩══════╩═══════════════════════════════════╝

备选 Agent（VoltAgent/Anthropic 官方）:
  Phase 1: business-analyst (VoltAgent, 7/10)
  Phase 4: qa-expert (VoltAgent, 8/10)
  Phase 6B: code-reviewer (Anthropic 官方, 9/10, 置信度≥80 过滤)
```

输出后提示：`输入 /autopilot-agents install 安装推荐 Agent`

---

### `sources` 模式

展示社区 Agent 市场（仅 ≥1000 stars）：

```
可用的 Agent 来源:

  1. oh-my-claudecode (Yeachan-Heo)     27.6k ★  19 agents   Agent 工程化最佳
  2. VoltAgent/awesome-claude-code-subs  17k ★    130+ agents  备选池最大
  3. wshobson/agents                     33.4k ★  182 agents   覆盖面最广
  4. claude-plugins-official (Anthropic) 16.7k ★  19 agents    官方 Agent
  5. vijaythecoder/awesome-claude-agents 4.1k ★   24 agents    分层团队架构
  6. alirezarezvani/claude-skills        10.5k ★  28 agents    跨工具兼容
  7. tech-leads-club/agent-skills        2.1k ★   安全验证      安全优先
  8. peterkrueck/Claude-Code-Dev-Kit     1.3k ★   工作流        Bug Hunter

安装市场: 使用 Bash 执行 claude plugin marketplace add <owner/repo>
浏览目录: https://cultofclaude.com/agents/ (1709 个 Agent)
```

---

### `install` 模式

#### Step 1: 检测已安装 Agent

```
使用 Glob 检查 .claude/agents/*.md 是否存在
统计已安装的 Agent 数量
```

#### Step 2: 选择安装方案

通过 AskUserQuestion 展示选项：

```
"选择 Agent 安装方案："

选项:
- "安装推荐 Agent (一键安装)" →
    安装 OMC 全部 8 个首选 Agent:
    analyst, planner, writer, test-engineer,
    executor, qa-tester, code-reviewer, git-master

    安装方式:
    1. 检查 OMC marketplace 是否已添加
    2. Bash('claude plugin marketplace add Yeachan-Heo/oh-my-claudecode') [若未添加]
    3. 通过 plugin install 安装，或直接复制 Agent 文件到 .claude/agents/
    4. Phase 1 适配: fork analyst.md 移除 disallowedTools 中的 Write
       (Phase 1 需要 Write 调研产出文件)
    5. 更新 .claude/autopilot.config.yaml 各 phase 的 agent 字段

- "按阶段选择 Agent" →
    逐 Phase 展示推荐 + 备选，用户每阶段可选

- "使用通用 Agent" →
    不安装，config 保持 general-purpose
```

#### Step 3: 安装 Agent 文件

```
对选定的每个 Agent:
1. 检查 .claude/agents/{name}.md 是否已存在
2. 已存在 → AskUserQuestion 确认覆盖
3. 安装 Agent 定义文件
4. 验证安装: Read(.claude/agents/{name}.md) 检查 frontmatter
```

#### Step 4: 更新配置

```
读取 .claude/autopilot.config.yaml
更新以下字段:
  phases.requirements.agent: "{selected_phase1_agent}"
  phases.openspec.agent: "{selected_phase2_agent}"
  phases.testing.agent: "{selected_phase4_agent}"
  phases.implementation.parallel.default_agent: "{selected_phase5_agent}"
```

#### Step 5: 输出结果

```
✓ 已安装 {N} 个专业 Agent

Phase-Agent 映射:
  Phase 1 (需求分析) → {agent} ({model})
  Phase 2 (OpenSpec)  → {agent} ({model})
  Phase 3 (FF 生成)   → {agent} ({model})
  Phase 4 (测试设计)  → {agent} ({model})
  Phase 5 (实施)      → {agent} ({model})
  Phase 6A (测试)     → {agent} ({model})
  Phase 6B (代码审查) → {agent} ({model})
  Phase 7 (归档)      → {agent} ({model})

热交换: /autopilot-agents swap <phase> <agent>
查看:   /autopilot-agents list
```

---

### `swap` 模式

用法: `/autopilot-agents swap phase4 test-engineer`

```
Step 1: 解析参数 — phase 编号 + 新 agent 名称
Step 2: 检查 .claude/agents/{agent}.md 是否存在
  存在 → 继续
  不存在 → 检查是否为内置类型（general-purpose/Plan/Explore）
  都不是 → 提示安装对应 Agent
Step 3: 读取 .claude/autopilot.config.yaml
Step 4: 更新对应 phase 的 agent 字段
Step 5: 输出新映射
```

Phase → config key 映射:

```
phase1 → phases.requirements.agent
phase2 → phases.openspec.agent
phase3 → phases.openspec.agent (共享 Phase 2)
phase4 → phases.testing.agent
phase5 → phases.implementation.parallel.default_agent
phase6 → phases.testing.agent (共享 Phase 4)
phase7 → (主线程执行，不配置 agent)
```

---

### `list` 模式

```
读取 .claude/autopilot.config.yaml 各 phase 的 agent 字段
检查 .claude/agents/ 下已安装的 Agent
展示完整表格:

Phase → Agent → 安装状态 → Model → 工具限制
```

---

## Agent 优先级链（运行时解析）

```
1. AUTOPILOT_PHASE{N}_AGENT 环境变量    ← 最高，单次实验用
2. config phases.{phase}.agent 字段     ← 持久配置
3. .claude/agents/{name}.md 定义        ← Agent 行为定义
4. 内置 general-purpose                 ← 兜底
```

## 适配说明

### OMC `analyst` → Phase 1 适配

OMC 原版 `analyst` 的 `disallowedTools: Write, Edit` 与 Phase 1 不兼容（需要 Write 调研产出文件）。

安装时自动适配：fork `analyst.md`，将 `disallowedTools: Write, Edit` 改为 `disallowedTools: Edit`（保留禁止 Edit，允许 Write）。

### OMC `planner` → Phase 2/3 适配

保持原版，Phase 2/3 的 dispatch prompt 已包含 OpenSpec 文档生成指令，叠加即可。
