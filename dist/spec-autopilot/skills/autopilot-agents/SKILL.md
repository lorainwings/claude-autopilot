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
╔══════════════╦═══════════════════════════╦════════════╦═══════╦══════╦═════════════════════════════════════╗
║ Phase/角色   ║ 推荐 Agent                ║ 来源       ║ Model ║ 评分 ║ 选择理由                            ║
╠══════════════╬═══════════════════════════╬════════════╬═══════╬══════╬═════════════════════════════════════╣
║ Phase 1 BA   ║ analyst                   ║ OMC        ║ opus  ║ 9/10 ║ 7 步调查协议 + 决策点识别           ║
║ Phase 1 扫描 ║ explore (forked +Write)   ║ OMC        ║ sonnet║ 8/10 ║ 符号映射 + 文件搜索专精             ║
║ Phase 1 调研 ║ architect                 ║ OMC        ║ opus  ║ 8/10 ║ 接口/依赖/可行性长期权衡            ║
║ Phase 1 联网 ║ search-specialist(forked) ║ VoltAgent  ║ sonnet║ 8/10 ║ 原生 WebSearch+WebFetch，最小权限   ║
║ Phase 2      ║ planner                   ║ OMC        ║ opus  ║ 9/10 ║ 访谈→计划→确认+共识协议              ║
║ Phase 3      ║ writer                    ║ OMC        ║ haiku ║ 8/10 ║ Haiku 成本最优+模板化精确执行        ║
║ Phase 4      ║ test-engineer             ║ OMC        ║ sonnet║ 9/10 ║ TDD铁律+70/20/10金字塔              ║
║ Phase 5      ║ executor                  ║ OMC        ║ sonnet║ 9/10 ║ 最小差异+3次升级+lsp 验证            ║
║ Phase 5.5    ║ code-reviewer             ║ OMC        ║ opus  ║ 9/10 ║ Red Team 攻击枚举 + 反例产出         ║
║ Phase 6A     ║ qa-tester                 ║ OMC        ║ sonnet║ 8/10 ║ tmux 行为验证+5阶段协议              ║
║ Phase 6B     ║ code-reviewer             ║ OMC        ║ opus  ║10/10 ║ 强制Read-Only+10步审查+严重性分级    ║
║ Phase 7      ║ git-master                ║ OMC        ║ sonnet║ 8/10 ║ 原子提交+commit style 检测           ║
╚══════════════╩═══════════════════════════╩════════════╩═══════╩══════╩═════════════════════════════════════╝

备选 Agent:
  Phase 1 BA    : business-analyst (VoltAgent, 7/10)
  Phase 1 扫描  : codebase-onboarding (alirezarezvani, 8/10) — 原生 +Write
  Phase 1 调研  : backend-architect (wshobson, 7/10)
  Phase 1 联网  : market-researcher (VoltAgent, 7/10 — 需 fork +Write)
  Phase 4       : qa-expert (VoltAgent, 8/10)
  Phase 5.5     : red-team-critic (Anthropic 官方, 8/10，需独立验证)
  Phase 6B      : code-reviewer (Anthropic 官方, 9/10, 置信度≥80 过滤)
```

> **Phase 1 三路独立**：`auto_scan.agent` / `research.agent` / `research.web_search.agent` 在 config 中**独立字段**，运行时按 prompt 引用的输出文件路径精确校验（不允许混用）。BA agent（`phases.requirements.agent`）用于需求分析阶段。

输出后提示：`输入 /autopilot-agents install 安装推荐 Agent`

#### 域级 Agent 推荐（Phase 5 并行域 Agent）

```
╔═══════════════════════╦═══════════════════════╦════════════╦══════╦═══════════════════════════════════════════╗
║ 域路径前缀             ║ 推荐 Agent            ║ 来源       ║ 评分 ║ 选择理由                                  ║
╠═══════════════════════╬═══════════════════════╬════════════╬══════╬═══════════════════════════════════════════╣
║ backend/              ║ backend-developer     ║ VoltAgent  ║ 8/10 ║ API/DB/安全/微服务专精                     ║
║ frontend/             ║ frontend-developer    ║ VoltAgent  ║ 8/10 ║ React/Vue/Angular+TS strict+A11y          ║
║ node/                 ║ fullstack-developer   ║ VoltAgent  ║ 9/10 ║ DB→API→UI 全链路+类型安全                  ║
║ infra/ / devops/      ║ devops-engineer       ║ VoltAgent  ║ 8/10 ║ IaC/K8s/CI-CD/监控全覆盖                  ║
║ shared/ / libs/       ║ executor              ║ OMC        ║ 8/10 ║ 通用执行+3 次升级+最小差异                 ║
║ docs/                 ║ documentation-engineer║ VoltAgent  ║ 8/10 ║ 结构化文档+API 覆盖                       ║
║ mobile/               ║ mobile-developer      ║ VoltAgent  ║ 8/10 ║ RN/Flutter/原生+离线同步                  ║
║ data/                 ║ data-engineer         ║ VoltAgent  ║ 8/10 ║ ETL/Spark/Kafka/Airflow                   ║
╚═══════════════════════╩═══════════════════════╩════════════╩══════╩═══════════════════════════════════════════╝

