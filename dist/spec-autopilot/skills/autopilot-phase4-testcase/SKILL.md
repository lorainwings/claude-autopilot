---
name: autopilot-phase4-testcase
description: "Use when the autopilot orchestrator advances into Phase 4 after OpenSpec alignment has completed and tasks.md is ready, and must design test cases with TDD awareness and strict gating before Phase 5 can dispatch. [ONLY for autopilot orchestrator]"
user-invocable: false
---

# Autopilot Phase 4 — 测试用例设计

> **前置条件自检**：本 Skill 仅在 autopilot 编排主线程中使用。如果当前上下文不是 autopilot 编排流程，请立即停止并忽略本 Skill。

Phase 4 在 full 模式下执行测试用例设计，具有特殊的 TDD 跳过逻辑和严格门禁规则。

**执行前读取**: `../autopilot/references/parallel-phase4.md` 并行配置 + `../autopilot/references/protocol.md` 特殊门禁

## TDD 模式跳过（确定性检测）

**必须执行确定性 Bash 检测**（禁止依赖 AI 记忆判断配置值）：

```
TDD_RESULT=$(bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/check-tdd-mode.sh)
```

> 脚本自动解析项目根目录（`$AUTOPILOT_PROJECT_ROOT` > `git rev-parse` > `$PWD`），无需手动传参。

根据 `TDD_RESULT` 值分路：

- **`TDD_SKIP`**（`tdd_mode: true` 且 `mode: full`）：
  - Phase 4 标记为 `skipped_tdd`
  - 写入 `phase-4-tdd-override.json` checkpoint：`{"status":"ok","tdd_mode_override":true}`
  - 直接跳转 Phase 5（不执行 dispatch）
- **`TDD_DISPATCH`**（非 TDD 模式）：
  - 正常 dispatch 测试用例设计 Agent（见下方"非 TDD 模式"章节）

## 非 TDD 模式

正常 dispatch，并行模式按测试类型分组。

**执行位置**: Task 子 Agent

- Agent: `config.phases.testing.agent`（默认 general-purpose；推荐安装 qa-expert / test-engineer）
- Model Tier: deep / opus
- **必须使用 `run_in_background: true`**：测试用例生成不需要交互，主线程等待完成通知后验证 gate 即可
- 项目上下文从 config.project_context + config.test_suites + Phase 1 Steering Documents 自动注入
- 可选覆盖：config.phases.testing.instruction_files / reference_files（非空时注入）

## 门禁规则（严格）

**Phase 4 只接受 ok 或 blocked**（warning 由 Hook 确定性阻断）。详见 `../autopilot/references/protocol.md`。

### Phase 4 → Phase 5 特殊门禁

**非 TDD 模式**：

```
- [ ] phase-4-testing.json 中 test_counts 的每个字段 ≥ config.phases.testing.gate.min_test_count_per_type
- [ ] artifacts 列表中包含 config.phases.testing.gate.required_test_types 对应的文件
- [ ] dry_run_results 的所有字段全部为 0（exit code）
```

**TDD 模式**：

```
- [ ] phase-4-tdd-override.json 存在且 tdd_mode_override === true
- [ ] 跳过 test_counts / dry_run 验证（测试在 Phase 5 per-task 创建）
```

## 关键约束摘要

- 必须创建实际测试文件，禁止以任何理由跳过
- 每种 test_type ≥ `min_test_count_per_type` 个用例
- `change_coverage.coverage_pct` ≥ 80%，否则 blocked
- 测试金字塔: unit ≥ `min_unit_pct`%，e2e ≤ `max_e2e_pct`%
- 每个测试用例必须追溯到 Phase 1 需求点（traceability matrix）
- status 只允许 "ok" 或 "blocked"（禁止 "warning"）

完整指令在参考文件中：`autopilot/templates/phase4-testing.md`（测试标准 + dry-run + 金字塔）
