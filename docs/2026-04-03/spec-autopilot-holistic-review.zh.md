# spec-autopilot 整体架构深度评审

日期: 2026-04-03
范围: `plugins/spec-autopilot`
方法: 架构文档审阅、运行时脚本审阅、GUI/Server 审阅、关键测试执行、并行子 agent 交叉审阅

## 0. 总结结论

当前插件的核心方向是对的: 它试图用阶段化编排、门禁、checkpoint、compact/recovery、事件总线和 GUI 控制面，去约束 AI 的已知缺点。这一产品方向具备明确商业价值，也比“纯自由发挥式” agent harness 更接近可交付系统。

问题不在于“没有治理”，而在于“治理面已经分叉”:

- 真正的控制面在 `prompt / skill / shell script / state-snapshot / server type / GUI store / tests` 之间重复定义。
- 部分规则只做到可观测，没有做到 fail-close 强制执行。
- `full/lite/minimal` 中，`lite/minimal` 有专门测试，`full` 缺少同等级整链路仿真。
- compact/recovery、OpenSpec/FF、TDD、fixup、报告链路都存在契约漂移。
- 主窗口“仅编排控制”的目标没有真正收口，执行细节仍大量泄露到主视图。

因此，当前版本更像“高潜力但尚未收敛为单一真相源”的系统。它已经具备工程化骨架，但还不具备“严格、确定性、长期可维护”的闭环。

## 1. 评审方法与已执行验证

### 1.1 直接审阅的关键位置

- 根规则: `CLAUDE.md`
- 插件规则: `plugins/spec-autopilot/CLAUDE.md`
- 架构文档:
  - `plugins/spec-autopilot/docs/architecture/overview.zh.md`
  - `plugins/spec-autopilot/docs/architecture/phases.zh.md`
  - `plugins/spec-autopilot/docs/architecture/gates.zh.md`
- 关键运行时脚本:
  - `runtime/scripts/check-predecessor-checkpoint.sh`
  - `runtime/scripts/save-state-before-compact.sh`
  - `runtime/scripts/reinject-state-after-compact.sh`
  - `runtime/scripts/recovery-decision.sh`
  - `runtime/scripts/validate-openspec-artifacts.sh`
  - `runtime/scripts/auto-emit-agent-dispatch.sh`
  - `runtime/scripts/emit-report-ready-event.sh`
  - `runtime/scripts/emit-tdd-audit-event.sh`
  - `runtime/scripts/unified-write-edit-check.sh`
  - `runtime/scripts/tdd-refactor-rollback.sh`
- GUI / server:
  - `gui/src/App.tsx`
  - `gui/src/components/ParallelKanban.tsx`
  - `gui/src/components/OrchestrationPanel.tsx`
  - `gui/src/components/ReportCard.tsx`
  - `gui/src/store/index.ts`
  - `runtime/server/src/api/routes.ts`
  - `runtime/server/src/ws/broadcaster.ts`
  - `runtime/server/src/snapshot/snapshot-builder.ts`
  - `runtime/server/src/types.ts`

### 1.2 已执行的关键测试

通过:

- `bash plugins/spec-autopilot/tests/test_lite_mode.sh`
- `bash plugins/spec-autopilot/tests/test_minimal_mode.sh`
- `bash plugins/spec-autopilot/tests/integration/test_e2e_checkpoint_recovery.sh`
- `bash plugins/spec-autopilot/tests/integration/test_e2e_hook_chain.sh`
- `bash plugins/spec-autopilot/tests/test_phase_graph_consistency.sh`
- `bash plugins/spec-autopilot/tests/test_recovery_auto_continue.sh`
- `bash plugins/spec-autopilot/tests/test_tdd_isolation.sh`
- `bash plugins/spec-autopilot/tests/test_tdd_rollback.sh`
- `bash plugins/spec-autopilot/tests/test_phase6_suite_results.sh`
- `bash plugins/spec-autopilot/tests/test_phase6_allure.sh`
- `bash plugins/spec-autopilot/tests/test_fixup_commit.sh`
- `bash plugins/spec-autopilot/tests/test_gui_snapshot_meta_refresh.sh`
- `bash plugins/spec-autopilot/tests/test_gui_store_cap.sh`
- `bash plugins/spec-autopilot/tests/test_gui_server_closures.sh`
- `bash plugins/spec-autopilot/tests/test_gui_server_health.sh`
- `bash plugins/spec-autopilot/tests/test_autopilot_server_aggregation.sh`
- `bash plugins/spec-autopilot/tests/test_server_robustness.sh`
- `bash plugins/spec-autopilot/tests/test_agent_priority_enforcement.sh`

