# 09. 可直接交给 Claude 的二次修复执行提示词

以下内容可直接作为 Claude Code / Claude agent 的执行提示词使用。

---

你现在需要继续修复 `plugins/parallel-harness`，目标是完成上一轮修复未真正闭环的问题。

不要重新做宏观方案，不要只写文档，不要只补测试。你必须直接改代码、补测试、运行验证，并把所有修改落到仓库里。

## 任务范围

本轮必须完整覆盖以下 8 个问题，不能只修一部分：

1. 并行调度冲突检测仍不正确
2. `ExecutionProxy` 未接入主链
3. `MergeGuard` 未接入主链
4. `determineFinalStatus()` 仍会忽略未尝试任务
5. evidence loader 对真实任务无效或低效
6. `RequirementGrounding` 还没有成为 plan truth
7. `RunResult` durable truth 仍可能落后于最终 PR 结果
8. control plane 与 RBAC 治理兼容性仍未修复

## 必须先阅读的文档

先阅读以下文档，并以它们作为统一施工依据：

- `plugins/parallel-harness/docs/architecture_and_research/04_parallel_harness_implementation_review.md`
- `plugins/parallel-harness/docs/architecture_and_research/06_full_remediation_execution_manual.md`
- `plugins/parallel-harness/docs/architecture_and_research/08_claude_followup_remediation_execution_plan.md`

## 执行原则

### 原则 1

不能只补测试记录问题，必须修实现。

### 原则 2

不能只补接口或新增未接线模块。凡是新增能力，必须真实进入 runtime 主链；若不接入，则删除对应占位模块，避免继续制造假能力。

### 原则 3

不能只修 happy path。每个问题都必须覆盖：

- 正常路径
- 冲突路径
- 阻断路径
- resume / persistence 路径

### 原则 4

完成代码后必须同步更新以下文档。如果能力尚未真正落地，文档必须降级表述，不能继续宣传已完成：

- `plugins/parallel-harness/README.md`
- `plugins/parallel-harness/README.zh.md`
- `plugins/parallel-harness/docs/architecture/overview.md`
- `plugins/parallel-harness/docs/architecture/overview.zh.md`

## 详细施工任务

按以下顺序执行，不允许跳过。

### Workstream D. 修正最终状态判定逻辑

问题：

`determineFinalStatus()` 仍只看 `completed_attempts` 中出现过的 task，未尝试任务仍可能被忽略。

必改文件：

- `plugins/parallel-harness/runtime/engine/orchestrator-runtime.ts`
- `plugins/parallel-harness/tests/unit/state-machine-eventbus.test.ts`
- `plugins/parallel-harness/tests/integration/runtime.test.ts`

修复要求：

1. 最终状态判定必须基于 `plan.task_graph.tasks` 的全集，而不是只基于 attempt 集合。
2. 至少区分：
   - 全部成功
   - 部分成功
   - 全部失败
   - 被 block
   - 有 skipped tasks
3. 当存在 skipped task 时，不能返回完全成功，除非这些 skipped 在语义上被明确标记为允许跳过。
4. 必要时调整方法签名，把 `plan` 传入 `determineFinalStatus()`。

新增测试：

- 有 skipped task 时不会判定为 `succeeded`
- 有 blocked status 时仍优先返回 `blocked`
- 预算中断后最终状态正确

完成标准：

- `RunResult.skipped_tasks` 与 `final_status` 语义一致

### Workstream A. 修正并行调度冲突检测

问题：

当前 `scheduler.ts` 只用 `exclusive_paths.includes(...)` 判断冲突，不能识别前缀重叠、目录包含、glob 匹配等真实 write-set 冲突。

必改文件：

- `plugins/parallel-harness/runtime/scheduler/scheduler.ts`
- `plugins/parallel-harness/runtime/orchestrator/ownership-planner.ts`
- `plugins/parallel-harness/tests/unit/scheduler.test.ts`
- `plugins/parallel-harness/tests/unit/remediation.test.ts`

修复要求：

1. 不要在 scheduler 里重新发明一套简化冲突判断。
2. 将 ownership 层已有的路径重叠语义抽成可复用函数，供 scheduler 使用。
3. 调度器必须能识别：
   - 相同文件
   - 目录包含
   - 前缀覆盖
   - `/**` / `/*` glob 重叠
4. 如果存在冲突：
   - 禁止进入同一批次
   - 如果 ready 集里所有任务互相冲突，则降级为串行

新增测试：

- `src/` 与 `src/a/` 不能同批
- `src/**` 与 `src/auth/login.ts` 不能同批
- 完全不相交路径仍可同批
- 冲突全集 ready 时自动串行退化

