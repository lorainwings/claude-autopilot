# 06. parallel-harness 全量修复执行手册

## 1. 文档定位

本文不是蓝图，也不是问题报告，而是给执行型 AI 或工程团队直接使用的 **全量修复施工手册**。

适用场景：

- 你要把 `parallel-harness` 做一次完整修复
- 不接受“只修 P0/P1”
- 不接受只做文档层整改
- 需要从需求理解、规划、调度、上下文、执行、门禁、持久化、控制面、报告、测试十个方面同时补齐

本文默认目标是：

**在一次连续工程执行中，把当前插件从“可运行骨架”提升到“研发全流程可依赖的高稳定 harness 插件”。**

## 2. 执行原则

### 2.1 不做优先级取舍

本手册中的所有工作流都必须完成，不能只做高优先级部分。允许按依赖顺序执行，但不允许把某些模块永久跳过。

### 2.2 不接受“文档修复代替实现修复”

以下类型的工作不算完成：

- 只改 README
- 只补注释
- 只新增 TODO
- 只新增空接口
- 只补测试但不修逻辑

### 2.3 必须边改边验证

每个工作流都要同时完成：

- 代码实现
- 单元测试
- 集成测试
- 文档同步
- 可观测性字段补齐

### 2.4 必须保留执行证据

每个工作流完成后要输出：

- 改动文件清单
- 新增测试清单
- 风险说明
- 未完成项清单

## 3. 全量修复范围

本次全量修复必须覆盖以下 10 个工作流：

1. Requirement Grounding 与需求契约
2. Repo-aware Planner 与 Task Graph V2
3. Ownership Reservation 与 Safe Scheduler
4. Context Planner / Context Envelope V2
5. Execution Proxy / Worker 强约束执行
6. Gate System V2 / Independent Verification / Merge Guard 接线
7. Persistence / Result Truth / Resume / Replay 修复
8. Control Plane / Governance / Approval 闭环修复
9. Reporting / Evidence Aggregation / 生命周期报告
10. 测试体系、回归基线、发布前验证

## 4. 仓库级完成定义

全量修复完成必须满足以下条件：

### 4.1 运行时正确性

- run-level gate 阻断后，最终状态绝不可能被写成 `succeeded`
- 未尝试任务存在时，最终状态绝不能写成完全成功
- `RunResult` durable store 中的数据必须与最终内存态一致

### 4.2 并行安全

- 同批任务不能共享冲突 write-set
- worker 不在同一个无隔离工作树中并发写入
- merge guard 必须进入主链，而不是独立工具类

### 4.3 上下文治理

- 每个 task 必须拥有真实 evidence 输入
- 每次 attempt 必须记录上下文占用率与压缩策略
- verifier context 与 author context 必须分离

### 4.4 门禁质量

- hard gates 必须由真实工具或独立 verifier 产生证据
- signal gates 不能伪装成强门禁
- gate 结果必须可回放、可追溯到 evidence

### 4.5 治理闭环

- RBAC 开启时 control plane 的 approve/reject/cancel 仍可正常使用
- 敏感操作必须可审批、可审计
- replay / resume / cancel 全链路可用

### 4.6 工程验证

- `bun test` 全绿
- `bunx tsc --noEmit` 全绿
- 新增真实集成测试覆盖 gate、worker、resume、durable store、control plane

## 5. 详细执行步骤

## Workstream 1. Requirement Grounding

### 目标

把当前自然语言意图解析前移为结构化需求契约，避免需求理解浅层化。

### 需要新增或修改

- 新增 `runtime/orchestrator/requirement-grounding.ts`
- 在 `runtime/orchestrator/index.ts` 导出
- 在 `runtime/engine/orchestrator-runtime.ts` 的 plan 阶段接入
- 如有必要，扩展 `runtime/schemas/ga-schemas.ts`

### 具体实施

1. 新增 `RequirementGrounding` 数据结构：
   - `restated_goal`
   - `acceptance_matrix`
   - `ambiguity_items`
   - `assumptions`
   - `impacted_modules`
   - `required_artifacts`
   - `required_approvals`
2. 在 `executeRun -> planPhase` 前先调用 grounding。
3. 如果 `ambiguity_items` 超过阈值，禁止进入 dispatch，转入 `awaiting_approval` 或 `blocked`。
4. 将 grounding 结果写入：
   - `RunPlan`
   - `AuditTrail`
   - 后续 gate 输入

### 验收标准

- 所有 run 都具备结构化需求契约
- 高歧义请求不会直接开始 worker 执行
- 需求报告与 gate 可以引用统一 acceptance matrix

### 必补测试

- grounding 正常产出
- 歧义阻断
- acceptance matrix 进入 run plan
- 审批恢复后 grounding 不丢失

## Workstream 2. Repo-aware Planner 与 Task Graph V2

### 目标

把 planner 从关键词启发式提升为基于仓库证据的任务规划器。

### 需要新增或修改

