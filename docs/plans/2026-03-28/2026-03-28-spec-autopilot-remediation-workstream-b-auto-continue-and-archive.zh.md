# Workstream B: 自动推进、Phase 7 收口与归档 fail-closed

日期: 2026-03-28
写入范围: 自动推进控制语义、Phase 7、fixup/archive 门禁、相关测试

## 1. 目标

修复以下产品冲突:

1. requirement packet 确认后，后续阶段默认自动执行，不逐阶段 AskUserQuestion。
2. Phase 7 不再把“归档必须人工确认”写死为硬规则。
3. fixup、autosquash、archive 必须 fail-closed。
4. full/lite/minimal 三模式都保持相同控制标准。

## 2. 必改文件

1. `plugins/spec-autopilot/skills/autopilot-init/SKILL.md`
2. `plugins/spec-autopilot/skills/autopilot-phase7/SKILL.md`
3. `plugins/spec-autopilot/skills/autopilot-gate/SKILL.md`
4. `plugins/spec-autopilot/runtime/scripts/check-predecessor-checkpoint.sh`
5. `plugins/spec-autopilot/runtime/scripts/poll-gate-decision.sh`
6. `plugins/spec-autopilot/runtime/scripts/rebuild-anchor.sh`
7. 如有需要，可新增 `archive-readiness.json` 相关脚本

## 3. 可建议但不直接修改的共享文件

1. `plugins/spec-autopilot/skills/autopilot/SKILL.md`
2. `plugins/spec-autopilot/README.zh.md`
3. `plugins/spec-autopilot/CLAUDE.md`

## 4. 必须落地的实现点

1. requirement packet 确认后默认连续执行 Phase 2-7
2. 用户确认只保留在真实业务裁决点:
   - 需求确认
   - 破坏性操作
   - 恢复歧义
   - archive 无法证明安全时的最终裁决
3. `archive-readiness` 成功时自动归档，不再强制人工确认
4. 不允许通过预设切换来改变自动推进语义
5. `FIXUP_COUNT`、checkpoint、anchor、review findings、dirty worktree 必须进入统一的 archive readiness 判断
6. anchor 重建后 message 体系必须与 autosquash 目标可对齐

## 5. 禁止走捷径

1. 禁止把默认 preset 改成 `relaxed` 充当修复。
2. 禁止通过关闭 review、降低门禁、切 `minimal` 模式换取自动推进。
3. 禁止保留“warning 后继续 archive”。
4. 禁止把 Phase 6.5 findings 继续视为对归档无影响的纯展示信息。

## 6. 必测项

至少新增或修订以下测试:

1. `plugins/spec-autopilot/tests/test_lite_mode.sh`
2. `plugins/spec-autopilot/tests/test_minimal_mode.sh`
3. `plugins/spec-autopilot/tests/test_recovery_auto_continue.sh`
4. `plugins/spec-autopilot/tests/test_fixup_commit.sh`
5. `plugins/spec-autopilot/tests/test_phase7_archive.sh`
6. 新增 archive fail-closed / auto-archive 黑盒

## 7. 完成定义

满足以下条件才算完成:

1. 三模式都能在 requirement packet 确认后自动推进。
2. Phase 7 只在真实 archive 裁决点中断。
3. fixup / autosquash / review 任一不完整都会阻断 archive。
4. 自动推进语义与 preset 深度解耦。

## 8. 交付给协调者的信息

请额外列出:

1. `README.zh.md` 与 `CLAUDE.md` 需要同步修订的条目
2. `archive-readiness.json` 的最终字段定义
3. GUI 侧需要展示的 archive/fixup/review 状态字段
