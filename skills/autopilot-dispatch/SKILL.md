---
name: autopilot-dispatch
description: "Sub-Agent dispatch protocol for autopilot phases. Constructs Task prompts with JSON envelope contract, explicit path injection, and parameterized templates."
---

# Autopilot Dispatch — 子 Agent 调度协议

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
| 4 | `test_counts: { unit, api, e2e, ui }`, `dry_run_results: { unit, api, e2e, ui }` |
| 5 | `test_results_path`, `tasks_completed`, `iterations_used` |
| 6 | `pass_rate`, `report_url`, `report_path` |

### 状态解析规则

| status | 主线程行为 |
|--------|-----------|
| ok | 写入 checkpoint，继续下一阶段 |
| warning | 写入 checkpoint，展示警告后继续 |
| blocked | 暂停，展示给用户，要求排除阻塞 |
| failed | 暂停，展示给用户，可能需要重新执行本阶段 |

## 显式路径注入模板

dispatch 子 Agent 时**必须**在 prompt 中明确列出所有引用文件路径：

```markdown
Task(prompt: "你是 autopilot 阶段 {phase_number} 的子 Agent。
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

**Phase 5（循环实施）**：
- 通过 ralph-loop 或 fallback 执行（由编排 Agent 决策）
- 指令文件从 config.phases.implementation.instruction_files 注入

**Phase 6（测试报告）**：
- Agent: qa-expert
- 指令文件从 config.phases.reporting.instruction_files 注入
- 报告命令从 config.phases.reporting.report_commands 读取
