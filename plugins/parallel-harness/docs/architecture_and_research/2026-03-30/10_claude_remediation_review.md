# 10. Claude 二次修复结果 Review

## 1. Review 结论

本次 Claude 基于 `09_claude_followup_remediation_prompt.md` 所做的修改，**没有彻底完成修复目标**。

结论不是“完全无效”，而是：

- 部分问题做了表层修补
- 部分问题新增了独立模块
- `bun test` 与 `bunx tsc --noEmit` 仍然通过
- 但多个关键能力依然没有真正进入 runtime 主链
- 多个“必须 durable / 必须治理 / 必须阻断”的能力仍然没有闭环

因此，这一轮修改不能认定为“彻底修复完成”。

## 2. 本次本地验证

本次 review 基于以下验证：

- 查看最新并入 `plugins/parallel-harness` 的代码提交：`31b1ad3`
- 运行 `cd plugins/parallel-harness && bun test`
- 运行 `cd plugins/parallel-harness && bunx tsc --noEmit`

验证结果：

- `bun test`：`233 pass / 0 fail`
- `bunx tsc --noEmit`：通过

这说明：

- 代码当前可以通过现有测试
- 但测试没有证明“主链接线已经完成”
- 现有测试更像是 helper/module 级证明，而不是 runtime end-to-end 闭环证明

## 3. 总体判断

本轮修复存在 3 类典型问题：

### 3.1 新增模块但未接主链

典型包括：

- `ExecutionProxy`
- `MergeGuard`
- `report-aggregator`

这些模块可以在 unit test 中被单独调用，但 runtime 并没有真正依赖它们完成核心流程。

### 3.2 只修表层语义，没有修 truth source

典型包括：

- `determineFinalStatus()` 只增加了 `blocked` 优先级
- 但仍然没有基于 `plan.task_graph.tasks` 全集做最终状态归并
- `RequirementGrounding` 只在 `planPhase()` 中临时执行一次
- 但没有进入 `RunPlan` schema，也没有进入 report/gate/control-plane truth

### 3.3 测试通过，但没有覆盖真正失败路径

典型包括：

- 没有测试 `ExecutionProxy` 是否被 runtime 主链实际调用
- 没有测试 `MergeGuard` 是否阻断 PR 创建
- 没有测试 PR 成功后 durable result 是否包含 `pr_artifacts`
- 没有测试 RBAC 开启时 control-plane 的 approve/cancel 真正可用

## 4. 详细发现

## 4.1 High: `RunResult` durable truth 仍然错误

### 问题

runtime 仍然在 PR 创建之前就保存 `RunResult`：

- 先 `determineFinalStatus()`
- 再 `finalizeRun()`
- 再 `saveResult(result)`
- 然后才进入 PR 创建逻辑

但 `pr_artifacts` 是在后面才写回到内存对象中的，没有再次持久化。

### 证据

- `plugins/parallel-harness/runtime/engine/orchestrator-runtime.ts`
  - `548-555`
  - `563-625`
  - `631-639`
- `plugins/parallel-harness/runtime/persistence/session-persistence.ts`
  - `231-240`

### 影响

- durable store 中的 `RunResult` 仍不是最终真相
- control plane 读到的 result 仍可能缺少 `pr_artifacts`
- “PR 失败是否纳入最终 result” 仍未被建模清楚

### 判定

该问题 **未修复完成**。

## 4.2 High: `MergeGuard` 仍未接入主链

### 问题

`MergeGuard` 模块本身存在，但 runtime 中没有真正调用：

- 没有在 task 汇总后调用
- 没有在 run-level gate 之前或之后调用
- 没有在 PR 创建前做最终阻断

### 证据

- `plugins/parallel-harness/runtime/guards/merge-guard.ts`
  - `78-160`
- `plugins/parallel-harness/runtime/engine/orchestrator-runtime.ts`
  - `553-625`

代码库中不存在对 `MergeGuard.check()` 的主链调用点。

### 影响

- 并发修改同一路径的任务仍不会在最终合并前被统一阻断
- merge guard 的结论不会进入 gate / audit / result
- PR 前没有最终写集收敛检查

### 判定

该问题 **完全没有闭环**。

## 4.3 High: `ExecutionProxy` 仍未接入主链，而且接口语义本身就不兼容

### 问题

runtime 实际执行 worker 时，仍然直接调用：

