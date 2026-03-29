# 04. 当前代码库 Review 与缺陷评估

## 1. 评审结论

`parallel-harness` 的目标定位是正确的：它试图把并行 agent 交付升级成一个受治理的工程控制平面，而不是单纯的 agent orchestration demo。问题不在目标，而在 **多个“核心承诺”在当前代码里还没有落成硬约束**。

更直接地说：

- 架构骨架已经存在
- 主链路已经可运行
- 测试覆盖了大量纯函数与 happy path
- 但核心卖点中的“严格所有权隔离”“最小上下文包”“GA 级 gate”“治理强约束”仍存在明显落差

本次本地验证结果：

- 运行命令：`cd plugins/parallel-harness && bun test`
- 结果：`219 pass / 0 fail`

这说明代码是“可运行的”；但不说明它已经具备文档宣称的工业级可靠性。

## 2. 评审口径

### 2.1 严重度定义

- `Critical`：直接击穿系统核心承诺，可能导致错误并发写、策略失效、错误发布或严重治理失真。
- `High`：会显著削弱可靠性、治理性或可恢复性，且在真实项目中很容易遇到。
- `Medium`：不会立即击穿主链路，但会造成误导、可维护性下降或后续扩展困难。

### 2.2 本次评审重点

1. 并发安全是否真能成立
2. worker 执行边界是否真受控
3. context packing 是否真正进入主链路
4. gate / policy / approval 是否和文档一致
5. control plane / persistence / resume 是否能支撑生产运行

## 3. 发现列表

## 3.1 Critical

### C1. “严格文件所有权隔离”并没有在执行阶段真正成立

**问题**

`planOwnership()` 会检测路径冲突，但当冲突解决策略是 `merge_guard` 时，并不会修改 assignment，也不会在执行链路里真正调用 `MergeGuard`。结果是：两个 task 仍可能保有重叠的 `exclusive_paths`，并被 scheduler 放进同一个 batch 并发执行。

**为什么严重**

这直接击穿了项目最核心的产品承诺之一：strict file ownership isolation。

**证据**

- `runtime/orchestrator/ownership-planner.ts:91-141`
- `runtime/orchestrator/ownership-planner.ts:232-246`
- `runtime/scheduler/scheduler.ts:95-145`
- `runtime/guards/merge-guard.ts:78-160`
- `runtime/engine/orchestrator-runtime.ts:753-817`

**影响**

- 并发写同一路径时没有预防性阻断
- merge guard 只存在为一个独立类，不在主链路落地
- scheduler 认为任务可以并行，但真实写集可能冲突

**建议**

1. 在 `planOwnership()` 阶段就把重叠写集改写成不可并发的 reservation。
2. 对 `merge_guard` 冲突禁止进入同一 batch。
3. 在 finalize / pre-merge / pre-pr 强制调用 `MergeGuard`，并让它具备阻断语义。

### C2. Worker 执行边界仍然是 prompt-based 的软约束，而不是硬沙箱

**问题**

`LocalWorkerAdapter` 的本质是：

- 把 `TaskContract` 拼成自然语言 prompt
- 调用 `claude -p ...`
- 再从输出里猜测 `modified_paths`

`tool_policy`、`model_tier`、路径边界主要通过 prompt 或 env 传递，不是执行前的强约束。真正的路径校验发生在 worker 执行之后。

**为什么严重**

如果没有强执行边界，系统只能“事后发现问题”，不能“事前防止问题”。这对高风险仓库、敏感目录和真实 CI/CD 场景都不够。

**证据**

- `runtime/engine/orchestrator-runtime.ts:1740-1826`
- `runtime/workers/worker-runtime.ts:275-333`
- `runtime/workers/worker-runtime.ts:353-360`

**进一步问题**

- `LocalWorkerAdapter` 没有把 `model_tier` 映射成真实模型选择参数
- `ToolPolicy` 并没有被真正接进 adapter 执行器
- 如果 `project_root` 不是绝对路径，git diff attestation 会被关闭

**建议**

1. 引入真正的 execution proxy，强制在受控工具/文件系统边界内运行。
2. 把 `model_tier` 映射到明确的 provider/model 配置，而不是 env hint。
3. 将 tool allowlist / denylist 变成 runtime enforced policy，而不是文档字段。

### C3. Context Packager 在真实主链路里基本被绕过

**问题**

runtime 在调用 `packContext()` 前，`getAvailableFiles()` 永远返回空数组，导致 packager 无法提供真实相关文件和 snippets。

**为什么严重**

