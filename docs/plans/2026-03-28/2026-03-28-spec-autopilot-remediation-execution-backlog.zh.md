# spec-autopilot 全量修复执行 Backlog

日期: 2026-03-28
范围: `plugins/spec-autopilot`
用途: 供协调者拆分并行实施，避免多个 Claude 会话互相覆盖。

## 1. 总体执行波次

### Wave 1: 并行修复

并行启动以下 5 个工作流:

1. Workstream A: Phase 1 主上下文隔离与需求评审收敛
2. Workstream B: 自动推进、归档收口、fixup fail-closed
3. Workstream C: `state-snapshot.json`、compact/recovery、崩溃恢复
4. Workstream D: GUI 主窗口 orchestration-first、server 健康、模型/恢复可观测性
5. Workstream E: rules / agent 治理、TDD、review 硬约束化

### Wave 2: 中央合并

协调者统一处理:

1. `skills/autopilot/SKILL.md`
2. `README.zh.md`
3. `CLAUDE.md`
4. 共享类型定义和快照模型
5. 跨工作流 schema 名称与事件字段统一

### Wave 3: 黑盒收口

由 Workstream F 或协调者最终执行:

1. 三模式产品仿真
2. OpenSpec / OpenSpec FF 黑盒
3. 文档与实现一致性修订
4. `run_all.sh` 与新增测试接线

## 2. 工作流清单

| 工作流 | 目标 | 主要写入范围 | 依赖 | 是否可并行 |
|---|---|---|---|---|
| A | Phase 1 收敛、research 隔离、requirement packet 主导 | `skills/autopilot-dispatch*`、`phase1*`、Phase 1 validators、Phase 1 tests | 无 | 是 |
| B | 自动推进、Phase 7 改造、archive-readiness 收口 | `autopilot-init`、`autopilot-phase7`、gate/poll/fixup 脚本、archive tests | 无 | 是 |
| C | `state-snapshot.json` 与恢复控制闭环 | compact/reinject/scan/recovery 脚本、recovery skill、recovery tests | 无 | 是 |
| D | GUI / server 编排主界面与健康可观测性 | `gui/src/*`、`runtime/server/src/*`、`start-gui-server.sh` | 共享 types 由协调者收口 | 是 |
| E | rules / agent / TDD / review 治理 | `rules-scanner.sh`、dispatch 记录、Phase5/6 docs、相关 tests | 无 | 是 |
| F | 黑盒验收与文档收口 | `tests/run_all.sh`、黑盒 tests、README/docs 收尾 | A-E 输出 | 否 |

## 3. 文件所有权边界

### Workstream A 独占

1. `plugins/spec-autopilot/skills/autopilot-dispatch/SKILL.md`
2. `plugins/spec-autopilot/skills/autopilot/references/parallel-phase1.md`
3. `plugins/spec-autopilot/skills/autopilot/references/phase1-requirements.md`
4. `plugins/spec-autopilot/skills/autopilot/references/phase1-requirements-detail.md`
5. `plugins/spec-autopilot/runtime/scripts/validate-decision-format.sh`
6. 与 Phase 1 隔离直接相关的新测试

### Workstream B 独占

1. `plugins/spec-autopilot/skills/autopilot-init/SKILL.md`
2. `plugins/spec-autopilot/skills/autopilot-phase7/SKILL.md`
3. `plugins/spec-autopilot/skills/autopilot-gate/SKILL.md`
4. `plugins/spec-autopilot/runtime/scripts/check-predecessor-checkpoint.sh`
5. `plugins/spec-autopilot/runtime/scripts/poll-gate-decision.sh`
6. `plugins/spec-autopilot/runtime/scripts/rebuild-anchor.sh`
7. 与 auto-continue / archive 直接相关的测试

### Workstream C 独占

1. `plugins/spec-autopilot/runtime/scripts/save-state-before-compact.sh`
2. `plugins/spec-autopilot/runtime/scripts/reinject-state-after-compact.sh`
3. `plugins/spec-autopilot/runtime/scripts/scan-checkpoints-on-start.sh`
4. `plugins/spec-autopilot/runtime/scripts/save-phase-context.sh`
5. `plugins/spec-autopilot/runtime/scripts/recovery-decision.sh`
6. `plugins/spec-autopilot/runtime/scripts/clean-phase-artifacts.sh`
7. `plugins/spec-autopilot/skills/autopilot-recovery/SKILL.md`
8. 与恢复闭环直接相关的测试

### Workstream D 独占

1. `plugins/spec-autopilot/gui/src/App.tsx`
2. `plugins/spec-autopilot/gui/src/components/*`
3. `plugins/spec-autopilot/gui/src/store/index.ts`
4. `plugins/spec-autopilot/gui/src/lib/ws-bridge.ts`
5. `plugins/spec-autopilot/runtime/server/autopilot-server.ts`
6. `plugins/spec-autopilot/runtime/server/src/bootstrap.ts`
7. `plugins/spec-autopilot/runtime/server/src/config.ts`
8. `plugins/spec-autopilot/runtime/server/src/ws/*`
9. `plugins/spec-autopilot/runtime/server/src/api/routes.ts`
10. `plugins/spec-autopilot/runtime/scripts/start-gui-server.sh`

### Workstream E 独占

1. `plugins/spec-autopilot/runtime/scripts/rules-scanner.sh`
2. `plugins/spec-autopilot/runtime/scripts/auto-emit-agent-dispatch.sh`
3. `plugins/spec-autopilot/runtime/scripts/post-task-validator.sh`
4. `plugins/spec-autopilot/skills/autopilot/references/tdd-cycle.md`
5. `plugins/spec-autopilot/skills/autopilot/references/phase5-implementation.md`
6. `plugins/spec-autopilot/skills/autopilot/references/phase6-code-review.md`
7. 与 agent 治理、TDD、review 直接相关的测试

### 协调者保留

1. `plugins/spec-autopilot/skills/autopilot/SKILL.md`
2. `plugins/spec-autopilot/README.zh.md`
3. `plugins/spec-autopilot/CLAUDE.md`
4. `plugins/spec-autopilot/runtime/server/src/types.ts`
5. `plugins/spec-autopilot/runtime/server/src/state.ts`
6. `plugins/spec-autopilot/runtime/server/src/snapshot/snapshot-builder.ts`
7. `plugins/spec-autopilot/tests/run_all.sh`

## 4. 每个工作流必须交付的内容

每个工作流都必须产出:

1. 真实代码修改
2. 对应测试修改或新增
3. 必要文档修订
4. 简短的“共享文件建议变更”说明，供协调者收口

## 5. 风险与冲突处理

发现以下冲突时，不允许各自私自覆盖:

1. 共享 JSON schema 字段命名不一致
2. server snapshot 字段与 GUI store 字段不一致
3. `archive-readiness.json`、`state-snapshot.json`、`agent-dispatch-record.json` 字段发生交叉重叠
4. `skills/autopilot/SKILL.md` 同时被多个工作流要求修改

这些冲突统一由协调者解决。

## 6. 工作流完成定义

单个工作流完成，必须同时满足:

1. 自己负责的文件集已修改完
2. 自己负责的测试已通过
3. 没有引入对其他工作流写入边界的破坏
4. 已明确列出对共享文件的收口要求

## 7. 最终总验收

最终必须对照 `docs/plans/2026-03-28-spec-autopilot-remediation-acceptance-matrix.zh.md` 做逐项核验。未通过的项不得宣称“整体完成”。
