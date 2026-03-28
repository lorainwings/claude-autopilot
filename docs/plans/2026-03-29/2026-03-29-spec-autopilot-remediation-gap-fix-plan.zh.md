# spec-autopilot 遗漏问题修复执行计划

日期: 2026-03-29
范围: `plugins/spec-autopilot`
来源:
- 2026-03-29 对 `spec-autopilot` v6.0 remediation 实际代码与测试的复核
- `docs/plans/2026-03-28/2026-03-28-spec-autopilot-remediation-acceptance-matrix.zh.md`
- `docs/plans/2026-03-28/2026-03-28-spec-autopilot-stability-remediation-master-plan.zh.md`

## 1. 文档定位

本文档不是重写 2026-03-28 总方案，而是对该轮 remediation 的**遗留缺口补修计划**。

适用场景:

1. 已合入 v6.0 主修复，但 code review 仍发现遗漏问题。
2. 需要把“review 结论”转成可执行 backlog，而不是停留在口头说明。
3. 需要补齐一轮小范围、高约束、可验收的 follow-up 修复。

本轮仅处理以下 5 类确认问题，不扩散到新的大范围重构：

1. 并行同 phase agent 的 artifact boundary 校验关联不精确
2. GUI orchestration-first 所依赖的 archive/readiness/requirement hash 状态未形成完整事件闭环
3. GUI server 常规启动路径未正确加载 `state-snapshot.json`
4. 文档默认值与 v6.0 自动推进语义仍有冲突残留
5. 测试未覆盖上述真实缺口，导致“已有测试全绿但问题仍存在”

## 2. 缺口摘要

| 缺口 | 当前表现 | 风险 | 归属 |
|---|---|---|---|
| Agent 边界校验按 phase 取最后一条 dispatch record | 并行 Phase 5 可能误用别的 agent 的 owned artifacts | 漏检越界写入或误拦截 | 治理 / Workstream G |
| `archive_readiness` 无稳定生产路径 | GUI 归档状态面板可能长期为空 | orchestration-first 验收不成立 | GUI / Server / Workstream H |
| `requirement_packet_hash` 只在 GUI 消费，不在主流程稳定产出 | GUI “需求包 hash”位无法反映真实运行态 | 恢复一致性不可观测 | GUI / Phase 1 / Workstream H |
| server 读取快照只看 `AUTOPILOT_PROJECT_ROOT` env | `start-gui-server.sh` 常规启动后 `stateSnapshot` 可能为 null | `state-snapshot.json` 未真正成为 GUI 主控制态来源 | Server / Workstream H |
| README / schema / config docs 仍写 `after_phase_1: true` 或默认 true | 文档与实现冲突 | 执行时容易回退到旧协议 | Docs / Workstream I |

## 3. 修复原则

本轮 follow-up 必须遵守以下硬约束：

1. 不允许用“测试放宽”替代真实实现修复。
2. 不允许把 GUI 的关键编排状态继续留在测试专用 mock event 上。
3. 不允许继续按 `phase` 粗粒度关联并行 agent 治理状态，必须精确到 `agent_id`。
4. 不允许文档继续保留“默认逐阶段确认”的旧语义。
5. 所有新增测试必须验证行为或真实数据流，不接受只 grep 注释。

## 4. 执行波次

### Wave 1: 代码闭环

1. 修复 agent dispatch record 与 post-task validator 的精确关联。
2. 修复 GUI/server 的 structured state 输入链路。
3. 为 archive readiness / requirement hash 建立真实事件或真实 snapshot 消费路径。

### Wave 2: 测试补强

1. 新增并行同 phase 多 agent 的 boundary 回归测试。
2. 新增 GUI server 读取 `state-snapshot.json` 的集成测试。
3. 新增 Phase 1 `requirement_packet_hash` 可观测性测试。
4. 新增 archive readiness 事件/快照驱动 GUI 状态的行为测试。

### Wave 3: 文档收口

1. 统一 README / config schema / getting-started / Phase 1 references 中的默认值。
2. 在总计划中补入 follow-up 文档入口。
3. 对齐“需求确认后默认自动推进”和“archive readiness 自动归档”的描述。

## 5. Workstream G: Agent 治理精确关联修复

### 5.1 问题定义

当前 `plugins/spec-autopilot/runtime/scripts/_post_task_validator.py` 在治理校验阶段只按 `phase` 倒序读取最后一条 dispatch record，再用该 record 的 `owned_artifacts` 校验当前 envelope。

这在单 agent phase 下通常成立，但在同一 phase 存在多个并行 agent 时不成立。

### 5.2 修复目标

实现以下结果：

1. PostTask validator 能拿到“当前完成的具体 agent_id”。
2. 边界校验基于 `agent_id + phase + session` 精确命中 dispatch 记录。
3. 并行同 phase 多 agent 时，各自只校验自己的 `owned_artifacts`。

### 5.3 主要改动文件

