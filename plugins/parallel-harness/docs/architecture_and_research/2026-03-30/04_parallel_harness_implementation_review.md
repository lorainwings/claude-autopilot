# 04. parallel-harness 当前实现评审

## 1. 评审范围与证据口径

本报告评审的是 `2026-03-30` 工作区中的 **当前实现**，不是 README 中的目标态描述。结论来自三类证据：

1. 本地源码审阅：`plugins/parallel-harness/runtime/**`
2. 本地验证：
   - `cd plugins/parallel-harness && bun test` -> `241 pass / 0 fail / 535 expect() / 10 files`
   - `cd plugins/parallel-harness && bunx tsc --noEmit` -> 失败
3. 现有文档与实现比对：`README.md`、`README.zh.md`、`docs/architecture/overview*.md`

本报告的重点不是罗列优点，而是识别在“产品设计 -> UI/技术方案 -> 编排 -> 代码实现 -> 测试 -> 报告”全链路里，哪些地方仍不足以支撑“最强 parallel-harness 编排插件”的目标。

## 2. 总体结论

当前版本已经不是纯概念稿，而是一个 **可运行的并行编排骨架**：

- 统一运行时、状态机、审批恢复、批次调度、任务级与运行级 gate、MergeGuard、审计日志、控制面、PR 集成都已进入主链。
- 与 2026-03-29 之前的版本相比，`Requirement Grounding`、`MergeGuard` 主链集成、`evidence-loader`、`ExecutionProxy`、运行时桥接等补强已经落地。

但它仍然不能被定义为“全流程高可靠控制平面”。根本原因不是“缺少功能点”，而是：

- 多个核心能力还是 **软约束、后验检查、启发式代理指标**，不是执行前硬约束。
- 测试大多证明“骨架可跑通”，还没有证明“高风险路径可靠”。
- 文档的成熟度表述明显强于当前真实实现。

一句话总结：

> 当前的 `parallel-harness` 已经具备了控制平面的形，但离“生产级、可审计、可恢复、可验证的全流程 harness”还差关键的执行硬化层。

## 3. 优先级最高的问题

### Critical-1. Worker 执行边界仍然是软约束，缺少真正的执行前隔离

**现象**

- `LocalWorkerAdapter` 本质上仍是把 `TaskContract` 拼成自然语言 prompt，再调用 `claude -p ...`：
  - `runtime/engine/orchestrator-runtime.ts:1860-1947`
- `ToolPolicy` 通过环境变量下发，但没有在 CLI 进程级强制执行：
  - `runtime/engine/orchestrator-runtime.ts:1896-1901`
- `PathSandbox` 的关键检查发生在执行完成后，属于后验校验：
  - `runtime/workers/worker-runtime.ts:282-318`
  - `runtime/workers/worker-runtime.ts:342-361`
- `ExecutionProxy` 目前只是根据 `WorkerOutput` 生成 attestation，并未实际拦截工具调用或文件写入：
  - `runtime/workers/execution-proxy.ts:35-72`

**失效模式**

- worker 在运行期间仍可能访问或修改超出 contract 的路径；
- tool allowlist / denylist 不是系统强制，而是“希望模型遵守”；
- attestation 更接近“事后包装的报告对象”，不是可信执行证据。

**为什么是 Critical**

因为这直接击穿了 harness 的第一性目标：**把 AI 的自由行为收缩到工程允许的边界内**。没有执行前硬隔离，系统只能“发现问题”，不能“防止问题”。

**修复方向**

- 增加真正的执行代理层，把模型选择、工具权限、cwd、文件系统边界、worktree 隔离和审计采集绑定在同一层；
- attestation 必须基于真实工具调用与真实 diff，而不是基于 `WorkerOutput` 二次包装；
- 对高风险任务使用独立 worktree / sandbox，而不是依赖单进程提示词约束。

### Critical-2. 类型检查基线是红的，GA/production-ready 宣称不成立

**现象**

本地执行 `bunx tsc --noEmit` 失败，主要错误包括：

- `require` 未声明：
  - `runtime/engine/orchestrator-runtime.ts:1378`
- `Bun`、`process`、`node:fs`、`fs`、`path`、`bun:test` 等类型缺失：
  - `runtime/gates/gate-system.ts:155`
  - `runtime/persistence/session-persistence.ts:83`
  - `runtime/session/evidence-loader.ts:1-2`
  - `tests/**/*.ts`
