# spec-autopilot 整体架构并行多维深度评审报告

> 评审日期: 2026-03-30  
> 评审对象: `plugins/spec-autopilot`  
> 评审方式: 静态代码审计 + Hook/恢复/GUI/Server/Test 交叉核查 + 并行子审查收敛  
> 本轮动作: 不改生产代码，只生成正式评审与修复执行文档

## 0. 评审方法与本轮真实验证

### 0.1 验证基线

本轮评审以 `hooks/hooks.json` 注册的实际运行时入口、`runtime/scripts/*`、`runtime/server/src/*`、`gui/src/*`、`skills/*`、`tests/*` 为主，不把 `SKILL.md` 的设计意图直接等同于“已经落地的运行时真相”。

### 0.2 本轮在仓库根目录执行的真实验证

| 命令 | 结果 |
|---|---|
| `make lint` | 通过 |
| `make build` | 通过 |
| `make typecheck` | 通过 |
| `make test` | 通过，`101 files, 1236 passed, 0 failed` |

### 0.3 本轮重点核验的代表性测试

- 模式与阶段图: `test_minimal_mode.sh`、`test_lite_mode.sh`、`test_mode_lock.sh`、`test_phase_graph_consistency.sh`
- 恢复与压缩: `test_recovery_decision.sh`、`test_phase_context_snapshot.sh`、`test_state_snapshot_hash.sh`
- TDD 与隔离: `test_tdd_isolation.sh`、`test_tdd_rollback.sh`、`test_tdd_gate_intent.sh`
- GUI/Server: `test_gui_server_health.sh`、`test_gui_store_cap.sh`、`test_autopilot_server_aggregation.sh`
- 治理与审计: `test_agent_priority_enforcement.sh`、`test_background_agent_bypass.sh`、`test_fixup_commit.sh`、`test_phase7_archive.sh`

### 0.4 关键说明

1. 仓库当前并不是“测试正在大面积失败”的状态。旧报告中“`make test` 有 7 个失败”的结论已经过时，本轮真实状态是全绿。
2. 但“测试全绿”不等于“体系已经闭环”。本轮发现的核心问题是: 大量关键控制语义仍分散在 `SKILL.md`、参考文档、运行时脚本、测试假设之间，尚未完全收敛为单一真相源和 fail-closed 运行时约束。

## 1. 执行摘要

### 1.1 总体结论

`spec-autopilot` 的产品方向是对的: 它试图用“分阶段编排 + Hook 门禁 + 子 Agent 分工 + Checkpoint + 压缩恢复 + GUI 可观测性”来对抗当前 AI 的典型缺点，例如跳步骤、上下文漂移、规则不稳定、记忆丢失和自由发挥。

但从工程化落地来看，当前插件的主要问题不是某一个脚本 bug，而是更高层的结构性分叉:

1. 关键控制语义仍有明显“文档比运行时更强”的现象。
2. 模式、阶段图、JSON 信封、TDD、fixup、archive-readiness、agent priority、主窗口边界，这些本该是硬协议的内容，仍有相当部分停留在 prompt/文档层。
3. 上下文压缩、恢复、清理三条链路已经有雏形，但还未完全做到语义闭环。
4. GUI 已经具备控制台雏形，但“编排控制面”和“观测调试面”仍混在一起。

### 1.2 一句话判断

这是一个“产品设计明显领先于当前运行时治理落地”的插件。  
它具备商业化潜力，但当前还不具备商业化交付所需要的确定性、可证明性和异常收敛能力。

### 1.3 优先级总表

| 优先级 | 主题 | 结论 |
|---|---|---|
| P0 | 单一真相源 | mode/phase/envelope/model routing 仍存在多处定义与分叉 |
| P0 | requirement packet | 仍未成为后续阶段唯一事实源 |
| P0 | compact/recovery/clean | 已成形但仍有 stale snapshot、早期 compact 丢状态、语义恢复不足 |
| P0 | rules/priority/required agent | 仍偏审计记录，不是强阻断治理 |
| P0 | Phase 1 主线程隔离 | 缺少真正的 Read 级硬约束 |
| P1 | OpenSpec/FF/TDD/fixup/archive | 协议强于执行器，真实 E2E 闭环不足 |
| P1 | Phase 6 报告/Allure | 没有从 runtime 到 GUI 的完整暴露链 |
| P1 | 测试体系 | 绿态可信，但部分测试仍验证文档或废弃脚本，而不是生产入口 |
| P2 | GUI 主窗口边界 | 主窗口混入 transcript/tool/raw，不是纯编排控制面 |
| P2 | UI 细节 BUG | GUI URL、卡片边框、报告卡片三个问题均成立 |

