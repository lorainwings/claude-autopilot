# spec-autopilot v5.6.0 深度分析报告：TDD 模式与 GUI 可观测性

> 分析日期：2026-04-16
> 分析范围：TDD 运行模式验证、GUI 模块完整性、可观测性缺口、Statusline 遥测

---

## 一、TDD 模式验证

### 1. TDD 运行是否产生实际测试报告

**会产生，但报告的"实质性"取决于串行还是并行模式。**

TDD 模式下的测试证据分为三个层次：

| 层次 | 串行 TDD (C+B) | 并行 TDD (C+A) |
|------|----------------|----------------|
| **L2 逐步验证** | 主线程在每个 RED/GREEN/REFACTOR 步骤执行 `Bash(test_command)`，结果确定性 | 仅 post-merge 一次全量测试（L2），per-task RED/GREEN 由 domain agent 自报（L1） |
| **TDD Cycle 结构化数据** | 每个 task checkpoint 含 `tdd_cycle.red/green/refactor`，含 `exit_code`、`assertion_message`、`output_tail` | 同样有此结构，但数据来自 agent 自报，可被伪造 |
| **Allure 测试数据** | Phase 5 每步测试结果写入 `allure-results/tdd/{red,green,refactor}/` | 类似，但依赖 agent 正确注入 Allure 参数 |
| **Phase 6 完整报告** | Phase 6 **强制完整重跑**所有测试套件（忽略 smart-skip），生成最终 Allure 报告 | 同上 |

**关键发现**：Phase 6 的 Step A2.6 会强制全量重跑测试并生成 Allure 报告，这部分是确定性的。但 TDD 过程中的 per-task RED→GREEN 转换证据：

- 串行模式 = **L2 确定性验证**（可信）
- 并行模式 = **L1 自报告**（不可信，agent 可以先写实现再补测试，伪造 `red_verified: true`）

**审计事件** `emit-tdd-audit-event.sh` 会汇总 `cycle_count`、`red_violations`、`green_violations`、`refactor_rollbacks` 写入 `events.jsonl` 和 `state-snapshot.json`，供 GUI 展示。

### 2. TDD 运行效果评估与已知问题

#### 评估维度矩阵

| 评估维度 | 串行 TDD | 并行 TDD | 当前差距 |
|----------|----------|----------|----------|
| RED 阶段测试确实失败 | L2 确定性验证 (exit_code!=0) | L1 自报告 | **并行模式有信任缺口** |
| GREEN 阶段测试确实通过 | L2 确定性验证 (exit_code=0) | 仅 post-merge L2 全量验证 | 并行模式无法验证 per-task GREEN |
| 文件写入隔离（RED 只写测试） | L2 Hook `unified-write-edit-check.sh` 强制执行 | 无 L2 Hook（agent 内部执行） | **并行模式文件隔离无法保证** |
| 恒真断言检测 | L2 Hook CHECK 3 拦截 | 仅限 Hook 拦截范围 | 覆盖率有限（仅匹配预定义模式） |
| REFACTOR 回归保护 | `tdd-refactor-rollback.sh` 按文件回滚 | Agent 自行管理 | 并行模式回滚不可控 |

#### 已知关键问题（按严重度排序）

1. **P0 — 并行 TDD 信任缺口**：Domain agent 可伪造 RED 证据，先写实现再补测试，主线程只做 post-merge 全量验证，无法证明每个 task 经历了真实的 RED→GREEN 转换

2. **P1 — REFACTOR 阶段文件隔离不完整**：Hook 在 REFACTOR 阶段允许同时修改测试和实现文件（`unified-write-edit-check.sh` 的 refactor 阶段不做文件类型限制），agent 可在 REFACTOR 时修改测试

3. **P1 — 测试文件识别依赖命名约定**：`*.test.*`、`*.spec.*`、`__tests__/` 等。非标准命名（如 Java 的 `*Check.java`）会绕过 TDD 文件隔离