- `tsconfig.json` 缺少对 Bun/Node 类型环境的显式声明：
  - `plugins/parallel-harness/tsconfig.json:2-24`

**失效模式**

- 类型系统无法作为 refactor 的安全网；
- 当前实现对运行时环境有隐式依赖；
- 文档中“fully tested / production-ready”会误导外部读者或未来维护者。

**为什么是 Critical**

对一个以“稳定实现”和“治理”作为卖点的 harness 而言，类型检查本身就是最基础的工程闸门。测试绿但类型红，说明验证闭环不完整。

**修复方向**

- 为 Bun/Node 混合环境补齐 `compilerOptions.types` 与必要依赖；
- 去掉 `require()` 这类逃逸式接法，改成 ESM/静态 import 或明确定义动态 import；
- 将 `typecheck` 纳入必过 gate，而不是仅作为 package script。

### Critical-3. PR/GitHub 集成缺少 repo 级隔离，存在误操作风险

**现象**

- `GitHubPRProvider` 内部执行 `git checkout`、`git add`、`git commit`、`git push` 时，没有显式使用目标项目的 `cwd`：
  - `runtime/integrations/pr-provider.ts:133-168`
- `execShellForGit()` 也没有接收工作目录参数：
  - `runtime/integrations/pr-provider.ts:110-125`
- Runtime 在创建 PR 时只传了 `modified_files`，没有传 `project_root`：
  - `runtime/engine/orchestrator-runtime.ts:656-663`

**失效模式**

- 如果运行时当前工作目录不是目标仓库，PR 操作可能在错误目录执行；
- 多仓、多工作区或插件开发环境下，存在污染宿主仓库的风险；
- “PR/CI integration” 成为高风险副作用点，而不是安全输出层。

**为什么是 Critical**

这属于“最后一公里的破坏性问题”。前面再多 gate，如果最终在错误仓库执行 `git push`，整条控制链都会失效。

**修复方向**

- `PRProvider` API 必须显式接收并使用 `repo_root`；
- 推送前强制校验远端仓库、当前分支、git status 和 path ownership；
- 对 PR 创建前增加 dry-run 和 repository identity check。

## 4. 高优先级问题

### High-1. Context budget 与 context packing 没有形成闭环

**现象**

- `routeModel()` 会产出 `context_budget`：
  - `runtime/models/model-router.ts:116-131`
- 但运行时在 `executeTask()` 中并没有把这个 budget 传给 `packContext()`：
  - `runtime/engine/orchestrator-runtime.ts:917-933`
  - `runtime/engine/orchestrator-runtime.ts:1029-1033`
- `packContext()` 仍使用自己的默认预算：
  - `runtime/session/context-packager.ts:27-46`

**失效模式**

- “模型路由”与“上下文治理”是并排存在的两个功能，而不是联动系统；
- 大上下文任务不会随着 tier、剩余预算、重试策略而动态收紧；
- 难以把“上下文超过 30%-40% 触发压缩”做成真正的运行时策略。

**修复方向**

- 让 `RoutingResult.context_budget` 进入 `PackagerConfig`；
- 在 attempt 级记录 `occupancy_ratio`、`evidence_count`、`compaction_policy`；
- 将 context 预算纳入审计和 gate 证据，而不是仅作为临时计算值。

### High-2. Requirement Grounding 已接入主链，但大部分输出仍未被消费

**现象**

- `RequirementGrounding` 已在 plan 阶段生成并进入 `RunPlan`：
  - `runtime/engine/orchestrator-runtime.ts:740-743`
  - `runtime/engine/orchestrator-runtime.ts:824-835`
- 当前真正被运行时消费的主要只有 `ambiguity_items.length > 2` 这一条阻断逻辑：
  - `runtime/engine/orchestrator-runtime.ts:482-495`
- `acceptance_matrix`、`impacted_modules`、`delivery_artifacts`、`required_approvals` 基本未进入后续调度、contract 或 gate：
  - `runtime/orchestrator/requirement-grounding.ts:3-16`
  - `runtime/orchestrator/requirement-grounding.ts:42-84`

**失效模式**

