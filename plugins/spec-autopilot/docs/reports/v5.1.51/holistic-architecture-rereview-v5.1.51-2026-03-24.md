# spec-autopilot v5.1.51 架构问题二次复审报告

> 复审日期: 2026-03-24
> 原始评审对象: `plugins/spec-autopilot/docs/reports/v5.1.51/holistic-architecture-review-v5.1.51.md`
> 本次复审范围: 针对 claude 已提交修复后的重新核查
> 关键修复提交: `9c1afde fix: Codex 评审 4 项问题全量修复 — P0 根目录解析/P1 规则+anchor 闭环/P2 GUI 空状态`
> 复审方式: 静态代码复核 + 定向测试 + 全量回归
> 全量测试结果: `87 files, 910 passed, 0 failed`

---

## 结论摘要

原报告中的 13 个问题，当前结论更新为：

- **已彻底修复**: 11 项
- **部分修复**: 1 项
- **仍未彻底修复**: 1 项

结论上，这次修复已经把上轮残留的 4 项问题中的 3 项推进到可接受状态：

- `P0-2` 已修复
- `P1-1` 已修复
- `P2-1` 从未修复提升为部分修复
- `P1-4` 仍未彻底修复

因此，不能判定为“旧报告所有问题都已彻底关闭”；当前唯一仍然明确未闭环的问题，是 **规则扫描结果没有真正接入运行时 Hook 检测链**。

---

## 逐项复核结果

| 编号 | 原问题 | 本次结论 | 关键依据 |
|------|------|------|------|
| P0-1 | `emit-tool-event.sh` 项目根解析错误导致 tool/agent 关联失真 | 已修复 | 旧问题已闭环，本次未见回退；相关聚合与关联测试全绿 |
| P0-2 | `save-phase-context.sh` / `write-phase-progress.sh` 嵌套 repo 可能写错目录 | **已修复** | 生产调用点已统一显式注入 `AUTOPILOT_PROJECT_ROOT=$(pwd)`；相关脚本测试与公共根解析测试通过 |
| P0-3 | compact `next_phase` 非 mode-aware | 已修复 | 旧问题已闭环，本次未见回退 |
| P0-4 | GUI 把 `decision_ack` 误判为 gate 已解除 | 已修复 | 旧问题已闭环，本次未见回退 |
| P0-5 | TDD 协议、validator、gate 文档不一致 | 已修复 | 旧问题已闭环，本次未见回退 |
| P1-1 | Recovery 只读取 `anchor_sha`，不负责失效时自动重建 | **已修复** | 新增 `rebuild-anchor.sh`，`recovery-decision.sh` 输出 `anchor_needs_rebuild`，recovery 与 Phase 7 都已接入重建路径 |
| P1-2 | Phase 1 文档对“三路并行”和“先澄清”表述冲突 | 已修复 | 旧问题已闭环，本次未见回退 |
| P1-3 | Phase 6.5 code review 门禁语义不确定 | 已修复 | 旧问题已闭环，本次未见回退 |
| P1-4 | rules / semantic rules / CLAUDE 约束无法形成可证明的运行时硬约束 | **未修复** | `_constraint_loader.py` 虽新增 scanner 合并能力，但实际 Hook 入口仍只调用 `load_constraints()` |
| P1-5 | 无法证明本次 task 真实使用了指定 `subagent_type` | 已修复 | 旧问题已闭环，本次未见回退 |
| P2-1 | GUI 中央区过度偏向 task/Phase 5，缺少一等 phase orchestration state | **部分修复** | 无 task/agent 时已展示 phase overview，`/api/info` 补了 `mode/currentPhase`；但仍缺一等 `phase-state/recovery-state` 建模 |
| P2-2 | `git_risk_level` 粗糙 | 已修复 | 旧问题已闭环，本次未见回退 |
| P2-3 | 大量测试仍锚定废弃脚本，主质量信号漂移 | 已修复 | 全量回归 `87 files, 910 passed, 0 failed`，相关迁移未回退 |

---

## 上轮遗留 4 项的逐项复核

### P0-2 已修复

这项问题没有通过修改 `runtime/scripts/_common.sh` 的根解析逻辑来修，而是通过**补齐所有实际生产调用点**来修。

当前主线程里对 `write-phase-progress.sh` 和 `save-phase-context.sh` 的调用，已经统一显式注入：

```bash
AUTOPILOT_PROJECT_ROOT=$(pwd)
```

关键证据：

- `skills/autopilot/SKILL.md:127`
- `skills/autopilot/SKILL.md:167`
- `skills/autopilot/SKILL.md:213`
- `skills/autopilot/SKILL.md:232`
- `skills/autopilot/SKILL.md:244`
- `skills/autopilot/SKILL.md:281`
- `skills/autopilot-phase7/SKILL.md:29`
- `skills/autopilot-phase7/SKILL.md:102`
- `skills/autopilot-phase7/SKILL.md:122`

同时，底层公共函数依然保持 env var 优先：

- `runtime/scripts/_common.sh:40`
- `runtime/scripts/_common.sh:54`

测试侧也补了同样的根路径约束，验证不再依赖外层仓库：

- `tests/_fixtures.sh:17`
- `tests/test_common_unit.sh:339`
- `tests/test_common_unit.sh:367`
- `tests/test_common_unit.sh:399`

定向测试通过：

- `test_common_unit`
- `test_phase_context_snapshot`
- `test_phase_progress`