完成标准：

- scheduler 的冲突判断语义与 ownership planner 一致
- 真实 write-set 冲突不会进入同批

### Workstream B. 将 ExecutionProxy 接入运行时主链

问题：

`runtime/workers/execution-proxy.ts` 目前只是未使用的占位模块，runtime 仍直接调用旧的 `workerController.execute(...)`。

必改文件：

- `plugins/parallel-harness/runtime/workers/execution-proxy.ts`
- `plugins/parallel-harness/runtime/workers/worker-runtime.ts`
- `plugins/parallel-harness/runtime/engine/orchestrator-runtime.ts`
- `plugins/parallel-harness/tests/unit/worker-runtime.test.ts`
- `plugins/parallel-harness/tests/unit/remediation.test.ts`

修复要求：

1. `ExecutionProxy` 不能再返回假 `output`。
2. 必须让 runtime 真正通过 execution proxy 执行 worker。
3. execution proxy 至少要做：
   - model tier -> model/provider 映射
   - 工具策略注入
   - 路径沙箱信息传递
   - attestation 生成
4. `WorkerExecutionController` 与 `ExecutionProxy` 之间职责要清晰：
   - controller 负责 attempt 生命周期、超时、快照、路径校验
   - proxy 负责执行代理、模型/工具/沙箱绑定、attestation
5. attestation 必须真实进入结果流或审计流，不能生成后丢弃。

新增测试：

- runtime 主链实际调用 execution proxy
- attestation 被收集
- model tier 上限映射仍生效
- denylist / allowlist 至少有可验证行为

完成标准：

- `ExecutionProxy` 在 runtime 中有真实调用点
- 不是只在 unit test 中被实例化

### Workstream C. 将 MergeGuard 接入主链并赋予阻断语义

问题：

`MergeGuard` 已实现，但仍未进入执行主链。

必改文件：

- `plugins/parallel-harness/runtime/guards/merge-guard.ts`
- `plugins/parallel-harness/runtime/engine/orchestrator-runtime.ts`
- `plugins/parallel-harness/tests/unit/gate-governance-persistence.test.ts`
- `plugins/parallel-harness/tests/integration/runtime.test.ts`

修复要求：

1. 在所有 task 执行完成后、run-level gate 前或其中一个清晰位置调用 merge guard。
2. `workerOutputs` 必须来自真实执行结果汇总，而不是重新推测。
3. merge guard 失败时：
   - 进入 `blocked` 或 `failed`
   - 写入 gate / audit / result
4. PR 创建前再执行一次 merge guard，确保最终对外输出前也有收敛检查。

新增测试：

- 两个 task 修改同一文件时 merge guard 阻断
- merge guard 通过时 run 正常继续
- PR 前 merge guard 失败时不创建 PR

完成标准：

- merge guard 不再是“库里存在但不用”
- merge guard 结论能影响最终状态

### Workstream E. 重写 Evidence Loader，使其对真实任务有效

问题：

当前 evidence loader 只能读取明确文件路径，对目录、glob、项目根路径几乎无效。

必改文件：

- `plugins/parallel-harness/runtime/session/evidence-loader.ts`
- `plugins/parallel-harness/runtime/engine/orchestrator-runtime.ts`
- `plugins/parallel-harness/runtime/session/context-packager.ts`
- `plugins/parallel-harness/tests/unit/context-pr-capability.test.ts`
- `plugins/parallel-harness/tests/unit/remediation.test.ts`

修复要求：

1. 支持读取：
   - 单文件
   - 目录
   - glob 模式
2. 避免对项目根路径做错误 `join`。
3. 引入文件遍历与筛选策略：
   - 文件数上限
   - 文件大小上限
   - 后缀/类型筛选
   - 稳定排序
4. 让 `packContext()` 能稳定拿到真实 snippet，而不是多数情况下空包。
5. 增加上下文元数据：
   - loaded_files_count
   - loaded_snippets_count
   - occupancy_ratio

新增测试：

- 目录路径可展开读取
- glob 路径可展开读取
- 项目根目录不会错误拼接
- context pack 在真实目录输入下可得到 snippets

完成标准：

- 对大多数真实 task，`relevant_files` 不再为空

### Workstream F. 让 RequirementGrounding 成为 Plan Truth

问题：

当前 grounding 只做了一次临时歧义检查，没有写入 `RunPlan`，也没有影响 gate/report。

必改文件：

