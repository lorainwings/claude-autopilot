# Claude 全量修复执行提示词

你现在在仓库根目录工作:

- `/Users/lorain/Coding/Huihao/claude-autopilot`

目标插件:

- `plugins/spec-autopilot`

你的任务不是做局部修补，而是对 `spec-autopilot` 做一次完整的、可交付的、全量修复。不要按优先级切分，不要只做其中一部分，不要跳过任何一个问题。你必须把下列所有架构问题、契约漂移、测试缺口和显式 BUG 一次性收敛掉，并补齐对应测试与文档。

## 0. 强约束

- 严格遵守仓库根 `CLAUDE.md` 与 `plugins/spec-autopilot/CLAUDE.md`
- 不允许只改文档不改运行时
- 不允许只改运行时不补测试
- 不允许只补测试不修控制面
- 不允许保留多处手写真相源
- 不允许引入新的架构分叉
- 修复后必须保证:
  - 控制面单一真相源
  - 主窗口只保留编排控制信息
  - 关键规则 fail-close
  - 所有关键路径有黑盒测试

## 1. 你必须解决的全量问题

### 1.1 三种模式 `full/lite/minimal`

要求:

- 补齐 `full` 模式专用整链路仿真测试
- 统一三种模式的 phase graph、gate、recovery、GUI 展示、测试矩阵
- 保证 `full/lite/minimal` 的阶段流转来自同一个真相源，而不是散落在:
  - `_phase_graph.py`
  - `check-predecessor-checkpoint.sh`
  - `recovery-decision.sh`
  - GUI store
  - tests

必须完成:

- 新增至少一条 `full` 模式主线 E2E
- 新增至少一条 `full` 模式恢复 E2E
- 确保 `lite/minimal` 跳过阶段逻辑继续通过

### 1.2 主编排 agent 的信息边界与主窗口编排方式

目标:

- 主窗口只显示编排控制面
- 诊断与执行明细必须下沉到二级面板

必要信息:

- 当前目标
- 当前 phase
- gate frontier / block reason
- 活跃 agent 数量与阶段分布
- 模型路由摘要
- compact 风险
- 恢复来源
- 报告摘要
- archive readiness

禁止继续出现在主窗口的信息:

- tool_use 明细
- output_files 明细
- raw hook/statusline/transcript
- 低层诊断噪音
- 非必要 agent 内部细节

必须修改:

- `plugins/spec-autopilot/gui/src/App.tsx`
- `plugins/spec-autopilot/gui/src/components/ParallelKanban.tsx`
- `plugins/spec-autopilot/gui/src/components/OrchestrationPanel.tsx`
- 任何与主窗口编排边界相关的 store / selector / event 聚合逻辑

### 1.3 compact / context compression / state snapshot / recovery

必须建立统一控制工件:

- `state-snapshot.json` 必须成为唯一结构化控制态

必须修复:

1. 任何改写 `state-snapshot.json` 的脚本都必须重算 `snapshot_hash`
2. `emit-report-ready-event.sh` 和 `emit-tdd-audit-event.sh` 不得再直接裸改 snapshot
3. structured recovery 必须补回 `phase-context-snapshots` 摘要
4. `requirement_packet_hash` 必须来自 `context/requirement-packet.json`
5. `runtime/server/src/types.ts` 必须与真实 snapshot schema 完全一致
6. 不允许保留“占位字段但没有真实语义”的控制字段

必须修改:

- `plugins/spec-autopilot/runtime/scripts/save-state-before-compact.sh`
- `plugins/spec-autopilot/runtime/scripts/reinject-state-after-compact.sh`
- `plugins/spec-autopilot/runtime/scripts/emit-report-ready-event.sh`
- `plugins/spec-autopilot/runtime/scripts/emit-tdd-audit-event.sh`
- `plugins/spec-autopilot/runtime/server/src/types.ts`
- 任何读取或广播 snapshot meta 的 server / GUI 逻辑

### 1.4 崩溃恢复整体流程

必须保证:

- snapshot valid 时优先走 snapshot 恢复
- snapshot hash mismatch 时必须显式暴露 `snapshot_hash_mismatch`
- checkpoint/progress fallback 必须保留完整恢复原因
- auto-continue 规则与产品设计一致

修复目标:

