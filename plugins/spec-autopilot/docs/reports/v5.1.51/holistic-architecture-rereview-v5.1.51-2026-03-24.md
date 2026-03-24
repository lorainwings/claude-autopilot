# spec-autopilot v5.1.51 架构问题复审报告

> 复审日期: 2026-03-24
> 复审对象: `plugins/spec-autopilot/docs/reports/v5.1.51/holistic-architecture-review-v5.1.51.md`
> 复审基线: `main@498a8e4`
> 复审方式: 逐项静态核查 + 定向测试 + 全量测试复跑
> 全量测试结果: `87 files, 909 passed, 0 failed`

---

## 结论摘要

旧报告列出的 13 个问题中：

- **已彻底修复**: 9 项
- **部分修复**: 2 项
- **仍未彻底修复**: 2 项

总体判断：本轮修复已经把大部分 **P0/P1 一致性和测试可信度问题** 收敛掉，但仍未把 **运行时项目根解析闭环** 和 **规则/GUI 编排态的一等建模** 完整补齐，因此不能判定为“全部问题已经彻底修复”。

---

## 逐项复核结果

| 编号 | 旧问题 | 复审结论 | 关键证据 |
|------|------|------|------|
| P0-1 | `emit-tool-event.sh` 项目根解析错误导致 tool/agent 关联失真 | 已修复 | `runtime/scripts/emit-tool-event.sh` 先读 stdin `cwd` 再定根；会优先读取 session-scoped marker 注入 `agent_id` |
| P0-2 | `save-phase-context.sh` / `write-phase-progress.sh` 嵌套 repo 可能写错目录 | **部分修复** | 测试夹具通过 `AUTOPILOT_PROJECT_ROOT` 修复了测试基线，但生产脚本仍只走 `resolve_active_change_dir()` → `resolve_project_root()`，未直接消费 `cwd/session_cwd` |
| P0-3 | compact `next_phase` 非 mode-aware | 已修复 | `save-state-before-compact.sh` 改为按 mode 构建 phase 序列并从序列求下一个阶段 |
| P0-4 | GUI 把 `decision_ack` 误判为 gate 已解除 | 已修复 | `GateBlockCard` 仅以同 phase 的后续 `gate_pass` 决定隐藏；`decision_ack` 仅保留 UI 反馈 |
| P0-5 | TDD 协议、validator、gate 文档不一致 | 已修复 | `protocol.md`、`_post_task_validator.py`、`phase5-implementation.md`、`autopilot-gate/SKILL.md` 已统一到 `total_cycles` 和 mode-aware 阻断语义 |
| P1-1 | Recovery 只读取 `anchor_sha`，不负责失效时自动重建 | **部分修复** | `autopilot-recovery/SKILL.md` 已补 anchor 重建协议；但 `recovery-decision.sh` 仍是只读扫描，`autopilot-phase7/SKILL.md` 在 archive 路径仍是 anchor 无效即跳过 autosquash |
| P1-2 | Phase 1 文档对“三路并行”和“先澄清”表述冲突 | 已修复 | `skills/autopilot/SKILL.md` 改为 `flags >= 2` 先澄清，再按复杂度自适应派发 |
| P1-3 | Phase 6.5 code review 门禁语义不确定 | 已修复 | 文档和测试都已统一为 Advisory Gate，不阻断 Phase 7 |
| P1-4 | rules / semantic rules / CLAUDE 约束无法形成可证明的运行时硬约束 | **未修复** | `rules-scanner.sh` 仍只做抽取；`_constraint_loader.py` 仍以 `code_constraints` 为主；`semantic_rules` 仍明确写着无法被 Hook 自动检测 |
| P1-5 | 无法证明本次 task 真实使用了指定 `subagent_type` | 已修复 | `auto-emit-agent-dispatch.sh` / `auto-emit-agent-complete.sh` 已把 `subagent_type` 写入事件 payload，形成最基本审计链 |
| P2-1 | GUI 中央区过度偏向 task/Phase 5，缺少一等 phase orchestration state | **未修复** | `ParallelKanban.tsx` 仍在无 task/agent 时直接 `return null`；`/api/info` 仍未提供 phase-state / recovery-state 一等视图 |
| P2-2 | `git_risk_level` 粗糙 | 已修复 | `recovery-decision.sh` 已引入 `medium`，并把 `worktree_residuals` 纳入 auto-continue 判定 |
| P2-3 | 大量测试仍锚定废弃脚本，主质量信号漂移 | 已修复 | 6 个测试已迁移到 `_post_task_validator.py`；全量测试通过 |

---

## 重点问题说明

### 1. P0-2 仅修到了测试层，没有完全修到生产层

当前 `save-phase-context.sh` 和 `write-phase-progress.sh` 依旧通过：

`resolve_active_change_dir()` → `resolve_changes_dir()` → `resolve_project_root()`

而 `resolve_project_root()` 仍然只支持：

1. `AUTOPILOT_PROJECT_ROOT`
2. `git rev-parse --show-toplevel`
3. `pwd`

也就是说，这次变更真正落地的是 **测试夹具导出 `AUTOPILOT_PROJECT_ROOT`**，不是让生产调用链天然拿到 `session_cwd`。如果主线程未来在非目标 repo 根目录下调用这两个脚本，这个问题仍可能复现。

