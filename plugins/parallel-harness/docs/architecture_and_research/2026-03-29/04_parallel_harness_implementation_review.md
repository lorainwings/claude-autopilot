# 04. 当前 parallel-harness 实现评审

## 1. 评审范围与验证方式

本评审基于 `2026-03-29` 当前仓库实现，重点覆盖：

- 需求理解与规划
- 并行调度与所有权
- 上下文供给
- worker 执行与治理
- gate / verification
- 持久化 / 恢复 / 控制面
- 文档与实现一致性

本地验证结果：

- `cd plugins/parallel-harness && bun test`
  - `219 pass / 0 fail / 499 expect()`
- `cd plugins/parallel-harness && bunx tsc --noEmit`
  - 通过

结论很明确：

**项目已经是可运行、可测试的骨架，但还不是可以支撑“研发全流程稳定交付”的强闭环实现。**

## 2. 总体判断

优点：

- 架构方向正确
- 生命周期主链路完整
- 状态机、持久化、审批、控制面都有雏形
- 测试覆盖了大量纯逻辑路径

核心问题：

- 多个“产品承诺”仍停留在文档层或接口层
- 执行期强约束没有彻底落地
- gate 体系与 context 体系还不够高保真
- 并发安全和 fail-closed 还存在关键漏洞

## 3. 发现列表

### 3.1 Critical

#### C1. run-level gate 阻断后，终态收敛可能错误地把 `blocked` 判成 `succeeded`

证据：

- `runtime/engine/orchestrator-runtime.ts:1077-1100`
- `runtime/engine/orchestrator-runtime.ts:1284-1308`
- `runtime/engine/orchestrator-runtime.ts:548-555`

问题：

- `runLevelGates()` 会把 run 状态设置为 `blocked`
- `determineFinalStatus()` 先按 attempt 成功率推导终态，再最后检查 `execution.status === "blocked"`
- 如果所有 task 成功但 run-level gate 阻断，后续可能尝试走 `blocked -> succeeded`

影响：

- 破坏 fail-closed 语义
- 可能触发非法状态迁移
- 结果、审计、控制面都可能出现错误最终态

结论：

这是当前最需要优先修复的状态机正确性问题。

#### C2. “严格文件所有权隔离”并没有在真实并发执行中成立

证据：

- `runtime/engine/orchestrator-runtime.ts:771-817`
- `runtime/orchestrator/ownership-planner.ts:67-126`
- `runtime/guards/merge-guard.ts:71-235`
- `runtime/engine/orchestrator-runtime.ts` 中无 `MergeGuard` 调用

问题：

- 调度器按 batch 并发执行任务
- ownership 冲突只有规划期检测和单任务 post-check
- `MergeGuard` 已实现，但没有进入主执行链
- general task 还可能退化到项目根目录级别 allowed path

影响：

- 同一工作树内仍可能发生并发写冲突
- 最终汇总前没有全局冲突收敛
- README 中“严格所有权隔离”表述与实现不符

#### C3. Worker 治理仍是软约束，不是强执行沙箱

证据：

- `runtime/workers/worker-runtime.ts:275-319`
- `runtime/engine/orchestrator-runtime.ts:1745-1826`

问题：

- 允许/禁止路径主要通过 prompt 提示
- tool policy 仅通过 env 注入，没有 runtime enforcement
- 修改文件路径大量依赖 worker 自报和文本解析
- 真正的路径沙箱校验发生在执行之后

影响：

- 越权写入不能被事前阻止
- 工具使用边界不可靠
- 如果 worker 未如实上报修改路径，治理会被绕过

### 3.2 High

#### H1. 上下文打包接口存在，但主链路默认拿不到真实项目文件

证据：

- `runtime/engine/orchestrator-runtime.ts:933-935`
- `runtime/engine/orchestrator-runtime.ts:1279-1282`
- `runtime/session/context-packager.ts:55-103`

问题：

- `packContext()` 被调用
- `getAvailableFiles()` 永远返回空数组

影响：

- “最小上下文包”退化成“只有任务描述”
- 代码生成质量更加依赖 worker 自行搜索与随机探索
- 上下文治理与复现能力不足

#### H2. 成功/失败收敛逻辑忽略未尝试任务

证据：

- `runtime/engine/orchestrator-runtime.ts:811`
- `runtime/engine/orchestrator-runtime.ts:1284-1308`
- `runtime/engine/orchestrator-runtime.ts:1314-1333`

问题：

- `determineFinalStatus()` 只统计 `completed_attempts` 中出现过的任务
- 预算中断或依赖跳过时，任务可能没有任何 attempt
- `finalizeRun()` 才会把这些任务标记为 `skipped`

影响：

- `RunResult` 里存在 skipped tasks，但 final status 仍可能是 `succeeded`
- 影响控制面、审计和 PR 报告可信度

#### H3. 结果持久化时序不一致

证据：

- `runtime/engine/orchestrator-runtime.ts:548-555`
- `runtime/engine/orchestrator-runtime.ts:563-625`
- `runtime/engine/orchestrator-runtime.ts:1460-1467`

问题：