- 不要把 hash mismatch 假装成 `fresh`
- `auto_continue_eligible` 不要只允许 `git_risk_level == none`
- 明确高/中/低风险下的恢复策略
- 恢复后主编排 agent 必须拿到足够上下文继续执行

必须修改:

- `plugins/spec-autopilot/runtime/scripts/recovery-decision.sh`
- `plugins/spec-autopilot/runtime/scripts/reinject-state-after-compact.sh`
- 所有恢复相关 GUI meta 展示逻辑

### 1.5 需求评审环节、三路 agent、需求来源稳定性、提示词工程化

必须达成:

- `requirement-packet.json` 成为唯一事实源
- 三路调研不是默认强制动作，而是成熟度驱动:
  - `clear` -> Auto-Scan
  - `partial` -> Auto-Scan + 技术调研
  - `ambiguous` -> Auto-Scan + 技术调研 + 联网搜索

你必须收敛:

- 主线程只消费结构化 envelope，不读取研究正文
- requirement packet 强制包含:
  - facts
  - decisions
  - assumptions
  - risks
  - acceptance criteria
  - open questions closed
  - source evidence
  - hash
- decision card 必须绑定证据来源

必须修改:

- `plugins/spec-autopilot/skills/autopilot/SKILL.md`
- `plugins/spec-autopilot/skills/autopilot/references/parallel-phase1.md`
- `plugins/spec-autopilot/skills/autopilot/references/phase1-requirements.md`
- 若需要，补充脚本或 schema 来固化 requirement packet

### 1.6 OpenSpec 与 OpenSpec FF 流程

必须收敛:

- Phase 2 / Phase 3 的 artifact contract
- validator / dispatch prompt / docs / tests 的命名一致性

当前必须解决的问题:

- `validate-openspec-artifacts.sh` 不能再查找过时文件名
- OpenSpec / FF 必须来自单一 schema
- 下游 phase 只能引用 schema 认可的 artifacts

必须修改:

- `plugins/spec-autopilot/runtime/scripts/validate-openspec-artifacts.sh`
- 相关 skills / references / tests

### 1.7 测试用例设计、合理性、覆盖性、独立性、避免 Hack Reward

必须重构测试策略:

- 关键路径一律黑盒测试
- docs consistency 只能是附加层，不能冒充主质量证明
- 废弃兼容脚本不再作为主回归入口
- GUI/server 集成测试必须随机端口
- 测试阶段不能只停留在 md 文档，必须有真实可执行 case

必须补齐:

- 产品需求 -> phase 输入 -> gate -> artifact -> report 的 traceability
- `full` 模式主线测试
- OpenSpec / FF / recovery / report / fixup / TDD 关键路径黑盒测试

必须修改:

- `plugins/spec-autopilot/tests/test_autopilot_server_aggregation.sh`
- `plugins/spec-autopilot/tests/test_server_robustness.sh`
- `plugins/spec-autopilot/tests/test_fixup_commit.sh`
- `plugins/spec-autopilot/tests/test_phase6_suite_results.sh`
- 所有仍围绕 deprecated 脚本或 grep 文档的关键测试

### 1.8 rules / `CLAUDE.md` / 子 agent / 优先级 / 稳定性 / 确定性

必须从“可观测”升级为“可强制”。

你必须实现:

- 单一 `agent-policy-resolver`
- 明确优先级:
  - project `.claude/agents`
  - plugin policy
  - builtin fallback
- dispatch 前校验
- PostToolUse 后校验
- 对以下情况 fail-close:
  - required agent 未使用
  - forbidden agent 被使用
  - agent 与 phase 不匹配
  - policy 缺失或冲突未消解

必须修改:

- `plugins/spec-autopilot/runtime/scripts/rules-scanner.sh`
- `plugins/spec-autopilot/runtime/scripts/auto-emit-agent-dispatch.sh`
- `plugins/spec-autopilot/runtime/scripts/_post_task_validator.py`
- 必要时新增 resolver 脚本或模块

### 1.9 Phase 5/6 的 TDD 闭环

必须形成完整 RED / GREEN / REFACTOR 生产闭环。

你必须做到:

- RED 必须有真实 failing signal
- GREEN 必须证明同一批测试转绿
- REFACTOR 必须校验结果未退化
- REFACTOR 失败必须自动回滚
- TDD 审计必须真实接入 phase 流程，而不是只存在脚本

必须修改:

- `plugins/spec-autopilot/runtime/scripts/unified-write-edit-check.sh`
- `plugins/spec-autopilot/runtime/scripts/tdd-refactor-rollback.sh`
- `plugins/spec-autopilot/runtime/scripts/emit-tdd-audit-event.sh`
- hooks 注册
- Phase 5 / Phase 6 相关 validator
- 新增 RED->GREEN->REFACTOR->rollback 端到端测试

### 1.10 fixup 合并完整性

必须保证:

- 不是“fixup 数量够了”就算完成
- 必须逐 checkpoint 一一映射 fixup
- manifest 缺失绝不允许放行

你必须实现:

- checkpoint ledger
- expected fixup subject
- anchor range
- manifest required
- per-checkpoint squash verdict

必须修改:

- `plugins/spec-autopilot/runtime/scripts/generate-fixup-manifest.sh`
- `plugins/spec-autopilot/runtime/scripts/validate-fixup-manifest.sh`
- Phase 7 archive readiness / autosquash 相关逻辑
- 新增真实 git 集成测试

### 1.11 每个阶段门禁和上下文恢复的意义要体现在实现里

必须让代码而不是文档体现:

- gate = 防跳步、防自由发挥、防契约丢失
- recovery = 断点续跑、compact 后连续性、避免重复执行

如果实现与文档冲突，以“单一真相源 + 可执行门禁 + 黑盒测试”重写文档和代码，而不是保留双轨。

### 1.12 整体编排流程与 harness 理念、AI 弱点规避、产品力

你必须以如下方向收敛:

- 强化确定性
- 弱化多头真相源
- 控制 prompt 自由度
- 让 GUI 成为真实控制面，而不是装饰层
- 用 gate / packet / recovery / report / archive 去放大 AI 优点、限制 AI 缺点

不要继续增加新功能面，优先做架构收敛。

### 1.13 报告输出与文档

修复完成后，必须把本次落地结果输出到:

- `docs/2026-04-03/`

至少包含:

- 修复说明
- 新旧契约对照
- 新增测试清单
- 仍有残余风险

## 2. 你必须修复的 5 个显式 BUG

### BUG 1: Phase 0 启动卡片 GUI 地址错误显示 `unavailable`

要求:

- 只允许解析 `start-gui-server.sh` 的结构化返回
- 不允许主线程硬编码 `http://localhost:9527`
- 不允许再把失败统一模糊显示成 `unavailable`
- HTTP / WS 端口必须统一真相源，不能出现 `9528 / 8765` 双轨
- Phase 0 banner / startup card 必须显示:
  - status
  - http_url
  - ws_url
  - health_url
  - error（若失败）

重点文件:

- `plugins/spec-autopilot/runtime/scripts/start-gui-server.sh`
- `plugins/spec-autopilot/skills/autopilot-phase0/SKILL.md`
- `plugins/spec-autopilot/runtime/server/src/config.ts`
- `plugins/spec-autopilot/gui/src/lib/ws-bridge.ts`

### BUG 2: 多个阶段模型展示卡片右边框未封闭，视觉呈 C 字型

要求:

- 卡片必须有明确闭合 outline
- 左侧强调色不能破坏整体闭合边框
- 先做浏览器复现与视觉快照，确认这是运行态样式问题而不是继续盲改 JSX
- 补视觉回归测试或最小化截图断言

重点文件:

- `plugins/spec-autopilot/gui/src/components/ParallelKanban.tsx`
- 相关 CSS / theme

### BUG 3: 主窗口 agent 仅做编排控制，检查并清理不受控内容

要求:

- 主窗口彻底去掉执行细节泄露
- `tool_use`、`output_files`、raw diagnostics 一律放到 diagnostics
- 主窗口仍保留必要的阶段/agent 状态摘要

重点文件:

- `plugins/spec-autopilot/gui/src/App.tsx`
- `plugins/spec-autopilot/gui/src/components/ParallelKanban.tsx`
- `plugins/spec-autopilot/gui/src/components/OrchestrationPanel.tsx`

### BUG 4: 测试阶段测试用例是否需要评审，是否需要真实 case 而不是 md