## 2. 问题 1: full/lite/minimal 三种模式的全流程仿真与测试

### 2.1 结论

三种模式的“阶段路由语义”基本成立，但“真实全流程仿真证明”仍不够；当前更多是在验证局部门禁和阶段图，而不是验证主编排从 Phase 0 一直到归档收口的黑盒闭环。

### 2.2 已确认的正向部分

- `autopilot-phase0/SKILL.md`、`runtime/scripts/_phase_graph.py`、`runtime/scripts/_common.sh` 都定义了相同的模式阶段序列:
  - `full = [1,2,3,4,5,6,7]`
  - `lite = [1,5,6,7]`
  - `minimal = [1,5,7]`
- `check-predecessor-checkpoint.sh` 已按 mode-aware graph 做前驱校验。
- `unified-write-edit-check.sh` 已按 mode-aware 逻辑判断是否处于 Phase 5。
- `make test` 中与模式相关的代表性测试全部通过。

### 2.3 主要问题

1. `Phase 0` 任务图和运行时阶段图仍是两套来源。  
   `autopilot-phase0/SKILL.md` 在描述“创建哪些任务”，`_phase_graph.py` 在描述“如何推导阶段图”，`mode-routing-table.md` 又在描述“模式声明表”。这不是单一真相源。

2. `lite/minimal` 的 Phase 5 任务来源仍不合理。  
   `mode-routing-table.md` 和 `phase5-implementation.md` 仍让 Phase 5 从 `phase-1-requirements.json + Steering Documents + research-findings.md` 重新拆任务，而不是严格只从 `requirement-packet.json` 出发。

3. 真实黑盒 E2E 仍缺位。  
   当前的 `test_lite_mode.sh`、`test_minimal_mode.sh`、`test_mode_lock.sh` 更像阶段门禁测试，不是“Phase 0 -> 归档”全链路仿真。

4. 模式相关语义仍有分叉风险。  
   Server/GUI 还有自己的 phase 展示逻辑，Phase 0 又把自己算在显示序列里，运行时 graph 却只管理 1..7。这种“执行序列”和“展示序列”没有明确分层。

### 2.4 最佳修复方案

1. 把模式与阶段图下沉为单一 machine-readable manifest。  
   manifest 至少定义:
   - `execution_sequence`
   - `display_sequence`
   - `predecessor`
   - `allowed_transitions`
   - `per_mode_required_artifacts`
   - `per_mode_skipped_phases`

2. 让 `Phase 0`、`_phase_graph.py`、`check-predecessor-checkpoint.sh`、`scan-checkpoints-on-start.sh`、`recovery-decision.sh`、Server phase labels、GUI phase labels 全部消费同一份定义。

3. 新增 3 条真实模式级 E2E:
   - `full: 0 -> 1 -> 2 -> 3 -> 4 -> 5 -> 6 -> 7`
   - `lite: 0 -> 1 -> 5 -> 6 -> 7`
   - `minimal: 0 -> 1 -> 5 -> 7`

4. 每条 E2E 都必须覆盖:
   - 首次执行
   - compact 后恢复
   - crash recovery
   - partial rollback 后恢复
   - archive 收口

## 3. 问题 2: 主编排 agent 信息必要性、非必要信息、冗余与主窗口最佳编排

### 3.1 结论

当前主编排线程和主窗口仍承载了太多非必要信息。  
主编排真正应该持有的是“控制面摘要”，不是“正文、工具和 raw 可观测流”。

### 3.2 主编排真正必要的信息

- `requirement-packet.json` 及其 `hash`
- `mode`
- `change_name`
- `session_id`
- `anchor_sha`
- `gate_frontier`
- `next_action`
- `active_tasks`
- `phase_results`
- `review_status`
- `fixup_status`
- `archive_status`
- `recovery_confidence`

### 3.3 主编排不应该直接吞入的信息

- `research-findings.md` 正文
- `web-research-findings.md` 正文
- `requirements-analysis.md` 正文
- transcript 正文
- tool trace
- raw hooks/statusline
- Phase 5 任务的全文细节

### 3.4 已发现的问题

1. GUI 主窗口不是纯控制面。  
   `gui/src/App.tsx` 的中心区同时挂了 `OrchestrationPanel + ParallelKanban + LogWorkbench`。  
   `LogWorkbench` 里默认 tab 还是 `events`，而 `raw` 还直接打开 `RawInspectorPanel`。

2. 主窗口混入观测与调试数据。  
   `ParallelKanban` 展开卡片直接显示 `tool_use` 细节。  
   `RawInspectorPanel` 甚至绕过 store 自己轮询 `/api/raw-tail`。

