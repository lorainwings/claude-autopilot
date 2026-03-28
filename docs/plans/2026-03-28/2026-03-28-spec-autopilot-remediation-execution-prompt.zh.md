# spec-autopilot 全量修复执行提示词

日期: 2026-03-28
仓库: `/Users/lorain/Coding/Huihao/claude-autopilot`
目标插件: `plugins/spec-autopilot`
语言要求: 全程使用中文简体

依据文档:
- `docs/reports/2026-03-28-spec-autopilot-holistic-review.zh.md`
- `docs/reports/2026-03-28-spec-autopilot-evidence-appendix.zh.md`
- `docs/reports/2026-03-28-spec-autopilot-secondary-review.zh.md`
- `docs/reports/2026-03-28-spec-autopilot-conflict-verification.zh.md`
- `docs/plans/2026-03-28-spec-autopilot-stability-remediation-master-plan.zh.md`
- `docs/plans/2026-03-28-spec-autopilot-remediation-execution-backlog.zh.md`
- `docs/plans/2026-03-28-spec-autopilot-remediation-acceptance-matrix.zh.md`

## 1. 任务性质

这不是分析任务，不是继续写方案，也不是只补文档。

你必须直接在仓库中完成 `spec-autopilot` 的全量稳定性修复，把代码、脚本、GUI、测试、文档一起改完，并让实现行为与产品目标一致。

## 2. 不可谈判的产品目标

以下目标不得被简化、替换、降级或绕开:

1. 需求评审完成后，后续阶段默认自动完成，不应逐阶段弹确认。
2. 子 agent 任务不得占用或污染主 agent 关键上下文。
3. full/lite/minimal 三模式都必须保留完整控制闭环，不允许通过降模式换自动化。
4. 上下文压缩、保存、恢复、召回必须可验证，不允许继续依赖“摘要后让 AI 猜”作为主路径。
5. 崩溃恢复、review、archive、fixup 必须 fail-closed。
6. OpenSpec 与 OpenSpec FF 不能形成旁路。
7. rules、`CLAUDE.md`、agent 选择优先级、TDD、review、测试独立性都必须成为真实运行时约束。

## 3. 禁止的错误修法

严禁以下做法:

1. 把默认预设改成 `relaxed`、`minimal`、关闭 code review、降低门禁，来伪造“自动推进”。
2. 保留 Phase 7 “必须 AskUserQuestion 才能归档”的硬编码。
3. 继续允许主线程读取或代写 `research-findings.md`、`web-research-findings.md`、`requirements-analysis.md` 正文。
4. 继续让 compact/recovery 只依赖自然语言摘要恢复。
5. 把 `openspec ff` 做成绕过 Phase 2/3 契约、review、archive 的快车道。
6. 用 grep 文档或 prompt 文本命中替代黑盒产品验收。
7. 用“仓库里没有 `.claude/agents` 所以跳过 agent 优先级治理”作为免责理由。

## 4. 执行方式

优先采用“一名协调者 + 多个并行工作流”的方式实施。

执行波次:

1. 协调者先完整阅读上述依据文档与 `docs/plans/2026-03-28-spec-autopilot-remediation-execution-backlog.zh.md`。
2. 并行派发 Workstream A/B/C/D/E。
3. 协调者集中处理共享文件、交叉冲突和最终协议收口。
4. 再执行 Workstream F 做黑盒补测、文档收口、验收矩阵核对。
5. 最后运行全量测试并修复失败项，直到通过。

如果你只有一个 Claude 会话，也必须按该分工顺序实施，不能跳过并行 backlog 中定义的边界。

## 5. 并行工作流文档

你必须基于以下工作流文档实施:

1. `docs/plans/2026-03-28-spec-autopilot-remediation-workstream-a-phase1-context-isolation.zh.md`
2. `docs/plans/2026-03-28-spec-autopilot-remediation-workstream-b-auto-continue-and-archive.zh.md`
3. `docs/plans/2026-03-28-spec-autopilot-remediation-workstream-c-state-snapshot-and-recovery.zh.md`
4. `docs/plans/2026-03-28-spec-autopilot-remediation-workstream-d-gui-orchestration-first.zh.md`
5. `docs/plans/2026-03-28-spec-autopilot-remediation-workstream-e-agent-governance-tdd-review.zh.md`
6. `docs/plans/2026-03-28-spec-autopilot-remediation-workstream-f-blackbox-tests-and-doc-sync.zh.md`