1. `plugins/spec-autopilot/runtime/scripts/auto-emit-agent-dispatch.sh`
2. `plugins/spec-autopilot/runtime/scripts/auto-emit-agent-complete.sh`
3. `plugins/spec-autopilot/runtime/scripts/capture-hook-event.sh`
4. `plugins/spec-autopilot/runtime/scripts/_post_task_validator.py`
5. 如需要，补充 `_hook_preamble.sh` / `_envelope_parser.py` 的 agent 透传辅助函数

### 5.4 实施步骤

1. 明确 PostToolUse 输入中当前 agent 身份来源，优先使用已存在的 `active_agent_id`。
2. 如 PostTask validator 当前拿不到该值，则在 hook capture 路径中把 `active_agent_id` 写入可消费字段。
3. 在 dispatch record 中增加稳定匹配维度，至少包括：
   - `agent_id`
   - `phase`
   - `session_id` 或等价 session 关联信息
4. 将 `_post_task_validator.py` 的“按 phase 取最后一条记录”改为“按当前 agent_id 精确匹配最近 dispatch record”。
5. 对无匹配 dispatch record 的情况定义 fail-closed 策略：
   - 默认 block
   - reason 必须明确提示“governance correlation missing”
   - 不能静默跳过边界校验

### 5.5 必测项

1. 单 phase 单 agent 兼容现有行为。
2. 同一 phase 两个 agent 拥有互斥 `owned_artifacts` 时，A 完成不得读取/继承 B 的边界。
3. 缺少匹配 dispatch record 时，validator 必须阻断而不是 warning。
4. dispatch record 中仍保留 `selection_reason`、`resolved_priority`、`fallback_reason`、`owned_artifacts`。

### 5.6 完成定义

以下同时满足才算完成：

1. 真实代码按 `agent_id` 关联。
2. 新增并行场景回归测试。
3. 现有 `test_agent_priority_enforcement.sh` 扩展覆盖而非仅保留静态断言。

## 6. Workstream H: GUI / Server 编排状态闭环修复

### 6.1 问题定义

当前 GUI 编排面板已经有消费逻辑，但关键状态没有稳定生产链路：

1. `archiveReadiness` 依赖 `archive_readiness` 事件，生产路径未闭环。
2. `requirementPacketHash` 依赖 Phase 1 `phase_end` payload，但主流程模板未带出。
3. server 读取 `state-snapshot.json` 只看环境变量，不看 `--project-root` 启动参数。

### 6.2 修复目标

实现以下结果：

1. GUI 主窗口在真实 autopilot 流程中能看到 archive readiness。
2. GUI 主窗口在真实 Phase 1 完成后能看到 requirement packet hash。
3. GUI server 常规启动即可稳定加载 `state-snapshot.json`。
4. `state-snapshot.json`、`archive-readiness.json`、Phase 1 requirement hash 三条链路至少有一条真实服务端聚合路径，不再依赖测试专用 mock event。

### 6.3 主要改动文件

1. `plugins/spec-autopilot/skills/autopilot/SKILL.md`
2. `plugins/spec-autopilot/skills/autopilot-phase7/SKILL.md`
3. `plugins/spec-autopilot/runtime/server/src/config.ts`
4. `plugins/spec-autopilot/runtime/server/src/snapshot/snapshot-builder.ts`
5. `plugins/spec-autopilot/runtime/server/src/api/routes.ts`
6. `plugins/spec-autopilot/runtime/server/src/types.ts`
7. `plugins/spec-autopilot/gui/src/store/index.ts`
8. 如需要，补充/复用现有 emit 脚本生成新的结构化事件

### 6.4 实施步骤

#### H-1. `requirement_packet_hash` 闭环

1. 明确 Phase 1 完成时 hash 的唯一来源：
   - 优先从 `requirement-packet.json`
   - 次选 `phase-1-requirements.json`
2. 在 Phase 1 `phase_end` 事件 payload 中稳定带出 `requirement_packet_hash`。
3. 补充 server snapshot / API 暴露，确保 GUI 首次打开也能拿到历史值，而不是必须依赖实时事件。

#### H-2. `archive_readiness` 闭环

1. 为 Phase 7 readiness 判定增加结构化事件输出，或在 snapshot builder 中直接读取 `archive-readiness.json` 并映射到 GUI 可消费字段。
2. 二选一只能选一种为主链路，禁止“文档说事件、实现靠文件、测试靠 mock”三套并存。
3. 若采用事件主链路：
   - 定义稳定 payload schema
   - 记录 `fixup_complete`
   - 记录 `review_gate_passed`
   - 记录 `ready`
   - 必要时附带 `block_reasons`
4. 若采用 snapshot 主链路：
   - server 在构建 snapshot 时读取 `archive-readiness.json`
   - API/WS 快照中稳定暴露该值
   - GUI store 从 snapshot 初始化，而非只靠事件增量

#### H-3. `state-snapshot.json` server 读取修复

1. 将 `snapshot-builder.ts` 的 project root 获取统一到 `config.ts` 导出的 `projectRoot`。
2. 禁止仅依赖 `AUTOPILOT_PROJECT_ROOT` 环境变量。
3. 保留 env var 仅作 fallback，不得反过来压过 CLI 参数。
4. 增加 server 级测试验证：
   - 仅通过 `--project-root` 启动
   - `state-snapshot.json` 存在
   - `stateSnapshot` 不为 null