- “需求理解”仍主要停留在入口检查，而没有成为后续实现/测试/报告的真相源；
- 需求澄清、验收矩阵、审批链无法贯通到 task contract 与 gates；
- 需求理解不到位的问题只能被早期粗暴阻断，不能被系统化跟踪。

**修复方向**

- 将 `acceptance_matrix` 下沉到 task-level acceptance criteria 和 verifier plan；
- 将 `required_approvals` 真正映射到审批矩阵；
- 将 `impacted_modules` 反馈到 repo-aware planning、test obligation 与报告摘要。

### High-3. GateSystem 只有部分 gate 具备真实工程检测能力

**现象**

真实度较强的 gate：

- `test`：执行 `bun test`
  - `runtime/gates/gate-system.ts:175-261`
- `lint_type`：执行 `tsc` / `ruff`
  - `runtime/gates/gate-system.ts:267-343`

启发式或代理性较强的 gate：

- `review`：主要检查摘要长度、改动文件数、是否改测文件
  - `runtime/gates/gate-system.ts:355-413`
- `security`：主要按敏感文件名匹配
  - `runtime/gates/gate-system.ts:419-474`
- `coverage`：优先正则解析 `bun test --coverage` 输出，失败后退化成“是否修改测试文件”的启发式
  - `runtime/gates/gate-system.ts:480-545`
- `documentation`、`perf`、`release_readiness`：主要是规则代理项
  - `runtime/gates/gate-system.ts:605-647`
  - `runtime/gates/gate-system.ts:654-716`
  - `runtime/gates/gate-system.ts:722-764`

**失效模式**

- 文档中“9-Gate Quality System”会被理解成 9 个同等级硬门禁，但当前并非如此；
- review/security/perf/doc/release 仍容易出现“看起来像通过，实际上没验证”的情况；
- 对 reward hacking 和测试投机的防御力不足。

**修复方向**

- 把 gates 分成 `hard gates` 与 `signal gates`；
- 对 security、coverage、release readiness 接入真实工具链与结构化结果；
- 报告中明确区分“阻断证据”和“提示信号”，避免误导。

### High-4. Hook/Instruction/Skill 扩展层没有真正介入主链决策

**现象**

- `HookRegistry` 只在阶段边界被调用：
  - `runtime/engine/orchestrator-runtime.ts:471-475`
  - `runtime/engine/orchestrator-runtime.ts:1828-1844`
- 但 hook 返回的 `HookResult[]` 没有被运行时消费成调度、contract、gate 或审批变化；
- `instructionRegistry` 只是挂到 runtime 成员上，没有进入 planner、context packager、worker prompt 或 gates：
  - `runtime/engine/orchestrator-runtime.ts:425-443`
- `SkillRegistry`、`InstructionRegistry` 更多停留在 registry 层：
  - `runtime/capabilities/capability-registry.ts:94-187`

**失效模式**

- 文档中的“Capability / Skill / Instruction extension layer”容易让人误以为这是活跃编排层；
- 实际上当前只有 hooks 被触发，但还是“旁路回调”，不是控制面原语；
- 很难承载组织级规范、行业规则、阶段性 reviewer profile。

**修复方向**

- 让 hook 返回可消费的 effect，例如：补充 contract、追加 gate、触发审批、降低并发；
- 将 instructions 在规划、上下文打包、worker 执行、报告综合四个阶段显式注入；
- 将 skill/instruction 的命中结果写入审计链。

### High-5. Execution attestation 目前更像“证明对象”，还不是“可信证据”

**现象**

- Runtime 在终态阶段用 `ExecutionProxy.wrapExecution()` 给每个 task 补一个 attestation：
  - `runtime/engine/orchestrator-runtime.ts:603-619`
- 但 `ExecutionProxy` 只是根据 `WorkerOutput` 生成：
  - `runtime/workers/execution-proxy.ts:39-72`
- `tool_calls` 为空数组，`actual_model` 只是 tier 到模型名的静态映射，`token_usage` 也来自 `WorkerOutput.tokens_used`。

**失效模式**

- 审计链里有 attestation 字段，但不具备真正可追责性；
- 无法用它支撑高风险发布、PR 合并或外部审计；
- “报告生成专业性”会被弱证据拖累。

**修复方向**

- attestation 必须绑定真实工具调用、stdout/stderr、git diff、模型 ID、环境信息；
- attestation 应在 worker 执行过程中采集，而不是 finalize 阶段补造。

## 5. 中优先级问题