要求:

- 回答必须落到实现:
  - 是，需要评审
  - 是，需要真实可执行 case
- 把这件事转成测试与门禁策略，而不是只写文档

### BUG 5: 报告阶段是否在主 agent 窗口打印卡片信息，并在卡片中开启 Allure 全量结果访问链接

要求:

- GUI `ReportCard` 与主线程终端 summary box 共用同一份结构化 payload
- 如果 Allure preview 存在，主窗口卡片和主线程终端都必须显示完整访问链接
- `report_ready` 不能只写事件和 snapshot，必须驱动可见输出
- 修复 `emit-report-ready-event.sh` 当前真实故障
- `report_ready` 事件必须写项目根 `logs/events.jsonl`
- 初始 WS snapshot 与增量 snapshot 必须复用同一份完整 meta 构建逻辑，确保首连就能看到 `reportState/recovery/tddAudit`

重点文件:

- `plugins/spec-autopilot/runtime/scripts/emit-report-ready-event.sh`
- `plugins/spec-autopilot/gui/src/components/ReportCard.tsx`
- `plugins/spec-autopilot/runtime/server/src/ws/ws-server.ts`
- `plugins/spec-autopilot/runtime/server/src/ws/broadcaster.ts`
- `plugins/spec-autopilot/runtime/server/src/config.ts`
- `plugins/spec-autopilot/gui/src/store/index.ts`
- Phase 7 相关 skill / runtime 逻辑

## 3. 实施要求

### 3.1 先做结构收敛，再做 UI 补丁

顺序建议:

1. 收敛 snapshot schema / mode graph / agent policy / report payload / fixup ledger
2. 修复 recovery / OpenSpec / TDD / tests
3. 最后修 GUI 和 Phase 0 / Phase 7 展示

### 3.2 代码之外必须同步更新的东西

- skills
- references
- architecture docs
- tests
- hooks registration

### 3.3 所有新增或改动都必须有验收

至少执行并保证通过:

```bash
bash plugins/spec-autopilot/tests/test_lite_mode.sh
bash plugins/spec-autopilot/tests/test_minimal_mode.sh
bash plugins/spec-autopilot/tests/integration/test_e2e_checkpoint_recovery.sh
bash plugins/spec-autopilot/tests/integration/test_e2e_hook_chain.sh
bash plugins/spec-autopilot/tests/test_phase_graph_consistency.sh
bash plugins/spec-autopilot/tests/test_recovery_auto_continue.sh
bash plugins/spec-autopilot/tests/test_tdd_isolation.sh
bash plugins/spec-autopilot/tests/test_tdd_rollback.sh
bash plugins/spec-autopilot/tests/test_phase6_suite_results.sh
bash plugins/spec-autopilot/tests/test_phase6_allure.sh
bash plugins/spec-autopilot/tests/test_fixup_commit.sh
bash plugins/spec-autopilot/tests/test_gui_snapshot_meta_refresh.sh
bash plugins/spec-autopilot/tests/test_gui_server_health.sh
bash plugins/spec-autopilot/tests/test_autopilot_server_aggregation.sh
bash plugins/spec-autopilot/tests/test_server_robustness.sh
bash plugins/spec-autopilot/tests/test_agent_priority_enforcement.sh
```

并且新增通过:

- `full` 模式主线 E2E
- `full` 模式恢复 E2E
- OpenSpec/FF 契约 E2E
- agent policy fail-close 测试
- report card / Allure link 主线程输出测试
- Phase 6 -> report_ready -> server snapshot/event -> ReportCard -> Allure link 端到端测试
- GUI 首连 snapshot meta 完整性测试
- fixup ledger / manifest 集成测试
- 随机端口版 GUI/server 并行稳定性测试

## 4. 交付物要求

完成后你的最终输出必须包含:

1. 改动摘要
2. 根因收敛说明
3. 新的单一真相源是什么
4. 新增/修改了哪些测试
5. 所有测试结果
6. 仍有的残余风险
7. 更新后的文档路径

如果你发现某一条要求在现有仓库里无法合理落地，你不能跳过，必须:

- 说明为什么
- 给出替代实现
- 补对应测试和文档

从现在开始执行，不要停在分析，不要只给建议，直接完成所有修复。
