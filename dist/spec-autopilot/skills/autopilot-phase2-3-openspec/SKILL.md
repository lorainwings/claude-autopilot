---
name: autopilot-phase2-3-openspec
description: "Use when the autopilot orchestrator main thread reaches Phase 2 or Phase 3 and must dispatch the mechanical OpenSpec change creation and Fast-Forward artifact generation as background tasks against the prepared requirements bundle."
user-invocable: false
---

# Autopilot Phase 2-3 — OpenSpec 创建与 FF 生成

> **前置条件自检**：本 Skill 仅在 autopilot 编排主线程中使用。如果当前上下文不是 autopilot 编排流程，请立即停止并忽略本 Skill。

Phase 2 和 Phase 3 均为机械性 OpenSpec 操作，共享同一 agent 和 model tier。本 Skill 描述两者在统一调度模板中的特殊行为。（下文 `<name>` 表示从需求推导出的 kebab-case change 名）

> dispatch 的具体 prompt 构造逻辑保持在 `autopilot-dispatch` 中。

## 共同执行规范

Phase 2 与 Phase 3 共用以下派发约束：

- **执行位置**: Task 子 Agent
- **Agent**: `config.phases.openspec.agent`（默认 Plan）
- **Model Tier**: fast / haiku
- **必须使用 `run_in_background: true`**：机械性操作不应占用主窗口上下文
- **JSON 信封 schema（输出最后一行）**：`{"status": "ok", "summary": "...", "artifacts": [...]}`
  > Hook 验证要求 `status` 与 `summary` 必须存在，缺一即 block。

## Phase 2: 创建 OpenSpec

- 任务：从需求推导 kebab-case 名称，执行 `openspec new change "<name>"`，写入 context 文件（prd.md、discussion.md、ai-prompt.md）

示例 summary（artifacts 数组按实际产物展开）：

```json
{"status": "ok", "summary": "已创建 OpenSpec change: <name>，包含 N 个文件", "artifacts": ["openspec/changes/<name>/proposal.md" /* 其余制品按实际产物展开 */]}
```

## Phase 3: FF 生成制品

- 任务：按 openspec-ff-change 流程生成 proposal/specs/design/tasks

示例 summary（artifacts 数组按实际产物展开）：

```json
{"status": "ok", "summary": "已生成 OpenSpec 制品: proposal/design/specs/tasks", "artifacts": ["openspec/changes/<name>/proposal.md", "openspec/changes/<name>/design.md" /* 其余制品按实际产物展开 */]}
```

## 共享约束

- Phase 2/3 采用**联合调度快速路径**：单次 gate 验证 + 单次 model routing + 两个串行 background Task
- Phase 2 完成后直接进入 Phase 3，**无需**再次调用 Skill("autopilot-gate") 或 resolve-model-routing.sh
- Phase 3 的前置 checkpoint 验证由 Hook L2 (`check-predecessor-checkpoint.sh`) 在 Task 派发时自动执行
- 两者均为 full 模式专属，lite/minimal 模式跳过
- Skill 名 `autopilot` 内的 "Phase 2-3 联合调度快速路径" 章节定义了完整的 Fast-Step 0-9 流程