### Medium-1. 测试结构偏重 happy path，关键高风险路径缺少端到端证据

本地测试虽然全绿，但覆盖不均衡：

- `OrchestratorRuntime` 集成测试默认关闭 gates 与 PR：
  - `tests/integration/runtime.test.ts:62-74`
- `GitHubPRProvider` 没有真实 `git/gh` 路径测试：
  - `runtime/integrations/pr-provider.ts:127-289`
- `createControlPlaneServer()` 的 HTTP POST、鉴权、重试、审批路径没有端到端测试：
  - `runtime/server/control-plane.ts:283-405`
- `FileStore` 的落盘与重启恢复缺少直接测试：
  - `runtime/persistence/session-persistence.ts:69-138`
- `GateSystem` 只有部分 evaluator 被细测：
  - `tests/unit/gate-governance-persistence.test.ts`

这意味着当前测试更能证明“骨架没坏”，不能证明“高风险路径可靠”。

### Medium-2. `context-packager.ts` 的“自动摘要”实际上仍是截断

**证据**

- 文件头宣称“超预算自动摘要，不是截断”：
  - `runtime/session/context-packager.ts:11-12`
- 实现上仍是“超过阈值后保留前 50 行”：
  - `runtime/session/context-packager.ts:211-236`

这会误导用户对“上下文压缩”和“语义摘要”的预期。

### Medium-3. 报告聚合层还没有把 artifact/attestation 变成一等证据

**证据**

- `EvidenceReference` 类型支持 `gate | attestation | artifact`：
  - `runtime/integrations/report-aggregator.ts:3-7`
- 实际实现只汇总了 `gate`：
  - `runtime/integrations/report-aggregator.ts:24-45`

这会限制最终报告的专业度和可审计性。

### Medium-4. 文档与实现存在多处不一致

最明显的偏差包括：

- README 的测试统计过期，仍写 `219 pass / 0 fail / 499 expect()`
- README/架构文档的 `Event Bus (38 event types)` 已过期，源码当前为 39 种事件：
  - `runtime/observability/event-bus.ts:16-66`
- 架构文档仍把 `Verifier Swarm -> Result Synthesizer` 画为主链，但真实主链是 `GateSystem -> finalizeRun`
- 中文 README 顶部状态机图仍与真实状态机不一致
- 模块树漏掉了 `runtime/server/`

这些偏差不会直接让代码出错，但会直接损伤使用者对系统能力边界的判断。

## 6. 已经修复或应从旧评审中移除的问题

与旧版评审相比，以下几点应当视为 **已部分修复或不再成立**：

1. `MergeGuard` 已进入主链，不应继续写成“完全未接入”：
   - `runtime/engine/orchestrator-runtime.ts:570-597`
2. `max_model_tier` 已在 `executeTask()` 重试路由中再次强制应用：
   - `runtime/engine/orchestrator-runtime.ts:917-931`
3. `RunResult` 已在 PR artifacts 收敛后再保存，旧的持久化时序问题已基本修复：
   - `runtime/engine/orchestrator-runtime.ts:640-709`
4. `packContext()` 不再总是空包，`evidence-loader` 已被运行时接入：
   - `runtime/engine/orchestrator-runtime.ts:1376-1387`
   - `runtime/session/evidence-loader.ts:33-77`

但这些“修复”多数仍停留在第一版落地，离工业级还有距离。

## 7. 结论：当前版本最准确的定位

截至 `2026-03-30`，`parallel-harness` 最准确的定位不是“GA 级全流程 AI 工程控制平面”，而是：

> 一个已经打通核心生命周期、具备治理骨架、正在从启发式编排器向高可靠 harness 演进的控制平面原型。

它最值得保留的资产有三项：

1. **Graph-first runtime**：不是自由对话式 agent loop，而是明确的 plan -> schedule -> execute -> verify -> finalize。
2. **治理意识是正确的**：审批、RBAC、审计、MergeGuard、PR 集成都已被视为一等对象。
3. **可演进性好**：模块边界已经分清，后续可以逐层硬化，而不是推翻重写。

它最需要补齐的也只有三项：

1. **执行硬隔离**
2. **可信验证证据**
3. **文档/测试/类型系统的一致性闭环**

做到这三点之后，这个项目才有资格向“最强 parallel-harness 编排插件”继续推进。