证据：

- `runtime/scripts/save-phase-context.sh`
- `runtime/scripts/write-phase-progress.sh`
- `runtime/scripts/_common.sh`
- `tests/_fixtures.sh`

### 2. P1-4 规约“可注入”，但仍非“可证明执行”

当前系统仍然没有把以下信息固化成运行时可审计证据：

- 规则注入哈希
- 规则来源优先级解析结果
- semantic rules 的实际命中/校验结果

`autopilot-dispatch/SKILL.md` 仍明确写着 semantic rules 无法被 Hook 自动检测，因此这条旧问题本质上还在。

证据：

- `runtime/scripts/rules-scanner.sh`
- `runtime/scripts/_constraint_loader.py`
- `skills/autopilot-dispatch/SKILL.md`

### 3. P2-1 GUI 仍不是单一编排态驱动

虽然 `decision_ack` 误隐藏卡片的问题已经修掉，但 GUI 主区仍然主要由 task/agent 事件驱动：

- 无 task/agent 时 `ParallelKanban` 直接返回 `null`
- `/api/info` 仍只暴露 session/change/telemetry 粗粒度信息
- 没有单独的 `phase-state` / `recovery-state` API

因此这项旧问题不能算“彻底修复”。

证据：

- `gui/src/components/ParallelKanban.tsx`
- `runtime/server/src/api/routes.ts`

### 4. P1-1 已补恢复协议，但 archive 异常路径仍未闭环

恢复 skill 现在确实定义了 anchor 无效时自动重建，这解决了旧报告指出的“恢复阶段只读不自修复”主问题。

但当前 archive 路径仍是：

- Phase 7 读取 `anchor_sha`
- 无效则跳过 autosquash 并警告

因此这项应评为“部分修复”，而不是“完全闭环”。

证据：

- `skills/autopilot-recovery/SKILL.md`
- `skills/autopilot-phase7/SKILL.md`
- `runtime/scripts/recovery-decision.sh`

---

## 已验证的修复项

以下旧问题我认为已经可以判定为“修复完成”：

### P0-1

- `emit-tool-event.sh` 已在解析项目根前读取 stdin 中的 `cwd`
- 同时优先读取 session-scoped `.active-agent-id`
- `tests/test_agent_correlation.sh` 通过

### P0-3

- compact state 保存已改为 mode-aware phase 扫描
- `next_phase` 不再写死 `last_completed + 1`
- `tests/integration/test_e2e_checkpoint_recovery.sh` 和 `tests/test_save_state_phase7.sh` 通过

### P0-4

- `GateBlockCard` 不再由 `decision_ack` 控制显隐
- `App.tsx` 的 ACK 状态更新合并为单次原子更新

### P0-5

- `tdd_metrics.total_cycles` 与协议统一
- `tdd_unverified` / `audit_passed` 语义已对齐为 full 硬阻断、lite/minimal 降级 warning
- `tests/test_json_envelope.sh`、`tests/test_post_task_validator.sh`、`tests/test_phase4_missing_fields.sh` 通过

### P1-2

- Phase 1 主流程已从“默认三路并行”改为“先 lint/澄清，再按复杂度决定 1/2/3 路”
- `tests/test_phase1_clarification.sh` 通过

### P1-3

- 当前语义已统一为：Phase 6.5 是 Advisory Gate，不阻断 Phase 7
- 文档、实现、测试一致
- `tests/test_phase7_predecessor.sh` 通过

### P1-5

- 事件中已有 `subagent_type`
- 对“本次 task 请求了什么 agent 类型”已形成基本证据链

### P2-2

- `git_risk_level` 已从 `none/low/high` 提升为包含 `medium`
- `worktree_residuals` 已纳入 `auto_continue_eligible`
- `tests/test_recovery_auto_continue.sh`、`tests/test_recovery_decision.sh` 通过

### P2-3

- 旧的废弃脚本测试已迁移到当前统一 validator
- 全量测试已恢复为全绿

---

## 测试记录

本次复审实际执行并确认通过：

- `bash plugins/spec-autopilot/tests/run_all.sh`

结果：

```text
Test Summary: 87 files, 909 passed, 0 failed
```

此外还单独复跑了与旧报告直接相关的定向测试，包括：

- `test_agent_correlation`
- `test_phase_context_snapshot`
- `test_phase_progress`
- `test_recovery_decision`
- `test_recovery_auto_continue`
- `test_phase7_predecessor`
- `test_json_envelope`
- `test_anti_rationalization`
- `test_change_coverage`
- `test_phase4_missing_fields`
- `test_phase6_allure`
- `test_pyramid_threshold`
- `integration/test_e2e_checkpoint_recovery`

---

## 最终结论

如果标准是“相较旧报告，主要 P0/P1 缺陷是否已经明显收敛”，答案是 **是**。

如果标准是“旧报告中的所有问题是否已经全部彻底修复”，答案是 **否**。

当前仍建议继续补两类收尾工作：

1. 让 `save-phase-context.sh` / `write-phase-progress.sh` 在生产路径中直接拿到 `session_cwd` 或等价根路径，而不是依赖测试注入的 `AUTOPILOT_PROJECT_ROOT`
2. 为 GUI 和规则系统补真正的一等编排态与规约证明链，而不是继续依赖事件推断和 prompt 约定
