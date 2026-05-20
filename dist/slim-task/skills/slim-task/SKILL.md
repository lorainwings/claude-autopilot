---
name: slim-task
description: "Use when the user invokes /slim-task or requests structured task execution with session init, requirements clarification, best-practice research, impact-scoped solution design, DAG-based parallel sub-agent dispatch, blind-audit quality review by independent sub-agents, and commit confirmation."
argument-hint: "[task description] [--lang zh-CN|en-US|...] [--worktree] [--base <branch>]"
user-invocable: true
---

7 阶段 SOP 编排器（Phase 0-6）。主 Agent 只做检查/决策/派发/验证（主检子执），子 Agent 做实际编码与质量审计。任务按 DAG 拓扑序最大化并行。Phase 5 由独立审计子 Agent 盲审，防止自评作弊。

## 全局护栏

1. **主 Agent 禁止直接写代码** — 只做需求澄清、方案设计、任务拆分、派发、汇总、提交确认
2. **Phase 2 审批前禁止任何代码变更** — 必须先完成需求澄清 + 方案设计 + 用户审批
3. **影响范围即合约** — 禁止修改影响范围表之外的任何文件
4. **每阶段必须有用户检查点（强制工具调用）** — 阶段转换前**必须调用 `AskUserQuestion` 工具**获得显式授权；禁止用纯文本提问（"要不要 / 是否继续 / 看起来如何"）作为检查点替代
5. **禁止未经确认的 commit/push** — Phase 6 commit 与 push 必须**分别**调用 `AskUserQuestion`（两次独立决策卡）获得明确授权；用户在历史对话中的笼统指令（如 "提交并推送" "拉个 PR"）**不构成本次授权**，仍须在执行点重新通过 `AskUserQuestion` 二次确认
6. **UI 改动必检** — 涉及 UI 时必须调用 `frontend-design` 或 `ui-ux-pro-max` Skill
7. **完全独立** — 本插件不依赖任何其他插件的基础设施或模式
8. **语言一致性** — 面向用户的对话、AskUserQuestion 选项、生成文档、子 Agent prompt 全部使用 `${LANG}` 配置语言（默认 `zh-CN`）。Conventional Commits 前缀保持英文，commit body 按 `${LANG}`；代码标识符 / API 名 / 框架关键字保持原文
9. **Worktree 模式硬约束** — 进入 worktree 后禁止 commit `release-please-config.json` / `.release-please-manifest.json` / `.claude-plugin/marketplace.json`；禁止 auto-merge 回 main 或 push 到 origin/main；只能由用户人工合并
10. **检查点 AskUserQuestion 标准格式** — 每个检查点的决策卡至少包含三选项：「采纳进入下阶段」「修改后重审」「终止流程」；选项标签按 `${LANG}`；自由文本回复（如用户答"不错"）**不自动视为采纳**，必须再次发起决策卡或显式询问

## Phase 0: 会话初始化

目标：解析参数、确定语言、决策是否使用 worktree。

1. **参数解析**：从 args 提取 `--lang` / `--worktree` / `--base`
2. **语言决策**（优先级）：
   - 命令行 `--lang` > 仓库 `.claude/slim-task.json` 的 `language` 字段 > 默认 `zh-CN`
   - 首次确定后写入 `.claude/slim-task.json`（若不存在则创建）持久化为后续默认值
3. **Worktree 决策**：
   - 若 `--worktree` 未出现：跳过，保持当前工作树（默认行为）
   - 若 `--worktree` 出现：
     a. `AskUserQuestion` 确认基线分支（默认 `head` 当前分支；可选 `origin/main` 或自定义）
     b. 调用 `EnterWorktree(name=slim-<task-slug>-<timestamp>)`
     c. 检查仓库根 `.gitignore` 是否包含 `.claude/worktrees/`，缺失则提示用户补齐
4. **输出初始化摘要**：`LANG=... | WORKTREE=<path 或 none> | BASE=<branch>`

**检查点（强制 `AskUserQuestion`）**：必须调用 `AskUserQuestion` 决策卡，展示初始化摘要并提供「采纳进入 Phase 1 / 修改语言或 worktree 配置 / 终止」三选项；用户选定「采纳」后进入 Phase 1。

## Phase 1: 需求澄清

目标：将模糊的任务描述转化为精确的需求摘要。

1. 解析用户输入的任务描述
2. 识别：歧义点、缺失上下文、隐含假设、边界条件、验收标准
3. 使用 `AskUserQuestion` 向用户提出结构化澄清问题（选项按 `${LANG}` 输出）
4. 若任务已足够清晰，列出关键假设请用户确认
5. **输出**：精炼需求摘要（bulleted list，按 `${LANG}`）