4. **P2 — 反模式检测几乎全靠 AI**：除恒真断言外，mock 过度使用、test-only 生产方法等反模式仅靠 prompt 指导

5. **历史 bug 暗示脆弱性**：PyYAML 布尔值大小写（`True` vs `true`）导致 TDD 检测失败、协议字段不一致（`cycles_completed` vs `total_cycles`）、REFACTOR 回滚策略多次变更

### 3. Allure 报告在 TDD 模式下的意义 & 能否开启 parallel

#### Allure 报告在 TDD 模式下仍有意义

- Phase 6 Step A2.5 合并 TDD 各阶段的 Allure 数据（`allure-results/tdd/{red,green,refactor}/`）
- Phase 6 Step A2.6 **强制完整重跑**所有测试（忽略 smart-skip），生成包含 TDD 历史和最终快照的完整报告
- 最终 Allure 报告同时包含 **TDD RED→GREEN 转换历史** 和 **完整实现后测试快照**

#### TDD 模式可以开启 parallel

这是明确的设计特性（`mode-routing-table.md`）：

> "TDD 是一个**正交修饰符**而非独立第三路径。启用 TDD 时，它与 parallel.enabled **组合**而非替换并行/串行选择。"

四种路径组合：

| 优先级 | 条件 | 路径 | 描述 |
|--------|------|------|------|
| 1 (最高) | tdd_mode=true + parallel=true | **C+A（并行 TDD）** | Domain agent 内部执行 RED-GREEN-REFACTOR + post-merge L2 验证 |
| 2 | tdd_mode=true + parallel=false | **C+B（串行 TDD）** | 每 task 3 个顺序 Task (RED→GREEN→REFACTOR) + L2 Bash 验证 |
| 3 | tdd_mode=false + parallel=true | **A（并行）** | worktree 隔离 + 后台任务 |
| 4 (最低) | tdd_mode=false + parallel=false | **B（串行）** | 顺序前台 Task |

**注意**：并行 TDD 会禁用 Batch Scheduler 并发优化，且 L2 验证降级。

### 4. 子 Agent 运行细节不可见的问题

#### 当前三层信息回传机制

| 层次 | 内容 | 可见性 |
|------|------|--------|
| **JSON 信封返回** | `{status, summary, artifacts}` | 主线程可见，但仅摘要级别 |
| **Hook 捕获** | `auto-emit-agent-dispatch.sh` + `auto-emit-agent-complete.sh` | GUI 可见（agent 卡片） |
| **工具调用旁听** | `emit-tool-event.sh` 通过 `.active-agent-id` 关联 tool call 到活跃 agent | GUI 可见（ToolTracePanel） |

#### 不可见的内容

- Agent 内部推理过程和决策链
- Agent 实际读写了哪些文件（只能看到 Hook 拦截的 Write/Edit，Read 无记录）
- Agent 运行的 Bash 命令实际输出（只有 tool call 记录，无 stdout 全文）
- Agent 是否真的按 TDD 规程执行（串行有 L2 验证，并行无法证明）

#### 改进方向建议

1. **transcript 实时转发**：将 sub-agent 的 transcript 通过 WebSocket 实时推送到 GUI
2. **L2 事件增强**：在并行模式下，要求 domain agent 每步 emit 结构化事件（而非仅最终信封）
3. **文件 diff 可视化**：记录并展示每个 agent 实际产生的 git diff
4. **Agent 内部日志**：通过 `Write` 将 agent 推理过程写入 `logs/agents/{agent_id}/reasoning.md`

---

## 二、GUI 验证

### 1. 缺少的关键模块

