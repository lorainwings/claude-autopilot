---
name: autopilot-phase2-3-openspec
description: "Use when the autopilot orchestrator main thread reaches Phase 2 or Phase 3 and must dispatch the mechanical OpenSpec change creation and Fast-Forward artifact generation as background tasks against the prepared requirements bundle. Not for direct user invocation; skip outside the orchestrator."
user-invocable: false
---

# Autopilot Phase 2-3 — OpenSpec 创建与 FF 生成

> **前置条件自检**：本 Skill 仅在 autopilot 编排主线程中使用。如果当前上下文不是 autopilot 编排流程，请立即停止并忽略本 Skill。

Phase 2 和 Phase 3 均为机械性 OpenSpec 操作，共享同一 agent 和 model tier。本 Skill 描述两者在统一调度模板中的特殊行为。

> dispatch 的具体 prompt 构造逻辑保持在 `autopilot-dispatch` 中。

## Phase 2: 创建 OpenSpec

**执行位置**: Task 子 Agent（`run_in_background: true`）

- Agent: `config.phases.openspec.agent`（默认 Plan）
- Model Tier: fast / haiku
- **必须使用 `run_in_background: true`**：此阶段为机械性操作（OpenSpec 创建），不应占用主窗口上下文
- 任务：从需求推导 kebab-case 名称，执行 `openspec new change "<name>"`
- 写入 context 文件（prd.md、discussion.md、ai-prompt.md）

**返回要求（必须严格遵守）**：执行完毕后，在输出的**最后一行**返回 JSON 信封：

```json
{"status": "ok", "summary": "已创建 OpenSpec change: <name>，包含 N 个文件", "artifacts": ["openspec/changes/<name>/proposal.md", ...]}
```

> Hook 验证要求 `status` 和 `summary` 两个字段都必须存在，缺少任一将被 block。

## Phase 3: FF 生成制品

**执行位置**: Task 子 Agent（`run_in_background: true`）

- Agent: `config.phases.openspec.agent`（默认 Plan）
- Model Tier: fast / haiku
- **必须使用 `run_in_background: true`**：此阶段为机械性操作（FF 生成），不应占用主窗口上下文
- 任务：按 openspec-ff-change 流程生成 proposal/specs/design/tasks

**返回要求（必须严格遵守）**：执行完毕后，在输出的**最后一行**返回 JSON 信封：

```json
{"status": "ok", "summary": "已生成 OpenSpec 制品: proposal/design/specs/tasks", "artifacts": ["openspec/changes/<name>/proposal.md", "openspec/changes/<name>/design.md", ...]}
```

> Hook 验证要求 `status` 和 `summary` 两个字段都必须存在，缺少任一将被 block。

## 共享约束

- Phase 2/3 采用**联合调度快速路径**：单次 gate 验证 + 单次 model routing + 两个串行 background Task
- Phase 2 完成后直接进入 Phase 3，**无需**再次调用 Skill("autopilot-gate") 或 resolve-model-routing.sh
- Phase 3 的前置 checkpoint 验证由 Hook L2 (`check-predecessor-checkpoint.sh`) 在 Task 派发时自动执行
- 两者均为 full 模式专属，lite/minimal 模式跳过
- 主编排器 `autopilot/SKILL.md` "Phase 2-3 联合调度快速路径" 定义了完整的 Fast-Step 0-9 流程