判断：这项旧问题在**真实编排调用链**上已经闭环，当前可判定为已修复。残留的只是脚本抽象层仍依赖 env 注入，不再属于原缺陷未修。

### P1-1 已修复

这项本次确实补全了恢复与归档两条链路。

新增确定性脚本：

- `runtime/scripts/rebuild-anchor.sh`

恢复扫描现在会显式告诉上层是否需要重建 anchor：

- `runtime/scripts/recovery-decision.sh:434`

恢复 Skill 已把这个信号接入执行协议：

- `skills/autopilot-recovery/SKILL.md:196`
- `skills/autopilot-recovery/SKILL.md:198`
- `skills/autopilot-recovery/SKILL.md:204`
- `skills/autopilot-recovery/SKILL.md:209`

Phase 7 归档路径也不再是“anchor 无效直接跳过 autosquash”，而是先尝试重建：

- `skills/autopilot-phase7/SKILL.md:121`
- `skills/autopilot-phase7/SKILL.md:125`
- `skills/autopilot-phase7/SKILL.md:126`
- `skills/autopilot-phase7/SKILL.md:128`

定向测试通过：

- `test_recovery_decision`
- `test_recovery_auto_continue`
- `test_phase7_archive`

判断：相较上次“恢复协议写了，但 archive 仍未真正闭环”的状态，这次已经补上 recovery + archive 双路径，故应提升为已修复。

### P1-4 仍未修复

这次提交里，`_constraint_loader.py` 的确新增了两块关键能力：

- `load_scanner_constraints(root)`
- `merge_constraints(base, scanner)`

证据：

- `runtime/scripts/_constraint_loader.py:131`
- `runtime/scripts/_constraint_loader.py:211`

并且 `check_file_violations()` 也新增了：

- `required_patterns`
- `naming_patterns`

但是，真正的运行时入口仍然没有调用这些新能力。

实际 Hook 链现状：

- `runtime/scripts/write-edit-constraint-check.sh:138` 仍是 `constraints = _cl.load_constraints(root)`
- `runtime/scripts/unified-write-edit-check.sh:323` 仍是 `constraints = _cl.load_constraints(root)`
- `runtime/scripts/_post_task_validator.py:440` 仍是 `constraints = _cl.load_constraints(root)`

也就是说：

- scanner 可以扫出规则
- loader 可以合并规则
- violation checker 也能校验 required/naming
- 但生产 Hook 从头到尾没有真正把 scanner 结果 merge 进去

结果就是，`required_patterns` / `naming_patterns` 仍未形成可证明执行的 L2 硬约束。这一点与 `skills/autopilot-dispatch/SKILL.md` 中“已合并进 L2 Hook”的描述不一致。

判断：这是当前唯一仍然明确未闭环的问题，维持“未修复”结论。

### P2-1 部分修复

这项相比上次已有明显改进。

此前 `ParallelKanban` 在没有 task/agent 时直接空白；现在会退化为 phase 编排总览：

- `gui/src/components/ParallelKanban.tsx:81`
- `gui/src/components/ParallelKanban.tsx:345`

新增的 `PhasePipelineOverview` 已能展示：

- 当前模式 `mode`
- 当前阶段 `currentPhase`
- phase duration / status
- gate 通过与阻断统计

同时 `/api/info` 也新增：

- `mode`
- `currentPhase`

证据：

- `runtime/server/src/api/routes.ts:57`
- `runtime/server/src/api/routes.ts:79`
- `runtime/server/src/api/routes.ts:80`

但这项还不能算彻底修复，原因也很清楚：

- `currentPhase` 仍是从事件流反推出来的，不是一等 phase-state 模型
- API 仍没有 `recovery-state`、`phase-state`、`orchestration-state` 这类明确状态对象
- GUI 的 phase overview 仍然是事件派生视图，不是单一真相源

判断：应从“未修复”提升为“部分修复”，但不能升到“已修复”。

---

## 运行结果与测试记录

本次实际执行的关键测试：

- `bash plugins/spec-autopilot/tests/run_all.sh test_recovery_decision test_recovery_auto_continue test_phase_context_snapshot test_phase_progress test_phase7_archive test_phase7_predecessor test_common_unit`
- `bash plugins/spec-autopilot/tests/run_all.sh`

结果：

```text
Test Summary: 87 files, 910 passed, 0 failed
```

这说明本次修复至少满足两点：

- 新补的 recovery / anchor / 根路径 / GUI 空状态没有引入回归
- 旧有主链路能力仍保持可通过状态

但测试全绿并不能推翻 `P1-4` 的静态事实，因为目前测试覆盖的是“已有 Hook 行为”，而不是“scanner 规则是否真被生产 Hook 合并执行”。

---

## 最终结论

本次二次复审后，原报告的结论应更新为：

- **11 项已彻底修复**
- **1 项部分修复**
- **1 项未彻底修复**

唯一仍需继续修复的问题是：

1. `P1-4`: 把 `load_scanner_constraints()` / `merge_constraints()` 真正接入 `write-edit-constraint-check.sh`、`unified-write-edit-check.sh`、`_post_task_validator.py` 的生产调用链，并补对应用例，证明 `required_patterns` / `naming_patterns` 已实际阻断。

如果按“claude 是否已经把上次残留的大部分问题修完”来判断，答案是 **是**。

如果按“原 13 个问题是否已全部彻底关闭”来判断，答案仍然是 **否**。
