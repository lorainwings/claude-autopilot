---
name: slim-task
description: "Use when the user invokes /slim-task or requests structured task execution with requirements clarification, best-practice research, impact-scoped solution design, DAG-based parallel sub-agent dispatch, quality review, and commit confirmation."
argument-hint: "[task description]"
user-invocable: true
---

6 阶段 SOP 编排器。主 Agent 只做检查/决策/派发/验证（主检子执），子 Agent 做实际编码。任务按 DAG 拓扑序最大化并行，无并行数量上限。

## 全局护栏

1. **主 Agent 禁止直接写代码** — 只做需求澄清、方案设计、任务拆分、派发、质量检查、提交确认
2. **Phase 2 审批前禁止任何代码变更** — 必须先完成需求澄清 + 方案设计 + 用户审批
3. **影响范围即合约** — 禁止修改影响范围表之外的任何文件
4. **每阶段必须有用户检查点** — 阶段转换前必须获得用户确认
5. **禁止未经确认的 commit/push** — Phase 6 必须通过 AskUserQuestion 获得明确授权
6. **UI 改动必检** — 涉及 UI 时必须调用 `frontend-design` 或 `ui-ux-pro-max` Skill
7. **完全独立** — 本插件不依赖任何其他插件的基础设施或模式

## Phase 1: 需求澄清

目标：将模糊的任务描述转化为精确的需求摘要。

1. 解析用户输入的任务描述
2. 识别：歧义点、缺失上下文、隐含假设、边界条件、验收标准
3. 使用 `AskUserQuestion` 向用户提出结构化澄清问题
4. 若任务已足够清晰，列出关键假设请用户确认
5. **输出**：精炼需求摘要（bulleted list）

**检查点**：用户确认需求摘要后进入 Phase 2。

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

向用户展示以下内容：

1. **方案描述**（1-3 段，含推荐理由和替代方案对比）
2. **影响范围表**（必须）：

| 操作 | 文件路径 | 理由 |
|------|---------|------|
| 修改 | `src/xxx.ts` | 具体原因 |
| 新增 | `src/yyy.ts` | 具体原因 |
| 不可触碰 | `src/zzz.ts` | 超出范围 |

3. **依赖影响** + **风险与权衡**

**检查点**：`AskUserQuestion` 请用户审批方案，审批通过后进入 Phase 3。

## Phase 3: 文档固化 + DAG 任务拆分

目标：将方案固化为项目文档，并按依赖关系拆分为可并行的子任务 DAG。

### 3a 文档固化

在项目中写入 `docs/tasks/{YYYY-MM-DD}/{task-slug}.md`，内容包含：

- Phase 1 的需求摘要
- Phase 2 的方案设计 + 影响范围表
- 执行时间戳

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

**检查点**：向用户展示 DAG 拆分结果，确认后进入 Phase 4。

## Phase 4: DAG 最大化并行执行

目标：按 DAG 拓扑序逐层派发子 Agent，最大化并行度。

### 执行协议

1. **Layer 0 启动**：所有无依赖的子任务同时派发
   - 使用 `Agent` 工具，`run_in_background: true`
   - 每个子 Agent 的 prompt 包含：Objective + File boundary + Tool boundary + Task boundary
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

## Output
完成后汇报：修改了哪些文件、做了什么变更、是否有遗留问题。
```

**检查点**：所有子 Agent 完成后，汇总结果通知用户，进入 Phase 5。

## Phase 5: 质量检查

目标：主 Agent 审查所有变更，确保符合方案和最佳实践。

### 5a 范围审查

- `git diff` 检查所有变更
- **验证无越界**：所有改动文件必须在影响范围表内
- **验证无遗漏**：影响范围表中的文件是否都已正确修改

### 5b 最佳实践对标

- 对照 Phase 2a 的最佳实践检查实现质量
- 检查代码风格与项目现有代码的一致性

### 5c 工程检查（涉及代码编写时）

- **Lint 检查**：检测项目中的 lint 工具配置（ESLint/shellcheck/ruff 等）并执行
- **构建检查**：前端 build / 后端 build / 类型检查（tsc/mypy 等）
- 所有检查必须通过后才能进入 Phase 6

### 5d UI 检查（涉及 UI 改动时）

- 提示用户调用 `frontend-design` 或 `ui-ux-pro-max` Skill 进行视觉一致性审查

### 5e 问题修复

- 列出所有发现的问题
- 派发子 Agent 修复问题
- 修复后重新验证 5a-5c

**检查点**：向用户展示质量检查报告，确认后进入 Phase 6。

## Phase 6: 提交确认

目标：获得用户明确授权后执行 commit 和可选的 push。

1. 展示：
   - 变更文件列表 + diff 摘要
   - 提议的 Conventional Commits 格式 commit message
2. 使用 `AskUserQuestion` 确认：
   - 是否 commit（Y/N）
   - 是否 push（Y/N，独立于 commit）
3. **用户确认 commit**：执行 `git add` + `git commit`
4. **用户确认 push**：执行 `git push`
5. **用户拒绝**：列出需要手动调整的事项，结束流程
