# spec-autopilot 全量修复验收矩阵

日期: 2026-03-28
范围: `plugins/spec-autopilot`

## 1. 核心验收矩阵

| 验收目标 | 主要改动域 | 必测项 | 通过标准 | 失败判据 |
|---|---|---|---|---|
| 需求评审后自动推进 | Phase 1/7 skills、gate scripts、README、`CLAUDE.md` | `test_lite_mode.sh`、`test_minimal_mode.sh`、新增 auto-continue 黑盒 | requirement packet 确认后自动跑到 archive-ready 或真实 blocked | 仍按 phase 弹确认，或必须改 `relaxed/minimal` 才自动 |
| 主上下文不被子 agent 污染 | Phase 1 references、dispatch、validator | 新增 Phase 1 context isolation 黑盒 | 主线程只消费 facts envelope / requirement packet 摘要/hash | 主线程继续读或代写 research / BA 正文 |
| 主窗口编排信息最小且充分 | GUI / store / snapshot / events | `test_gui_store_cap.sh`、`test_autopilot_server_aggregation.sh`、GUI 新测 | 主窗口优先展示 goal、phase、gate、agent、recovery、archive、model | telemetry-first，或关键 gate/recovery/model 信息缺失 |
| compact/restore 完全受控 | compact/reinject/save/scan 脚本 | 新增 state snapshot hash 黑盒 | 恢复前后 requirement packet hash、gate frontier、next action 一致 | 仍靠 Markdown 摘要主导恢复，或无法校验一致性 |
| 崩溃恢复闭环完整 | recovery skill、decision script、cleanup、tests | `test_recovery_auto_continue.sh`、`integration/test_e2e_checkpoint_recovery.sh` | 能判断恢复起点、遗弃工件、重跑项、自动继续资格 | 只找最近 checkpoint，不判断 fixup/review/archive 状态 |
| 需求评审方案更可控 | Phase 1 Clarify/Research/Synthesis/Confirm | `test_phase1_clarification.sh`、`test_phase1_hard_gate.sh` | 按成熟度选择轻量澄清/双路/三路调研，并输出唯一 requirement packet | 仍默认三路调研，或 open questions 不闭合 |
| OpenSpec / FF 不越权 | Phase 2/3 契约、FF tests | 现有 Phase 2/3 tests + 新增 FF 黑盒 | `openspec ff` 仍受 Phase 2/3 合同和后续 gate 约束 | FF 绕过 review/recovery/archive |
| 测试覆盖真实产品目标 | tests、fixtures、run_all | `run_all.sh`、三模式仿真、Phase 1/恢复/archive 黑盒 | 每项产品目标至少有一个行为测试 | 只靠文档 grep 或 prompt 文本断言 |
| rules / `CLAUDE.md` / agent 优先级受控 | rules scanner、dispatch record、post validator | 新增 agent priority test、`test_auto_emit_agent.sh` | dispatch 记录 selection_reason、priority、fallback、owned artifacts | 仍无法证明为什么选用该 agent 或是否遵守优先级 |
| TDD 与 review 质量受控 | phase5/6 docs、validators、review outputs | `test_tdd_isolation.sh`、`test_phase65_bypass.sh`、`test_phase6_independent.sh` | test intent、failing signal、review findings 成为真实门禁依据 | 伪 TDD、review 仍纯 advisory 且不阻断归档 |
| fixup 全量收口 | Phase 7、anchor、archive-readiness | `test_fixup_commit.sh`、`test_phase7_archive.sh` | 本轮所有 fixup 全部被识别并合并，无遗漏 | `FIXUP_COUNT < CHECKPOINT_COUNT` 仅警告继续 |
| 阶段门禁与上下文恢复语义清晰 | skills/docs/GUI | 对应静态测试 + GUI/黑盒 | gate 语义、恢复语义在代码与文档中一致 | 文档与实现冲突、存在旧协议残留 |
| 产品流程符合 harness 理念 | 总控技能、子 agent 边界、GUI 编排 | 综合黑盒与人工复核 | 主 agent 编排、子 agent 受限执行、状态由 artifacts 驱动 | 主 agent 吞正文、快速路径绕 gate、恢复靠猜测 |

## 2. 共享产物验收

以下结构化产物必须真实落地并被代码消费:

1. `requirement-packet.json`
2. `decision-log.json`
3. `state-snapshot.json`
4. `archive-readiness.json`
5. `agent-dispatch-record.json`
6. Phase 5/6 所需的 TDD / review 结构化工件

## 3. 文档一致性验收

以下文档必须与实现一致:

1. `plugins/spec-autopilot/README.zh.md`
2. `plugins/spec-autopilot/CLAUDE.md`
3. `plugins/spec-autopilot/skills/autopilot/SKILL.md`
4. `plugins/spec-autopilot/skills/autopilot-phase7/SKILL.md`
5. `plugins/spec-autopilot/skills/autopilot-recovery/SKILL.md`
6. Phase 1、Phase 5、Phase 6 参考文档

## 4. 最终拒收条件

出现以下任一项即拒收:

1. 需要用户逐阶段确认才能跑完全流程。
2. 用切到 `relaxed`、`minimal`、关闭 review 等方式规避核心修复。
3. 主线程仍可读取或代写子 agent 正文工件。
4. `state-snapshot.json` 未成为恢复主控制态。
5. review / fixup / archive 仍为 fail-open。
6. GUI 主窗口仍把调试噪音放在主视觉，而不是编排信息。
7. 验收主要依赖文档 grep，而不是行为测试。
