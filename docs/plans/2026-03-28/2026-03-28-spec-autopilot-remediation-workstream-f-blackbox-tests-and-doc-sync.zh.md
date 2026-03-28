# Workstream F: 黑盒验收、三模式仿真与文档收口

日期: 2026-03-28
执行时机: Wave 3，等待 A-E 与协调者共享文件收口后执行
写入范围: 黑盒测试、三模式仿真、OpenSpec/FF 验收、README/docs 对齐

## 1. 目标

负责最终验收闭环，而不是先行设计:

1. 把用户的 13 项产品目标转成真实黑盒测试或仿真夹具
2. 让 full/lite/minimal 三模式都跑产品级闭环
3. 校验 OpenSpec / OpenSpec FF、恢复、archive、review、agent 治理
4. 清理“文档即验收”的偏差，完成 README/docs 收口

## 2. 必改文件

1. `plugins/spec-autopilot/tests/run_all.sh`
2. `plugins/spec-autopilot/tests/_fixtures.sh`
3. `plugins/spec-autopilot/tests/_test_helpers.sh`
4. 与三模式仿真、archive、OpenSpec/FF、agent priority 相关的新黑盒测试
5. `plugins/spec-autopilot/README.zh.md`
6. `plugins/spec-autopilot/CLAUDE.md`
7. `plugins/spec-autopilot/docs/README.zh.md`
8. `plugins/spec-autopilot/skills/autopilot/SKILL.md`

## 3. 前置输入

执行前必须先读取:

1. `docs/plans/2026-03-28-spec-autopilot-remediation-acceptance-matrix.zh.md`
2. A-E 与协调者的最终改动结果
3. 现有全部测试目录与新增测试目录

## 4. 必须落地的实现点

1. 为以下目标建立黑盒覆盖:
   - requirement packet 后自动推进
   - Phase 1 主上下文不污染
   - compact/restore hash 一致
   - crash recovery 自动继续
   - review fail-closed
   - fixup/archive fail-closed
   - OpenSpec / FF 不越权
   - agent priority enforced
2. 重新区分:
   - 协议/静态测试
   - 运行时脚本行为测试
   - 产品黑盒验收测试
3. `run_all.sh` 必须显式纳入新增产品黑盒
4. README / `CLAUDE.md` / `SKILL.md` 必须与真实实现一致

## 5. 禁止走捷径

1. 禁止继续把 grep 文档命中作为“产品通过”。
2. 禁止跳过 full/lite/minimal 中任一模式。
3. 禁止跳过 OpenSpec / FF 黑盒，只保留静态文档检查。
4. 禁止文档继续保留旧语义，例如逐阶段确认、Phase 7 强制人工确认、主线程回读 research 正文。

## 6. 必测项

至少执行:

1. `bash plugins/spec-autopilot/tests/run_all.sh`
2. `bash plugins/spec-autopilot/tests/integration/test_e2e_checkpoint_recovery.sh`
3. `bash plugins/spec-autopilot/tests/test_lite_mode.sh`
4. `bash plugins/spec-autopilot/tests/test_minimal_mode.sh`
5. `bash plugins/spec-autopilot/tests/test_fixup_commit.sh`
6. `bash plugins/spec-autopilot/tests/test_phase7_archive.sh`
7. 新增的三模式产品仿真套件
8. 新增的 OpenSpec / FF 黑盒

## 7. 完成定义

满足以下条件才算完成:

1. 验收矩阵中的每一项目标至少有一个真实行为测试。
2. `run_all.sh` 已纳入新增核心黑盒。
3. 文档、README、`CLAUDE.md`、`SKILL.md` 与实现完全一致。
4. 不再存在“测试全绿但产品目标仍未满足”的明显缺口。

## 8. 最终汇报要求

最终必须输出:

1. 验收矩阵逐项通过情况
2. 新增测试列表
3. 文档修订点
4. 剩余风险