额外发现:

- GUI/server 两个集成测试在并行运行时会因固定端口互相干扰，串行运行后恢复通过。这是测试独立性问题，不是产品行为正确性的证明。

## 2. 评审结论: 13 个问题逐项分析

## 2.1 三种模式 `full/lite/minimal` 的全流程仿真与测试

### 结论

`lite/minimal` 的模式门禁覆盖明显强于 `full`。`full` 当前没有同等级的整链路仿真测试，这会让很多跨阶段契约漂移在回归中漏检。

### 证据

- 仓库里只有两个显式模式测试文件:
  - `plugins/spec-autopilot/tests/test_lite_mode.sh`
  - `plugins/spec-autopilot/tests/test_minimal_mode.sh`
- 不存在对应的 `test_full_mode.sh`
- `full` 主要依赖分散测试拼接证明，例如:
  - `plugins/spec-autopilot/tests/integration/test_e2e_hook_chain.sh`
  - `plugins/spec-autopilot/tests/test_phase_graph_consistency.sh`
  - `plugins/spec-autopilot/tests/integration/test_e2e_checkpoint_recovery.sh`

### 发现的问题

- `full` 模式没有一条从 Phase 0 到 Phase 7 的主线仿真。
- `full` 才会经过 OpenSpec/FF/测试设计/报告全链路，而这些恰恰是契约漂移最多的区域。
- `lite/minimal` 的“跳过阶段”行为被测试覆盖了，但 `full` 的“必须经过且契约连续”没有被同等覆盖。

### 最佳修复方案

- 新增一条 `full` 主线 E2E:
  - Phase 1 requirement packet
  - Phase 2 OpenSpec
  - Phase 3 FF
  - Phase 4 test design
  - Phase 5 implementation
  - Phase 6 report
  - Phase 7 archive
- 新增 `full` 崩溃恢复 E2E:
  - 在 Phase 2、Phase 5、Phase 6 分别中断
  - 验证 compact 恢复、checkpoint 恢复、报告恢复、Allure 链接恢复
- 把三种模式收敛成同一张 mode-flow matrix，由此自动生成:
  - `_phase_graph.py`
  - predecessor gate
  - recovery sequencing
  - mode tests

## 2.2 主编排 agent 信息的必要性、冗余、主窗口最佳编排方式

### 结论

主窗口当前不是纯编排控制面，而是“编排 + 执行细节 + 调试信息”混合面。必要信息和非必要信息没有真正隔离。

### 证据

- `gui/src/App.tsx:4` 自称“主窗口只保留编排控制信息”，但 `gui/src/App.tsx:271-276` 仍把 `ParallelKanban` 作为主编排视图核心内容。
- `gui/src/components/ParallelKanban.tsx:230-247` 在展开 agent 卡片时展示 `tool_use` 历史。
- `gui/src/components/ParallelKanban.tsx:218-227` 展示产出文件。
- `gui/src/components/ParallelKanban.tsx:198-205` 展示 agent summary 和完整 `agent_id`。

### 主窗口必须保留的信息

- 当前目标
- 当前 phase
- gate frontier 和阻断原因
- 当前活跃 agent 的数量和阶段分布
- 模型路由摘要
- compact 风险摘要
- 恢复来源与恢复置信度
- 报告状态摘要
- archive readiness 摘要

### 不应进入主窗口的一线执行细节

- tool_use 逐条历史
- output files 明细
- raw hook/statusline/transcript
- 具体命令、诊断噪音、低层日志
- 完整 agent_id 和过长 summary

### 最佳实践

- 主窗口只保留“控制面对象”，不显示“执行面明细”。
- 执行明细统一下沉到 `diagnostics` 视图或 drawer。
- `ParallelKanban` 在主窗口只保留:
  - 任务状态
  - agent 状态
  - 结果摘要
- 详细 tool/event/output file 只在二级诊断面板中展开。

