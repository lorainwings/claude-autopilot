---
name: autopilot-dispatch
description: "[ONLY for autopilot orchestrator] Sub-Agent dispatch protocol for autopilot phases. Constructs Task prompts with JSON envelope contract, explicit path injection, and parameterized templates."
---

# Autopilot Dispatch — 子 Agent 调度协议

> **前置条件自检**：本 Skill 仅在 autopilot 编排主线程中使用。如果当前上下文不是 autopilot 编排流程，请立即停止并忽略本 Skill。

从 `autopilot.config.yaml` 读取项目配置，构造标准化 Task prompt 分派子 Agent。

## JSON 信封契约

每个子 Agent 的 prompt 末尾**必须**要求返回此格式：

```json
{
  "status": "ok | warning | blocked | failed",
  "summary": "单行决策级摘要",
  "artifacts": ["已创建/修改的文件路径"],
  "risks": ["可选风险列表"],
  "next_ready": true
}
```

### 各阶段额外返回字段

| Phase | 额外字段 |
|-------|----------|
| 2-6 | `context_summary` (3-5 行核心决策与产出摘要) |
| 4 | `test_counts: { unit, api, e2e, ui }`, `dry_run_results: { unit, api, e2e, ui }` |
| 5 | `test_results_path`, `tasks_completed`, `zero_skip_check: { passed: bool }`, `iterations_used` |
| 6 | `pass_rate`, `report_url`, `report_path` |

### 状态解析规则

| status | 主线程行为 |
|--------|-----------|
| ok | 写入 checkpoint，继续下一阶段 |
| warning | 写入 checkpoint，展示警告后继续（**Phase 4 例外：见下**） |
| blocked | 暂停，展示给用户，要求排除阻塞 |
| failed | 暂停，展示给用户，可能需要重新执行本阶段 |

**Phase 4 特殊规则**：Phase 4（测试设计）**不接受 warning**。如果 Phase 4 返回 warning 且 test_counts 任一项 < 门禁阈值，主线程必须将 status 覆盖为 blocked 并重新 dispatch。

## 结构化标记（Hook 识别依据）

每个子 Agent 的 prompt **开头第一行**必须包含标记：

```
<!-- autopilot-phase:{phase_number} -->
```

此标记是 Hook 脚本（`check-predecessor-checkpoint.sh` / `validate-json-envelope.sh`）识别 autopilot Task 的**唯一依据**。无标记的 Task 调用会被 Hook 直接放行（exit 0），不执行任何校验。

## 显式路径注入模板

dispatch 子 Agent 时**必须**在 prompt 中明确列出所有引用文件路径：

```markdown
Task(
  prompt: "<!-- autopilot-phase:{phase_number} -->
你是 autopilot 阶段 {phase_number} 的子 Agent。
先读取以下指令文件：
{for each file in config.phases[phase].instruction_files}
- {file_path}
{end for}
再读取以下参考文件：
{for each file in config.phases[phase].reference_files}
- {file_path}
{end for}
执行完毕后返回结构化 JSON 结果。",
  model: "{resolved_model}"
)
```

### 模型解析规则

按优先级从高到低解析 `model` 参数：

1. `config.model_tier.phase_{N}` — 阶段级覆盖
2. `config.model_tier.default` — 全局默认
3. `"opus"` — 硬编码兜底

缺失 `model_tier` 配置节 → 所有阶段使用 Opus（向后兼容）。

### 契约链注入

dispatch 时主线程从前置 checkpoint 提取字段直接注入子 Agent prompt：

```markdown
**前置阶段上下文（Phase {N-1} 产出）**：
- 状态: {predecessor.status}
- 摘要: {predecessor.context_summary ?? predecessor.summary}
- 产物: {predecessor.artifacts}
- 风险: {predecessor.risks ?? "无"}
```

注入规则:
- Phase 2: 不注入（首个子 Agent 阶段，无前置 checkpoint）
- Phase 3-6: 注入前一阶段 checkpoint 的上述字段
- 字段缺失时降级: `context_summary` 缺失 → 使用 `summary`; `risks` 缺失 → 填入 "无"

### 上下文压缩建议

长流水线执行中建议在以下时机执行 `/compact`：

| 时机 | 原因 |
|------|------|
| Phase 3 完成后 | 需求分析 + OpenSpec 创建的上下文已持久化到 checkpoint，可安全释放 |
| Phase 5 完成后 | 实施阶段产生大量代码上下文，释放后为测试报告腾出空间 |

主线程在上述阶段 checkpoint 写入成功后，**可选**输出提示：`"💡 建议执行 /compact 释放上下文空间（阶段状态已持久化到 checkpoint）"`。

## 参数化调度模板

### 输入参数

| 参数 | 来源 |
|------|------|
| phase_number | 当前阶段编号 (2-6) |
| agent_name | config.phases[phase].agent 或默认 agent |
| change_name | 活跃 change 的 kebab-case 名称 |
| instruction_files | config.phases[phase].instruction_files |
| reference_files | config.phases[phase].reference_files |
| model | config.model_tier.phase_{N} ?? config.model_tier.default ?? "opus" |

### 子 Agent 前置校验指令（必须包含在 prompt 开头）