来源仓库:
  VoltAgent: VoltAgent/awesome-claude-code-subagents (17k+ ★) — 域级专精 Agent 最佳来源
  OMC:       Yeachan-Heo/oh-my-claudecode (27.6k+ ★) — 工程化执行 + 通用 fallback
```

输出后提示：`输入 /autopilot-agents install 安装推荐 Agent（含域级 Agent）`

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
    4. 更新 .claude/autopilot.config.yaml 各 phase 的 agent 字段
    5. **工具权限适配（必须）**: 运行
       Bash('python3 ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/adapt-agent-tools.py --project-root "$(pwd)"')
       自动检测所有 phase→agent 的 `disallowedTools` 与所需工具的冲突，
       对冲突 agent fork 到 .claude/agents/{name}.md 并剥离冲突项（如
       analyst/explore 的 Write/Edit、code-reviewer 用于域 agent 时等）。
       幂等、可重复执行；源 marketplace agent 保持不变。

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

#### Step 3.5: 域级 Agent 安装

在 Phase-level Agent 安装完成后，检查并引导域级 Agent 安装：

```
IF config.phases.implementation.parallel.domain_agents 中已有非 general-purpose agent:
  → 输出 "✓ 已检测到 {N} 个域级 Agent 配置"
  → 跳过

ELSE:
  # 检测项目域（利用 Glob 扫描）
  detected_domains = []
  FOR dir IN ["backend/", "frontend/", "node/", "infra/", "devops/",
              "shared/", "libs/", "packages/", "docs/", "mobile/",
              "android/", "ios/", "data/", "analytics/"]:
    IF Glob("{dir}*") 有匹配文件:
      detected_domains.append(dir)

  IF detected_domains 非空:
    AskUserQuestion: "检测到 {N} 个项目域，是否安装域级专业 Agent？"
    选项:
    - "安装推荐域 Agent (Recommended)" →
        按域推荐映射表安装:
          backend/        → backend-developer (VoltAgent)
          frontend/       → frontend-developer (VoltAgent)
          node/           → fullstack-developer (VoltAgent)
          infra/ / devops/→ devops-engineer (VoltAgent)
          shared/ / libs/ / packages/ → executor (OMC, 已安装)
          docs/           → documentation-engineer (VoltAgent)
          mobile/ / android/ / ios/ → mobile-developer (VoltAgent)
          data/ / analytics/ → data-engineer (VoltAgent)

        VoltAgent Agent 安装方式:
        Bash('curl -sfL "https://raw.githubusercontent.com/VoltAgent/awesome-claude-code-subagents/main/agents/{agent_name}.md" -o ".claude/agents/{agent_name}.md"')
        验证: Read(.claude/agents/{agent_name}.md) 检查 frontmatter
        失败 → 使用 fallback agent（executor/general-purpose）

    - "使用与 Phase 5 相同的 Agent" →
        所有域使用 default_agent（如 executor）

    - "跳过域 Agent" →
        保持 general-purpose

  ELSE:
    → 输出 "未检测到多域项目结构，跳过域级 Agent 安装"