## 2.3 上下文压缩流程是否受控、保留与恢复是否符合预期

### 结论

没有完全受控。结构化 snapshot 的方向是对的，但当前最严重的问题是: `state-snapshot.json` 在保存后又被其他脚本二次修改，`snapshot_hash` 不再可信。

### 证据

- `runtime/scripts/save-state-before-compact.sh:392-430` 构建 `state-snapshot.json`，并在最后计算 `snapshot_hash`。
- `runtime/scripts/emit-report-ready-event.sh:131-164` 直接改写 `state-snapshot.json.report_state`，没有重算 hash。
- `runtime/scripts/emit-tdd-audit-event.sh:120-124` 直接改写 `state-snapshot.json.tdd_audit`，没有重算 hash。
- `runtime/scripts/reinject-state-after-compact.sh:86-99` 恢复时严格校验 hash；不一致则 structured 路径直接失效。
- `runtime/server/src/ws/ws-server.ts:37-42` 初始 WS snapshot 只发送 `archiveReadiness/requirementPacketHash/gateFrontier`
- `runtime/server/src/ws/broadcaster.ts:10-29` 增量 snapshot meta 却包含 `reportState/recovery/tddAudit/executedPhases/skippedPhases/currentPhase`

### 进一步问题

- `runtime/scripts/reinject-state-after-compact.sh:172-201` 的 structured 恢复只恢复 phase/results/report/tdd 等摘要，不恢复 phase-context-snapshots。
- 旧 markdown 恢复路径反而会把 `phase-context-snapshots` 重新注入。
- `runtime/scripts/save-state-before-compact.sh:252-265` 的 `requirement_packet_hash` 来自 Phase 1 checkpoint 文件，而不是 `context/requirement-packet.json` 这一唯一事实源。
- `runtime/server/src/types.ts:251-280` 的 `StateSnapshot` 类型与真实写入结构不一致:
  - `next_action` 被声明为 `string`，实际是对象
  - `active_tasks` 被声明为 `string[]`，实际是对象数组
  - `active_agents` 被声明为 `DispatchRecord[]`，实际是另一种结构
- GUI 首次连接时拿到的 meta 比后续广播更少，因此报告卡片、恢复状态、TDD 审计可能首屏缺失

### 必须保留的上下文

- requirement packet hash
- 当前模式
- 当前 phase
- 已执行/跳过阶段
- gate frontier
- 下一步 action
- 当前 in-progress sub-step
- Phase 5 task-level progress
- phase context snapshots
- report state
- TDD audit
- active agents / active tasks
- recovery source / reason / confidence
- model routing effective state

### 最佳修复方案

- 把 `state-snapshot.json` 改成唯一结构化控制工件。
- 任何脚本改写 snapshot 时，必须走同一个 `snapshot-upsert` 工具:
  - merge payload
  - recompute hash
  - validate schema
- structured 恢复路径补回 `phase-context-snapshots` 摘要。
- `requirement_packet_hash` 只允许从 `context/requirement-packet.json.hash` 读取。
- server `types.ts` 与 snapshot schema 做严格一一对应。

## 2.4 崩溃恢复整体流程是否符合预期

### 结论

恢复流程有设计雏形，但仍存在三类关键问题:

- snapshot 路径容易因 hash 失效被击穿
- auto-continue 条件过于保守，和文档目标不一致
- hash mismatch 被降级成 `fresh`，观测语义不够清晰

### 证据

- `runtime/scripts/recovery-decision.sh:556-579` 只有在 `git_risk_level == none` 时才允许 `auto_continue_eligible=true`
- `runtime/scripts/recovery-decision.sh:552` 在 hash mismatch 时把 `recovery_source` 直接降成 `fresh`
- `runtime/scripts/reinject-state-after-compact.sh:140-161` structured 恢复固定写成 `snapshot_resume`

### 发现的问题

- 有 `fixup` 或 worktree residual 时，即使恢复路径清晰也不会自动继续。
- `snapshot_hash_mismatch` 作为显式问题没有被长期暴露，只是被吞成 `fresh`。
- structured 路径恢复的信息面小于 legacy markdown 路径。

### 最佳修复方案