**检查点（强制 `AskUserQuestion`）**：必须调用 `AskUserQuestion` 决策卡，展示需求摘要并提供「采纳进入 Phase 2 / 补充澄清问题 / 终止」三选项；自由文本回复不视为采纳。

## Phase 2: 方案设计

目标：基于最佳实践和代码现状，输出带影响范围的可执行方案。

### 2a 最佳实践调研

- **优先使用 AI 内置知识**推荐最佳实践、设计模式、已知陷阱
- **仅当内置知识可能过时时**（新版本 API、新发布的库、近期安全公告）使用 `WebSearch` 补充

### 2b 代码库扫描

- 派发 `Explore` 子 Agent（`Agent` 工具，`subagent_type: Explore`）扫描代码库
- 查找：相关代码、可复用的工具函数、现有设计模式、潜在冲突点
- 可同时派发多个 Explore Agent 扫描不同维度

### 2c 方案输出

向用户展示以下内容（按 `${LANG}`）：

1. **方案描述**（1-3 段，含推荐理由和替代方案对比）
2. **影响范围表**（必须）：

| 操作 | 文件路径 | 理由 |
|------|---------|------|
| 修改 | `src/xxx.ts` | 具体原因 |
| 新增 | `src/yyy.ts` | 具体原因 |
| 不可触碰 | `src/zzz.ts` | 超出范围 |

1. **依赖影响** + **风险与权衡**

**检查点（强制 `AskUserQuestion`）**：必须调用 `AskUserQuestion` 决策卡，展示方案描述 + 影响范围表 + 风险，提供「批准方案进入 Phase 3 / 修改方案 / 终止」三选项；批准通过后进入 Phase 3。

## Phase 3: 文档固化 + DAG 任务拆分

目标：将方案固化为项目文档，并按依赖关系拆分为可并行的子任务 DAG。

### 3a 文档固化

在项目中写入 `docs/tasks/{YYYY-MM-DD}/{task-slug}.{lang}.md`（文件名含语言后缀，例 `.zh-CN.md` / `.en-US.md`），内容包含：

- Phase 1 的需求摘要
- Phase 2 的方案设计 + 影响范围表
- 执行时间戳 + Worktree 路径（若启用）

### 3b DAG 任务拆分

1. 将方案分解为原子子任务
2. 分析子任务间的依赖关系，构建 **DAG（有向无环图）**
3. 识别 DAG 层级：
   - **Layer 0**：无前置依赖的任务（可立即并行）
   - **Layer 1**：依赖 Layer 0 的任务
   - **Layer N**：依此类推
4. 每个子任务必须包含：
   - **Objective**：具体要完成什么
   - **File boundary**：允许修改的文件列表（源自影响范围表）
   - **Dependencies**：前置子任务 ID
   - **Output format**：完成标准

**检查点（强制 `AskUserQuestion`）**：必须调用 `AskUserQuestion` 决策卡展示 DAG 拆分结果（含 Layer/Objective/File boundary），提供「采纳并派发 Phase 4 / 修改拆分 / 终止」三选项。

## Phase 4: DAG 最大化并行执行

目标：按 DAG 拓扑序逐层派发子 Agent，最大化并行度。

### 执行协议

1. **Layer 0 启动**：所有无依赖的子任务同时派发
   - 使用 `Agent` 工具，`run_in_background: true`
   - 每个子 Agent 的 prompt 包含：Objective + File boundary + Tool boundary + Task boundary + Language
2. **逐层推进**：Layer N 全部完成后，自动派发 Layer N+1 的全部任务
3. **无并行上限**：同层任务全部同时派发，不限数量
4. **单任务优化**：若 DAG 仅有 1 个节点，由主 Agent 直接内联执行，不派子 Agent
5. **主 Agent 职责**：监控子 Agent 完成通知，汇总执行结果

### 子 Agent Prompt 模板

```
## Objective
{子任务目标}

## File Boundary
仅允许修改以下文件：{文件列表}
严禁修改此范围外的任何文件。

## Task Boundary
不要做超出目标范围的额外工作（不重构无关代码、不添加不需要的功能）。

## Language
Respond in ${LANG}. Code identifiers and English-only conventions
(commit prefix, API names, framework keywords) stay original.

## Output
完成后汇报：修改了哪些文件、做了什么变更、是否有遗留问题。
```

**检查点（强制 `AskUserQuestion`）**：所有子 Agent 完成后，必须调用 `AskUserQuestion` 决策卡展示执行汇总，提供「进入 Phase 5 审计 / 回退修复 / 终止」三选项。

## Phase 5: 质量检查（独立审计 Agent 盲审）

目标：派发独立审计子 Agent 在隔离 context 内对实现做盲审，防止自评作弊。

**核心反作弊原则**：写实现的 Agent ≠ 审实现的 Agent。主 Agent 只做派发与汇总，**不做实质审查**。所有审计子 Agent 的 prompt 严禁注入 Phase 4 子 Agent 的执行日志、思考过程、自评结论。