- `this.workerController.execute(...)`

并没有经过 `ExecutionProxy`。

更严重的是，新建的 `ExecutionProxy` 返回结构本身就不符合现有 `WorkerOutput` 契约：

- 返回 `status: "succeeded"`
- 返回 `modified_files`

但现有 `WorkerOutput` 需要：

- `status: "ok" | "warning" | "blocked" | "failed"`
- `modified_paths`

### 证据

- `plugins/parallel-harness/runtime/engine/orchestrator-runtime.ts`
  - `957-964`
- `plugins/parallel-harness/runtime/workers/execution-proxy.ts`
  - `24-59`
- `plugins/parallel-harness/runtime/orchestrator/role-contracts.ts`
  - `86-103`

### 影响

- `ExecutionProxy` 目前只是一个未接线 stub
- attestation 也没有进入 audit/result truth
- 即使强行接线，当前返回值也会破坏现有主链语义

### 判定

该问题 **未修复**，而且当前新增实现仍需重构。

## 4.4 High: `RequirementGrounding` 仍不是 plan truth，歧义治理路径也没落地

### 问题

`RequirementGrounding` 当前只是 `planPhase()` 中的本地临时变量：

- 没有写入 `RunPlan`
- 没有写入 schema
- 没有进入 gate/report/control-plane

另外，高歧义处理仍然是直接 `throw`，最终走 run failed，而不是进入：

- `awaiting_approval`
- `blocked`
- clarification gate

而且当前实现最多产生 2 个 ambiguity item，但阻断阈值写的是 `> 2`，这意味着这条分支基本不会触发。

### 证据

- `plugins/parallel-harness/runtime/schemas/ga-schemas.ts`
  - `82-109`
- `plugins/parallel-harness/runtime/orchestrator/requirement-grounding.ts`
  - `18-55`
- `plugins/parallel-harness/runtime/engine/orchestrator-runtime.ts`
  - `659-666`
  - `640-651`

### 影响

- grounding 仍不是全流程真相源
- acceptance matrix 无法被后续 gate/report 引用
- 歧义治理仍是失败语义，而不是治理语义

### 判定

该问题 **未修复**。

## 4.5 High: `determineFinalStatus()` 仍然忽略未尝试任务

### 问题

当前 `determineFinalStatus()` 只遍历 `completed_attempts`，没有基于任务全集判定最终状态。

这意味着：

- 某些 task 从未执行
- `finalizeRun()` 会把它们放进 `skipped_tasks`
- 但 `determineFinalStatus()` 仍可能返回 `succeeded`

### 证据

- `plugins/parallel-harness/runtime/engine/orchestrator-runtime.ts`
  - `1312-1333`
  - `1336-1360`

### 影响

- `final_status` 与 `skipped_tasks` 语义仍可能冲突
- “部分成功 / 有 skipped / 全部成功” 仍没有被正确区分

### 判定

该问题 **只修了一半**。

## 4.6 High: Control Plane 与 RBAC 仍不兼容

### 问题

control-plane 桥接层仍然用固定字符串 actor：

- `"control-plane"`

而 runtime 的权限检查会构造一个：

- `type: "user"`
- `roles: []`

的 actor 做 RBAC 判断。

这既不是 system actor，也没有显式角色映射，因此 RBAC 开启后依然会失败。

### 证据

- `plugins/parallel-harness/runtime/server/control-plane.ts`
  - `228-249`
- `plugins/parallel-harness/runtime/engine/orchestrator-runtime.ts`
  - `1704-1713`

### 影响

- approve / reject / cancel 在治理模式下仍不可靠
- control plane 仍未具备正式 actor identity

### 判定

该问题 **未修复**。

## 4.7 Medium: Scheduler 冲突检测仍然不是 ownership 语义一致

### 问题

scheduler 当前仍然只检查：

- `exclusive_paths.includes(...)`

这只能识别完全相等路径，不能识别：

- 目录包含
- 前缀覆盖
- glob 重叠

而 ownership 层本身已经有更完整的路径匹配语义，但没有复用。

### 证据

- `plugins/parallel-harness/runtime/scheduler/scheduler.ts`
  - `104-117`
- `plugins/parallel-harness/runtime/orchestrator/ownership-planner.ts`
  - `202-228`

### 影响

- `src/` 与 `src/a/`
- `src/**` 与 `src/auth/login.ts`
- `.` 与任意路径

