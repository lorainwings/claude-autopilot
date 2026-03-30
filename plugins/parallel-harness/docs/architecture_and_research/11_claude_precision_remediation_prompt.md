# 11. 可直接交给 Claude 的第三轮精确返修提示词

以下内容可直接作为 Claude Code / Claude agent 的执行提示词使用。

---

你现在需要继续修复 `plugins/parallel-harness`，目标不是继续做“局部补丁”或“新增未接线模块”，而是完成上一轮修复后仍然没有闭环的主链问题。

你必须把本轮工作视为一次 **precision remediation**：

- 修主链，不修表层
- 修 durable truth，不修内存假象
- 修治理语义，不修 happy path
- 修 runtime 真相源，不修孤立 helper

## 你必须先阅读的文档

先完整阅读以下文档，并以这些文档作为唯一施工依据：

- `plugins/parallel-harness/docs/architecture_and_research/04_parallel_harness_implementation_review.md`
- `plugins/parallel-harness/docs/architecture_and_research/08_claude_followup_remediation_execution_plan.md`
- `plugins/parallel-harness/docs/architecture_and_research/09_claude_followup_remediation_prompt.md`
- `plugins/parallel-harness/docs/architecture_and_research/10_claude_remediation_review.md`

其中：

- `08` 是二次修复施工单
- `09` 是上轮实际执行提示词
- `10` 是对上轮修复结果的正式 review，指出了哪些地方仍未闭环

你的任务是：**严格按照 `10_claude_remediation_review.md` 中指出的问题，完成第三轮精确返修。**

## 本轮必须完成的目标

本轮必须完整修复以下 8 个未闭环问题，不能漏任何一个：

1. `RunResult` durable truth 仍然错误
2. `MergeGuard` 仍未接入主链
3. `ExecutionProxy` 仍未接入主链，且当前接口语义不兼容
4. `RequirementGrounding` 仍不是 plan truth
5. `determineFinalStatus()` 仍然忽略未尝试任务
6. Control Plane 与 RBAC 仍不兼容
7. Scheduler 冲突检测仍然不是 ownership 语义一致
8. Evidence Loader 与 report aggregation 仍未形成真实主链闭环

## 本轮禁止事项

### 禁止 1

禁止只补测试，不修实现。

### 禁止 2

禁止继续新增“可单测调用但 runtime 不用”的模块。

### 禁止 3

禁止把“写入内存对象”误当成“durable truth 已修复”。

### 禁止 4

禁止只修 `executeRun()` happy path，不修：

- blocked
- approval/resume
- PR creation
- control-plane 调用
- durable store 读取

### 禁止 5

禁止用 README 文案更新替代代码闭环。

## 核心施工要求

下面 8 个 workstream 必须全部完成。

## Workstream 1. 修复最终状态真相源

### 问题

当前 `determineFinalStatus()` 仍只看 `completed_attempts`，没有基于任务全集做状态归并，因此可能出现：

- `final_status = succeeded`
- 但 `skipped_tasks` 非空

这种语义冲突。

### 必改文件

- `plugins/parallel-harness/runtime/engine/orchestrator-runtime.ts`
- `plugins/parallel-harness/tests/unit/state-machine-eventbus.test.ts`
- `plugins/parallel-harness/tests/integration/runtime.test.ts`

### 必须实现

1. `determineFinalStatus()` 必须基于 `plan.task_graph.tasks` 全集判定。
2. 必须支持明确区分：
   - 全部成功
   - 部分成功
   - 全部失败
   - blocked
   - 存在 skipped tasks
3. 当 `skipped_tasks` 非空时，不能返回完全成功，除非该 task 在 schema 上被明确标记为 allow_skip。
4. `approveAndResume()` 路径必须复用同一套最终状态语义，不能出现 normal path / resume path 结果不一致。

### 必测场景

- skipped task 存在时不会判定为 `succeeded`
- blocked 优先级高于部分成功
- budget 中断后最终状态正确
- resume 后仍使用全集任务判定终态

## Workstream 2. 让 Scheduler 冲突检测与 Ownership 语义一致

### 问题

当前 scheduler 仍然只做 exact path equality 检测。

### 必改文件

- `plugins/parallel-harness/runtime/orchestrator/ownership-planner.ts`
- `plugins/parallel-harness/runtime/scheduler/scheduler.ts`
- `plugins/parallel-harness/tests/unit/scheduler.test.ts`
- `plugins/parallel-harness/tests/unit/remediation.test.ts`

### 必须实现

1. 从 ownership 层抽出正式可复用的路径重叠判断函数，供 scheduler 和 validation 共用。
2. scheduler 必须识别：
   - 同文件
   - 目录包含
   - 前缀覆盖
   - `/*`
   - `/**`
   - 项目根路径 `.` / `./`