| 缺失模块 | 影响 | 数据是否已有 |
|----------|------|-------------|
| **需求包详情面板** | 用户无法看到 Phase 1 生成的实际需求内容（goal、scope、non_goals 等），只能看到 hash | 服务端已暴露 `RequirementPacket` 类型 |
| **Review Findings 面板** | Phase 6.5 代码审查发现完全不可见，只有 `reviewGatePassed` 布尔值 | 类型系统已定义 `ReviewFinding` |
| **Dispatch 审计面板** | Agent 调度策略不透明（selection_reason、resolved_priority、owned_artifacts）不可见 | `DispatchRecord` 类型已定义 |
| **阶段结果汇总表** | `phase_results`（per-phase status + timestamp）未以表格展示 | `StateSnapshot` 已包含 |
| **错误聚合面板** | 错误事件散落在终端日志中，无汇总视图 | 事件已捕获 |
| **Fixup Manifest 面板** | 归档前的 commit fixup 状态不透明 | 类型已定义但未渲染 |

### 2. 缺少的关键数据 & 可观测性不足

当前 GUI 的核心问题：**大量阶段切换时页面几乎无变化**。

| 问题 | 具体表现 | 根因 |
|------|----------|------|
| **Phase 0-3 无任务卡片** | 这些阶段没有 `task_progress` 事件，ParallelKanban 空白，退化为静态展示 | 仅 Phase 5 发射 `task_progress` 事件 |
| **Phase 1 需求讨论不可见** | 多轮澄清、挑战 Agent 激活等过程无实时可视化 | 仅捕获最终 `clarityScore` / `discussionRounds` |
| **Phase 2-3 产物生成透明** | Fast-Forward 是后台任务，页面只显示"Phase 2 运行中" | 无细粒度子步骤事件 |
| **Gate 判定过程不可见** | 8-step gate 检查只产出 pass/block 二值结果 | 仅 `gate_pass`/`gate_block` 事件，无 8-step 明细 |
| **Context compaction 不可见** | 上下文压缩无视觉指示 | `compact_start`/`compact_end` 未可视化 |
| **`parallel_task_ready/blocked` 未处理** | 并行任务就绪/阻塞状态未被 Store 消费 | Store `addEvents` 未处理这两种事件 |

**关键改进建议**：

1. 为 Phase 0-4 增加细粒度 `sub_step` 事件
2. Phase 1 需求讨论实时推送每轮问答
3. Gate 8-step 检查逐步发射事件
4. Store 处理 `parallel_task_ready`/`parallel_task_blocked` 事件

### 3. 板块和字段的作用未体现

| 板块/字段 | 当前展示 | 问题 |
|-----------|---------|------|
| **Requirement Hash** | 一串 hash 值 | 无法点击查看原始需求内容 |
| **Clarity Score** | 单一数字 | 无解释分值含义和风险阈值 |
| **Context Budget** | 百分比 + risk 标签 | 无 risk 等级含义解释，无历史趋势 |
| **Archive Readiness** | 布尔值列表 | 不清楚失败意味着什么、如何修复 |
| **Model Routing Card** | 模型名和 tier | 不理解选择原因和成本影响 |
| **TDD 审计区域** | 4 个数字 | 无"正常"值范围参考，无法判断是否正常运行 |

### 4. Statusline "未安装" 的原因分析

分析 `auto-install-statusline.sh` 和 `install-statusline-config.sh` 完整流程后，最可能的原因：

1. **项目相关性守卫**（第 29 行）：要求目标项目存在 `openspec/` 或 `.claude/autopilot.config.yaml`，否则跳过
2. **SessionStart 异步时序问题**：安装是 async hook，可能在 GUI 首次连接时未完成
3. **路径失效**：statusLine command 中的 `.sh` 脚本路径因插件升级而失效
4. **`CLAUDE_PLUGIN_ROOT` 未解析**：fallback 路径也失效时 collector 不会被执行
5. **Session ID 不匹配**：statusline 记录按 session_id 过滤，不匹配则无 `status_snapshot` 事件
6. **Claude Code 版本不支持**：`statusLine` 是平台特性，旧版本不支持

**遥测的作用**：statusLine 是 GUI 右侧面板运行时指标（模型、成本、context window 使用率、cwd、worktree 状态）的唯一数据源。缺失时 GUI 只能展示事件驱动数据。