这意味着“最小上下文包”在主链路中不是实际能力，只是接口壳。最终 worker 实际上还是靠自己的 repo 探索能力在做工作。

**证据**

- `runtime/engine/orchestrator-runtime.ts:933-935`
- `runtime/engine/orchestrator-runtime.ts:1279-1282`
- `runtime/session/context-packager.ts:55-83`

**影响**

- 无法真正控制上下文污染
- 无法稳定复现 planner 期望的任务证据集
- 无法把“上下文预算”纳入可靠治理

**建议**

1. 在 plan 阶段生成 context plan，明确 symbol/file/snippet 级证据。
2. 运行时必须加载真实文件内容和代码片段，不允许空包进入 worker。
3. 将 `occupancy_ratio`、`evidence_count`、`compaction_reason` 写入审计与结果对象。

## 3.2 High

### H1. `max_model_tier` 只在计划阶段生效，重试阶段可被绕过

**问题**

`planPhase()` 会裁剪初始 routing decision，使其不超过 `ctx.config.max_model_tier`。但在 `executeTask()` 的重试循环里，task 会重新 `routeModel()`，这里没有再次应用 `max_model_tier` 上限。

**为什么严重**

这是明显的策略失效：产品以 tier cap 作为预算和风险控制项，但 retry 会绕过它。

**证据**

- `runtime/engine/orchestrator-runtime.ts:679-710`
- `runtime/engine/orchestrator-runtime.ts:829-839`

**建议**

统一引入 `enforceModelTierCap()`，在所有 routing 入口生效，包括 retry 和 resume。

### H2. 结果持久化时序错误，落盘结果可能不是最终真相

**问题**

`saveResult(result)` 发生在：

- 最终状态收敛前
- `result.final_status` 重写前
- `pr_artifacts` 回填前

在持久化存储下，这会导致磁盘中的 `RunResult` 不是最终真相。

**证据**

- `runtime/engine/orchestrator-runtime.ts:548-555`
- `runtime/engine/orchestrator-runtime.ts:563-629`
- `runtime/engine/orchestrator-runtime.ts:1458-1470`
- `runtime/persistence/session-persistence.ts:112-117`

**影响**

- control plane 读取的结果可能落后于真实运行结束状态
- PR 相关结果可能只存在内存，不存在 durable store

**建议**

所有 `RunResult` 字段都补齐后再持久化；resume 路径同理。

### H3. PolicyEngine 实现与文档不一致：忽略 `priority`，不支持 `log`

**问题**

Schema 和文档都定义了：

- `priority`
- `log`
- “取最严格 enforcement”

但 `DefaultPolicyEngine.evaluate()` 只是按数组顺序遍历规则，并没有：

- 先按 priority 排序
- 聚合得到 strictest enforcement
- 处理 `log` 类型

**证据**

- `runtime/schemas/ga-schemas.ts:344-376`
- `docs/policy-guide.md:151`
- `runtime/engine/orchestrator-runtime.ts:120-166`

**为什么严重**

这会让 policy 行为受配置顺序影响，而不是受规则语义影响，直接削弱策略可信度。

**建议**

引入单独的 `PolicyDecision` 归并步骤：

- 先排序
- 再匹配
- 再按 `block > approve > warn > log` 归并
- 输出统一决策对象

### H4. 意图分析与任务图生成没有 repo grounding，任务到域的映射还是启发式拼接

**问题**

当前 planner 主要基于：

- 关键词
- 段落拆分
- 默认估值
- round-robin 域分配

它并不会真正读取仓库结构、依赖图、符号关系。

**证据**

- `runtime/orchestrator/intent-analyzer.ts:95-219`
- `runtime/orchestrator/task-graph-builder.ts:112-158`
- `runtime/orchestrator/task-graph-builder.ts:164-214`

**影响**

- `allowed_paths` 可能与真实改动域无关
- 依赖边可能漏掉或错建
- 风险估计与预算估计偏差很大

**建议**

新增 repo-aware grounding 阶段，输入至少包括：

- 文件树摘要
- import/dependency graph
- changed module candidates
- existing tests map

### H5. Gate System 中多项 gate 仍是启发式代理，而不是高保真独立验证

**问题**

9 类 gate 并不都达到“GA 级门禁”：

- `review` 主要看摘要长度、文件数量、是否改测试
- `security` 主要看敏感文件名模式
- `perf` 主要看 token、时长、文件数
- `documentation` 主要看是否改了 `.md`
- `release_readiness` 只统计任务状态

同时 `test` / `lint_type` 会对整个项目直接跑全量命令，而不是针对任务做差量验证。