```

#### Step 4: 更新配置

```
读取 .claude/autopilot.config.yaml
更新以下字段:
  # Phase 1 BA + 三路调研（四字段独立）
  phases.requirements.agent: "{selected_phase1_ba_agent}"
  phases.requirements.auto_scan.agent: "{selected_phase1_autoscan_agent}"
  phases.requirements.research.agent: "{selected_phase1_research_agent}"
  phases.requirements.research.web_search.agent: "{selected_phase1_websearch_agent}"
  # Phase 1 Synthesizer（专职汇总 auto_scan + research + BA）
  phases.requirements.synthesizer.agent: "{selected_phase1_synthesizer_agent}"
  # 推荐链：OMC "architect" > "Plan" > 用户自配（architect/judge 类，非 explore 类）
  # 选型约束：Synthesizer 负责结构化判断与冲突仲裁，必须选 architect/judge 类 agent；
  #           禁止使用 explore 类（如 Explore / research-investigator），它们偏向发散探索，
  #           与 Synthesizer 的"收敛仲裁 + [NEEDS CLARIFICATION] 标注"职责不匹配。
  # IF 检测到旧 phases.requirements.research.web_search.agent 字段:
  #   stderr 输出: "[DEPRECATED] phases.requirements.research.web_search.agent 已合并进 research.web_search_subtask；该字段保留仅为向后兼容"
  phases.openspec.agent: "{selected_phase2_agent}"
  phases.testing.agent: "{selected_phase4_agent}"
  phases.implementation.parallel.default_agent: "{selected_phase5_agent}"
  phases.implementation.review_agent: "{selected_phase5_review_agent}"
  phases.redteam.agent: "{selected_phase5_5_redteam_agent}"
  phases.reporting.agent: "{selected_phase6_agent}"
  phases.code_review.agent: "{selected_phase6_review_agent}"
  phases.archive.agent: "{selected_phase7_agent}"

  # 域级 Agent 配置写入（Step 2.5 选定的域 Agent）
  IF 用户在 Step 2.5 选择了域级 Agent:
    FOR each (prefix, agent) in selected_domain_agents:
      phases.implementation.parallel.domain_agents."{prefix}".agent: "{agent}"
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

域级 Agent 映射 (Phase 5 并行):
  {prefix} → {agent} ({source})
  ...

热交换 Phase Agent: /autopilot-agents swap <phase> <agent>
热交换域 Agent:     /autopilot-agents swap <domain_prefix/> <agent>
查看:               /autopilot-agents list
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
Step 5: 工具权限适配（必须）
  Bash('python3 ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/adapt-agent-tools.py --project-root "$(pwd)"')
  → 对新交换进来的 agent 执行 disallowedTools 冲突检测 + 自动 fork
Step 6: 输出新映射
```

Phase → config key 映射:

```
phase1                → phases.requirements.agent (BA)
phase1-autoscan       → phases.requirements.auto_scan.agent
phase1-research       → phases.requirements.research.agent
phase1-websearch      → phases.requirements.research.web_search.agent  # [DEPRECATED] 仅热交换旧 config 时使用
phase1-synthesizer    → phases.requirements.synthesizer.agent  # 专职汇总者
phase2 → phases.openspec.agent
phase3 → phases.openspec.agent (共享 Phase 2)
phase4 → phases.testing.agent
phase5 → phases.implementation.parallel.default_agent
phase5-review → phases.implementation.review_agent
phase5.5 / redteam    → phases.redteam.agent
phase6 → phases.reporting.agent
phase6-review → phases.code_review.agent
phase7 → phases.archive.agent
```

#### 域 Agent 热交换

用法: `/autopilot-agents swap backend/ backend-developer`

```
判断规则: 若第一参数包含 "/" → 视为域 swap；否则视为 Phase swap

Step 1: 解析路径前缀（确保以 / 结尾）+ 新 agent 名称
Step 2: 检查 .claude/agents/{agent}.md 是否存在
  存在 → 继续
  不存在 → 检查是否为内置类型（general-purpose/Plan/Explore）
  都不是 → 提示安装: "Agent '{agent}' 未安装。运行 /autopilot-agents install 或手动下载到 .claude/agents/"
Step 3: 读取 .claude/autopilot.config.yaml
Step 4: 更新 phases.implementation.parallel.domain_agents."{prefix}".agent
  IF 该前缀在 domain_agents 中不存在 → 新增条目
Step 5: 输出新域映射

示例:
  /autopilot-agents swap backend/ backend-developer
  → phases.implementation.parallel.domain_agents."backend/".agent: "backend-developer"

  /autopilot-agents swap services/auth/ java-architect
  → phases.implementation.parallel.domain_agents."services/auth/".agent: "java-architect"
```

---

### `list` 模式

```
读取 .claude/autopilot.config.yaml 各 phase 的 agent 字段
检查 .claude/agents/ 下已安装的 Agent
展示完整表格:

Phase-Agent 映射:
  Phase → Agent → 安装状态 → Model → 工具限制

域级 Agent 映射 (Phase 5 并行):
  域路径前缀 → Agent → 安装状态

  IF config.phases.implementation.parallel.enabled == false:
    附加提示: "⚠ parallel 模式未启用，域级 Agent 在启用 parallel.enabled: true 后生效"
  IF 所有 domain_agents.*.agent 均为 general-purpose:
    附加提示: "💡 运行 /autopilot-agents install 安装域级专业 Agent"
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
