# spec-autopilot 全量修复执行提示词

> 生成日期: 2026-03-30  
> 对应评审报告: `docs/reports/v5.8/spec-autopilot-holistic-architecture-review-2026-03-30.md`  
> 用途: 直接复制给 Claude，用于对 `plugins/spec-autopilot` 做整套工程化修复

## 使用说明

建议直接复制下方“全量执行提示词”给 Claude。  
这个提示词不是让 Claude 做口头分析，而是要求它按波次真正改代码、脚本、测试和文档，并在每一波执行后做针对性验证。

---

## 全量执行提示词

```text
你现在在仓库根目录 `/Users/lorain/Coding/Huihao/claude-autopilot`。

目标:
对 `plugins/spec-autopilot` 做一次真正的工程化修复。重点不是“补几句文档”，而是把目前散落在 `SKILL.md`、参考文档、运行时脚本、GUI、测试里的协议收敛成单一真相源和 fail-closed 执行体系。

工作边界:
- 只允许修改 `plugins/spec-autopilot/` 下的代码、脚本、测试、文档
- 不要修改 `plugins/parallel-harness`
- 不要回退任何与本任务无关的用户改动

语言要求:
- 所有对外说明使用中文简体

关键背景:
1. 当前仓库根目录 `make lint`、`make build`、`make typecheck`、`make test` 全部通过
2. 当前全量测试状态是 `101 files, 1236 passed, 0 failed`
3. 但评审发现的核心问题不是“测试挂了”，而是“很多关键控制语义仍主要活在文档和提示词里，没有完全下沉为运行时硬约束”

总原则:
1. 不要只修文档，必须把关键治理逻辑下沉为运行时脚本、hook、server/store/UI 和黑盒测试
2. 能 fail-closed 的地方不要只做 warning/audit
3. 主编排只保留最小控制面，正文和调试观测不得继续污染主窗口
4. requirement packet 必须成为真正唯一事实源
5. 所有修复都要补对应测试；最终必须再次通过仓库根目录:
   - `make lint`
   - `make build`
   - `make typecheck`
   - `make test`

执行要求:
1. 先读以下文件建立上下文，再开始改:
   - `plugins/spec-autopilot/docs/reports/v5.8/spec-autopilot-holistic-architecture-review-2026-03-30.md`
   - `plugins/spec-autopilot/hooks/hooks.json`
   - `plugins/spec-autopilot/runtime/scripts/_phase_graph.py`
   - `plugins/spec-autopilot/runtime/scripts/check-predecessor-checkpoint.sh`
   - `plugins/spec-autopilot/runtime/scripts/save-state-before-compact.sh`
   - `plugins/spec-autopilot/runtime/scripts/reinject-state-after-compact.sh`
   - `plugins/spec-autopilot/runtime/scripts/recovery-decision.sh`
   - `plugins/spec-autopilot/runtime/scripts/clean-phase-artifacts.sh`
   - `plugins/spec-autopilot/runtime/scripts/_post_task_validator.py`
   - `plugins/spec-autopilot/runtime/scripts/auto-emit-agent-dispatch.sh`
   - `plugins/spec-autopilot/runtime/scripts/auto-emit-agent-complete.sh`
   - `plugins/spec-autopilot/runtime/server/src/types.ts`
   - `plugins/spec-autopilot/runtime/server/src/api/routes.ts`
   - `plugins/spec-autopilot/runtime/server/src/snapshot/snapshot-builder.ts`
   - `plugins/spec-autopilot/gui/src/App.tsx`
   - `plugins/spec-autopilot/gui/src/store/index.ts`
   - `plugins/spec-autopilot/gui/src/components/ParallelKanban.tsx`
   - `plugins/spec-autopilot/skills/autopilot/references/protocol.md`
   - `plugins/spec-autopilot/skills/autopilot/references/mode-routing-table.md`
   - `plugins/spec-autopilot/skills/autopilot/references/phase5-implementation.md`
   - `plugins/spec-autopilot/skills/autopilot-dispatch/SKILL.md`
   - `plugins/spec-autopilot/skills/autopilot-phase7/SKILL.md`

2. 禁止跳波次。每个 Wave 结束后必须执行该 Wave 的针对性测试，再进入下一 Wave。
3. 如果发现旧测试在验证废弃脚本或文档文本，不要直接删除；要么把它升级为生产入口黑盒测试，要么移动到兼容性套件并从主覆盖口径中剥离。

必须按以下 Wave 顺序实施。

Wave 0: 基线与单一真相源设计

目标:
- 明确哪些内容属于“运行时真相”，哪些只是技能文档
- 搭一个真正可复用的 phase/mode/schema 控制面基础

必须完成:
1. 设计并落地单一真相源文件，建议新增:
   - `plugins/spec-autopilot/runtime/contracts/phase-manifest.json`
   - `plugins/spec-autopilot/runtime/contracts/envelope-schema.json`
   - 或者等价的 machine-readable manifest/schema 目录
2. phase manifest 至少覆盖:
   - full/lite/minimal 的 `execution_sequence`
   - `display_sequence`
   - `phase_labels`
   - `predecessor`
   - `allowed_transitions`
   - `per_mode_skipped_phases`
   - `checkpoint_slug`
   - `default_model_routing`
3. envelope schema 至少覆盖 Phase 1~7 的 required/optional fields
4. 明确“由 manifest/schema 生成或约束”的消费点:
   - runtime scripts
   - server types
   - dispatch 文档示例
   - 黑盒测试 fixture

验收:
- 仓库里不再同时存在 3 套以上 mode/phase/envelope 真相源
- `protocol.md`、dispatch 示例、validator 逻辑不再互相分叉

Wave 1: mode/phase/state machine 收口

目标:
- 把模式序列、阶段图、Phase 0 任务创建、恢复推导、UI phase 展示统一成同一套定义

必须完成:
1. `_phase_graph.py`、`_common.sh`、`check-predecessor-checkpoint.sh`、`scan-checkpoints-on-start.sh`、`recovery-decision.sh`、server phase label/total phases、GUI phase label 全部改为消费 phase manifest
2. `Phase 0` 的任务创建逻辑改为消费 manifest，不允许继续在 `autopilot-phase0/SKILL.md` 里单独维护一套执行图
3. 将“执行序列”和“展示序列”分层
4. 统一 Phase 5 的入口阶段推导:
   - full: `4 -> 5`
   - lite/minimal: `1 -> 5`
5. 修复并统一 Phase 6 的路径 A/B/C 背景/前台语义，不允许文档和运行时互相打架

必须补的测试:
1. `full/lite/minimal` 的统一 phase graph 一致性测试
2. `Phase 0 -> next phase -> predecessor -> resume phase` 一致性测试
3. `full`、`lite`、`minimal` 各一条更接近真实流程的 E2E fixture

验收:
- 所有 mode/phase 脚本只依赖 manifest，不再各自硬编码一套逻辑
- Phase 6 路径语义在文档、运行时、测试中一致

Wave 2: requirement packet 成为真正唯一事实源

目标:
- 让 `context/requirement-packet.json` 取代散落的 Phase 1 正文材料，成为后续阶段唯一主输入

必须完成:
1. Phase 2~7 的 prompt/template/脚本统一只允许依赖:
   - `context/requirement-packet.json`
   - 最小控制面摘要
2. lite/minimal 下 Phase 5 任务拆分只能基于 requirement packet，不允许再从:
   - `phase-1-requirements.json`
   - `project-context.md`
   - `research-findings.md`
   - `web-research-findings.md`
   重新拼事实源
3. `requirement_packet_hash` 的保存、恢复、server 暴露、GUI 消费全部统一为 packet 内部 hash
4. 缺 packet 或 hash 不匹配时必须 fail-closed

必须补的测试:
1. packet 缺失 -> 后续 phase 阻断
2. packet hash 不匹配 -> 阻断
3. lite/minimal Phase 5 不再依赖 `phase-1-requirements.json` 的黑盒测试

验收:
- requirement packet 缺失或 hash 不一致时，流程无法继续
- Phase 5 任务自动拆分的唯一事实源变成 packet

Wave 3: Phase 1 主线程隔离与需求调研工程化

目标:
- 把“主线程不读 research/BA 正文”的约束从文档变成真正的运行时硬限制
- 把需求调研策略变成 maturity-driven，而不是含糊 prompt

必须完成:
1. 新增真正的 Read hook 或等价硬限制，阻断主线程直接读取:
   - `research-findings.md`
   - `web-research-findings.md`
   - `requirements-analysis.md`
2. 允许 BA/Research 子 Agent 在自己的执行环境读取这些文件
3. 把需求成熟度策略固化:
   - clear -> Auto-Scan
   - partial -> Auto-Scan + tech research
   - ambiguous -> Auto-Scan + tech research + web research
4. requirement packet 强制补齐:
   - `goal`
   - `scope`
   - `non_goals`
   - `acceptance_criteria`
   - `assumptions`
   - `risks`
   - `decisions`
   - `open_questions_closed`
   - `source_evidence`
   - `hash`

必须补的测试:
1. 非法 Read 真黑盒阻断测试
2. 不同 maturity 的 research 路由测试
3. Phase 1 输出 packet 的 schema 测试

验收:
- 不再靠 grep 文档证明“主线程不读正文”
- 需求调研策略可预测、可追溯、可验证

Wave 4: compact / recovery / clean 三链路语义统一

目标:
- 解决 stale snapshot、progress-only compact 丢状态、structured reinject 语义不足

必须完成:
1. `save-state-before-compact.sh` 在没有最终 checkpoint 时也生成最小 `state-snapshot.json`
2. snapshot 至少保存:
   - `change_name`
   - `mode`
   - `anchor_sha`
   - `gate_frontier`
   - `last_completed_phase`
   - `next_action`
   - `requirement_packet_hash`
   - `active_tasks`
   - `progress_entries`
   - `review_status`
   - `fixup_status`
   - `archive_status`
   - `recovery_confidence`
3. `reinject-state-after-compact.sh` 必须消费 `phase-*-context.json` 的 bounded semantic fields:
   - `summary`
   - `decisions`
   - `constraints`
   - `next_phase_context`
4. `clean-phase-artifacts.sh` 只要 `FROM_PHASE >= 1` 且会影响恢复控制态，就必须删除或重建 `state-snapshot.json` 和 `autopilot-state.md`
5. `recovery-decision.sh` 恢复前校验 snapshot 与真实工件一致性
6. 统一 `runtime/server/src/types.ts` 与真实 snapshot schema
7. 所有 snapshot/context/state 文件统一改成 tmp + rename 原子写
8. 把 auto-continue 条件从“没有 fixup commit”改成“没有高风险 git 状态”

必须补的测试:
1. progress-only / interim-only compact 恢复测试
2. partial rollback 失效 stale snapshot 测试
3. structured reinject 带回 decisions/constraints/next_phase_context 的测试
4. snapshot 与 server types 对齐测试

验收:
- partial rollback 后不会被旧 snapshot 误导
- compact 后主线程知道“下一步是什么”也知道“为什么是这一步”

Wave 5: rules / priority / required agent / background semantics fail-closed

目标:
- 把当前“审计优先”的 agent 治理改成“强阻断优先”

必须完成:
1. `auto-emit-agent-dispatch.sh` 不再只是 observational
2. 抽出明确的 agent policy resolver，至少产出:
   - `effective_agent`
   - `selection_reason`
   - `resolved_priority`
   - `required_by_rule`
   - `forbidden_by_rule`
   - `rule_source`
3. 在 PreToolUse(Task) 阶段就对以下情况 deny:
   - forbidden phase
   - required agent 未命中
   - owned boundary 非法
   - 优先级决策无法稳定收敛
4. `_post_task_validator.py` 完成 forbidden/priority 的真正校验，不允许继续 `pass`
5. 完成 rules cache 的生成、失效、重扫闭环
6. 统一 background semantics:
   - 任何带 `autopilot-phase` 标记的 Task，不管是否 `run_in_background: true`，都必须接受相同的阶段门禁、envelope 校验和治理校验
   - 不带 phase marker 的 advisory/background 任务可留在旁路，但语义必须和文档、测试完全一致

必须补的测试:
1. required/forbidden phase 真阻断测试
2. 优先级冲突矩阵测试
3. rules cache 生成与失效测试
4. background + phase marker 的生产入口测试

验收:
- 现在可以用测试和 dispatch record 同时证明“哪个 agent 被要求、为什么被选、为什么其他 agent 没被选”

Wave 6: OpenSpec / FF / TDD / fixup / archive-readiness 执行器补齐

目标:
- 把目前偏文档驱动的高价值链路下沉成真实执行器

必须完成:
1. 以 envelope schema 为基础，统一修复 Phase 2/3/7 的协议分叉
2. 新增 `build-archive-readiness.sh` 或等价脚本:
   - 输入: checkpoint、anchor、git 状态、review、zero-skip
   - 输出: 唯一 `archive-readiness.json`
3. 新增 `run-autosquash.sh` 或等价脚本
4. Phase 7 只消费 readiness 脚本结果，不再在 prompt 里隐式推理
5. 新增 TDD per-task audit 脚本，强校验:
   - `test_intent`
   - `failing_signal.assertion_message`
   - `red/green/refactor verified`
6. 把 `tdd-refactor-rollback.sh` 真正接进失败路径
7. 新增 OpenSpec/FF E2E fixture:
   - `openspec new change`
   - FF 产物链
   - 中断恢复
8. 新增 Phase 7 fixup completeness E2E:
   - anchor..HEAD 范围
   - fixup completeness
   - autosquash readiness

必须补的测试:
1. OpenSpec/FF 真实产物链测试
2. TDD 红绿重构真实 E2E
3. fixup completeness / autosquash 执行器测试
4. archive-readiness blocked/ready 矩阵测试

验收:
- Phase 7 readiness 不再只靠 `SKILL.md`
- TDD 的逐 task 证据可以由运行时脚本而不是文档证明

Wave 7: Phase 6 报告链路 + GUI 主窗口边界 + 已知 5 个 BUG 修复

目标:
- 让 GUI 真正成为“编排控制面 + 可选调试面”
- 打通测试报告/Allure 链路

必须完成:
1. 修 `start-gui-server.sh`
   - 返回结构化 JSON: `{status,url,httpPort,wsPort,reason}`
   - 启动失败时不要再“失败但 exit 0”
2. Phase 0 启动卡片只能消费这个 JSON，不能自己猜 URL
3. 去掉 GUI 端 `9527/8765` 硬编码:
   - `RawInspectorPanel`
   - `WSBridge`
   - `vite.config`
   - 统一从 `location.origin` 或 `/api/info` 派生
4. 主窗口默认只保留:
   - Timeline
   - OrchestrationPanel
   - ParallelKanban
   - Gate 控制
   - 报告卡片
5. `LogWorkbench`、`TranscriptPanel`、`ToolTracePanel`、`RawInspectorPanel` 下沉到 debug drawer/secondary route
6. 修卡片边框:
   - agent/task 卡片改成完整 `border`
   - 左边强调色单独实现
7. 把 Phase 6 报告链路打通到 GUI:
   - runtime/server/store/UI 透传 `report_path`
   - `report_format`
   - `report_url`
   - `allure_results_dir`
   - `suite_results`
8. 在主窗口新增 `ReportCard` 或等价面板，提供可点击 Allure 链接
9. 清理半接线/死状态:
   - `gateFrontier`
   - `escalated_from`
   - `telemetryAvailable`
   - `decisionLifecycle`
   - `recoverySource`
   如果要保留，就必须打通数据链；否则删除死字段

必须补的测试:
1. `start-gui-server.sh` 失败契约测试
2. 动态端口 GUI/server 集成测试
3. 主窗口默认不展示 `LogWorkbench` 的组件测试
4. `ParallelKanban` 完整边框 DOM/视觉回归测试
5. Phase 6 report URL / Allure 链接传播测试

验收:
- `GUI URL unavailable` 修复
- 卡片右边框缺失修复
- 主窗口不再混入调试观测流
- 测试报告卡片和 Allure 链接在 GUI 可见

Wave 8: 测试体系 production-path 化

目标:
- 让测试覆盖真正围绕生产入口，而不是围绕文档文本和废弃脚本

必须完成:
1. 盘点所有仍以 grep 文档为主的测试
2. 对每一类测试做二选一处理:
   - 升级为生产入口黑盒/集成测试
   - 移动到 `tests/compat` 或等价 legacy 套件，不再计入主覆盖口径
3. 盘点所有仍命中废弃脚本的测试，并按同样方式处理
4. 新增需求 -> 产物 -> gate -> 测试的 traceability matrix 文档
5. 给 Phase 4/5/6 的测试用例增加“可执行 fixture”，而不是只保留 md 设计稿

必须补的测试:
1. full/lite/minimal 三条主流程 E2E
2. OpenSpec/FF E2E
3. compact/recovery/partial rollback E2E
4. TDD E2E
5. Phase 7 readiness E2E
6. GUI/report 动态端口 E2E

验收:
- 主测试套件的“通过”能更直接代表产品承诺成立
- 文档类断言不再充当关键运行时能力的主证明

最终交付要求:
1. 代码、脚本、测试、文档全部落盘
2. 更新相关架构文档与迁移说明
3. 最终在仓库根目录执行并通过:
   - `make lint`
   - `make build`
   - `make typecheck`
   - `make test`
4. 最终汇报必须包含:
   - 改了哪些波次
   - 每个波次的核心变更
   - 新增/升级了哪些测试
   - 还剩哪些非阻断风险

注意:
如果某个问题已经在评审报告里被点明为“当前只是文档协议，不是运行时闭环”，你必须优先把它变成运行时闭环，而不是继续加强文档描述。
```

