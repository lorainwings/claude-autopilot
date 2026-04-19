# Sub-Agent 生态调研报告（spec-autopilot 7 Phase 选型）

> 版本：v5.10.1  |  日期：2026-04-19  |  目的：为 spec-autopilot 各 Phase 挑选最佳 sub-agent 预设
> 硬约束：所有候选 agent 必须具备 **Write 权限**（只读 agent 如内置 Explore 会被 `_config_validator.py` 硬阻断）

---

## Part A：来源确认表

| 用户提及名 | 真实仓库 | stars（2026-04） | agent 数 | 是否推荐 | 理由 |
|---|---|---|---|---|---|
| OMC | [Yeachan-Heo/oh-my-claudecode](https://github.com/Yeachan-Heo/oh-my-claudecode) | 27.6k | 7 类核心 agent（explore/executor/researcher/test-engineer/reviewer×5/scientist） | ✅ 强烈推荐 | 当前预设之一；agent 角色定位清晰、与 spec-autopilot Phase 模型天然对齐；作者活跃，v4.12.0 内置 Exa（联网）+ Context7（文档）MCP |
| GSD | [gsd-build/get-shit-done](https://github.com/gsd-build/get-shit-done) | 中等（元提示框架，非严格 subagent 仓库） | 以 slash command + plan 为主，无标准 subagent 定义 | ⚠️ 不直接采用 | GSD 是"元提示 + 规划工作流"，与 spec-autopilot 编排层定位重叠，不提供可复用的 `.md` subagent |
| Superpowers | [obra/superpowers](https://github.com/obra/superpowers) | 数千（活跃） | skills/commands/agents 混合，含 parallel plan、teammate tool | ⚠️ 部分参考 | 定位是"技能库 + 团队协作"，subagent 命名风格与 OMC 不同，适合借鉴 TeammateTool/SendMessage 思路，不适合直接替换 |
| ECC | [affaan-m/everything-claude-code](https://github.com/affaan-m/everything-claude-code) | 宣称 158k+（含跨平台统计，需核实） | 28 specialized agents + 119 skills | ✅ 强候选 | Anthropic hackathon 获奖，含 TDD enforcement + security scanner + memory persistence，跨 Claude/Cursor/Codex 通用 |
| Gstack | [garrytan/gstack](https://github.com/garrytan/gstack) | 66k+ | 23 个"虚拟角色"（CEO/Designer/QA/ReleaseManager/DocEngineer 等） | ⚠️ 参考 | 以角色扮演 slash command 为主，不是严格的 subagent 定义；Phase 1 业务理解可参考 CEO/PM 视角，但需改造 |
| Hermes/Hermess | [NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent) | 数千 | 以 skill 为主，Claude Code 为其中一个 skill 入口 | ❌ 不推荐 | Hermes 是自主 agent 框架，Claude Code 是其 skill，方向与 spec-autopilot 相反 |
| Anthropic 官方（内置） | anthropic [claude-code](https://github.com/anthropics/claude-code) 运行时内置 | — | Explore / Plan / Bash / general-purpose | ❌ 不可用 | Explore/Plan 无 Write 权限，会被 `_config_validator.py` 硬阻断；general-purpose 可用但无领域特化 |
| 官方插件市场 | [anthropics/claude-plugins-official](https://github.com/anthropics/claude-plugins-official) | 官方 | 50+ plugins（非 subagent 定义为主） | ⚠️ 参考 | 以 plugin 为单位，agent 嵌入在各插件内，如 `code-simplifier`，可选作 Phase 6.5 外援 |
| VoltAgent | [VoltAgent/awesome-claude-code-subagents](https://github.com/VoltAgent/awesome-claude-code-subagents) | 17.7k | 130+ subagents（10 大类） | ✅ 强烈推荐 | 当前预设之一；分类最齐全、覆盖 research-analyst / search-specialist / qa-expert / code-reviewer / backend-developer 等 |
| wshobson/agents | [wshobson/agents](https://github.com/wshobson/agents) | 33.8k | 184 agents / 78 plugins / 25 类 | ✅ 强候选 | 规模最大；含 Conductor（spec→plan→implement）、qa-orchestra、Agent Teams research 预设；可作 Phase 1/4/6 后备 |

> 备注：GSD / Gstack / Superpowers 均是与 spec-autopilot 同层的"编排/流程"产品，不是 subagent 源，因此仅作思路参考，不纳入替换候选池。ECC stars 数以其仓库页为准（本报告未直接抓取 stars API，仅引用搜索结果）。

---

## Part B：7 Phase 最佳 Agent 推荐（每 Phase 3 候选 + 首选）

> 评估维度：来源、核心能力、推荐模型（haiku/sonnet/opus）、适配度（Write 权限 / JSON 信封兼容 / reasoning 深度）

### Phase 1 — 需求分析 + 三路调研（Auto-Scan / 技术调研 / 联网搜索）
此 Phase 会分三路并行派发，见 Part D。此处给出"需求理解主线 agent"：

| 序 | Agent | 来源 | 模型 | 能力摘要 | 适配度 |
|---|---|---|---|---|---|
| 1★ | `business-analyst` | VoltAgent | sonnet | 需求澄清 / 用户故事 / 验收标准 | Write ✓；JSON 信封需 prompt 约束；中等 reasoning |
| 2 | `conductor(setup)` | wshobson Conductor | sonnet/opus | 产品愿景 + 技术栈 + 流程规则生成 | Write ✓；偏重规划产物，需截断输出 |
| 3 | `researcher` | OMC | sonnet | 外部文档调研 | Write ✓；轻量 |
**首选：`business-analyst` (VoltAgent)**

### Phase 2/3 — OpenSpec + Fast-Forward 产物生成（机械型）
| 序 | Agent | 来源 | 模型 | 能力 | 适配度 |
|---|---|---|---|---|---|
| 1★ | `executor` | OMC | sonnet | 规格化文档落盘、文件改写 | Write ✓；强；当前预设 |
| 2 | `backend-developer` | VoltAgent | sonnet | 通用实现 | Write ✓ |
| 3 | `fullstack-developer` | VoltAgent | sonnet | 跨层文件生成 | Write ✓ |
**首选：`executor` (OMC)** — 机械操作 haiku/sonnet 足矣，无需 opus

### Phase 4 — 测试设计（TDD）
| 序 | Agent | 来源 | 模型 | 能力 | 适配度 |
|---|---|---|---|---|---|
| 1★ | `test-engineer` | OMC | sonnet | 测试策略 + flaky 加固 + 覆盖 | Write ✓；与 Phase 4 硬门禁完全对齐 |
| 2 | `qa-expert` / `test-automator` | VoltAgent | sonnet | 测试自动化 + 质量保障 | Write ✓；偏通用 |
| 3 | `qa-orchestra` | wshobson | sonnet | 多 agent QA + Chrome MCP 验证 | Write ✓；GUI 场景强，纯后端偏重 |
**首选：`test-engineer` (OMC)**

### Phase 5 — 实施（支持并行域 agent）
| 序 | Agent | 来源 | 模型 | 能力 | 适配度 |
|---|---|---|---|---|---|
| 1★ | `backend-developer` + `frontend-developer` | VoltAgent | sonnet | 域分离并行最佳 | Write ✓；天然支持并行派发 |
| 2 | `executor` | OMC | sonnet | 通用实现 | Write ✓；单域场景首选 |
| 3 | `python-pro` / `typescript-pro` | wshobson | sonnet | 语言深度特化 | Write ✓；按栈选择 |
**首选：并行 = VoltAgent `backend-developer`/`frontend-developer`；串行 = OMC `executor`**

### Phase 6 — 测试执行 + 报告
| 序 | Agent | 来源 | 模型 | 能力 | 适配度 |
|---|---|---|---|---|---|
| 1★ | `test-engineer` | OMC | sonnet | 执行 + 归纳 + 漂移报告 | Write ✓；与 Phase 4 同源，上下文可复用 |
| 2 | `qa-expert` | VoltAgent | sonnet | 质量综合报告 | Write ✓ |
| 3 | `comprehensive-review`（内 qa 分支） | wshobson | sonnet | 多 perspective 报告 | Write ✓ |
**首选：`test-engineer` (OMC)**

### Phase 6.5 — Code Review
| 序 | Agent | 来源 | 模型 | 能力 | 适配度 |
|---|---|---|---|---|---|
| 1★ | `code-reviewer` | VoltAgent | sonnet/opus | 代码质量 + 风格 + bug | Write ✓（写 review 产物）；与 review 语义严格对齐 |
| 2 | `architect-reviewer` | VoltAgent | opus | 架构级审查 | Write ✓；重大变更首选 |
| 3 | `reviewer`（api/security/performance 变体） | OMC | sonnet | 多维审查 | Write ✓；当前预设 |
**首选：`code-reviewer` (VoltAgent)；架构级升级为 `architect-reviewer`**

### Phase 7 — 归档
| 序 | Agent | 来源 | 模型 | 能力 | 适配度 |
|---|---|---|---|---|---|
| 1★ | `executor` | OMC | haiku | 机械归档、moves、索引 | Write ✓；低成本 |
| 2 | `dx-optimizer` | VoltAgent | sonnet | 归档 + DX 改进建议 | Write ✓；可选 |
| 3 | `project-manager` | VoltAgent | sonnet | 收尾 + 总结 | Write ✓ |
**首选：`executor` (OMC) + haiku**

---

## Part C：当前预设 vs 推荐预设 Diff

| Phase | 当前预设（推测） | 推荐预设 | 变更原因 |
|---|---|---|---|
| Phase 1 主线 | OMC `researcher` | VoltAgent `business-analyst` | `researcher` 偏外部资料；需求理解主线更应由 business-analyst 主导，researcher 降格到"技术调研路" |
| Phase 1 三路 | 单 researcher | 三路分离（见 Part D） | Auto-Scan/技术调研/联网搜索能力差异大，合并会稀释效果 |
| Phase 2/3 | OMC `executor` | 保持 `executor` | 无需改 |
| Phase 4 | OMC `test-engineer` | 保持 | 无需改 |
| Phase 5 并行 | OMC `executor` 多实例 | VoltAgent `backend-developer` + `frontend-developer` 域拆分 | 域分离时专职 agent 优于多实例通用 agent，减少 prompt 污染 |
| Phase 5 串行 | OMC `executor` | 保持 | 单域继续用 executor |
| Phase 6 | OMC `test-engineer` | 保持 | 无需改 |
| Phase 6.5 | OMC `reviewer` | VoltAgent `code-reviewer`（架构级升级 `architect-reviewer`） | VoltAgent code-reviewer 定位更专，OMC reviewer 更偏通用多变体 |
| Phase 7 | OMC `executor` | 保持（强制 haiku） | 通过模型降级省成本 |

**核心结论**：现有 OMC 预设在 Phase 2/3/4/6/7 已足够，**真正需要替换的是 Phase 1 三路分离 + Phase 5 并行域拆分 + Phase 6.5 代码评审专职化**。

---

## Part D：Phase 1 三路分离后的推荐组合

Phase 1 会并行派发三路调研，每路诉求差异巨大，应使用不同 agent：

### 路 1 — Auto-Scan（本地代码/结构扫描）
- **诉求**：快速枚举仓库结构、symbol、依赖、历史 commit 模式
- **候选**：
  - ★ OMC `explore`（注意：若 OMC explore 是只读则不可用 → 改为 `executor` 限制在扫描模式）
  - **首选**：**OMC `executor`（scan 模式）** — 保证 Write 权限，写入 `scan-report.json`
  - 备选：VoltAgent `refactoring-specialist`（含代码地图能力）
- **模型**：haiku/sonnet（haiku 优先）

### 路 2 — 技术调研（深度 reasoning）
- **诉求**：技术选型权衡、架构模式对比、tradeoff 分析
- **候选**：
  - ★ **首选**：**OMC `researcher`** — 定位就是"外部文档和参考研究"，天然匹配
  - 备选：wshobson `conductor` setup 阶段（偏产品/技术栈）
  - 备选：VoltAgent `research-analyst`
- **模型**：sonnet（关键决策可升级 opus）

### 路 3 — 联网搜索（WebSearch + 信息综合）
- **诉求**：抓取最新 API 文档、竞品、社区讨论；需要 WebSearch 工具 + 信息去噪 + 综合能力
- **候选**：
  - ★ **首选**：**VoltAgent `search-specialist`** — 专为搜索+综合而设，输出结构化
  - 备选：VoltAgent `data-researcher`
  - 备选：OMC `researcher`（配合 Exa MCP）
- **模型**：sonnet（搜索结果去噪需要一定 reasoning）
- **关键**：agent 必须显式启用 WebSearch 工具，并约束 JSON 信封返回

### 推荐组合汇总表

| 路 | 首选 Agent | 来源 | 模型 | 关键工具 |
|---|---|---|---|---|
| Auto-Scan | `executor`（scan 模式） | OMC | haiku | Read/Grep/Glob/Bash/Write |
| 技术调研 | `researcher` | OMC | sonnet | Read/Write + Context7 MCP |
| 联网搜索 | `search-specialist` | VoltAgent | sonnet | WebSearch/WebFetch/Write |

---

## 首选 Agent 推荐清单（快速决策）

| Phase | 首选 Agent | 来源 |
|---|---|---|
| Phase 1 主线 | `business-analyst` | VoltAgent |
| Phase 1 Auto-Scan | `executor`（scan 模式） | OMC |
| Phase 1 技术调研 | `researcher` | OMC |
| Phase 1 联网搜索 | `search-specialist` | VoltAgent |
| Phase 2/3 | `executor` | OMC |
| Phase 4 | `test-engineer` | OMC |
| Phase 5（并行后端） | `backend-developer` | VoltAgent |
| Phase 5（并行前端） | `frontend-developer` | VoltAgent |
| Phase 5（串行） | `executor` | OMC |
| Phase 6 | `test-engineer` | OMC |
| Phase 6.5 | `code-reviewer` / `architect-reviewer` | VoltAgent |
| Phase 7 | `executor`（haiku） | OMC |

---

## 附录：来源链接
- [OMC — Yeachan-Heo/oh-my-claudecode](https://github.com/Yeachan-Heo/oh-my-claudecode)
- [VoltAgent — awesome-claude-code-subagents](https://github.com/VoltAgent/awesome-claude-code-subagents)
- [wshobson/agents](https://github.com/wshobson/agents)
- [ECC — affaan-m/everything-claude-code](https://github.com/affaan-m/everything-claude-code)
- [GSD — gsd-build/get-shit-done](https://github.com/gsd-build/get-shit-done)
- [Gstack — garrytan/gstack](https://github.com/garrytan/gstack)
- [Superpowers — obra/superpowers](https://github.com/obra/superpowers)
- [anthropics/claude-plugins-official](https://github.com/anthropics/claude-plugins-official)
- [Hermes — NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent)