## 6. 协调者保留的共享文件

以下文件默认由协调者统一合并，其他工作流如需变更，先在各自结果中说明，再由协调者落盘:

1. `plugins/spec-autopilot/skills/autopilot/SKILL.md`
2. `plugins/spec-autopilot/README.zh.md`
3. `plugins/spec-autopilot/CLAUDE.md`
4. `plugins/spec-autopilot/tests/run_all.sh`
5. `plugins/spec-autopilot/runtime/server/src/types.ts`
6. `plugins/spec-autopilot/runtime/server/src/state.ts`
7. `plugins/spec-autopilot/runtime/server/src/snapshot/snapshot-builder.ts`

## 7. 必须核实的实现事实

在修改前必须核实真实代码，而不是只相信报告:

1. Phase 1 协议与脚本当前是否仍允许主线程读取/代写子 agent 正文工件。
2. Phase 7 是否仍把用户确认写死为硬门禁。
3. recovery/compact 是否仍以 Markdown 摘要回灌为主。
4. GUI 是否仍是 telemetry-first，且 `OrchestrationPanel.tsx` 未接主路径。
5. rules 扫描是否覆盖 `.claude/agents`、`.claude/rules` 与项目 `CLAUDE.md`。
6. `post-task-validator.sh`、`auto-emit-agent-dispatch.sh`、`rules-scanner.sh` 是否已具备目标闭环。
7. `test_background_agent_bypass.sh`、`test_phase65_bypass.sh` 等遗留测试是否会误导验收。

## 8. 交付要求

必须同时交付:

1. 运行时代码修改
2. GUI 和 server 修改
3. skills / references / `CLAUDE.md` / README 修订
4. 新增或修订黑盒测试、集成测试、协议测试
5. 与验收矩阵一致的最终实现

不得只提交其中一部分。

## 9. 测试要求

基线信息:

- 现有基线曾跑过 `bash plugins/spec-autopilot/tests/run_all.sh`
- 当时结果为 `91 files / 1003 passed / 0 failed`
- 这只能说明“当前实现匹配当前测试”，不能说明“满足目标产品设计”

你必须在改造后至少完成以下验证:

1. `bash plugins/spec-autopilot/tests/run_all.sh`
2. `bash plugins/spec-autopilot/tests/integration/test_e2e_checkpoint_recovery.sh`
3. `bash plugins/spec-autopilot/tests/test_lite_mode.sh`
4. `bash plugins/spec-autopilot/tests/test_minimal_mode.sh`
5. `bash plugins/spec-autopilot/tests/test_recovery_auto_continue.sh`
6. `bash plugins/spec-autopilot/tests/test_fixup_commit.sh`
7. 新增的 Phase 1 主上下文隔离黑盒测试
8. 新增的 compact/restore hash 一致性测试
9. 新增的 archive fail-closed / review fail-closed 测试

## 10. 完成定义

只有满足以下条件才算完成:

1. `docs/plans/2026-03-28-spec-autopilot-remediation-acceptance-matrix.zh.md` 中所有条目均被实现并验证。
2. full/lite/minimal 三模式可自动推进至归档，除真实阻断裁决外不再逐阶段确认。
3. 主线程不再读取或代写 Phase 1 子 agent 正文工件。
4. 恢复与压缩拥有统一的 `state-snapshot.json` 控制态。
5. GUI 主窗口变为 orchestration-first。
6. review、fixup、archive 全部 fail-closed。
7. 文档、测试、代码行为一致。

## 11. 最终输出格式

实施完成后，最终汇报必须包含:

1. 修改概览
2. 新增或更新的关键文件
3. 执行过的测试与结果
4. 仍存在的风险或未完成项

如果任何项未完成，必须明确说明原因，不能伪装为已完成。
