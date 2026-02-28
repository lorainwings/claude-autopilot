---
name: autopilot-dispatch
description: "[ONLY for autopilot orchestrator] Sub-Agent dispatch protocol for autopilot phases. Constructs Task prompts with JSON envelope contract, explicit path injection, and parameterized templates."
user-invocable: false
---

# Autopilot Dispatch — 子 Agent 调度协议

> **前置条件自检**：本 Skill 仅在 autopilot 编排主线程中使用。如果当前上下文不是 autopilot 编排流程，请立即停止并忽略本 Skill。

从 `autopilot.config.yaml` 读取项目配置，构造标准化 Task prompt 分派子 Agent。

## 共享协议

> JSON 信封契约、阶段额外字段、状态解析规则、结构化标记等公共定义详见：`autopilot/references/protocol.md`。
> 以下仅包含 dispatch 专属的模板和指令。

## 显式路径注入模板

dispatch 子 Agent 时**必须**在 prompt 中明确列出所有引用文件路径：

```markdown
Task(prompt: "<!-- autopilot-phase:{phase_number} -->
你是 autopilot 阶段 {phase_number} 的子 Agent。
先读取以下指令文件：
{for each file in config.phases[phase].instruction_files}
- {file_path}
{end for}
再读取以下参考文件：
{for each file in config.phases[phase].reference_files}
- {file_path}
{end for}
执行完毕后返回结构化 JSON 结果。")
```

## 参数化调度模板

### 输入参数

| 参数 | 来源 |
|------|------|
| phase_number | 当前阶段编号 (2-6) |
| agent_name | config.phases[phase].agent 或默认 agent |
| change_name | 活跃 change 的 kebab-case 名称 |
| instruction_files | config.phases[phase].instruction_files |
| reference_files | config.phases[phase].reference_files |

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

### 测试金字塔比例约束

测试用例分布必须符合金字塔模型（从 `config.test_pyramid` 读取阈值，默认值如下）：
- **单元测试** ≥ 总用例数的 50%（快速反馈层）
- **API/集成测试** ≤ 总用例数的 30%（服务契约层）
- **E2E + UI 测试** ≤ 总用例数的 20%（端到端验证层）

返回信封中必须包含 `test_pyramid` 字段：
```json
{
  "test_pyramid": {
    "total": 25,
    "unit_pct": 60,
    "integration_pct": 24,
    "e2e_pct": 16
  }
}
```
```

**Phase 5（循环实施）**：
- 通过 ralph-loop 或 fallback 执行（由编排主线程决策）
- 指令文件从 config.phases.implementation.instruction_files 注入
- **Worktree 隔离模式**（当 config.phases.implementation.worktree.enabled = true）：
  - 主线程按 task 粒度逐个派发，每个 task 使用 `Task(isolation: "worktree")`
  - 子 Agent prompt 中注入当前 task 内容和前序 task 摘要
  - 子 Agent 完成后返回 worktree 路径和分支名，主线程决定合并策略

**Phase 6（测试报告）**：
- Agent: qa-expert
- 指令文件从 config.phases.reporting.instruction_files 注入
- 报告命令从 config.phases.reporting.report_commands 读取
- **Allure 统一报告**（当 `config.phases.reporting.format === "allure"` 时）：
  - 所有测试套件输出到同一 `allure-results/` 目录
  - pytest: `--alluredir=allure-results`
  - Playwright: reporter 配置 `allure-playwright`
  - JUnit: Allure Gradle Plugin 输出到 `allure-results/`
  - 生成统一报告: `npx allure generate allure-results -o allure-report --clean`
  - 返回 `report_format: "allure"` 和 `allure_results_dir` 路径