3. Store 聚合也不是纯控制面聚合。  
   `events` 大数组被主窗口多个面板共用，`transcriptEvents`、`toolEvents`、`modelRoutingHistory`、`parallelPlan`、`orchestration` 都混在同一个全局大状态里。

### 3.5 主窗口最佳实践

1. 主线程只消费结构化控制状态，不直接消费正文工件。
2. 主窗口默认只显示:
   - 当前阶段
   - 当前 gate
   - 当前 routing decision
   - requirement packet 摘要
   - active tasks
   - review/fixup/archive readiness
   - recovery 来源与下一步动作
3. transcript/tool/raw 全部进入独立的 observability drawer 或 secondary route。
4. 子 Agent 直接读取正文，主线程只读取子 Agent 的结构化 envelope。

## 4. 问题 3: 上下文压缩流程是否完全受控、是否保留足够上下文

### 4.1 结论

compact 保存与恢复已经进入结构化阶段，但还没有完全受控。  
当前的 structured snapshot 更像“恢复控制壳子”，而不是“恢复足够语义上下文”。

### 4.2 当前做对的部分

- `save-state-before-compact.sh` 会生成 `state-snapshot.json`
- `reinject-state-after-compact.sh` 会优先恢复结构化状态
- `recovery-decision.sh` 会把 snapshot hash 纳入恢复置信度判定
- `state-snapshot.json` 具备 `schema_version + snapshot_hash` 校验

### 4.3 关键问题

1. 没有最终 checkpoint 时直接不写 snapshot。  
   `save-state-before-compact.sh` 在 `phases` 为空时直接退出。这意味着只有 progress/interim、尚无 final checkpoint 的时候，compact 可能完全丢掉主恢复控制态。

2. `requirement_packet_hash` 取值错误。  
   现在拿的是 `phase-1-requirements.json` 文件内容 hash，而不是 `requirement-packet.json` 自身的 hash。

3. structured snapshot 没保存足够的后续控制态。  
   `review_status / fixup_status / archive_status` 在 snapshot 里没有真正写实值。

4. reinject 没恢复语义连续性。  
   `save-phase-context.sh` 已经写下了 `summary / decisions / constraints / next_phase_context`，但 `reinject-state-after-compact.sh` 的 structured path 并没有把这些关键语义带回来。

5. structured reinject 信息密度失衡。  
   一边没有恢复关键决策/约束，一边又会把 `phase5_task_details` 全量打印到恢复上下文里，容易造成恢复后上下文再次膨胀。

6. 类型与真实 schema 不一致。  
   `runtime/server/src/types.ts` 中的 `StateSnapshot` 与脚本实际写出的字段并不一致，后续维护容易继续分叉。

### 4.4 应该保存哪些必要上下文

建议把恢复控制态分成两层:

1. Primary control state
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

2. Bounded semantic state
   - 最近 2~3 个 phase 的 `summary`
   - 最近 2~3 个 phase 的 `decisions`
   - 最近 2~3 个 phase 的 `constraints`
   - 最近 2~3 个 phase 的 `next_phase_context`
   - 当前被阻断原因
   - 最近一次 override/retry/autocontinue 决策

### 4.5 恢复后是否留有足够信息给主编排 agent

当前答案是: 控制面信息“基本够继续执行”，语义信息“不够解释为什么这样继续”。  
主编排知道“下一步执行什么”，但不知道“为什么是这一步、有哪些已决议约束、哪些风险不能再忘记”。

### 4.6 最佳修复方案

1. `save-state-before-compact.sh` 在 progress-only/interim-only 场景也必须生成最小 snapshot。
2. `requirement_packet_hash` 统一改为从 `requirement-packet.json` 读取。
3. `review_status/fixup_status/archive_status` 写入真实结构化状态。
4. `reinject-state-after-compact.sh` 读取 `phase-*-context.json` 的 bounded 摘要，而不是只靠 markdown fallback。
5. 给 `phase5_task_details` 加硬上限，只保留未完成任务和最近变更任务。
6. 统一 `StateSnapshot` 脚本与 TS 类型。

## 5. 问题 4: 崩溃恢复整体流程是否符合设计预期

### 5.1 结论

崩溃恢复的总体设计方向是对的: `lock file + anchor + checkpoint + snapshot hash` 这一层已经成立。  
但 partial rollback、stale snapshot、auto-continue 判定、语义回放这几处仍有真实缺口。

### 5.2 已成立的部分

- `recovery-decision.sh` 是纯只读扫描器
- `scan-checkpoints-on-start.sh` 能做 mode-aware 扫描
- `rebuild-anchor.sh` 有原子写和失败保护
- `check-predecessor-checkpoint.sh` 可在恢复后继续提供 L2 阶段阻断

