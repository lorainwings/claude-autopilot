---
name: autopilot-gate
description: "[ONLY for autopilot orchestrator] Gate verification protocol for autopilot phase transitions. Enforces 8-step checklist and special gates (Phase 4→5 test_counts, Phase 5→6 zero_skip)."
user-invocable: false
---

# Autopilot Gate — 门禁验证协议

> **前置条件自检**：本 Skill 仅在 autopilot 编排主线程中使用。如果当前上下文不是 autopilot 编排流程，请立即停止并忽略本 Skill。

阶段切换时的 AI 侧验证清单。Layer 1（Task blockedBy）和 Layer 2（磁盘 checkpoint）已由 Hooks 确定性执行，本 Skill 负责 Layer 3（AI 执行的补充检查清单）。

> JSON 信封契约、状态规则、特殊门禁阈值等详见：`autopilot/references/protocol.md`

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

## Phase 6.5 代码审查门禁（可选）

当 `config.phases.code_review.enabled = true` 时，Phase 6 完成后额外检查：

```
- [ ] phase-6.5-code-review.json 存在
- [ ] findings 中 critical 数量为 0（当 block_on_critical = true 时）
- [ ] status 为 "ok" 或 "warning"（用户已确认）
```

Phase 6.5 是可选步骤，不影响 Layer 1（TaskCreate blockedBy）和 Layer 2（Hook predecessor check）。
当 `code_review.enabled = false` 时，Phase 6 直接进入质量扫描和 Phase 7。

## 可选 Layer 3 补充：语义验证

> 详见：`autopilot/references/semantic-validation.md`

在 8 步检查清单的 Step 6 之后，可选执行语义验证：

1. 读取 `references/semantic-validation.md` 中对应阶段的检查清单
2. 逐项验证（读取相关文件确认）
3. 不通过项记录为 `warning`（不硬阻断，除非发现严重不一致）
4. 输出语义验证摘要

**注意**: 语义验证为 AI 执行的软检查，不替代 Layer 2 Hook 的确定性验证。

## 可选 Layer 3 补充：Brownfield 验证

> 详见：`autopilot/references/brownfield-validation.md`
> 通过 `config.brownfield_validation.enabled` 控制（默认关闭）。

当启用时，在特定阶段切换时执行额外的三向一致性检查：

| 切换点 | 检查内容 |
|--------|---------|
| Phase 4 → Phase 5 | 设计-测试对齐 |
| Phase 5 启动 | 测试-实现就绪 |
| Phase 5 → Phase 6 | 实现-设计一致性 |

`strict_mode: true` 时不一致直接阻断；`false` 时仅 warning。

## 执行模式感知

本 Skill 在执行门禁检查时，需感知当前执行模式（从锁文件 `openspec/changes/.autopilot-active` 的 `mode` 字段读取）。

### 模式对门禁的影响

| 切换点 | full 模式 | lite 模式 | minimal 模式 |
|--------|----------|----------|-------------|
| Phase 1 → Phase 2 | 正常检查 | **跳过**（Phase 2 不执行） | **跳过** |
| Phase 2 → Phase 3 | 正常检查 | **跳过** | **跳过** |
| Phase 3 → Phase 4 | 正常检查 | **跳过** | **跳过** |
| Phase 4 → Phase 5 | 正常检查 + 特殊门禁 | **跳过**（Phase 1 → Phase 5） | **跳过**（Phase 1 → Phase 5） |
| Phase 5 → Phase 6 | 正常检查 + 特殊门禁 | 正常检查 + 特殊门禁 | **跳过**（Phase 5 → Phase 7） |
| Phase 6 → Phase 7 | 正常检查 | 正常检查 | **跳过** |

### lite/minimal 的 Phase 1 → Phase 5 门禁

当 mode 为 lite 或 minimal 时，Phase 5 的前置检查为：
- Phase 1 checkpoint（`phase-1-requirements.json`）存在且 status 为 ok
- Phase 2/3/4 checkpoint **不需要存在**（已被跳过）

## 阶段强制执行保障

阶段跳过由 Hook（`check-predecessor-checkpoint.sh`）+ TaskCreate blockedBy 依赖链确定性阻断，AI 无需自我审查。在 full 模式下 8 个阶段是不可分割整体；在 lite/minimal 模式下，跳过的阶段由 Phase 0 的 TaskCreate 链控制，不需要产出 checkpoint。非跳过的阶段产出为空时应产出 "N/A with justification" 而非跳过。