### 5. 页面的 Test Report 和 Allure 链接

**`ReportCard` 组件已实现**（`gui/src/components/ReportCard.tsx:206-237`）：

- `reportState.report_url` → 可点击链接（新标签页打开）
- `reportState.report_path` → 文本展示（URL 不可用时 fallback）
- `reportState.allure_preview_url` → 可点击链接（新标签页打开）
- `reportState.allure_results_dir` → 文本展示（preview URL 不可用时 fallback）
- TDD 审计数据（cycle_count、red_violations 等）在 `TddAuditSection` 中展示

**存在的不足**：

1. **数据到达时机晚**：报告链接来自 Phase 6 的 `report_ready` 事件，之前显示"等待 Phase 6 报告生成..."
2. **非内嵌展示**：点击链接是新标签页打开，不是 iframe 内嵌预览
3. **TDD 审计与报告无交叉引用**
4. **信息密度可提升**：建议 Phase 5 执行过程中就展示临时测试结果

---

## 三、最高优先级改进建议

| 优先级 | 领域 | 建议 |
|--------|------|------|
| **P0** | TDD | 并行 TDD 增加 per-task L2 验证机制（如 worktree 隔离下的独立测试运行） |
| **P0** | GUI | Phase 0-4 增加细粒度 sub_step 事件，消除"页面无变化"问题 |
| **P1** | GUI | 增加需求包详情面板、Review Findings 面板，利用已有服务端数据 |
| **P1** | 可观测性 | sub-agent transcript 实时转发到 GUI，解决"黑盒运行"问题 |
| **P1** | Statusline | 增加更鲁棒的安装状态检测和自动修复机制 |
| **P2** | GUI | 为所有指标增加上下文解释（tooltip/help text） |
| **P2** | GUI | Store 处理 `parallel_task_ready`/`parallel_task_blocked` 事件 |
| **P2** | GUI | Gate 8-step 检查逐步可视化 |

---

## 附录：关键文件索引

### TDD 核心文件

| 文件 | 用途 |
|------|------|
| `runtime/scripts/_common.sh` (get_tdd_mode) | TDD 模式检测单一真相源 |
| `runtime/scripts/check-tdd-mode.sh` | Phase 4 入口确定性检测 |
| `skills/autopilot/references/tdd-cycle.md` | RED-GREEN-REFACTOR 完整协议 |
| `skills/autopilot/references/mode-routing-table.md` | 路径选择决策矩阵 |
| `runtime/scripts/unified-write-edit-check.sh` | L2 Hook TDD 文件类型隔离 |
| `runtime/scripts/tdd-refactor-rollback.sh` | REFACTOR 按文件回滚 |
| `runtime/scripts/emit-tdd-audit-event.sh` | TDD 审计事件发射 |

### GUI 核心文件

| 文件 | 用途 |
|------|------|
| `gui/src/components/ReportCard.tsx` | 测试报告 + Allure 链接 + TDD 审计 |
| `gui/src/components/TelemetryDashboard.tsx` | Statusline 遥测 + 模型路由 + 阶段耗时 |
| `gui/src/components/ParallelKanban.tsx` | 任务/Agent 看板 |
| `gui/src/components/OrchestrationPanel.tsx` | 编排控制面板 |
| `gui/src/store/index.ts` | Zustand 全局状态管理 |
| `runtime/server/src/snapshot-builder.ts` | 四源数据聚合 |

### 测试文件

| 文件 | 覆盖范围 |
|------|----------|
| `tests/test_check_tdd_mode.sh` | TDD 检测 11 用例 |
| `tests/test_tdd_isolation.sh` | 文件写入隔离 8 用例 |
| `tests/test_tdd_rollback.sh` | REFACTOR 回滚 7 用例 |
| `tests/test_tdd_gate_intent.sh` | test_intent/failing_signal 门禁 11 用例 |
| `tests/test_phase5_tdd_evidence.sh` | L2 test_driven_evidence 20+ 用例 |