### 5.3 高风险问题

1. partial rollback 不会失效主 snapshot。  
   `clean-phase-artifacts.sh` 只有 `FROM_PHASE <= 1` 才删除 `state-snapshot.json` 和 `autopilot-state.md`。  
   这意味着从 Phase 3/5 回滚后，旧的 `next_action/phase_results/gate_frontier` 仍可能误导后续恢复。

2. auto-continue 逻辑过度保守且与协议分叉。  
   现在任何 fixup commit 都会把 `git_risk_level` 拉低，而 auto-continue 又要求 `none`，这导致正常的 fixup 工作流被当成恢复风险。

3. 恢复链路对 phase-context 的结构化消费不足。  
   skill 文档要求主线程“再去读 phase-context-snapshots”，这说明恢复语义仍依赖 prompt 纪律，而不是运行时强闭环。

4. `phase-*-context.json` 的 `content_hash` 写了但没有被恢复链路真正校验。

### 5.4 最佳修复方案

1. 任何 `clean-phase-artifacts.sh FROM_PHASE >= 1` 都必须同步删除或重建 snapshot。
2. 恢复前必须校验 snapshot 与真实工件是否一致，不一致直接降级为低置信恢复。
3. 把 `phase-context.json` 纳入 structured reinject 主路径。
4. `auto_continue_eligible` 改为“无高风险 git 状态”，而不是“完全无 fixup commit”。
5. `state-snapshot.json`、`autopilot-state.md`、`phase-context.json` 统一改成 tmp + rename 原子写。

## 6. 问题 5: 需求评审环节、三路 agent、需求理解深化、需求来源稳定性、提示词工程化

### 6.1 结论

三路调研不是天然必要，应该由需求成熟度驱动。  
当前最优方案不是“永远多派几个 agent”，而是“把需求来源收敛成稳定 packet，并让调研策略可证明、可裁剪、可追溯”。

### 6.2 现状判断

- `parallel-phase1.md` 和相关文档已经尝试引入 `requirement_maturity`
- clear/partial/ambiguous 三级成熟度的方向是正确的
- 主线程禁止直接读研究正文的设计也是正确的

### 6.3 主要问题

1. 需求来源还没有完全收束成单一事实源。  
   现在 Phase 1 之后仍有大量后续环节重新读取 `phase-1-requirements.json`、`project-context.md`、`research-findings.md` 等散落材料。

2. 三路调研的必要性没有完全从运行时体现。  
   设计上已经有“成熟度分层”，但缺少由运行时 manifest 和 gate 驱动的确定性调研策略。

3. 需求理解的“深度”还过度依赖 prompt 质量，而不是结构化强输出。  
   如果 AI 输出了看似完整但证据不足的分析，当前系统对“来源是否稳定、假设是否显式、开放问题是否真正闭合”的强校验还不够。

### 6.4 最佳实践

1. 需求来源稳定性
   - 只允许三类输入进入 Phase 1 主决策:
     - `RAW_REQUIREMENT`
     - Steering 文档
     - 子调研 agent 的结构化 envelope
   - 最终统一收束到 `requirement-packet.json`

2. 需求理解深化
   - packet 强制包含:
     - `goal`
     - `scope`
     - `non_goals`
     - `acceptance_criteria`
     - `decisions`
     - `assumptions`
     - `risks`
     - `open_questions_closed`
     - `source_evidence`
     - `hash`

3. 三路调研策略
   - `clear`: 只做 Auto-Scan
   - `partial`: Auto-Scan + 定向技术调研
   - `ambiguous`: Auto-Scan + 技术调研 + 联网调研

4. 提示词工程化
   - 明确要求输出 decision card
   - 明确要求引用证据来源
   - 明确区分事实、推断、风险、待确认项
   - 明确禁止把未验证猜测写成事实

## 7. 问题 6: OpenSpec 与 OpenSpec FF 流程是否存在不合理意外、如何杜绝异常

### 7.1 结论

OpenSpec/FF 的主要风险不是“完全没做”，而是“Phase 2/3/7 的契约已经分叉”。  
这类分叉现在还能靠人和测试兜底，但继续演化会越来越不稳定。

### 7.2 已发现的契约分叉

1. Phase 2/3 运行时 validator 要求比 dispatch 文档更强。  
   `_post_task_validator.py` 要求:
   - Phase 2 必须有 `alternatives`
   - Phase 3 必须有 `plan` 和 `test_strategy`
   
   但 `autopilot-dispatch/SKILL.md` 示例只要求 `status/summary/artifacts`。

2. Phase 7 协议字段不一致。  
   `protocol.md` 要求 `archive_path` 和 `change_name`，  
   但 `autopilot-phase7/SKILL.md`、架构文档、测试又使用 `archived_change`。