- 首次 `saveResult(result)` 发生在最终状态和 PR 产物完全回填前
- 恢复流程与正常流程的持久化时序也不一致

影响：

- durable store 中的数据不一定是最终真相
- 控制面读取结果可能与内存中的最终结果不一致

#### H4. 模型 tier 上限只在计划阶段裁剪，重试阶段可能绕过

证据：

- `runtime/engine/orchestrator-runtime.ts:679-710`
- `runtime/engine/orchestrator-runtime.ts:829-839`

问题：

- plan 阶段对 `max_model_tier` 做了裁剪
- attempt 重试时重新 `routeModel()`，未再次统一裁剪

影响：

- 预算与风险控制项可能在 retry 时失效

#### H5. planner 仍然缺乏 repo-aware grounding

证据：

- `runtime/orchestrator/intent-analyzer.ts:176-218`
- `runtime/orchestrator/task-graph-builder.ts:112-214`

问题：

- 域识别依赖关键词
- `known_modules` 匹配简单
- task 到 domain 的映射是 round-robin
- 依赖推断主要依赖路径重叠与关键词

影响：

- 任务图质量和 ownership 质量都不稳定
- 并行计划无法真正基于代码库结构

#### H6. Gate System 有 9 类，但多类 gate 仍是启发式代理项

证据：

- `runtime/gates/gate-system.ts:355-412` `ReviewGateEvaluator`
- `runtime/gates/gate-system.ts:419-473` `SecurityGateEvaluator`
- `runtime/gates/gate-system.ts:480-545` `CoverageGateEvaluator`
- `runtime/gates/gate-system.ts:605-647` `DocumentationGateEvaluator`
- `runtime/gates/gate-system.ts:654-715` `PerfGateEvaluator`

问题：

- review 主要看摘要长度、文件数、是否改测试
- security 主要看敏感文件名模式
- coverage 在无法解析覆盖率时退化为是否改测试文件
- documentation 和 perf 主要是信号，不是高保真验证

影响：

- 文档写“9 类门禁系统”没有问题
- 但如果宣称这些 gate 全部已达到 GA 级强验证，会高估成熟度

### 3.3 Medium

#### M1. 控制面在启用 RBAC 后可能无法正常执行写操作

证据：

- `runtime/server/control-plane.ts:229-250`
- `runtime/engine/orchestrator-runtime.ts:1674-1684`

问题：

- 控制面固定以 `control-plane` 身份调用 runtime
- `requirePermission()` 创建的 actor 默认无角色
- 开启 RBAC 时，这些写操作可能统一报权限不足

影响：

- cancel / approve / reject 等控制面能力在治理模式下可能不可用

#### M2. 持久化文件写入缺少目录保证和原子性

证据：

- `runtime/persistence/session-persistence.ts:69-118`

问题：

- `FileStore.set()` 直接 `Bun.write`
- 没有确保父目录存在
- 没有临时文件 + rename 的原子写策略

影响：

- 新环境首次 durable store 写入存在失败风险
- 崩溃时可能产生部分写入

#### M3. 文档与实现存在漂移

证据：

- `README.zh.md:3`
- `README.zh.md:22`
- `docs/architecture/overview.zh.md`
- `runtime/observability/event-bus.ts`

问题：

- README 标题 `v1.1.1`，版本信息仍写 `v1.0.0 (GA)`
- 架构图中部分模块被描述得比真实执行链更成熟
- 状态机、metrics、verifier swarm 等描述与实现有落差

影响：

- 对外叙事风险高
- 销售、交付、内部判断都容易被误导

## 4. 测试覆盖评估

当前测试体系的优点：

- 纯逻辑模块覆盖比较完整
- 状态机、gate、governance、persistence、scheduler 等单测较充分
- 基础集成测试能验证主流程跑通

主要缺口：

- 集成测试默认关闭 gates：`tests/integration/runtime.test.ts:68`
- 主要使用 mock worker，不覆盖真实 CLI、真实文件系统并发、真实 git diff、真实 PR provider
- 不覆盖 merge guard 未接线问题
- 不覆盖 run-level gate 阻断后的终态正确性
- 不覆盖 durable store 新目录首次写入

因此当前测试更适合描述为：

**对架构骨架的逻辑验证充分，对“真实执行风险”的验证不足。**

## 5. 商业化视角的风险结论

如果按你们的目标去做“全流程稳定编排插件”，当前版本最大的商业化风险不是功能少，而是：

1. 营销承诺高于执行闭环
2. 并行安全承诺高于真实隔离能力
3. gate 完整度高于 gate 证据质量
4. 文档成熟度高于代码成熟度

## 6. 结论

当前 `parallel-harness` 最值得肯定的是方向：它已经不是普通 agent demo，而是明显在往治理型工程控制面走。

但要达到你们想要的“产品开发全流程稳定插件”，必须先补上五个关键闭环：

1. fail-closed 状态机
2. 真正的执行隔离与 write-set reservation
3. 真实代码证据驱动的上下文供给
4. evidence-based gate 与 merge guard 主链接线
5. durable、可回放、与治理兼容的控制面