**证据**

- `runtime/gates/gate-system.ts:175-259`
- `runtime/gates/gate-system.ts:267-343`
- `runtime/gates/gate-system.ts:355-412`
- `runtime/gates/gate-system.ts:419-473`
- `runtime/gates/gate-system.ts:480-545`
- `runtime/gates/gate-system.ts:605-646`
- `runtime/gates/gate-system.ts:654-714`
- `runtime/gates/gate-system.ts:722-763`

**建议**

把 gate 分成两类：

- `Hard gates`：真实执行、有证据、有阻断语义
- `Heuristic signals`：只作为风险提示，不再伪装成同等级 gate

### H6. 运行级 gate 没有拿到聚合 worker 证据，导致多类 gate 在 run-level 基本失效

**问题**

`runLevelGates()` 调用 gate system 时只传入了 `{ ctx, plan, level: "run" }`，没有传入聚合后的 `workerOutput` / diff / 证据对象。而当前 `security`、`coverage`、`documentation`、`perf` 这些 gate 的核心逻辑都依赖 `workerOutput.modified_paths` 或相关执行证据。

**证据**

- `runtime/engine/orchestrator-runtime.ts:1077-1085`
- `runtime/gates/gate-system.ts:434-473`
- `runtime/gates/gate-system.ts:480-545`
- `runtime/gates/gate-system.ts:605-646`
- `runtime/gates/gate-system.ts:654-714`

**影响**

- 运行级最终验收并没有真正对“本次 run 改了什么”做严肃聚合判断
- 表面上存在 run-level gate，实际上很多 gate 在此层级近似空转

**建议**

引入 `RunEvidenceBundle`，把所有 task 的：

- modified files
- diff refs
- test artifacts
- security findings
- coverage data

先聚合，再作为 run-level gate 的输入。

### H7. PR Provider 对 cwd 和 staging 的处理不安全

**问题**

`GitHubPRProvider` 的 git 操作没有接收 `project_root` / `cwd` 参数，只依赖进程当前目录；在 `modified_files` 缺失时还会 `git add -A`。

**证据**

- `runtime/integrations/pr-provider.ts:110-168`

**影响**

- 在多仓或插件工作目录不一致时，git/gh 行为可能作用到错误目录
- 极端情况下会暂存无关改动

**建议**

所有 git/gh 操作必须显式携带 target repo cwd，且默认只允许精确 file list staging。

### H8. Control Plane 能看结果，但还不能真正操作“图级重调度”

**问题**

控制面支持取消、审批，但 `retryTask()` 明确返回未实现；同时 `listRuns()` 和 `getRunDetail()` 的 task 视图来自 `completed_attempts`，而不是完整 `task_graph`。

**证据**

- `runtime/server/control-plane.ts:256-259`
- `runtime/engine/orchestrator-runtime.ts:1550-1565`
- `runtime/engine/orchestrator-runtime.ts:1621-1645`

**影响**

- 未执行过的 task 不会准确出现在控制面任务清单里
- Dashboard 不是完整的调度面板，更像结果查看器

**建议**

control plane 数据模型应以 `RunPlan.task_graph` 为真相源，而不是以 attempts 为真相源。

## 3.3 Medium

### M1. 超时配置没有真正透传到 controller 的硬超时

**问题**

runtime 把 `ctx.config.timeout_ms` 传给了 `max_idle_ms`，但 `WorkerExecutionController.executeWithTimeout()` 用的是 `this.config.timeout_ms`。

**证据**

- `runtime/engine/orchestrator-runtime.ts:938-943`
- `runtime/workers/worker-runtime.ts:342-350`

**影响**

- 用户以为配置了 run timeout，实际上 worker controller 可能仍使用默认超时

### M2. Capability Registry 和 ToolPolicy 现在更像“声明”，不是“执行约束”

**问题**

pre-check 中 capability 匹配失败也会 `passed: true`；`ToolPolicy` 只定义了 allowlist/denylist，但没有被 LocalWorkerAdapter 实际执行。

**证据**

- `runtime/engine/orchestrator-runtime.ts:1259-1269`
- `runtime/workers/worker-runtime.ts:134-164`

### M3. Hook 体系目前只有观测价值，没有真正的治理执行力

**问题**

`executeHookPhase()` 会执行 hook，但不会消费 hook 返回结果去：

- 修改数据
- 中断流程
- 改变审批/策略判断

异常也主要被记录成审计事件，而不是控制动作。

**证据**

- `runtime/engine/orchestrator-runtime.ts:1708-1723`