- 将 auto-continue 政策收敛为:
  - `high` 风险禁止自动继续
  - `medium/low/none` 允许继续，但要带原因和显式标记
- `snapshot_hash_mismatch` 必须保留为显式恢复来源，不得伪装成 `fresh`
- 把 recovery decision、reinject、GUI meta 展示全部绑定同一个恢复语义枚举
- 新增恢复回放测试:
  - snapshot valid
  - snapshot hash mismatch
  - checkpoint fallback
  - progress-only fallback

## 2.5 需求评审环节、更优方案、三路 agent 是否必要、提示词工程化

### 结论

当前方向基本合理，但“三路调研”不应被当作默认必选动作，而应当是成熟度驱动的可选编排。需求来源稳定性的关键不是“调研越多越好”，而是“最终 requirement packet 是否唯一、证据是否可追溯”。

### 证据

- `skills/autopilot/SKILL.md:145-153` 已经引入成熟度驱动的分路思想
- `skills/autopilot/references/parallel-phase1.md:129-156` 明确了 `clear / partial / ambiguous`
- `skills/autopilot/SKILL.md:205-213` 要求 Phase 1 生成 `requirement-packet.json`

### 结论拆解

- 三路调研不是永远必要。
- `clear` 需求只需要 Auto-Scan。
- `partial` 才需要技术调研。
- `ambiguous` 或外部知识强依赖时才需要联网与多路调研。

### 需求来源稳定性的最佳实践

- 主线程只允许三类输入进入 Phase 1 决策:
  - `RAW_REQUIREMENT`
  - steering / project context
  - 子调研 agent 的结构化 envelope
- 最终只允许 `requirement-packet.json` 成为后续阶段事实源。

### 提示词工程化建议

- 强制区分:
  - facts
  - inference
  - assumptions
  - risks
  - open questions closed
- 明确禁止:
  - 未验证猜测写成事实
  - 主线程读取 research 正文拼 prompt
- decision card 必须绑定证据来源

## 2.6 OpenSpec 与 OpenSpec FF 流程是否存在异常风险

### 结论

存在，而且是典型的“文档 / validator / phase 产物命名”三方分叉。

### 证据

- `runtime/scripts/validate-openspec-artifacts.sh:107-120` 仍在查找:
  - `openspec.md`
  - `ff.md`
  - `fast-forward.md`
- 但架构与协议更偏向 `proposal/design/tasks` 风格产物

### 风险

- Phase 2/3 实际产物可能完全正确，但 validator 会判找不到。
- FF 和 OpenSpec 的 contract 没有单一 schema。
- 文档改名或 phase 演化后，运行时校验非常容易继续漂移。

### 最佳修复方案

- 为 Phase 2 / Phase 3 引入单一 schema 真相源:
  - artifact names
  - required sections
  - hash binding
  - downstream references
- validator、dispatch prompt、docs、tests 全部从 schema 生成。

## 2.7 测试用例设计是否贴合产品需求、如何保证覆盖与独立性、避免 Hack Reward

### 结论

当前测试“数量很多”，但“产品承诺覆盖的真实性”不够均匀。问题集中在四点:

- 文档一致性测试过多
- 仍围绕废弃兼容脚本测试
- 真实独立性不够
- 缺少对 Phase 0 Banner 与 `Phase 6 -> report_ready -> ReportCard/Allure` 的真实主链路测试

### 证据

- `tests/run_all.sh` 会把 `docs_consistency` 作为低信号层
- `tests/test_fixup_commit.sh:1-72` 明确是 `docs_consistency`
- `tests/test_phase6_suite_results.sh:1-40` 仍直接围绕 `validate-json-envelope.sh`
- `runtime/scripts/validate-json-envelope.sh` 已是 deprecated 兼容脚本
- `tests/test_autopilot_server_aggregation.sh:44-68` 与 `tests/test_server_robustness.sh:72-99` 都固定使用 `http://localhost:9527`

### 关键问题

- 测试阶段不能只靠 md 文档，必须有真实可执行 case。
- 文档 grep 容易形成 Hack Reward。
- 固定端口会造成并行误报，削弱测试独立性。
- `full` 模式缺少 dedicated E2E，也削弱了覆盖真实性。

### 最佳修复方案

