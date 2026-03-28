# Workstream A: Phase 1 主上下文隔离与需求评审收敛

日期: 2026-03-28
写入范围: Phase 1 协议、dispatch、validator、Phase 1 测试

## 1. 目标

修复 Phase 1 的核心偏差:

1. 主线程不得读取或代写 research / BA 正文工件。
2. Phase 1 必须变成 `Clarify -> Research -> Synthesis -> Requirement Confirm` 的受控流程。
3. 三路 agent 不再默认启用，而由需求成熟度驱动。
4. 唯一可信输入必须收敛到 `requirement-packet.json`。

## 2. 必改文件

1. `plugins/spec-autopilot/skills/autopilot-dispatch/SKILL.md`
2. `plugins/spec-autopilot/skills/autopilot/references/parallel-phase1.md`
3. `plugins/spec-autopilot/skills/autopilot/references/phase1-requirements.md`
4. `plugins/spec-autopilot/skills/autopilot/references/phase1-requirements-detail.md`
5. `plugins/spec-autopilot/runtime/scripts/validate-decision-format.sh`
6. 如有需要，可新增 Phase 1 schema 或 validator 脚本

## 3. 可建议但不直接修改的共享文件

以下文件如需改动，请记录建议给协调者:

1. `plugins/spec-autopilot/skills/autopilot/SKILL.md`
2. `plugins/spec-autopilot/README.zh.md`
3. `plugins/spec-autopilot/CLAUDE.md`

## 4. 必须落地的实现点

1. 增加需求成熟度判断: `clear / partial / ambiguous`
2. `clear` 需求不默认走三路调研
3. `partial` 需求至少先做定向澄清，再决定是否双路调研
4. `ambiguous` 需求才进入三路调研
5. research / BA / synthesis 使用独立事实工件或结构化 envelope
6. 主线程只能验证 `output_file` 与读取结构化 facts，不读取正文
7. 为子任务引入轻量 `autopilot-subtask:*` 标记，允许统一验证但不误触主 phase gate
8. `open_questions` 必须映射到 `decision_points`
9. requirement confirm 后，主线程只保留 requirement packet 摘要、hash、决策点、未决项

## 5. 禁止走捷径

1. 不能仅删除 `parallel-phase1.md:81` 一处文字就算完成。
2. 不能保留主线程 `Read(ba_envelope.output_file)` 之类正文读取路径。
3. 不能继续让主线程为 Explore / BA 任务落盘正文工件。
4. 不能把所有需求都强制走三路调研来回避成熟度判断。

## 6. 必测项

至少新增或修订以下测试:

1. `plugins/spec-autopilot/tests/test_phase1_clarification.sh`
2. `plugins/spec-autopilot/tests/test_phase1_hard_gate.sh`
3. 新增 `plugins/spec-autopilot/tests/test_phase1_context_isolation.sh`
4. 如有 output_file / envelope 契约变化，补充相关静态测试

## 7. 完成定义

满足以下条件才算完成:

1. 主线程不再读取或代写 Phase 1 子 agent 正文工件。
2. Phase 1 形成唯一 `requirement-packet.json` 主输入。
3. Clarify/Research/Synthesis/Confirm 具有明确条件分流。
4. 新测试可直接证明上下文隔离与需求收敛逻辑。

## 8. 交付给协调者的信息

请额外列出:

1. 需要协调者同步进 `autopilot/SKILL.md` 的协议收口点
2. Phase 1 新 schema 字段清单
3. 对 GUI / recovery / archive 侧需要消费的新字段建议