**影响**

- hook 更像 observability extension，而不是 governance extension
- 文档里“扩展点可治理流程”的预期与实现不一致

### M4. Resume 路径会丢失历史 gate 聚合上下文

**问题**

`approveAndResume()` 重建 `ExecutionContext` 时，`auditLog` 和 `collectedGateResults` 都是新数组。

**证据**

- `runtime/engine/orchestrator-runtime.ts:1433-1445`

**影响**

- 恢复后的最终质量报告只包含恢复段的 gate 集合，不一定包含阻断前的完整 gate 历史

### M5. Routing / Budget 字段语义不够干净

**问题**

`routeModel()` 的 `token_budget` 字段被传入的是成本预算（如 `budget_limit` / `remaining_budget`），导致命名与实际语义不一致。

**证据**

- `runtime/models/model-router.ts:97-130`
- `runtime/engine/orchestrator-runtime.ts:684-689`
- `runtime/engine/orchestrator-runtime.ts:831-837`

### M6. Control Plane 的 `?token=` 鉴权方式不适合生产环境

**问题**

dashboard 页面在启用 token 时，通过 URL query 参数传递 `?token=...`。

**证据**

- `runtime/server/control-plane.ts:387-396`

**影响**

- token 容易进入浏览器历史、代理日志、referrer 和截图
- 不符合生产控制面的基本鉴权习惯

**建议**

统一使用 header-based auth 或 session/cookie/token exchange，不再把凭证放进 URL。

### M7. 质量报告评分过于粗粒度

**问题**

`finalizeRun()` 的等级几乎只按 failed task 数量给 `A/B/C`，与 gate 风险、critical findings、审批、重试成本的结合很弱。

**证据**

- `runtime/engine/orchestrator-runtime.ts:1353-1366`

## 4. 技术债主题归纳

### 4.1 文档成熟度先于实现成熟度

README、架构文档和能力文档把大量模块标成了 GA / production-ready，但源码仍保留多个 MVP 级实现特征。

### 4.2 结构化对象先于执行硬约束

现在系统已经拥有很多漂亮的数据结构：

- `TaskGraph`
- `OwnershipPlan`
- `TaskContract`
- `GateResult`
- `ApprovalRequest`

但这些对象还没有全部变成强 enforcement。

### 4.3 治理能力在“接口层”比在“执行层”成熟

控制面、审批、RBAC、审计对象都已出现；真正薄弱的是 worker 执行边界和并发写冲突处置。

## 5. 测试覆盖的优势与盲区

### 5.1 已覆盖较好

- 状态机
- schema
- planner 纯函数
- ownership / scheduler 纯函数
- 持久化抽象
- runtime happy path
- approval / resume 回归

### 5.2 关键盲区

1. 没有验证 `max_model_tier` 在 retry 场景中的硬约束。
2. 没有验证 policy `priority` 和 `log` 语义。
3. 没有验证 conflicting write 在真实并发执行中的阻断。
4. 没有验证 result 持久化顺序导致的 durable state 偏差。
5. 没有验证 PR provider 在非当前 cwd 场景下的行为。
6. 没有验证空 context pack 对 worker 质量的影响。
7. 没有验证 run-level gate 聚合证据链是否真实有效。
8. 没有验证 hook 是否能真正改变编排行为。

## 6. 修复优先级建议

### P0：先修“核心承诺失真”

1. Ownership reservation + MergeGuard 主链集成
2. Worker 强执行边界
3. Context Pack 主链打通
4. `max_model_tier` 全链路 enforcement
5. Result 持久化时序修复

### P1：再修“治理语义失真”

1. Policy priority / log / strictest enforcement
2. Control plane task retry / graph truth source
3. Resume 过程中的 gate/audit 连续性
4. Gate 分类重构：hard gates vs heuristic signals

### P2：最后修“体验与扩展性”

1. repo-aware intent grounding
2. richer quality scoring
3. provider/cwd abstraction
4. capability/tool policy 的真正执行化

## 7. 总判断

当前 `parallel-harness` 不是“不可用”，而是“**可以跑，但还不能把自己的核心产品承诺当成既定事实**”。

如果只把它当作一个有审计、有审批、有 dashboard 的 orchestrator skeleton，它已经达到相当不错的完成度；但如果把它当作“行业级高保真并行工程 harness”，那么当前最大的缺口仍集中在：

- 并发写安全
- worker 硬边界
- 最小上下文真正落地
- 独立验证不被启发式代理稀释

这些缺口一旦补齐，项目的差异化价值就会显著提升。