3. Phase 6 的并行协议也有分叉。  
   `mode-routing-table.md` 和 `parallel-phase6.md` 说三路都后台，  
   `autopilot-dispatch/SKILL.md` 却把路径 A 写成前台。

### 7.3 风险

- 子 Agent 按 prompt 返回的 envelope 可能符合文档，却不符合运行时 validator
- 流程迁移后容易在文档、validator、测试之间继续分叉
- OpenSpec 产物与后续 gate 校验之间缺乏单一 schema

### 7.4 最佳修复方案

1. 引入 per-phase JSON schema 真相源。  
   由 schema 统一生成:
   - validator 规则
   - dispatch 示例
   - protocol 文档
   - 黑盒测试 fixture

2. 把 Phase 7 的 archive-readiness 从 prompt 协议下沉成确定性执行脚本。

3. 新增 OpenSpec/FF E2E:
   - `openspec new change`
   - FF 生成 proposal/specs/design/tasks
   - Phase 2 -> 3 -> 5 契约连续性
   - 异常中断 + 恢复

## 8. 问题 7: 测试用例设计是否贴合产品需求、如何保证合理性/覆盖性/独立性、避免 Hack Reward

### 8.1 结论

当前测试体系“广度很好，绿态可信”，但“与产品真实承诺的耦合度还不够均匀”。  
尤其是某些治理类测试仍在验证文档文本、手工 JSON 或废弃脚本，而不是生产运行时入口。

### 8.2 已做得好的部分

- 有大量 hook 黑盒测试
- 有 state snapshot hash 测试
- 有 server robustness 测试
- 有 TDD 阶段隔离测试
- 有 fixup 和 archive git 模拟测试

### 8.3 主要问题

1. 部分测试仍是 grep 文档。  
   例如 `test_phase1_context_isolation.sh`、`test_tdd_gate_intent.sh`、`test_fixup_commit.sh` 中相当一部分断言是在校验 `SKILL.md` 或参考文档文本。

2. 部分测试命中废弃脚本。  
   `test_background_agent_bypass.sh` 明确还在兼容窗口期测试 `anti-rationalization-check.sh`、`code-constraint-check.sh`、`validate-json-envelope.sh` 等旧脚本，而生产 `PostToolUse(Task)` 实际走的是 `post-task-validator.sh`。

3. 测试用例和产品需求的 traceability 还没形成系统化矩阵。  
   现在更多是“有很多测试”，而不是“每条产品承诺都有唯一主测试证明”。

4. 仅有 md 文档不够，必须有真实可执行 test case。  
   对于测试阶段的测试用例，答案是: 需要评审，而且不能只停留在 md 文档，必须有真正的可运行样例和门禁断言。

### 8.4 如何避免 Hack Reward

1. 测试要尽量命中生产入口，而不是内部 helper 或文档文本。
2. 要求黑盒断言用户可见结果和产物，而不是断言 prompt 里出现了某句文案。
3. 把 deprecated/compat 测试单独拆到 legacy 套件，不计入主覆盖口径。
4. 建立需求 -> 产物 -> gate -> 测试的 traceability matrix。
5. 对 TDD、report、archive 等高价值链路增加集成夹具，而不是手工 JSON 模拟。

## 9. 问题 8: 代码实现阶段是否严格遵守 rules/CLAUDE.md/子 agent/优先级/稳定性要求

### 9.1 结论

当前能证明“谁被派发了、写了哪些文件边界、走了哪些记录”，还不能严格证明“必须使用的 agent 一定被使用、禁止使用的 agent 一定被阻断、优先级冲突一定按预期决策”。

### 9.2 已有能力

- `rules-scanner.sh` 能扫描 `.claude/agents/` 和规则来源
- `auto-emit-agent-dispatch.sh` 会记录:
  - `selection_reason`
  - `resolved_priority`
  - `owned_artifacts`
  - `agent_id`
  - `session_id`
- `_post_task_validator.py` 能校验 artifact boundary

### 9.3 关键缺口

1. `auto-emit-agent-dispatch.sh` 明确是 observational hook。  
   它自己声明 `never denies`，不会在 PreToolUse 阶段做 fail-closed。

2. `_post_task_validator.py` 的 priority/forbidden 校验是空实现。  
   当前分支里只是 `pass`。

3. rules cache 协议和运行时并未真正闭环。  
   文档写了 `.rules-scanner-cache.json` 和 `.rules-scan-mtime`，但运行时主要是“读取缓存”，没有完整的“生成缓存 -> 失效重扫 -> 强校验”闭环。