3. ready 集中如果任务互相冲突，必须自动降级为串行。
4. 不允许 scheduler 与 ownership 使用两套不同语义。

### 必测场景

- `src/` 与 `src/a/` 不能同批
- `src/**` 与 `src/auth/login.ts` 不能同批
- `.` 与任意写路径不能同批
- 无冲突路径仍可同批

## Workstream 3. 让 ExecutionProxy 成为真实执行入口

### 问题

当前 runtime 仍然直接调用 `workerController.execute(...)`，`ExecutionProxy` 只是孤立模块。

### 必改文件

- `plugins/parallel-harness/runtime/workers/execution-proxy.ts`
- `plugins/parallel-harness/runtime/workers/worker-runtime.ts`
- `plugins/parallel-harness/runtime/engine/orchestrator-runtime.ts`
- `plugins/parallel-harness/tests/unit/worker-runtime.test.ts`
- `plugins/parallel-harness/tests/unit/remediation.test.ts`
- `plugins/parallel-harness/tests/integration/runtime.test.ts`

### 必须实现

1. runtime 主链必须通过 `ExecutionProxy` 执行 worker。
2. `ExecutionProxy` 返回值必须与现有 `WorkerOutput` 契约一致：
   - 不能返回 `status: "succeeded"`
   - 不能返回 `modified_files`
3. `ExecutionProxy` 必须负责：
   - model tier -> provider/model 映射
   - tool allowlist / denylist enforcement
   - path sandbox 信息传递
   - execution attestation 生成
4. `WorkerExecutionController` 与 `ExecutionProxy` 职责拆分必须明确：
   - controller：attempt 生命周期、超时、snapshot、post-validation
   - proxy：执行代理、模型/工具/沙箱绑定、attestation
5. attestation 必须进入 audit 或 result truth，不能生成后丢弃。

### 必测场景

- runtime 主链实际调用 `ExecutionProxy`
- attestation 被持久化或可查询
- max model tier 在 retry 路径仍生效
- denylist / allowlist 真实影响执行行为

## Workstream 4. 把 MergeGuard 接入 runtime 主链

### 问题

`MergeGuard` 当前只是存在于库中，没进入 runtime 主链。

### 必改文件

- `plugins/parallel-harness/runtime/guards/merge-guard.ts`
- `plugins/parallel-harness/runtime/engine/orchestrator-runtime.ts`
- `plugins/parallel-harness/tests/unit/gate-governance-persistence.test.ts`
- `plugins/parallel-harness/tests/integration/runtime.test.ts`

### 必须实现

1. 在所有 task 完成后、PR 创建前，必须执行 `MergeGuard.check()`。
2. `workerOutputs` 必须来自真实执行结果汇总，而不是重新推测。
3. merge guard 失败时必须：
   - 阻断 run
   - 进入 `blocked` 或 `failed`
   - 写入 gate / audit / result
4. 如果存在 PR 产出流程，PR 前必须再做一次最终 merge guard。
5. merge guard 结论必须在 control-plane 可见。

### 必测场景

- 两个 task 修改同一文件时 merge guard 阻断
- merge guard 通过时 run 可继续完成
- PR 前 merge guard 失败时 PR 不创建

## Workstream 5. 让 RequirementGrounding 成为 Plan Truth

### 问题

grounding 当前只是局部变量，不是 `RunPlan` truth source。

### 必改文件

- `plugins/parallel-harness/runtime/orchestrator/requirement-grounding.ts`
- `plugins/parallel-harness/runtime/schemas/ga-schemas.ts`
- `plugins/parallel-harness/runtime/engine/orchestrator-runtime.ts`
- `plugins/parallel-harness/runtime/integrations/report-aggregator.ts`
- `plugins/parallel-harness/tests/unit/remediation.test.ts`
- 必要时更新其他 plan/result/control-plane 测试

### 必须实现

1. 在 schema 中正式扩展 `RunPlan`，容纳 grounding 结果。
2. `planPhase()` 返回的 `RunPlan` 必须包含 grounding。
3. acceptance matrix 必须可被 gate/report 读取。
4. 高歧义不允许直接 `throw -> failed`。
5. 高歧义必须进入可治理状态之一：
   - `awaiting_approval`
   - `blocked`
   - clarification gate
6. 歧义阈值必须合理，不能写成事实上永远不触发的条件。

### 必测场景

- grounding 被持久化到 `RunPlan`
- acceptance matrix 可在报告中被读取
- 高歧义请求进入阻断/审批，而不是直接失败

## Workstream 6. 修复 Evidence Loader 与 Context 主链