- `runtime/orchestrator/intent-analyzer.ts`
- `runtime/orchestrator/task-graph-builder.ts`
- 可能新增：
  - `runtime/orchestrator/repo-grounding.ts`
  - `runtime/orchestrator/test-impact-analyzer.ts`

### 具体实施

1. 读取项目文件树、模块列表、已知测试文件映射。
2. 为每个 task 生成：
   - `phase`
   - `objective`
   - `depends_on`
   - `read_set`
   - `write_set`
   - `artifact_outputs`
   - `verifier_plan`
3. 删除当前 round-robin domain 分配逻辑。
4. 依赖推断从“路径重叠 + schema关键词”升级为：
   - artifact dependency
   - module dependency
   - interface dependency
5. 规划阶段产出 test obligations。

### 验收标准

- 任务图不再主要依赖关键词猜测
- 每个 task 都有明确读写边界
- task graph 与 test obligations 可用于后续调度和 gate

### 必补测试

- repo-aware module grounding
- dependency inference
- task graph v2 schema
- test obligations generation

## Workstream 3. Ownership Reservation 与 Safe Scheduler

### 目标

把所有权从“事后检查”升级为“调度前硬约束”。

### 需要新增或修改

- `runtime/orchestrator/ownership-planner.ts`
- `runtime/scheduler/scheduler.ts`
- `runtime/guards/merge-guard.ts`
- `runtime/engine/orchestrator-runtime.ts`

### 具体实施

1. 给 `OwnershipPlan` 增加：
   - `read_set`
   - `write_set`
   - `reserved_paths`
   - `merge_guard_only`
2. 调度器在生成 batch 之前先做 reservation solve。
3. 任意 write-set 相交任务禁止进入同一 batch。
4. 高风险任务强制降低 batch 并发。
5. merge guard 必须在以下位置执行：
   - task 全部完成后
   - PR 创建前
   - release readiness 前

### 验收标准

- 同批任务无 write-write 冲突
- merge guard 真正在主链阻断
- “严格所有权隔离”具备可执行含义

### 必补测试

- overlapping write-set block
- reservation fallback to serial
- merge guard in runtime chain
- concurrent batch conflict prevention

## Workstream 4. Context Planner / Envelope V2

### 目标

让上下文包真正进入主链，而不是停留在接口壳。

### 需要新增或修改

- `runtime/session/context-packager.ts`
- `runtime/session/context-pack.ts`
- `runtime/engine/orchestrator-runtime.ts`
- 可能新增：
  - `runtime/session/evidence-loader.ts`
  - `runtime/session/context-metrics.ts`

### 具体实施

1. 将 `getAvailableFiles()` 从空实现替换为真实 evidence loader。
2. context envelope 至少包含：
   - policy capsule
   - requirement capsule
   - dependency outputs
   - evidence items
   - token budget
   - occupancy ratio
   - compaction policy
3. 根据 task 类型构造不同上下文模板：
   - design
   - implementation
   - testing
   - review
   - reporting
4. verifier 使用独立 context envelope，不能直接复用 author context。

### 验收标准

- worker 输入中有真实文件/片段/证据
- 每次 attempt 有 occupancy 记录
- 重试时支持 context compaction 策略切换

### 必补测试

- evidence loading
- occupancy calculation
- compaction policy switching
- verifier context isolation

## Workstream 5. Execution Proxy / Worker 强约束执行

### 目标

将当前 prompt/env 软约束改为强执行代理。

### 需要新增或修改

- `runtime/workers/worker-runtime.ts`
- `runtime/engine/orchestrator-runtime.ts`
- `LocalWorkerAdapter` 或新增 `ExecutionProxy`
- 必要时新增：
  - `runtime/workers/execution-proxy.ts`
  - `runtime/workers/execution-attestation.ts`

### 具体实施

1. 模型 tier 必须映射为真实 provider/model。
2. 工具 allowlist / denylist 必须在执行器里强 enforcement。
3. 文件访问必须受 sandbox 或 worktree 隔离。
4. 生成 `ExecutionAttestation`：
   - actual model
   - tool calls
   - modified files
   - diff ref
   - sandbox violations
   - token usage
5. 不允许只依赖 `MODIFIED:` 文本解析判断写入路径。

### 验收标准

- worker 越界写入会被执行期阻止或明确记为 violation
- tool policy 不是提示语义，而是执行语义
- diff attestation 可用于 gate 与报告

### 必补测试

- tool denylist enforcement
- sandbox violation
- actual diff capture
- model tier mapping

## Workstream 6. Gate System V2 / Independent Verification / Merge Guard

### 目标

把当前 9 类 gate 从“混合真实检查 + 启发式代理”升级为分层验证系统。

### 需要新增或修改

- `runtime/gates/gate-system.ts`
- `runtime/guards/merge-guard.ts`
- `runtime/verifiers/*`
- `runtime/engine/orchestrator-runtime.ts`
- 必要时新增：
  - `runtime/gates/run-evidence-aggregator.ts`