4. 如何判断是否用了项目要求的子 agent?  
   现在最可靠的是看 `logs/agent-dispatch-record.json`，但它只能证明“记录了谁被派发”，不能证明“required/forbidden 已被强制执行”。

### 9.4 多个 agent 优先级的最佳实践

建议把优先级固化成明确算法:

1. `required_for_phase`
2. `forbidden_phase` 检查
3. `owned_artifacts/domain_match`
4. `priority`
5. `default_agent`

如果项目同时存在:
- repo 级 `.claude/agents`
- plugin 级 agent 定义
- 全局默认 agent

则必须有清晰 precedence:

1. 项目本地 phase-required 规则
2. 项目本地 forbidden 规则
3. 项目本地域匹配
4. 项目本地 priority
5. 插件默认
6. 全局默认

### 9.5 产出稳定性与可确定性

1. Agent resolver 需要输出结构化决策证据。
2. 决策必须写入 dispatch record。
3. 违反 required/forbidden/owned boundary 时必须 deny，而不是仅审计。
4. 若发生优先级平票，必须使用稳定 tie-breaker，不允许 AI 自由发挥。

## 10. 问题 9: Phase 5/6 TDD 代码生成，如何保证独立性、review 质量、RED/GREEN/REFACTOR 是否完整测试

### 10.1 结论

TDD 的“文件隔离”已经落地一部分，但“逐 task 证据审计”和“失败后自动回滚”还没有真正接进主流程。  
因此当前只能说“有 TDD 纪律骨架”，不能说“完整 TDD 闭环已经被运行时强证明”。

### 10.2 已落地的部分

- `.tdd-stage` 驱动的 `Write/Edit` 隔离已经存在
- RED 只能写测试、GREEN 不能改测试、REFACTOR 会记录候选回滚文件
- `test_tdd_isolation.sh`、`test_tdd_rollback.sh` 都通过

### 10.3 未闭环的部分

1. 运行时只看 `tdd_metrics` 汇总，不看逐 task 证据。  
   `_post_task_validator.py` 当前校验的是:
   - `red_violations === 0`
   - `total_cycles >= 1`
   
   这不是逐 task 的证据闭环。

2. `test_tdd_gate_intent.sh` 主要还是文档和手工 JSON 审计，不是跑真实 hook/gate。

3. `tdd-refactor-rollback.sh` 虽然存在并且单测通过，但我没有看到主流程在 REFACTOR 失败时自动调用它。

4. Phase 6 测试报告链路没有把 `report_url / allure_results_dir / suite_results` 真正变成可视化控制面。

### 10.4 最佳修复方案

1. 新增 `audit-tdd-evidence.sh` 或等价脚本。  
   扫描 `phase5-tasks/task-*.json`，强制检查:
   - `test_intent`
   - `failing_signal.assertion_message`
   - `red.verified`
   - `green.verified`
   - `refactor.verified`

2. Phase 5 -> 6 门禁必须消费这个逐 task 审计结果，而不是只信汇总 `tdd_metrics`。

3. REFACTOR 失败路径必须真实接入 `tdd-refactor-rollback.sh`。

4. 代码 review 质量要和实现 agent 解耦。  
   不建议让同一实现 agent 自证“已符合预期”，至少要有独立 review 路径和 blocking finding 模型。

## 11. 问题 10: 合并多个 fixup 提交是否符合预期、是否全部合并且无遗漏

### 11.1 结论

目前无法从运行时强证明“本次迭代的所有 fixup 都被完整合并且无遗漏”。  
现状更像“协议完整 + 局部 git 模拟存在 + 主流程执行器缺失”。

### 11.2 现状判断

- `autopilot-phase7/SKILL.md` 对 fixup completeness、anchor rebuild、autosquash 的协议写得很完整
- `test_phase7_archive.sh` 用 git 仿真证明了“理想流程应该怎样”
- `test_fixup_commit.sh` 证明了 `git add -A` 和 lockfile exclusion 的局部正确性

### 11.3 缺口

1. 没有独立的 runtime fixup 审计执行器。
2. 没有独立的 runtime autosquash 执行器。
3. `archive-readiness.json` 的构造更多仍在 skill 协议层，不是稳定脚本产物。

### 11.4 最佳修复方案

1. 新增 `build-archive-readiness.sh`:
   - 输入 `anchor_sha..HEAD`
   - 统计 checkpoint_count
   - 统计 fixup_count
   - 检查 worktree/anchor/review/zero-skip
   - 输出唯一 `archive-readiness.json`

2. 新增 `run-autosquash.sh`:
   - 仅在 readiness = ready 时执行
   - 失败即 fail-closed

3. Phase 7 不再靠 prompt 隐式推理 fixup 状态，只读取脚本产物。