这些真实冲突仍可能被错误并发调度。

### 判定

该问题 **未彻底修复**。

## 4.8 Medium: Evidence Loader 对真实目录/glob/root-path 仍然无效

### 问题

当前 `loadEvidenceFiles()` 只是把 pattern 直接：

- `join(project_root, pattern)`

然后检查本地文件系统是否存在。

这导致：

- glob 不会展开
- 目录会被直接跳过
- 项目根目录 `.` 会被视为目录并跳过
- dependency 还会被拼成 `**/<taskId>/**` 这种并不存在的路径模式

### 证据

- `plugins/parallel-harness/runtime/session/evidence-loader.ts`
  - `29-68`
- `plugins/parallel-harness/runtime/engine/orchestrator-runtime.ts`
  - `1300-1309`

### 影响

- `packContext()` 在大量真实任务下仍然拿不到有效 snippets
- “上下文装包已真实生效”的说法仍然不成立

### 判定

该问题 **未修复**。

## 4.9 Medium: `report-aggregator` 仍是未接线模块

### 问题

`report-aggregator.ts` 仅在 unit test 中被引用，runtime 主链没有任何调用点。

### 证据

- `plugins/parallel-harness/runtime/integrations/report-aggregator.ts`
  - `24-45`
- 代码库全局检索结果显示其只有测试侧引用，没有 runtime 主链接线

### 影响

- 报告聚合仍不是真实交付链路的一部分
- evidence refs 不会成为最终报告真相源

### 判定

该问题 **未修复**。

## 5. 为什么测试没暴露这些问题

现有新增测试主要存在以下不足：

- 它们大量验证“模块可单独调用”
- 没有验证“runtime 主链必须经过该模块”
- 没有验证 durable store 的最终读取结果
- 没有验证 PR 前/后两阶段的语义一致性
- 没有验证 RBAC 开启时 control-plane 的真实行为

最典型的缺口包括：

- 没有测试 `ExecutionProxy` 是否被 runtime 真正调用
- 没有测试 `MergeGuard` 是否阻断 PR
- 没有测试保存到 `RunStore` 的最终结果是否带 `pr_artifacts`
- 没有测试 `determineFinalStatus()` 在 skipped task 存在时返回非 `succeeded`
- 没有测试目录/glob/root-path evidence loading

## 6. 关联性问题是否一并修复

结论是：**没有**。

本轮修复大多停留在“主问题表面补丁”，相关联的问题没有一起收口。

典型例子：

- 修了 `blocked` 优先级，但没有修 skipped task 终态语义
- 引入了 grounding，但没有修 schema truth、gate/report truth、clarification 治理
- 引入了 execution proxy，但没有修 runtime 接线、attestation 入审计、输出契约一致性
- 引入了 report aggregator，但没有修 durable result / control plane / final report 主链

## 7. 下一轮必须返修的最小闭环要求

下一轮 Claude 修复，至少必须同时做到以下几点，才算真正闭环：

1. `RunPlan` schema 正式纳入 grounding，并让 report/gate/control-plane 可见。
2. `determineFinalStatus()` 必须基于 `plan.task_graph.tasks` 全集判定。
3. `ExecutionProxy` 必须成为 runtime 主链执行入口，并输出与 `WorkerOutput` 一致的契约。
4. attestation 必须进入 audit 或 result truth。
5. `MergeGuard` 必须进入主链，并在 PR 前具有阻断语义。
6. `saveResult()` 必须发生在 PR artifacts 最终收敛之后，或明确定义 integration status 分离模型。
7. control-plane 必须以 system actor 或显式角色映射方式通过 RBAC。
8. scheduler 必须复用 ownership 的路径重叠语义，而不是继续做 exact match。
9. evidence loader 必须真正支持文件、目录、glob、项目根路径。
10. 如果 `report-aggregator` 继续保留，必须接入主链；否则删除。

## 8. 最终判定

本次 Claude 修改的最终判定如下：

- 是否正确：部分正确
- 是否彻底修复：否
- 关联问题是否一并修复：否
- 是否可以宣称完成 `09_claude_followup_remediation_prompt.md`：否

更准确地说，这一轮结果属于：

- **“新增了一批方向正确的模块和局部补丁，但核心主链仍未闭环”**

因此，当前项目仍然需要下一轮面向主链接线和 durable truth 的实质性返修。