### 具体实施

1. 拆分为：
   - hard gates
   - signal gates
2. hard gates 至少包含：
   - test
   - lint/type/build
   - policy
   - security scan
   - merge guard
   - hidden regression
   - release readiness
3. 所有 gate 统一输出 evidence bundle。
4. 将 merge guard 纳入 hard gate。
5. 把 review、documentation、perf 等区分为 signal 或更高保真实现。

### 验收标准

- 每个 blocking verdict 都有证据引用
- gate 结果可回放
- signal gate 不会伪装成 hard gate

### 必补测试

- hard gate block behavior
- evidence bundle generation
- merge guard as hard gate
- hidden regression plumbing

## Workstream 7. Persistence / Result Truth / Resume / Replay

### 目标

确保 durable store 中的事实与最终运行结果完全一致，并支持真实恢复。

### 需要新增或修改

- `runtime/persistence/session-persistence.ts`
- `runtime/engine/orchestrator-runtime.ts`
- `runtime/server/control-plane.ts`

### 具体实施

1. 修正 `RunResult` 的写入顺序，保证最终状态、PR 产物、质量报告全部回填后再持久化。
2. `FileStore` 增加：
   - 自动创建父目录
   - 原子写入
   - 损坏恢复策略
3. replay 必须可回放：
   - task timeline
   - gate timeline
   - approval timeline
   - cost timeline

### 验收标准

- durable result 始终等于最终真相
- 新目录环境首次持久化可正常工作
- resume / replay 有完整运行证据

### 必补测试

- durable result truth
- file store first-write
- replay timeline
- resume after blocked run

## Workstream 8. Control Plane / Governance / Approval

### 目标

让控制面在开启治理后仍然可用，并成为全流程的可操作入口。

### 需要新增或修改

- `runtime/server/control-plane.ts`
- `runtime/governance/governance.ts`
- `runtime/engine/orchestrator-runtime.ts`

### 具体实施

1. 定义 control-plane actor 身份与角色映射。
2. 修复 approve/reject/cancel 在 RBAC 模式下的权限模型。
3. 控制面展示：
   - run summary
   - task graph
   - gate panel
   - approval inbox
   - cost dashboard
   - replay / resume / cancel
4. 控制面读到的结果必须来自 runtime 真相源，而不是落后缓存。

### 验收标准

- governance 模式下 control plane 写操作可用
- 审批动作可完整记录到审计链
- 运行结果与控制面展示一致

### 必补测试

- RBAC control-plane approve
- cancel under governance
- control-plane truth-source consistency

## Workstream 9. Reporting / Evidence Aggregation

### 目标

让报告生成从“总结文本”升级为“证据驱动的专业交付文档”。

### 需要新增或修改

- `runtime/engine/orchestrator-runtime.ts`
- `runtime/integrations/pr-provider.ts`
- 可能新增：
  - `runtime/reporting/report-builder.ts`
  - `runtime/reporting/evidence-aggregator.ts`

### 具体实施

1. 聚合：
   - execution attestation
   - gate results
   - coverage delta
   - approval chain
   - cost ledger
   - modified files
2. 报告支持阶段化章节：
   - requirement grounding
   - architecture/design
   - implementation
   - testing and quality
   - release readiness
3. 每个关键结论都带 evidence refs。

### 验收标准

- PR summary 和最终报告不再只是自然语言总结
- 报告可追溯到真实证据

### 必补测试

- report evidence references
- quality summary consistency
- PR artifact completeness

## Workstream 10. 测试体系与发布前验证

### 目标

让测试覆盖真实风险，而不是只覆盖骨架逻辑。

### 需要新增或修改

- `tests/unit/*`
- `tests/integration/*`
- 如有必要新增 `tests/e2e/*`

### 具体实施

1. 新增真实风险测试：
   - run-level gate blocked final status
   - skipped tasks final status
   - merge guard in runtime
   - context evidence loading
   - sandbox enforcement
   - durable file store
   - control-plane governance
2. 集成测试不再默认关闭所有 gate，至少保留一组真实 gate 场景。
3. 为全量修复建立 release verification matrix。

### 验收标准

- 新增测试覆盖所有本轮修复项
- 回归路径可自动验证

## 6. 最终交付清单

执行完成后，必须同时提交：

1. 代码实现
2. 测试补齐
3. 文档同步
4. 报告与证据聚合能力
5. 最终验证记录

## 7. 完成后必须输出的总结格式

执行者完成全部工作后，必须输出以下结构：

1. 完成范围
2. 修改的模块与文件
3. 新增测试
4. 仍存风险
5. 验证结果

## 8. 对 Claude 的执行要求

如果把本文交给 Claude 或类似 coding agent，必须附加这些硬要求：

- 不允许只修局部高优先级问题
- 不允许把未完成工作写成未来建议
- 不允许跳过测试补齐
- 不允许用文档掩盖实现缺口
- 每个工作流都要真实改代码并验证
