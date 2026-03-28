# Workstream C: `state-snapshot.json`、compact/recovery 与崩溃恢复

日期: 2026-03-28
写入范围: compact/reinject/save/scan/recovery 脚本与恢复协议

## 1. 目标

把当前“有损 Markdown 摘要恢复”升级为“结构化控制态恢复”:

1. 引入统一 `state-snapshot.json`
2. compact/restore 先恢复结构化状态，再注入最小必要摘要
3. 崩溃恢复同时判断恢复起点、遗弃工件、重跑任务与自动继续资格
4. 恢复后的一致性可机器校验

## 2. 必改文件

1. `plugins/spec-autopilot/runtime/scripts/save-state-before-compact.sh`
2. `plugins/spec-autopilot/runtime/scripts/reinject-state-after-compact.sh`
3. `plugins/spec-autopilot/runtime/scripts/scan-checkpoints-on-start.sh`
4. `plugins/spec-autopilot/runtime/scripts/save-phase-context.sh`
5. `plugins/spec-autopilot/runtime/scripts/recovery-decision.sh`
6. `plugins/spec-autopilot/runtime/scripts/clean-phase-artifacts.sh`
7. `plugins/spec-autopilot/skills/autopilot-recovery/SKILL.md`

## 3. 可建议但不直接修改的共享文件

1. `plugins/spec-autopilot/skills/autopilot/SKILL.md`
2. `plugins/spec-autopilot/runtime/server/src/types.ts`
3. `plugins/spec-autopilot/runtime/server/src/state.ts`
4. `plugins/spec-autopilot/runtime/server/src/snapshot/snapshot-builder.ts`

## 4. 必须落地的实现点

1. `state-snapshot.json` 至少记录:
   - requirement packet hash
   - gate frontier
   - current phase / next action
   - active tasks
   - review / fixup / archive 状态
   - compact 前后恢复校验字段
2. compact 时保存结构化状态，而不是只截断 Markdown
3. reinject 时优先恢复 `state-snapshot.json`
4. 恢复指令只向主线程注入最小必要事实集
5. `recovery-decision.sh` 输出:
   - `resume_from_phase`
   - `discarded_artifacts`
   - `replay_required_tasks`
   - `recovery_reason`
   - `recovery_confidence`
6. scan/startup 路径与 compact/recovery 路径使用同一控制态模型

## 5. 禁止走捷径

1. 禁止新增 `context-ledger.json` 与 `recovery-state.json` 双工件体系。
2. 禁止继续把完整 Markdown 直接打回 stdout 当恢复主路径。
3. 禁止只保存对话摘要而不保存 artifact graph / gate frontier / next action。

## 6. 必测项

至少新增或修订以下测试:

1. `plugins/spec-autopilot/tests/test_scan_checkpoints.sh`
2. `plugins/spec-autopilot/tests/test_phase_context_snapshot.sh`
3. `plugins/spec-autopilot/tests/test_recovery_auto_continue.sh`
4. `plugins/spec-autopilot/tests/integration/test_e2e_checkpoint_recovery.sh`
5. 新增 compact/restore hash 一致性测试
6. 新增 crash recovery artifact/gate/next-action 一致性测试

## 7. 完成定义

满足以下条件才算完成:

1. `state-snapshot.json` 成为恢复控制面的唯一主工件。
2. requirement packet hash、gate frontier、next action 恢复前后一致。
3. crash recovery 能判断该丢弃什么、该重跑什么、能否自动继续。
4. 恢复逻辑和测试不再依赖人工解读 Markdown。

## 8. 交付给协调者的信息

请额外列出:

1. `state-snapshot.json` 最终 schema
2. GUI / server 需要消费的恢复字段
3. 与 Workstream B 的 archive/fixup 状态字段对接要求