- `plugins/parallel-harness/runtime/orchestrator/requirement-grounding.ts`
- `plugins/parallel-harness/runtime/schemas/ga-schemas.ts`
- `plugins/parallel-harness/runtime/engine/orchestrator-runtime.ts`
- `plugins/parallel-harness/runtime/integrations/report-aggregator.ts`
- `plugins/parallel-harness/tests/unit/remediation.test.ts`
- 必要时更新相关 plan/result 测试

修复要求：

1. 在 schema 中扩展 `RunPlan` 或关联结构，正式容纳 grounding 结果。
2. `planPhase()` 返回的 `RunPlan` 必须包含 grounding。
3. 歧义判断阈值必须合理，不要写成永远触发不了的条件。
4. 高歧义不应该简单抛异常进入 `failed`，而应进入可治理状态：
   - `awaiting_approval`
   - 或 `blocked`
   - 或产生 clarification gate
5. 报告和 gate 至少能引用 grounding 中的 `acceptance_matrix`。

新增测试：

- grounding 被写入 run plan
- 歧义请求进入阻断/审批，而不是直接失败
- acceptance matrix 可被报告聚合器读取

完成标准：

- grounding 不再是一次性局部变量，而是全流程真相源的一部分

### Workstream G. 修复 Result Durable Truth 与报告聚合接线

问题：

`RunResult` 仍在 PR 产物补齐前落盘；`report-aggregator.ts` 也还没接入主链。

必改文件：

- `plugins/parallel-harness/runtime/engine/orchestrator-runtime.ts`
- `plugins/parallel-harness/runtime/integrations/report-aggregator.ts`
- `plugins/parallel-harness/runtime/server/control-plane.ts`
- `plugins/parallel-harness/tests/integration/runtime.test.ts`
- `plugins/parallel-harness/tests/unit/remediation.test.ts`

修复要求：

1. 最终 `saveResult()` 必须发生在：
   - final status 收敛后
   - gate 结果确定后
   - PR artifacts 回填后
2. 如果 PR 创建失败：
   - 要么将该失败纳入最终 result
   - 要么明确分离 result 与 integration status
3. `report-aggregator.ts` 如果保留，必须接入主链；否则删除，避免继续堆未接线模块。
4. control plane 读取的 `RunResult` 必须是最终真相，而不是 PR 之前的半成品。

新增测试：

- 成功创建 PR 后 durable result 包含 `pr_artifacts`
- PR 失败时 result 状态与 artifacts 语义一致
- control plane 读取到的 result 与 runtime 最终结果一致

完成标准：

- durable store 中的 `RunResult` 与最终输出一致

### Workstream H. 修复 Control Plane 与 RBAC 兼容性

问题：

当前 control plane 仍以无角色 actor 调用 runtime，RBAC 模式下依然可能失效。

必改文件：

- `plugins/parallel-harness/runtime/server/control-plane.ts`
- `plugins/parallel-harness/runtime/governance/governance.ts`
- `plugins/parallel-harness/runtime/engine/orchestrator-runtime.ts`
- `plugins/parallel-harness/tests/integration/runtime.test.ts`

修复要求：

1. 定义 control-plane actor 的身份策略：
   - system actor
   - 或显式角色映射
2. 不能再使用固定空角色用户身份执行审批与取消操作。
3. 在治理模式下验证：
   - approve
   - reject
   - cancel
   - retry
4. 如果需要，扩展 runtime bridge 接口以传递 actor 身份。

新增测试：

- RBAC 开启时 control-plane approve 成功
- RBAC 开启时 control-plane cancel 成功
- 无权限 actor 仍被正确阻止

完成标准：

- control plane 与治理模式兼容

## 固定执行顺序

必须按以下顺序执行，因为存在依赖关系：

1. Workstream D
2. Workstream A
3. Workstream B
4. Workstream C
5. Workstream E
6. Workstream F
7. Workstream G
8. Workstream H

## 每个工作流完成后的固定验证

每完成一个工作流，至少执行：

```bash
cd plugins/parallel-harness
bun test tests/unit/
bunx tsc --noEmit
```

全部工作流完成后，执行：

```bash
cd plugins/parallel-harness
bun test
bunx tsc --noEmit
```

## 最终输出要求

全部完成后，必须输出：

1. 已修复问题列表
2. 修改文件列表
3. 新增/更新测试列表
4. 最终验证结果
5. 仍存在的残余风险

只有同时满足以下条件，才算本轮完成：

- review 中指出的 8 个问题全部有代码级修复
- 新增模块全部接入主链或被删除
- `bun test` 全绿
- `bunx tsc --noEmit` 全绿
- 文档表述与真实实现一致

在满足这些条件前，不要停止。