- 所有关键能力改成“黑盒 + 真实 hooks.json 注册入口”测试:
  - recovery
  - agent governance
  - TDD
  - OpenSpec
  - report
  - fixup
- docs_consistency 单独统计，不计入主质量口径。
- GUI/server 集成测试一律随机端口。
- 建立产品需求 -> gate -> artifact -> test 的 traceability matrix。

## 2.8 代码实现是否严格遵守 rules、`CLAUDE.md`、子 agent、优先级与稳定性要求

### 结论

现在最多只能证明“记录了谁被派发”，不能证明“必须用谁、不能用谁、优先级冲突时谁生效”。

### 证据

- `rules-scanner.sh` 只产出 `agent_priority_map`
- `auto-emit-agent-dispatch.sh` 只记录:
  - `selection_reason`
  - `resolved_priority`
  - `fallback_reason`
- 子 agent 约束在 PostToolUse 校验中仍没有真正 fail-close 落地
- 并行子 agent 审阅结论: 当前是“可观测”，不是“可强制”

### 风险

- 项目 `CLAUDE.md` 和插件 `CLAUDE.md` 的规则只停留在审计，不是执行器约束。
- `.claude/agents/` 若以后接入多个 agent，也没有清晰的优先级真相源。

### 最佳修复方案

- 引入单一 `agent-policy-resolver`:
  - project agent policy
  - plugin policy
  - builtin fallback
- 明确优先级:
  - project `.claude/agents` > plugin policy > builtin
- 在 dispatch 前和 PostToolUse 后都进行 fail-close 校验:
  - required agent missing
  - forbidden agent used
  - wrong phase ownership

## 2.9 Phase 5/6 的 TDD 代码生成、独立性、review 质量、RED/GREEN/REFACTOR 是否完整

### 结论

当前只完成了 TDD 治理的一部分:

- 有写文件隔离
- 有 rollback 脚本
- 有部分审计

但没有形成完整的生产闭环。

### 证据

- `tests/test_tdd_isolation.sh` 证明了 RED/GREEN 文件写入隔离
- `tests/test_tdd_rollback.sh` 证明了 rollback 脚本本身可工作
- 但并行子 agent 审阅发现:
  - 生产链路没有完整强制 `test_intent/failing_signal`
  - `emit-tdd-audit-event.sh` 存在，但未形成完整 hooks 闭环
  - RED/GREEN/REFACTOR 的真实 phase E2E 缺失

### 最佳修复方案

- 定义生产级 `tdd_cycle` schema:
  - red evidence
  - failing signal
  - green verification
  - refactor verification / rollback
- 在 Phase 5/6 真流程中接通:
  - tdd audit
  - rollback
  - report summary
- 新增一条端到端测试:
  - RED 真失败
  - GREEN 真通过
  - REFACTOR 故意失败后真回滚

## 2.10 fixup 合并过程是否完整、是否遗漏

### 结论

现在不能严格证明“本次迭代所有 fixup 都被一一合并且无遗漏”。现有实现更像启发式检查，而不是严格 ledger。

### 证据

- 并行子 agent 审阅指出:
  - manifest 生成依赖 `git log --grep` 和启发式推断
  - manifest 缺失时校验会放行
  - Phase 7 仍高度依赖 `fixup_count >= checkpoint_count`
- `tests/test_fixup_commit.sh` 的后半段本质是文档断言，不是 manifest 集成测试

### 最佳修复方案

- checkpoint 写入时同步写不可变 ledger:
  - `checkpoint_id`
  - expected fixup subject
  - anchor range
- Phase 7 必须要求 manifest 存在且逐 checkpoint 一一映射。
- `count` 只能做辅助指标，不能做主 gate。

## 2.11 每个阶段门禁与上下文恢复的意义

### 阶段门禁的真正意义

- 防止 phase skipping
- 把 AI 的“自由发挥”压进状态机
- 把 phase 输出变成下游显式输入
- 为 recovery 提供可裁决边界
- 为 GUI 提供真实控制面对象

### 上下文恢复的真正意义

- 让 compact 之后继续保持同一条任务事实链
- 降低 AI 在长链任务里的记忆丢失
- 避免已完成阶段被重复执行
- 将“断点续跑”从经验行为变成确定性协议

### 当前问题