### 5a 范围审查 — 派发 scope-auditor

`Agent` 工具，`subagent_type: general-purpose`。prompt 注入：

- 任务描述（Phase 1 摘要）
- 影响范围表（Phase 2 审批版本）
- 完整 `git diff` 输出

职责：判定所有改动文件是否在影响范围表内 + 表中预期改动是否真的发生。
输出：`.claude/slim-task/audits/{task-slug}/scope-audit.json`（含越界文件、遗漏文件列表）。

### 5b 最佳实践对标 — 派发 practice-auditor

`Agent` 工具，`subagent_type: general-purpose`。prompt 注入：

- 任务描述 + Phase 2c 方案
- 完整 `git diff` 输出
- 项目编码规范引用（`CLAUDE.md` / `.claude/rules/code-quality.md` 等路径）

职责：对照方案与项目规范评分；标记偏离与违规。
输出：`practice-audit.json`。

### 5c 工程检查 — 派发 engineering-auditor

`Agent` 工具，`subagent_type: general-purpose`。prompt 注入：

- 项目根路径 + 影响范围内文件路径
- 项目 lint / build / typecheck 命令清单（从 `CLAUDE.md` / `Makefile` 自动发现）

职责：执行 lint / build / typecheck，捕获所有失败。
输出：`engineering-audit.json`（含失败命令、错误日志）。

### 5d UI 检查（涉及 UI 改动时）

提示用户调用 `frontend-design` 或 `ui-ux-pro-max` Skill 进行视觉一致性审查。

### 5e 汇总与修复

主 Agent：

1. 读取 3 份 `audit.json`
2. 向用户展示统一审计报告（按 `${LANG}`）
3. 若存在 issue：派发 fixer 子 Agent（独立 context，**不复用** Phase 4 原 Agent ID）修复
4. 修复后再次派发 5a/5b/5c 审计 Agent 复核（同样独立 context）
5. 全部通过后进入 Phase 6

**隔离硬约束**：

- 审计 Agent prompt 严禁包含 Phase 4 实现 Agent 的对话历史、思考记录、自评内容
- 审计 Agent 与 fixer Agent 均使用 `general-purpose` subagent_type 独立派发
- 单次 Phase 5 循环上限 3 次（修复 + 复核），超过则停下让用户人工介入

**检查点（强制 `AskUserQuestion`）**：必须调用 `AskUserQuestion` 决策卡展示三份 audit.json 综合报告，提供「批准进入 Phase 6 提交 / 派 fixer 修复后复审 / 终止」三选项。

## Phase 6: 提交确认

目标：获得用户明确授权后执行 commit 和可选的 push / PR。

**核心铁律**：

- 用户在本会话历史中的笼统指令（"提交并推送"、"拉个 PR"、"全部弄完"）**不构成本阶段授权**
- 每次进入 Phase 6 必须**重新发起**至少 1 次 `AskUserQuestion`（commit 决策）
- 若用户在 commit 决策卡选「commit + push」，仍需**第二次** `AskUserQuestion` 确认 push 与 PR 范围
- 严禁主 Agent 自行执行 `git commit` / `git push` / `gh pr create` 后再追溯告知

执行步骤：

1. 展示（按 `${LANG}`）：
   - 变更文件列表 + diff 摘要
   - 提议的 Conventional Commits 格式 commit message（前缀保持英文 `feat:`/`fix:`/...，body 按 `${LANG}`）
2. **Worktree 模式禁用文件检查**：若处于 worktree，扫描 staged 文件，命中以下任一则拒绝 commit 并提示：
   - `release-please-config.json` / `.release-please-manifest.json` / `.claude-plugin/marketplace.json`
3. **第一次 `AskUserQuestion`（Commit 决策）**，选项至少包含：
   - 「确认 commit（按提议的 message）」
   - 「修改 commit message 后再 commit」
   - 「取消，回到 Phase 5」
4. 若用户选确认 commit：执行 `git add` + `git commit`，**然后立即发起第二次 `AskUserQuestion`（Push / PR 决策）**，选项至少包含：
   - 「push 到当前分支并开 PR」
   - 「仅 push，不开 PR」
   - 「保留本地不 push（用户稍后人工处理）」
   - **worktree 模式下「push 到 main」选项必须禁用**
5. 按用户在第二次决策卡的选择执行；执行后再做最后汇报，不得追加自作主张的动作
6. **Worktree 收尾**：再发起一次 `AskUserQuestion` 询问是否 `ExitWorktree(action=keep)` 保留 worktree 待用户人工合并；给出合并指引：

   ```bash
   git fetch && git checkout main && git merge worktree-slim-<slug>
   ```

7. **用户拒绝 commit**：列出需要手动调整的事项，结束流程，不得自动进入 push/PR 步骤
