---
name: autopilot-gate
description: "[ONLY for autopilot orchestrator agent] Gate verification protocol for autopilot phase transitions. Enforces 8-step checklist, special gates, and cognitive shortcut immunity."
---

# Autopilot Gate — 门禁验证协议

> **前置条件自检**：本 Skill 仅在 autopilot 编排 Agent 上下文中使用。如果你不是由 autopilot agent 调度的，请立即停止并忽略本 Skill。

阶段切换时的 AI 侧验证清单。Layer 1（Task blockedBy）和 Layer 2（磁盘 checkpoint）已由 Hooks 确定性执行，本 Skill 负责 Layer 3（AI 执行的补充检查清单）。

## 三层门禁架构

| 层级 | 机制 | 执行者 |
|------|------|--------|
| Layer 1 | TaskCreate + blockedBy 依赖 | 任务系统（自动） |
| Layer 2 | 磁盘 checkpoint JSON 校验 | Hook 脚本（确定性） |
| **Layer 3** | **8 步切换清单 + 特殊门禁** | **本 Skill（AI 执行）** |

## 8 步阶段切换检查清单

每次从 Phase N 切换到 Phase N+1 时，**必须**执行：

```
- [ ] Step 1: 确认阶段 N 的子 Agent 已返回 JSON 信封
- [ ] Step 2: 验证 JSON status 为 "ok" 或 "warning"
- [ ] Step 3: 将 JSON 写入 phase-results/phase-N-*.json（由 checkpoint Skill 执行）
- [ ] Step 4: TaskUpdate 将阶段 N 标记为 completed
- [ ] Step 5: TaskGet 阶段 N+1 的任务，确认 blockedBy 为空
- [ ] Step 6: 读取 phase-results/phase-N-*.json 确认文件存在且可解析
- [ ] Step 7: TaskUpdate 将阶段 N+1 标记为 in_progress
- [ ] Step 8: 准备 dispatch 子 Agent（由 dispatch Skill 执行）
```

**任何 Step 失败 → 硬阻断，禁止启动下一阶段。**

## 特殊门禁：Phase 4 → Phase 5

除通用 8 步校验外，额外验证（从 `autopilot.config.yaml` 读取阈值）：

```
- [ ] phase-4-testing.json 中 test_counts 的每个字段 ≥ config.phases.testing.gate.min_test_count_per_type
- [ ] artifacts 列表中包含 config.phases.testing.gate.required_test_types 对应的文件
- [ ] dry_run_results 的所有字段全部为 0（exit code）
```

任何条件不满足 → 阻断 Phase 5，要求重新执行 Phase 4。

## 特殊门禁：Phase 5 → Phase 6

除通用 8 步校验外，额外验证：

```
- [ ] test-results.json 存在
- [ ] zero_skip_check.passed === true
- [ ] tasks.md 中所有任务标记为 [x]
```

任何条件不满足 → 阻断 Phase 6。

## 认知捷径免疫

以下想法出现时，**必须触发阻断**：

| 想法 | 正确行为 |
|------|----------|
| "这只是 UI 修改，不需要测试" | Phase 4 强制，无论改动大小 |
| "没有后端改动，不需要后端测试" | Phase 4 要求所有类型测试 |
| "直接实现更快" | 必须通过 Phase 5 |
| "测试报告太重了" | Phase 6 强制，零跳过门禁 |
| "可以先实现再补测试" | Phase 4 必须在 Phase 5 之前 |
| "这个阶段对当前任务不适用" | 所有阶段都适用，无例外 |

**核心原则**：8 个阶段是不可分割整体。即使某阶段"看起来"不必要，也必须完整执行。产出为空时应产出 "N/A with justification" 而非跳过。