- snapshot hash 被破坏后，恢复语义被削弱。
- structured recovery 比 legacy markdown 恢复反而少上下文。

## 2.12 整体编排理念是否合理、是否符合 harness 理念、是否规避 AI 缺点、产品力与商业价值如何

### 结论

整体理念合理，而且方向先进:

- 用阶段化 + 门禁 + checkpoint + recovery 去压制上下文混乱
- 用 requirement packet 去压制需求漂移
- 用 GUI 控制面去压制“黑箱感”
- 用 fixup / archive / audit 去压制产物不确定性

这套理念总体上符合社区对 harness 的核心诉求: 把 agent 从“聪明但不可控”改造成“可观测、可恢复、可验证”。

### 当前不足

- 单一真相源没有真正建立
- 文档/skill/script/test/GUI 多头定义
- 部分治理停留在 advisory，不是 enforcement
- 测试体系仍有 Hack Reward 风险
- 主窗口边界不干净

### 资深产品经理视角

优点:

- 痛点命中准确
- 差异化明显
- 对企业级长链路 AI 开发流程有实际价值

问题:

- 控制面过多，学习成本高
- 文档与实现耦合过深，维护成本高
- 某些区域过度设计，尤其是重复协议与重复载体

商业化结论:

- 有商业化价值
- 但要先做“收敛和硬化”，而不是继续扩展功能面

## 2.13 报告输出与修复执行文档要求

本次已按要求将评审报告和全量修复提示词输出到:

- `docs/2026-04-03/spec-autopilot-holistic-review.zh.md`
- `docs/2026-04-03/spec-autopilot-full-remediation-execution-prompt.zh.md`

## 3. 已确认的显式 BUG

## 3.1 BUG 1: 启动卡片中的 GUI 字段错误显示 `unavailable`

### 结论

成立。根因不是 GUI server 本身不会返回地址，而是 Phase 0 启动卡片仍然依赖 prompt 约定和硬编码，而不是解析脚本的结构化返回。

### 证据

- `runtime/scripts/start-gui-server.sh:9-47` 已经输出 `GUI_SERVER_JSON:{status,http_url,ws_url,health_url,...}`
- `skills/autopilot-phase0/SKILL.md:55-84` 仍把启动结果描述成:
  - 成功就显示硬编码 `http://localhost:9527`
  - 失败就显示 `unavailable`
- `skills/autopilot-phase0/SKILL.md:61` 仍写着日志重定向 `/dev/null`，与实际脚本写入 `logs/gui-server.log`、`logs/gui-server.err.log` 不一致

### 根因

- Phase 0 Banner 没有被强制绑定到 `GUI_SERVER_JSON`
- 启动卡片仍允许模型“猜一个 GUI URL”
- prompt 与脚本行为已经分叉

### 最佳修复方案

- Phase 0 只能解析 `GUI_SERVER_JSON`
- 成功时显示真实 `http_url`
- 失败时显示 `status=failed + error`
- 不允许再硬编码 `9527` 或 `unavailable`

## 3.2 BUG 2: 多个阶段模型展示卡片右边框没有封闭，视觉上像 C 字型

### 结论

按用户现象应视为成立，但从当前源码无法直接证明“右边框被删掉”；更像是视觉对比度、构建产物或样式覆盖导致的运行态问题。

### 证据

- `gui/src/components/ParallelKanban.tsx:174`
- `gui/src/components/ParallelKanban.tsx:281`

当前样式是:

- 基底 `border border-border`
- 再叠加 `border-l-4 border-l-*`

### 根因

- JSX 层不是“没有右边框”，而是“闭合边框过弱”
- 深色主题下 `border-border` 对比度不足
- 可能存在 CSS 构建或运行态覆盖
- 没有做 GUI visual regression 覆盖

### 最佳修复方案

- 先增加可复现的视觉快照测试，确认问题来自运行态而不是主观观察
- 把卡片分成两层:
  - 外层统一闭合 outline
  - 内层或伪元素负责左侧强调色
- 提高右边界对比度
- 增加截图测试或 story visual baseline

## 3.3 BUG 3: 主窗口 agent 仅做编排控制，但是否有不受控内容进入主窗口

### 结论

成立，而且是当前主窗口最明显的产品边界问题。

### 证据