### 问题

当前 evidence loader 仍不能正确处理目录、glob、项目根路径。

### 必改文件

- `plugins/parallel-harness/runtime/session/evidence-loader.ts`
- `plugins/parallel-harness/runtime/session/context-packager.ts`
- `plugins/parallel-harness/runtime/engine/orchestrator-runtime.ts`
- `plugins/parallel-harness/tests/unit/context-pr-capability.test.ts`
- `plugins/parallel-harness/tests/unit/remediation.test.ts`

### 必须实现

1. 正式支持：
   - 单文件
   - 目录
   - glob
   - 项目根路径
2. 正确遍历并筛选文件，而不是直接 `join(project_root, pattern)` 后判存在。
3. 增加：
   - 文件数上限
   - 文件大小上限
   - 类型/后缀筛选
   - 稳定排序
4. `packContext()` 在真实目录输入下必须能拿到 snippets。
5. 上下文元数据必须包含：
   - `loaded_files_count`
   - `loaded_snippets_count`
   - `occupancy_ratio`

### 必测场景

- 目录输入可展开
- glob 输入可展开
- `.` 不会错误 join
- context pack 在真实任务下能拿到 snippet

## Workstream 7. 修复 Result Durable Truth 与 Report 主链

### 问题

当前 `RunResult` 在 PR 产物补齐前就被持久化；`report-aggregator` 仍未进入主链。

### 必改文件

- `plugins/parallel-harness/runtime/engine/orchestrator-runtime.ts`
- `plugins/parallel-harness/runtime/integrations/report-aggregator.ts`
- `plugins/parallel-harness/runtime/server/control-plane.ts`
- `plugins/parallel-harness/tests/integration/runtime.test.ts`
- `plugins/parallel-harness/tests/unit/remediation.test.ts`

### 必须实现

1. 最终 `saveResult()` 必须发生在：
   - final status 收敛后
   - merge guard / gate 结果确定后
   - PR artifacts 回填后
2. 如果 PR 创建失败：
   - 要么进入最终 result truth
   - 要么明确分离 integration status，并让 control-plane 可读
3. `report-aggregator` 必须进入主链；如果不接线就删除。
4. control-plane 读取到的 result 必须与 runtime 最终输出一致。

### 必测场景

- PR 成功后 durable result 带 `pr_artifacts`
- PR 失败时 result 语义一致
- control-plane 读取结果与 runtime 最终结果一致

## Workstream 8. 修复 Control Plane 与 RBAC 兼容性

### 问题

当前 control-plane 仍然用固定字符串 actor 调 runtime，RBAC 模式下仍会失效。

### 必改文件

- `plugins/parallel-harness/runtime/server/control-plane.ts`
- `plugins/parallel-harness/runtime/governance/governance.ts`
- `plugins/parallel-harness/runtime/engine/orchestrator-runtime.ts`
- `plugins/parallel-harness/tests/integration/runtime.test.ts`

### 必须实现

1. 定义 control-plane actor 策略：
   - system actor
   - 或显式角色映射
2. 不允许继续以 `roles: []` 的 user actor 去执行审批/取消。
3. runtime bridge 必须能传递 actor identity，而不是只传一个字符串。
4. RBAC 开启时必须验证：
   - approve
   - reject
   - cancel
   - retry（如果仍未实现，必须明确阻断并在文档里说明）

### 必测场景

- RBAC 开启时 control-plane approve 成功
- RBAC 开启时 control-plane cancel 成功
- 无权限 actor 仍被阻止

## 强制执行顺序

必须按以下顺序施工：

1. Workstream 1
2. Workstream 2
3. Workstream 3
4. Workstream 4
5. Workstream 5
6. Workstream 6
7. Workstream 7
8. Workstream 8

原因：

- 先修状态真相与调度语义
- 再修执行主链与 merge 收敛
- 最后修 durable truth / control-plane / RBAC

## 每个 workstream 完成后的固定验证

每完成一个 workstream，至少执行：

```bash
cd plugins/parallel-harness
bun test tests/unit/
bunx tsc --noEmit
```

全部完成后，执行：

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
5. 剩余风险

## 最终验收标准

只有同时满足以下条件，才算本轮真正完成：

- `10_claude_remediation_review.md` 中指出的未闭环项全部完成代码级修复
- 新增模块全部接入主链，或被删除
- `RunResult` durable truth 与 control-plane 读取结果一致
- `ExecutionProxy`、`MergeGuard`、`report-aggregator` 均不再是孤立模块
- `bun test` 全绿
- `bunx tsc --noEmit` 全绿
- 文档表述与真实实现一致

在满足这些条件前，不要停止。