## 12. 问题 11: 每个阶段门禁的意义是什么？上下文恢复的意义是什么？

### 12.1 阶段门禁的意义

阶段门禁不是“多此一举的形式主义”，它是把 AI 的软纪律变成硬边界的核心机制。

它的意义在于:

1. 防止跳阶段
2. 防止空产出继续流入下游
3. 把“需求理解、设计、测试、实现、归档”拆成可证明边界
4. 把“AI 说自己做了”变成“产物和状态真的存在”
5. 在上下文漂移时仍能用 checkpoint 重新收敛

### 12.2 上下文恢复的意义

上下文恢复的意义不只是“省 token”，而是:

1. 在 compact 后保留控制连续性
2. 在 crash 后恢复到正确阶段
3. 防止主线程重复阅读大量正文
4. 保留关键决策和约束，减少 AI 失忆和自由发挥

### 12.3 当前问题

当前门禁理念是对的，恢复理念也是对的。  
问题不在“有没有这些概念”，而在“恢复与门禁之间的结构化协议还不够统一”。

## 13. 问题 12: 整体编排流程和设计理念是否合理，是否符合社区 harness 理念，能否规避 AI 缺点、放大优点，产品力如何，是否过度设计

### 13.1 结论

总体设计理念是合理的，也符合社区对 harness 的主流理解:  
用 artifact、阶段、hook、checkpoint、review、recovery 去约束 AI，而不是把 AI 当作一次性自由生成器。

### 13.2 与 harness 理念的契合点

1. 明确分阶段
2. 主线程与子 Agent 分工
3. 用 checkpoint 和 gate 管理推进
4. 用 hook 管理运行时约束
5. 用 GUI 做观察与编排反馈
6. 用恢复链路对抗上下文丢失

### 13.3 对 AI 已知缺点的规避程度

当前规避得比较好的:

- 跳步骤
- 空 envelope
- 文件越界
- 基础阶段门禁
- 部分上下文丢失

当前规避得还不够好的:

- 主线程读到过多无关观测内容
- rules/priority 仍可绕过
- Phase 1 正文隔离不是 Read 级硬限制
- TDD/fixup/archive 仍有较大 prompt 依赖
- compact/recovery 语义恢复不够完整

### 13.4 对 AI 优点的利用程度

当前放大得不错的优点:

- 并行调研
- artifact 化输出
- hook 反馈循环
- 可观测性
- 可恢复性

### 13.5 资深产品经理视角下的产品力判断

优点:

1. 价值主张清晰: 让 Claude 从“写点代码”升级到“带护栏的端到端交付”
2. 用户痛点明确: AI 不稳定、上下文丢失、规则不遵守、测试偷懒
3. 差异化明显: 不是单纯 prompt 包装，而是带 runtime/hook/recovery/GUI 的工程系统

短板:

1. 产品承诺和运行时刚性之间还有差距
2. GUI 控制面边界还不够干净
3. 报告/Allure/归档 readiness 还没有形成用户可见闭环
4. 某些复杂设计已经超前于当前落地，导致“看起来很强，实际不够确定”

### 13.6 是否过度设计

我的判断是:

- 核心理念不过度设计
- 局部实现存在过度分层和重复表达

过度设计主要体现在:

1. 同一协议同时存在于多份文档、脚本和测试中
2. 一些 UI 状态已经定义，但没有真实数据源
3. Phase 6.5、archive-readiness、agent priority 等能力已经设计得很完整，但运行时执行器仍不够硬

### 13.7 商业化价值判断

结论是“有价值，但还不能直接按商业级可靠性对外承诺”。

要达到可收费交付的门槛，至少还需要:

1. 单一真相源
2. fail-closed 治理
3. compact/recovery 语义闭环
4. 测试从文档验证升级为生产路径验证
5. GUI 真正成为控制面，而不是控制 + 调试混合面

## 14. 问题 13: 报告与修复执行文档生成

本轮已生成两份文档:

1. 本报告  
   `plugins/spec-autopilot/docs/reports/v5.8/spec-autopilot-holistic-architecture-review-2026-03-30.md`

2. 给 Claude 的全量修复执行提示词  
   `plugins/spec-autopilot/docs/roadmap/spec-autopilot-remediation-execution-prompt-2026-03-30.md`

后者不是概念建议，而是按波次拆解的可执行修复提示词，覆盖:

- 控制面单一真相源
- requirement packet 唯一事实源
- compact/recovery/clean 语义统一
- rules/priority/read hook fail-closed
- OpenSpec/FF/TDD/fixup/archive 执行器补齐
- GUI 主窗口边界、URL、边框、Allure/report 卡片修复
- 测试体系去 grep 化、去 legacy 主路径依赖