- `gui/src/App.tsx:4` 声称主窗口只保留编排控制信息
- `gui/src/App.tsx:271-276` 主视图仍直接渲染 `ParallelKanban`
- `gui/src/components/ParallelKanban.tsx:218-247` 展示 output files 和 tool_use

### 最佳修复方案

- 主视图只显示:
  - 阶段进度
  - gate 状态
  - agent 状态摘要
  - report 摘要
- `tool_use / output_files / diagnostics` 下沉到 diagnostics 视图

## 3.4 BUG 4: 测试阶段的测试用例是否需要评审，是否需要真实 test case 而不是 md

### 结论

需要，而且必须有真实可执行 case。只靠 md 文档或 grep 文本不够。

### 原因

- 当前仍有大量 docs consistency / grep 型测试
- 这无法证明真实 hooks、真实 phase、真实报告、真实 fixup 的行为

### 最佳修复方案

- 测试用例设计纳入显式评审
- 每条产品承诺至少有一条生产入口黑盒测试
- md 文档只做说明，不做主证明

## 3.5 BUG 5: 生成测试报告阶段是否在主 agent 窗口打印卡片信息，并在卡片中开启 Allure 全量结果访问链接

### 结论

目前不是半闭环，而是主链路本身就没有真正接通:

- GUI 卡片支持报告与 Allure 链接
- Phase 7 prompt 也要求主线程展示
- 但运行时没有“确定性主线程卡片发射器”
- `report_ready` 事件发射脚本当前还存在真实故障与错误写入路径

### 证据

- `runtime/scripts/emit-report-ready-event.sh:33-80` 会扫描 `report_url/allure_preview_url`
- `runtime/scripts/emit-report-ready-event.sh:101-164` 只发事件并更新 snapshot
- `runtime/scripts/emit-report-ready-event.sh:10` 错误 `source` 了可执行脚本
- `runtime/scripts/emit-report-ready-event.sh:102` 事件写入的是 `changes/<change>/logs/events.jsonl`
- `runtime/server/src/config.ts:39` server 实际只读项目根 `logs/events.jsonl`
- `gui/src/components/ReportCard.tsx:205-236` 已支持展示 `report_url` 和 `allure_preview_url`
- `skills/autopilot-phase7/SKILL.md:50-53,90-96` 要求 Phase 7 主线程展示测试报告汇总和 Allure 地址
- `runtime/server/src/ws/ws-server.ts:37-42` 初始 snapshot meta 不含 `reportState`
- `gui/src/store/index.ts:863-874` meta 初始化又是“仅为空时回填”

### 缺口

- `Phase 6` 正常完成路径没有被确定性接上 `emit-report-ready-event.sh`
- 就算 `report_state` 已经存在，GUI 首次连接也可能看不到
- 运行时没有强制主线程输出“报告卡片”
- 只有 GUI 控制面可见，不保证主 agent 终端视图同步
- `gui/src/store/index.ts:838-874` 的 meta 初始化是“仅为空时回填”，后续 meta-only 更新存在陈旧风险

### 最佳修复方案

- 新增 deterministic `emit-report-card.sh`:
  - 输出主线程终端 summary box
  - 写 `report_ready` 事件
  - 更新 snapshot 并重算 hash
- 把 `emit-report-ready-event.sh` 改成确定性 Phase 6 收口步骤，而不是游离脚本
- `report_ready` 只能写项目根 `logs/events.jsonl`
- 移除错误 `source`
- GUI 和主线程都消费同一份 report card payload
- store meta 合并逻辑改为“按时间戳替换最新值”，不再只在空值时注入

## 4. 全量修复原则

- 建立单一真相源，不允许一个事实在多个载体重复手写
- 主窗口只保留编排控制面
- 所有规则必须可执行、可阻断、可测试
- 所有关键测试必须命中生产入口，避免 Hack Reward
- `full/lite/minimal` 必须共享一张 mode graph 和一套生成式契约
- compact/recovery/report/tdd/fixup 全部进入统一控制面

## 5. 最终判断

这套插件不是方向错了，而是已经进入“必须收敛”的阶段。

如果继续在当前状态上叠加功能，它会越来越像一套聪明但脆弱的系统。
如果先完成这次收敛，它有机会成为真正有产品力、有商业价值的 AI 编排底座。
