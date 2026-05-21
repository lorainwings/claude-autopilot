# Phase 0-6 完整 SOP

本文件包含各阶段的详细执行步骤。主 SKILL.md 仅保留阶段索引，具体操作参照此处。

## Contents

- [Phase 0: 会话初始化](#phase-0-会话初始化)
- [Phase 1: 需求澄清](#phase-1-需求澄清)
- [Phase 2: 方案设计](#phase-2-方案设计)
- [Phase 3: 文档固化 + DAG 任务拆分](#phase-3-文档固化--dag-任务拆分)
- [Phase 4: DAG 最大化并行执行](#phase-4-dag-最大化并行执行)
- [Phase 5: 质量检查（独立审计 Agent 盲审）](#phase-5-质量检查独立审计-agent-盲审)
- [Phase 6: 提交确认](#phase-6-提交确认)

---

## Phase 0: 会话初始化

1. **参数解析**：从 args 提取 `--lang` / `--worktree` / `--base`
2. **语言决策**（优先级）：
   - 命令行 `--lang` > 仓库 `.claude/slim-task.json` 的 `language` 字段 > 默认 `zh-CN`
   - 首次确定后写入 `.claude/slim-task.json`（若不存在则创建）持久化为后续默认值
3. **`.gitignore` 自检**（首次运行必检）：
   - 检查仓库 `.gitignore` 是否包含 `.claude/slim-task.json` 与 `.claude/slim-task/`（运行时配置 + Phase 5 审计落盘）
   - 任一缺失：通过 `AskUserQuestion` 决策卡确认后追加，禁止静默写入；用户拒绝则继续但提示后续 commit 必须人工排除这些路径
   - 仓库无 `.gitignore` 时：提示用户在仓库根创建并加入上述两条
4. **Worktree 决策**：
   - 若 `--worktree` 未出现：跳过，保持当前工作树
   - 若 `--worktree` 出现：
     a. `AskUserQuestion` 确认基线分支（默认 `head` 当前分支；可选 `origin/main` 或自定义）
     b. 调用 `EnterWorktree(name=slim-<task-slug>-<timestamp>)`
     c. 检查 `.gitignore` 是否包含 `.claude/worktrees/`，缺失则比照 step 3 流程补齐
5. **输出初始化摘要**：`LANG=... | WORKTREE=<path 或 none> | BASE=<branch> | GITIGNORE=<ok 或 patched/skipped>`

**检查点**：执行标准检查点协议，选项为「采纳 → Phase 1 / 修改配置 / 终止」。

---

## Phase 1: 需求澄清

1. 解析用户输入的任务描述
2. 识别：歧义点、缺失上下文、隐含假设、边界条件、验收标准
3. 使用 `AskUserQuestion` 向用户提出结构化澄清问题（选项按 `${LANG}`）
4. 若任务已足够清晰，列出关键假设请用户确认
5. **输出**：精炼需求摘要（bulleted list，按 `${LANG}`）

**检查点**：执行标准检查点协议，选项为「采纳 → Phase 2 / 补充澄清 / 终止」。

---

## Phase 2: 方案设计

### 2a 最佳实践调研

- **优先使用 AI 内置知识**推荐最佳实践、设计模式、已知陷阱
- **仅当内置知识可能过时时**（新版本 API、新发布的库、近期安全公告）使用 `WebSearch` 补充

### 2b 代码库扫描

- 派发 `Explore` 子 Agent（`subagent_type: Explore`）扫描代码库
- 查找：相关代码、可复用的工具函数、现有设计模式、潜在冲突点
- 可同时派发多个 Explore Agent 扫描不同维度

### 2c 方案输出

向用户展示（按 `${LANG}`）：

1. **方案描述**（1-3 段，含推荐理由和替代方案对比）
2. **影响范围表**（必须）：

| 操作 | 文件路径 | 理由 |
|------|---------|------|
| 修改 | `src/xxx.ts` | 具体原因 |
| 新增 | `src/yyy.ts` | 具体原因 |
| 不可触碰 | `src/zzz.ts` | 超出范围 |

3. **依赖影响** + **风险与权衡**

**检查点**：执行标准检查点协议，选项为「批准方案 → Phase 3 / 修改方案 / 终止」。

---

## Phase 3: 文档固化 + DAG 任务拆分

### 3a 文档固化

在项目中写入 `docs/tasks/{YYYY-MM-DD}/{task-slug}.{lang}.md`，内容包含：

- Phase 1 的需求摘要
- Phase 2 的方案设计 + 影响范围表
- 执行时间戳 + Worktree 路径（若启用）

### 3b DAG 任务拆分

1. 将方案分解为原子子任务
2. 分析依赖关系，构建 **DAG（有向无环图）**
3. 识别 DAG 层级：
   - **Layer 0**：无前置依赖（可立即并行）
   - **Layer 1**：依赖 Layer 0
   - **Layer N**：依此类推
4. 每个子任务必须包含：
   - **Objective**：具体要完成什么
   - **File boundary**：允许修改的文件列表（源自影响范围表）
   - **Dependencies**：前置子任务 ID
   - **Output format**：完成标准

**检查点**：执行标准检查点协议，选项为「采纳 DAG → Phase 4 / 修改拆分 / 终止」。

---

## Phase 4: DAG 最大化并行执行

### 执行协议

1. **Layer 0 启动**：所有无依赖任务同时派发（`Agent` 工具，`run_in_background: true`）
2. **逐层推进**：Layer N 全部完成后，自动派发 Layer N+1
3. **无并行上限**：同层任务全部同时派发
4. **单任务优化**：若 DAG 仅有 1 个节点，主 Agent 直接内联执行
5. **主 Agent 职责**：监控完成通知，汇总执行结果

子 Agent prompt 格式见 `references/subagent-prompt-template.md`。

**检查点**：执行标准检查点协议，选项为「进入 Phase 5 审计 / 回退修复 / 终止」。

---

## Phase 5: 质量检查（独立审计 Agent 盲审）

详细审计协议见 `references/phase5-audit-protocol.md`。

核心流程：
1. 并行派发 scope-auditor / practice-auditor / engineering-auditor 三个独立审计 Agent
2. 涉及 UI 时提示用户调用视觉审查 Skill
3. 汇总审计报告，有 issue 则派发修复 Agent → 复核（上限 3 轮）
4. 全部通过后执行检查点

**检查点**：执行标准检查点协议，选项为「批准 → Phase 6 / 派修复 Agent / 终止」。

---

## Phase 6: 提交确认

### 核心铁律

- 历史笼统指令**不构成本阶段授权**，必须重新发起 `AskUserQuestion`
- 严禁主 Agent 自行执行 `git commit` / `git push` / `gh pr create` 后追溯告知

### 执行步骤

1. 展示（按 `${LANG}`）：变更文件列表 + diff 摘要 + 提议的 Conventional Commits 格式 commit message
2. **Worktree 模式禁用文件检查**：staged 文件命中 `release-please-config.json` / `.release-please-manifest.json` / `.claude-plugin/marketplace.json` 则拒绝 commit
3. **第一次 `AskUserQuestion`（Commit 决策卡）**：
   - 「确认 commit」 / 「修改 message 后再 commit」 / 「取消回 Phase 5」
4. commit 后**立即第二次 `AskUserQuestion`（Push/PR 决策卡）**：
   - 「push + 开 PR」 / 「仅 push」 / 「保留本地不 push」
   - worktree 模式下「push 到 main」选项**必须禁用**
5. 按决策执行，完成后汇报
6. **Worktree 收尾**：`AskUserQuestion` 询问是否 `ExitWorktree(action=keep)` 保留 worktree，并给出合并指引：
   ```bash
   git fetch && git checkout main && git merge worktree-slim-<slug>
   ```
7. **用户拒绝 commit**：列出手动调整事项，结束流程