## 15. 已确认的 5 个 BUG

### 15.1 BUG 1: 启动卡片中的 GUI URL 显示 `unavailable`

结论: 成立，而且根因偏架构，不是单个 UI 字段拼错。

根因:

1. `start-gui-server.sh` 的默认 `start` 模式在启动失败时仍 `exit 0`
2. 脚本没有输出结构化 `{status,url,httpPort,wsPort,reason}`
3. GUI/server 两端都存在端口硬编码:
   - HTTP `9527`
   - WS `8765`
4. Phase 0 启动卡片更像 AI 自己渲染，而不是消费脚本的确定性返回值

最佳修复:

1. `start-gui-server.sh` 返回结构化 JSON
2. 启动失败保留非零退出码或显式 `status=failed`
3. GUI/WS 端口只保留单一真相源
4. 启动卡片只解析脚本 JSON，不允许 AI 自由猜测 URL

### 15.2 BUG 2: 多个阶段模型展示卡片右边框没有封闭，像 C 字型

结论: 成立，而且是实现问题，不是终端字体偶发问题。

根因:

- `ParallelKanban.tsx` 的 agent/task 卡片只用了 `border-l-4`，没有完整 `border`

最佳修复:

- 卡片基底改为 `border border-border`
- 左侧强调色另用 `border-l-4` 或 `ring` 实现

### 15.3 BUG 3: 主窗口 agent 仅做编排控制，是否有不受控内容进入主窗口

结论: 有，而且当前问题明确成立。

表现:

- `App.tsx` 主中心区固定挂 `LogWorkbench`
- `LogWorkbench` 默认展示 `events`
- `ParallelKanban` 展开卡片可看 `tool_use`
- `RawInspectorPanel` 还能直接看 raw hooks/statusline

这已经不是“纯编排控制面”，而是“编排 + 观测 + 调试”混合面。

最佳修复:

- 主窗口默认只保留 timeline + orchestration + kanban + gate
- `LogWorkbench` 和 `RawInspectorPanel` 下沉到 debug drawer / secondary route

### 15.4 BUG 4: 测试阶段的测试用例是否需要评审？是否需要真实 case，而不仅是 md 文档

结论: 需要，而且必须有真实可执行 case，不能只靠 md 文档。

原因:

- 当前相当一部分治理测试仍在 grep 文档或手工 JSON
- 这会造成“协议写得很好，所以测试通过”的假象

最佳修复:

1. 每条产品级承诺至少有一条生产入口黑盒测试
2. 用例设计需要独立评审
3. 测试文档只作为说明，不作为主证明

### 15.5 BUG 5: 生成测试报告的阶段是否在主 agent 窗口打印卡片，并在卡片中开启 Allure 全量测试结果访问链接

结论: 当前没有闭环实现。

现状:

- runtime validator 只强制 `pass_rate/report_path/report_format`
- `auto-emit-agent-complete.sh` 只把 `artifacts` 提升成 `output_files`
- GUI/store 没有 report 专用状态
- 当前不会形成“测试报告卡片”，也不会稳定暴露可点击 Allure 链接

最佳修复:

1. 给 store 增加 report 专用状态:
   - `report_path`
   - `report_format`
   - `report_url`
   - `allure_results_dir`
   - `suite_results`
2. runtime/server -> WS -> store 形成完整透传链
3. `ParallelKanban` 或独立 `ReportCard` 渲染测试报告卡片和 Allure 链接

## 16. 最终判断与推荐修复顺序

### 16.1 最终判断

当前版本不是“架构方向错误”，而是“架构意图与运行时刚性之间仍有明显落差”。  
如果继续只补 prompt 和文档，不补 runtime 执行器、schema、fail-closed hook 和黑盒测试，这个插件会越来越难维护。

### 16.2 推荐修复顺序

1. 单一真相源: mode/phase/envelope/model routing/schema
2. requirement packet 唯一事实源
3. compact/recovery/clean 语义统一
4. rules/priority/read hook fail-closed
5. Phase 7 archive-readiness / autosquash 执行器
6. TDD per-task 审计与 REFACTOR 自动回滚接入
7. GUI 控制面边界、报告卡片、Allure 链接、URL/边框 bug
8. 测试体系 production-path 化与 legacy 套件拆分

---

## 附: 本轮核心判断

1. 当前仓库状态是“能跑、能测、能恢复一部分”，不是“已经完全闭环”。
2. 现在最值得做的不是再加新阶段，而是把现有阶段的控制协议彻底下沉成运行时事实。
3. 一旦把单一真相源、fail-closed 治理、恢复闭环和 GUI 边界收口，这个插件的产品力会明显提升一个台阶。
