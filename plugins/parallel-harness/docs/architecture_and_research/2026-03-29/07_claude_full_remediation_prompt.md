# 07. 可直接交给 Claude 的全量修复执行提示词

以下内容可直接作为 Claude Code / Claude agent 的执行提示词使用。

---

你现在不是做评审，也不是做规划，而是对当前仓库 `plugins/parallel-harness` 执行一次 **全量修复工程**。

## 任务目标

将 `parallel-harness` 从当前“可运行的 orchestrator skeleton”修复为“可以支撑 AI 在产品开发全流程中稳定编排与交付”的高稳定 harness 插件。

本次任务必须覆盖整个全流程，不允许只修高优先级，不允许留下主要模块到后续版本。

你必须完整修复以下能力域：

1. Requirement Grounding 与需求契约
2. Repo-aware Planner 与 Task Graph V2
3. Ownership Reservation 与 Safe Scheduler
4. Context Planner / Context Envelope V2
5. Execution Proxy / Worker 强约束执行
6. Gate System V2 / Independent Verification / Merge Guard
7. Persistence / Result Truth / Resume / Replay
8. Control Plane / Governance / Approval 闭环
9. Reporting / Evidence Aggregation / PR Artifacts
10. 测试体系、回归基线、发布前验证

## 必须阅读的仓库文档

先完整阅读以下文档，并以它们作为统一施工依据：

- `plugins/parallel-harness/docs/architecture_and_research/01_lifecycle_architecture_design.md`
- `plugins/parallel-harness/docs/architecture_and_research/02_ai_limitations_mitigation_strategy.md`
- `plugins/parallel-harness/docs/architecture_and_research/03_harness_best_practices_and_competitors.md`
- `plugins/parallel-harness/docs/architecture_and_research/04_parallel_harness_implementation_review.md`
- `plugins/parallel-harness/docs/architecture_and_research/05_parallel_harness_enhancement_blueprint.md`
- `plugins/parallel-harness/docs/architecture_and_research/06_full_remediation_execution_manual.md`

## 执行约束

### 约束 1

你不能只输出计划，必须真实修改代码、测试和文档，直到本轮任务完成。

### 约束 2

你不能只修局部问题。所有 10 个能力域都必须完成落地。

### 约束 3

你不能把重要缺口留作 TODO、future work 或 follow-up。若有无法完成项，必须明确说明阻塞原因并尽量解决。

### 约束 4

你不能用 README 更新代替实现修复。

### 约束 5

每个能力域修复后，必须补对应测试。最终必须运行：

- `cd plugins/parallel-harness && bun test`
- `cd plugins/parallel-harness && bunx tsc --noEmit`

### 约束 6

在执行过程中，所有设计与实现必须符合以下原则：

- graph-first
- least-context
- least-write
- independent-verification
- durable-governance

## 详细施工步骤

按以下顺序施工，但不能跳过任何部分：

### Step 1. 修复运行时正确性与结果真相

必须完成：

- 修 run-level gate blocked 后的终态错误
- 修 skipped tasks 仍可能被判为 succeeded 的问题
- 修 `RunResult` 持久化时序问题
- 修 `approveAndResume()` 与正常流程的结果收敛一致性

完成后新增回归测试。

### Step 2. 落地 Requirement Grounding

必须完成：

- 新增结构化 `RequirementGrounding`
- 在 plan 阶段前接入
- 支持 `acceptance_matrix`
- 高歧义请求可阻断或要求审批
- grounding 写入 run plan、audit、report

完成后新增测试。

### Step 3. 重构 Planner 为 Repo-aware Planner

必须完成：

- 去掉以关键词和 round-robin 为主的 task/domain 映射
- 引入 repo 结构、模块、测试映射
- 生成 task graph v2
- 任务包含 read-set、write-set、artifact outputs、verifier plan

完成后新增测试。

### Step 4. 修 Ownership 与 Scheduler

必须完成：

- Ownership 从路径建议升级为 reservation hard constraint
- 任意 write-set 冲突任务不能同批并发
- 高风险任务降并发
- 调度器与 reservation solver 打通

完成后新增测试。

### Step 5. 修 Context 主链

必须完成：

- `getAvailableFiles()` 不再返回空列表
- 引入真实 evidence loader
- Context Envelope V2 支持 evidence、occupancy、compaction policy
- verifier context 与 author context 分离

完成后新增测试。

### Step 6. 修 Worker 执行模型

必须完成：

- 引入 execution proxy 或等价强约束执行器
- 模型 tier 映射为真实 provider/model
- tool allowlist/denylist 变成强 enforcement
- 文件系统访问受 sandbox 或隔离 worktree 限制
- 生成 execution attestation
- 不再依赖 `MODIFIED:` 文本作为唯一真实来源

完成后新增测试。

### Step 7. 重构 Gate System

必须完成：

- 将 gate 拆成 hard gates 与 signal gates
- merge guard 进入主链并具备 blocking 语义
- review/security/coverage/perf/documentation 的结论必须更高保真
- 支持 evidence bundle
- 引入 anti-gaming signals

完成后新增测试。

### Step 8. 修 Persistence / Replay / Resume

必须完成：

- `FileStore` 支持创建目录与原子写入
- replay timeline 更完整
- checkpoint / resume 恢复真实上下文与真相源
- run result、gate results、audit timeline durable 可一致读取

完成后新增测试。

### Step 9. 修 Control Plane / Governance

必须完成：

- control-plane actor 与 RBAC 兼容
- approve/reject/cancel/retry 在治理模式下正常
- control plane 读取 runtime 真相源
- UI/接口至少返回 run timeline、gate panel、cost panel、approval status

完成后新增测试。

### Step 10. 修报告与交付物

必须完成：

- 新增 run evidence aggregator
- 最终报告可引用 evidence refs
- PR summary / review comments / quality report 与 gate/evidence 一致
- 面向产品设计、架构设计、实现、测试、报告的阶段化输出能力进入统一生命周期

完成后新增测试。

## 输出要求

当你完成全部施工后，必须输出：

1. 完成了哪些能力域
2. 修改了哪些文件
3. 新增了哪些测试
4. `bun test` 和 `bunx tsc --noEmit` 的结果
5. 仍存在的风险

你不能在完成前停止。

---

如果你是 Claude，请从阅读 `06_full_remediation_execution_manual.md` 开始，然后立即进入代码修改。