### 6.5 必测项

1. `test_gui_store_cap.sh` 从静态 mock 扩展为真实 server/snapshot 输入校验，至少新增 1 个非 mock 路径用例。
2. 新增 `test_server_reads_state_snapshot.sh` 或同等集成测试。
3. 新增 `test_requirement_packet_hash_visibility.sh` 或同等测试。
4. 新增 `test_archive_readiness_visibility.sh` 或同等测试。

### 6.6 完成定义

以下同时满足才算完成：

1. GUI 首屏能稳定显示 requirement packet hash。
2. GUI 首屏能稳定显示 archive readiness。
3. server 常规启动能读到 `state-snapshot.json`。
4. 以上三项均有真实行为测试，而非仅 store mock 测试。

## 7. Workstream I: 文档与默认值一致性修复

### 7.1 问题定义

v6.0 已把“需求确认后默认自动推进”作为硬约束，但英文 README、config schema、getting-started 文档、Phase 1 参考文档仍残留 `after_phase_1: true` 或“默认 true”。

### 7.2 修复目标

统一所有公开文档，使其与当前协议一致：

1. `after_phase_1` 默认值为 `false`
2. `after_phase_3` / `after_phase_4` 默认值保持自动推进语义
3. 归档不再描述为“必须人工确认”
4. 文档中清楚区分：
   - 用户业务裁决
   - 系统流程自动推进

### 7.3 主要改动文件

1. `plugins/spec-autopilot/README.md`
2. `plugins/spec-autopilot/README.zh.md`（复核是否还需补充英文一致性说明）
3. `plugins/spec-autopilot/skills/autopilot/references/config-schema.md`
4. `plugins/spec-autopilot/skills/autopilot/references/phase1-requirements.md`
5. `plugins/spec-autopilot/docs/getting-started/configuration.md`
6. `plugins/spec-autopilot/docs/getting-started/configuration.zh.md`
7. 如有必要，补充 `docs/architecture/phases*.md`

### 7.4 实施步骤

1. 全量搜索 `after_phase_1: true`、`默认 true`、`必须 AskUserQuestion 归档`。
2. 将默认值和说明统一改为 v6.0 语义。
3. 对“仍可能 AskUserQuestion”的位置改写为：
   - 仅在真实 blocked / recovery ambiguity / destructive action 时交互
4. 复核中英文文档，避免中英文默认值再次分叉。

### 7.5 必测项

1. 扩展 `test_auto_continue.sh`，覆盖 README / config-schema / getting-started 文档一致性。
2. 增加反向断言：公开文档中不得再出现 `after_phase_1: true`。

## 8. 建议执行顺序

建议按以下顺序实施，避免反复返工：

1. 先做 Workstream H 的 server root/snapshot 修复
2. 再做 Workstream H 的 requirement/archive 状态闭环
3. 再做 Workstream G 的 agent 精确关联治理修复
4. 最后做 Workstream I 的文档收口
5. 收尾时统一补测试和 `tests/run_all.sh` 接线

原因:

1. GUI/server 的数据模型一旦定稿，文档和测试才能稳定。
2. Agent 治理修复需要明确 hook 输入侧的最终字段方案，晚于 server root 修复不会互相阻塞。
3. 文档必须以最终实现为准，不应先改文档再改协议。

## 9. 测试补强清单

本轮至少新增或补强以下测试：

1. `test_parallel_agent_boundary_correlation.sh`
   - 验证同 phase 多 agent 以 `agent_id` 精确校验
2. `test_server_state_snapshot_loading.sh`
   - 验证 `--project-root` 启动后 server 能读取 `state-snapshot.json`
3. `test_requirement_packet_hash_visibility.sh`
   - 验证 Phase 1 完成后 GUI/server 可观测到 hash
4. `test_archive_readiness_visibility.sh`
   - 验证 Phase 7 readiness 状态能进入 GUI 主窗口
5. 扩展 `test_auto_continue.sh`
   - 公开文档不得再保留 `after_phase_1: true`
6. 扩展 `test_agent_priority_enforcement.sh`
   - 增加多 agent 并行边界回归，而不只是 dispatch record 字段存在性

## 10. 最终验收标准

以下全部满足，才可以宣称这轮遗漏问题已修复：

1. 并行同 phase 多 agent 的 artifact boundary 校验按 `agent_id` 精确关联。
2. GUI 主窗口真实显示 requirement packet hash。
3. GUI 主窗口真实显示 archive readiness。
4. server 常规启动路径能读取 `state-snapshot.json`。
5. README / schema / getting-started / Phase 1 文档的自动推进默认值一致。
6. 新增行为测试能覆盖以上全部缺口。

## 11. 拒收条件

出现以下任一项即拒收：

1. 只修改测试 mock，不修改真实生产路径。
2. 继续按 `phase` 粗粒度关联 dispatch record。
3. GUI 仍只能在人工注入 `archive_readiness` mock event 时显示归档状态。
4. `state-snapshot.json` 读取仍依赖手工导出环境变量。
5. 公开文档中仍残留 `after_phase_1: true` 的默认值。