---

## 可选: 只修 5 个已知 BUG 的热修提示词

```text
你现在在仓库根目录 `/Users/lorain/Coding/Huihao/claude-autopilot`。

只修 `plugins/spec-autopilot` 的以下 5 个问题，不做大范围架构重构:

1. 启动卡片里的 GUI URL 现在错误显示 `unavailable`
2. 多个阶段模型/agent/task 卡片右边框缺失，显示成类 C 形
3. 主窗口默认混入 `LogWorkbench`、transcript、tool、raw，违背“主窗口仅做编排控制”
4. 测试阶段的测试用例还停留在文档说明，缺少真正可执行 case
5. 测试报告阶段没有稳定的报告卡片，也没有 Allure 链接

要求:
1. 允许修改 `plugins/spec-autopilot/` 下代码、脚本、测试、文档
2. 所有说明用中文简体
3. 每个 bug 修完都补测试
4. 最终在仓库根目录通过:
   - `make lint`
   - `make build`
   - `make typecheck`
   - `make test`

具体要求:

BUG 1:
- `start-gui-server.sh` 返回结构化 JSON
- 启动失败不要再 `exit 0`
- GUI URL 统一从脚本返回值或 `/api/info` 获取
- 移除 GUI 端 `9527/8765` 硬编码

BUG 2:
- `ParallelKanban` 的 agent/task 卡片基底改为完整边框
- 左侧强调色单独实现
- 补组件测试或 DOM 断言

BUG 3:
- 主窗口默认只保留 timeline + orchestration + kanban + gate
- `LogWorkbench` 下沉到 debug drawer 或 secondary route
- 补组件测试，断言默认主窗口不渲染 `LogWorkbench`

BUG 4:
- 给 Phase 4/5/6 增加至少一条真实可执行 fixture 测试
- 不要只 grep 文档
- 如果保留文档测试，移到兼容/文档套件，不作为主证明

BUG 5:
- runtime/server/store/UI 打通 `report_path/report_format/report_url/allure_results_dir/suite_results`
- 主窗口增加报告卡片或报告区
- 卡片里提供可点击 Allure 链接
- 补 Phase 6 报告传播测试
```