```markdown
**前置校验（在执行任何操作之前）**：
1. 读取 `openspec/changes/{change_name}/context/phase-results/phase-{N-1}-*.json`
2. 如果文件不存在 → 立即返回：
   `{"status": "blocked", "summary": "Phase {N-1} checkpoint 不存在"}`
3. 如果 status 不是 "ok" 或 "warning" → 立即返回：
   `{"status": "blocked", "summary": "Phase {N-1} 状态为 {status}"}`
4. 校验通过后，继续执行本阶段任务。
```

### 各阶段调度内容

**Phase 2（创建 OpenSpec）**：
- Agent: general-purpose
- 任务：从需求推导 kebab-case 名称，执行 `openspec new change "<name>"`
- 写入 context 文件（prd.md、discussion.md、ai-prompt.md）

**Phase 3（FF 生成制品）**：
- Agent: general-purpose
- 任务：按 openspec-ff-change 流程生成 proposal/specs/design/tasks
- artifacts 列出所有已创建制品路径

**Phase 4（测试用例设计）**：
- Agent: config.phases.testing.agent（默认 qa-expert）
- 指令文件 + 参考文件从 config 注入
- 门禁：4 类测试全部创建、每类 ≥ min_test_count_per_type
- **Phase 4 不可跳过，不可降级为 warning**

Phase 4 子 Agent prompt 必须包含以下强制指令：

```markdown
## 强制要求（不可违反）

你**必须**创建实际的测试文件，不允许以"后续补充"或"纯 UI 变更不需要"为由跳过。

### 必须创建的 4 类测试文件

1. **单元测试**（≥5 个用例）
   - 后端: `backend/src/test/java/.../*Test.java` (JUnit 5)
   - 或前端: `frontend/*/src/**/*.spec.ts` (Vitest)
2. **API 集成测试**（≥5 个用例）
   - `tests/api/test_*_api.py` (pytest)
   - 如无新 API，测试现有 API 的联通性和字段校验
3. **E2E 端到端测试**（≥5 个用例）
   - `tests/e2e/*.spec.ts` (Playwright)
   - 覆盖完整用户操作流程
4. **UI 自动化测试**（≥5 个用例）
   - `tests/ui/test_*_ui.py` (Playwright + pytest)
   - 覆盖组件渲染、交互、响应式

### 测试计划文档（必须创建）

在 `openspec/changes/{change_name}/context/test-plan.md` 中记录：
- 测试策略概述
- 各类型用例数量统计
- 每个测试文件路径和覆盖范围

### Dry-run 语法验证（必须执行）

创建测试文件后必须执行语法检查：
- 后端: `cd backend && ./gradlew test --dry-run` 或 `javac` 编译检查
- pytest: `python -m py_compile <file>`
- Playwright: `npx tsc --noEmit <file>`

### 返回要求

status 只允许 "ok" 或 "blocked"：
- 所有测试文件创建成功 + dry-run 通过 → `"status": "ok"`
- 任何原因无法创建 → `"status": "blocked"`，summary 说明阻塞原因
- **禁止返回 "warning"**：Phase 4 不接受降级通过
```

**Phase 5（循环实施）**：
- 通过 ralph-loop 或 fallback 执行（由编排主线程决策）
- 指令文件从 config.phases.implementation.instruction_files 注入

**Phase 6（测试报告）**：
- Agent: qa-expert
- 指令文件从 config.phases.reporting.instruction_files 注入
- 报告命令从 config.phases.reporting.report_commands 读取

---

## 并行调度协议

当 `config.parallel.enabled` 且对应阶段的 `parallel.phase_{N}.enabled` 为 true 时，dispatch 可在单条消息中发起多个并行 Task。

### 并行标记扩展

并行子 Agent 的 prompt 使用扩展标记：

```
<!-- autopilot-phase:{phase_number} sub:{sub_type} -->
```

例如 `<!-- autopilot-phase:4 sub:unit -->`。`sub:` 后缀让 Hook 脚本仍然通过正则 `autopilot-phase:4` 匹配为 Phase 4 Task，同时允许区分子任务。

### Phase 4 并行调度模板

主线程在单条消息中同时 dispatch 4 个 Task：

```
Task 4a: <!-- autopilot-phase:4 sub:unit -->
  → 设计单元测试（≥5 用例），model: {resolved_model}
  → 返回 JSON: { status, test_counts: { unit: N }, artifacts: [...], context_summary }

Task 4b: <!-- autopilot-phase:4 sub:api -->
  → 设计 API 集成测试（≥5 用例），model: {resolved_model}
  → 返回 JSON: { status, test_counts: { api: N }, artifacts: [...], context_summary }

Task 4c: <!-- autopilot-phase:4 sub:e2e -->
  → 设计 E2E 测试（≥5 用例），model: {resolved_model}
  → 返回 JSON: { status, test_counts: { e2e: N }, artifacts: [...], context_summary }

Task 4d: <!-- autopilot-phase:4 sub:ui -->
  → 设计 UI 自动化测试（≥5 用例），model: {resolved_model}
  → 返回 JSON: { status, test_counts: { ui: N }, artifacts: [...], context_summary }
```

每个子 Agent 的 prompt 仍须包含:
- 前置校验指令（读取 Phase 3 checkpoint）
- 对应测试类型的强制要求（从 Phase 4 完整指令中提取对应部分）
- 契约链注入（Phase 3 产出）
- JSON 信封契约（只需返回该子类型负责的 `test_counts` 字段）

### Fallback

如果 `config.parallel` 缺失、`parallel.enabled = false` 或 `parallel.phase_{N}.enabled = false`，退回单 Agent 串行模式（现有行为，向后兼容）。
