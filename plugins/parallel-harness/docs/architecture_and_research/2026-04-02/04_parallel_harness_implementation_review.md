# 04. parallel-harness 当前实现评审

## 1. 评审范围与口径

本报告只评审当前工作区的真实实现，不评审 README 目标态叙事。

评审输入：

1. 源码：`plugins/parallel-harness/runtime/**`
2. 本地验证：
   - `bun test` -> `415 pass / 0 fail / 868 expect() calls`
   - `bunx tsc --noEmit` -> 通过
3. 文档对照：
   - `plugins/parallel-harness/README.md`
   - `plugins/parallel-harness/README.zh.md`
   - `plugins/parallel-harness/docs/**`
4. 最小复现：
   - `groundRequirement()` 中文请求复现
   - `packContext()` 根路径选择复现
   - `loadEvidenceFiles()` 绝对路径复现

本报告优先列出问题、风险和文档偏差。

## 2. Findings

### Critical-1. 上下文打包主链在根路径/绝对路径场景下会失效，许多任务实际拿到的是空上下文

**证据**

- `buildTaskGraph()` 在 general task 场景下会把 `allowed_paths` 设为 `project_root`。
- `EvidenceLoader` 读取文件时返回的是**相对路径**。
- `ContextPackager.selectRelevantFiles()` 用 `f.path.startsWith(p)` 与 `f.path === p` 直接匹配 `task.allowed_paths`。
- `loadEvidenceFiles()` 对绝对路径模式使用 `join(project_root, pattern)`，会导致根路径模式失真。

**最小复现**

```bash
cd plugins/parallel-harness
bun -e 'import { packContext } from "./runtime/session/context-packager";
const task={id:"t1",title:"x",goal:"g",dependencies:[],status:"pending",risk_level:"low",
complexity:{score:1,level:"low",dimensions:{estimated_tokens:100,file_count:1,dependency_depth:0,interface_touchpoints:0}},
allowed_paths:["."],forbidden_paths:[],acceptance_criteria:[],required_tests:[],model_tier:"tier-1",
verifier_set:["test"],retry_policy:{max_retries:1,escalate_on_retry:true,compact_context_on_retry:true}};
const files=[{path:"src/a.ts",content:"export const a=1",size:10,type:"ts"}];
console.log(JSON.stringify(packContext(task, files), null, 2));'
```

输出关键字段：

```json
{
  "relevant_files": [],
  "relevant_snippets": [],
  "loaded_files_count": 0,
  "loaded_snippets_count": 0
}
```

另一个复现：

```bash
cd plugins/parallel-harness
bun -e 'import { loadEvidenceFiles } from "./runtime/session/evidence-loader";
console.log(JSON.stringify(loadEvidenceFiles({id:"t1",allowed_paths:[process.cwd()],dependencies:[]},
{project_root:process.cwd(),max_files_per_task:3,max_file_size_kb:50}), null, 2));'
```

输出为：

```json
[]
```

**风险**

- general task 或绝对根路径任务很可能拿不到任何上下文证据。
- “最小上下文包”会退化成“空上下文包”，直接影响需求理解、代码生成和验证稳定性。

**最佳修复方案**

1. 把路径系统统一成 `NormalizedPath`，明确 `repo_relative` 与 `repo_absolute`。
2. `EvidenceLoader` 与 `ContextPackager` 使用同一套 `pathMatches()`。
3. 在 `packContext()` 内加入 fail-closed 保护：若 `allowed_paths` 非空但 `loaded_files_count=0`，默认阻断而不是静默继续。

### Critical-2. 成本预算、token 预算和 token 使用量被混为一谈，已经污染路由、上下文预算与成本统计

**证据**

- `routeModel()` 需要的是 `token_budget`，但 `planPhase()` 和 `executeTask()` 传入的是 `budget_limit` / `remaining_budget`。
- `LocalWorkerAdapter` 把 `cost_usd` 映射成 `tokens_used = cost_usd * 100000`。
- `recordCost()` 又基于 `tokens_used` 重新计算成本。

**直接后果**

- 成本预算被误当作 token 上下文预算。
- `tokens_used` 不再是 token 统计，而是混入了美元成本派生值。
- `total_cost`、`budget_utilization`、`context_budget`、`occupancy` 的解释性下降。

**风险**

- 模型路由可能被错误裁剪。
- 上下文预算和真实上下文承载能力脱钩。
- 成本控制面板与质量报告无法作为稳定运营信号。

**最佳修复方案**

1. 拆成三套类型：
   - `CostBudget`
   - `TokenBudget`
   - `TokenUsage`
2. `WorkerOutput` 必须记录真实 token 使用；没有真实 token 时要标记 `usage_source = "estimated"`，不能把 `cost_usd` 伪装成 token。
3. `routeModel()` 只接收 token 维度，成本预算通过独立 admission control 管理。

### High-1. 默认 gate 配置下，task-level test/lint gate 会在并行批次里重复触发全仓命令，既昂贵又不稳定

**证据**

- 默认配置启用了 `test`、`lint_type`、`review`、`policy`。
- `executeTask()` 在每个成功 attempt 后立即执行 task-level gates。
- `TestGateEvaluator` 直接运行 `bun test 2>&1`。
- `LintTypeGateEvaluator` 对 TS 文件直接运行 `bunx tsc --noEmit 2>&1`。
- `Scheduler` 支持同一批次并行执行多个 task。

**风险**

- 一个 5 task 的批次可能并发触发 5 次全仓测试 / 类型检查。
- 测试耗时、锁竞争、临时文件、缓存和并发抖动会显著放大。
- 默认行为与“并行 harness 稳定性”目标相冲突。

**最佳修复方案**

1. task-level 仅跑 diff-aware 或 task-aware gate。
2. 全仓测试 / 全仓类型检查提升到 batch-level 或 run-level verifier。
3. 引入 `TestImpactAnalysis` 或 `VerifierBatchPlan`，避免 N 次重复全仓命令。

### High-2. 多个生命周期/验证/报告模块虽然已有代码和测试，但没有接入主运行时

**证据**

下列模块在当前主链中没有调用点或没有实质接线：

- `engine/admission-control.ts`
- `models/routeWithOccupancy()`
- `session/context-memory-service.ts`
- `lifecycle/lifecycle-spec-store.ts`
- `lifecycle/stage-contract-engine.ts`
- `verifiers/evidence-producer.ts`
- `verifiers/hidden-eval-runner.ts`
- `integrations/report-template-engine.ts`
- `persistence/PersistentEventBusAdapter`
- `persistence/ReplayEngine`

**风险**

- 生命周期阶段、hidden eval、专业报告、memory、admission control 目前仍是“有代码的能力设想”，不是当前产品能力。
- README 和 marketplace 文档如果继续按整体 `GA` 宣传，会高估成熟度。

**最佳修复方案**

1. 把模块状态分成 `wired / experimental / latent` 三档。
2. 先接线 `StageContractEngine`、`HiddenEvalRunner`、`ReportTemplateEngine`。
3. 未接线模块不要继续在对外文档里按已完成能力表述。

### High-3. ExecutionProxy 与 attestation 仍然偏“派生证明”，没有成为可信执行面

**证据**

- `ExecutionProxy.finalizeExecution()` 里的 `tool_calls` 是从 `modified_paths` 派生，不是真实工具调用。
- `diff_ref` 当前使用的是 baseline commit，不是真正 diff 引用。
- `sandbox_mode = "worktree"` 明确未实现。
- `WorkerExecutionController` 只有在 `project_root` 为绝对路径时才启用真实 git diff 采集。
- `executeTask()` 里传给 `ExecutionProxy` 的 `allowed_tools` 永远是 `undefined`。

**风险**

- attestation 更接近“后验摘要”，不是可信执行记录。
- 相对路径项目根时，真实 diff 采集直接失效。
- 工具策略和执行隔离依然不够硬。

**最佳修复方案**

1. `ExecutionProxy` 直接托管工具调用、stdout/stderr、diff、cwd 和沙箱。
2. 用真实 tool trace 填充 `actual_tool_calls` 和 attestation。
3. 默认启用 worktree / isolated workspace，而不是把它标成 future feature。

### High-4. Requirement Grounding 与 Intent Analyzer 仍是关键词级实现，且对中文连续文本不友好

**证据**

`groundRequirement()` 的动词识别、模块识别依赖空格切词与精确匹配。对中文请求：

```bash
cd plugins/parallel-harness
bun -e 'import { groundRequirement } from "./runtime/orchestrator/requirement-grounding";
const req={request_id:"req1", intent:"实现用户认证并补齐测试覆盖", actor:{id:"u",type:"user",name:"u",roles:[]},
project:{root_path:".",known_modules:[],scope:{}},
config:{max_concurrency:1,high_risk_max_concurrency:1,prioritize_critical_path:true,budget_limit:100000,
max_model_tier:"tier-3",enabled_gates:[],auto_approve_rules:[],timeout_ms:1000,pr_strategy:"none",enable_autofix:false},
requested_at:new Date().toISOString(), schema_version:"1.0.0"};
console.log(JSON.stringify(groundRequirement(req), null, 2));'
```

关键输出：

```json
{
  "ambiguity_items": [
    "需求描述过于简短，可能缺少关键细节",
    "需求缺少明确的动作动词"
  ],
  "impacted_modules": []
}
```

对更复杂的中文全流程请求：

```bash
cd plugins/parallel-harness
bun -e 'import { analyzeIntent } from "./runtime/orchestrator/intent-analyzer";
console.log(JSON.stringify(analyzeIntent("实现产品设计、UI设计、技术方案、前后端实现、测试和报告"), null, 2));'
```

关键输出：

- `sub_goals` 只有 1 个
- `domains` 只有 `frontend/backend/test`
- 无 `product/ui/architecture/reporting`

**风险**

- 复杂中文需求会被压扁成单任务或错误域分类。
- 产品/UI/架构/报告阶段在 planner 入口就已经丢失。

**最佳修复方案**

1. 用 `GroundingBundle` 取代关键词级 `RequirementGrounding`。
2. 加入 clarification loop、阶段模板和 repo evidence 检索。
3. 中文及混合语言请求使用 tokenizer / semantic parser，而不是空格切词。

### High-5. 当前 gate 覆盖面很宽，但真实性和可信度并不对齐

**证据**

- `test`、`lint_type` 部分属于真实命令执行。
- `security` 主要是敏感文件路径模式，不是 scanner。
- `review`、`documentation`、`perf`、`release_readiness` 大量依赖启发式规则。
- `coverage` 在解析失败时直接降级为“是否修改测试文件”之类的代理信号。

**风险**

- 用户容易把“9 类 gate”误读为“9 类同等级强门禁”。
- 奖励挟持与表面合规仍存在较大空间。

**最佳修复方案**

1. 对外显式分成 `hard gates` 与 `signal gates`。
2. security / coverage / design / report 分别引入独立 evidence producer。
3. 让 hidden verification 成为 hard gate 的组成部分。

### High-6. RBAC 与控制面治理当前仍是默认弱约束

**证据**

- `requirePermission()` 在未配置 `rbacEngine` 时直接返回，不阻断任何写操作。
- `cancelRun()`、`approveAndResume()`、`rejectRun()`、`retryTask()` 的权限校验都依赖 `requirePermission()`。
- README 把 RBAC 描述为内置治理能力，但当前实现更接近“可选启用”，不是“默认强制生效”。

**风险**

- 多操作者环境下，控制面写操作可能在默认部署里直接放行。
- 团队容易误以为审批、取消、重试等动作天然有角色边界保护。

**最佳修复方案**

1. 将 `rbacEngine` 设为生产模式默认必配项。
2. 明确区分 `dev_mode` 与 `enforced_mode`。
3. 控制面写接口在治理未加载时 fail closed，而不是 silent allow。

### Medium-1. 控制面生命周期视图没有接到真实运行时

**证据**

- `RuntimeBridgeDataProvider` 没有实现 `getLifecyclePhases()`。
- `/api/runs/:id/lifecycle` 在 runtime 模式下会返回空数组。
- 生命周期 store 与阶段引擎虽存在，但没有驱动控制面。

**风险**

- 控制面无法成为“全流程阶段视图”的事实来源。
- 生命周期相关文档和 GUI 容易被误解为已落地。

**最佳修复方案**

1. 把 `LifecycleSpecStore` 接到真实 run。
2. 让 control plane 以 `RunPlan + StageContractEngine` 为真相源暴露阶段数据。

### Medium-2. 测试体系对纯函数和 mocked runtime 覆盖较强，但对真实隔离执行、真实 HTTP 和真实 PR/CLI 覆盖不足

**证据**

- 集成测试主入口 `runtime.test.ts` 使用 `MockSuccessAdapter` / `MockFailAdapter`。
- 多个集成测试显式关闭 gates：`enabled_gates: []`。
- 没有针对 `createControlPlaneServer()` 的 HTTP 端到端测试。
- 没有对真实 `GitHubPRProvider`、真实 `claude CLI`、真实 worktree 隔离做集成验证。

**风险**

- 主链“在 mocked 语义上成立”，但最敏感的真实运行时边界仍未被证明。
- 最容易出问题的正是测试当前回避的部分：CLI、git、PR、并行 gate、隔离执行。

**最佳修复方案**

1. 增加黑盒集成测试：HTTP、git worktree、relative/absolute root path、PR provider。
2. 加入 gated integration test profile，而不是默认全部关 gate。
3. 对关键执行路径做 smoke suite。

### Medium-3. 对外文档中的测试数字和成熟度表述已经过期

**证据**

当前多处文档仍写：

- `295 pass / 0 fail / 649 expect()`
- “GA = fully tested / production-ready”

但当前工作区实测已经是：

- `415 pass / 0 fail / 868 expect() calls`

而且多个能力仍是 latent modules。

**风险**

- 团队内部和外部读者都会高估当前成熟度。
- 问题优先级会被错误排序。

**最佳修复方案**

1. 把测试统计改成自动生成或发布前注入。
2. 成熟度表改成：
   - `wired`
   - `experimental`
   - `latent`
3. 文档中明确区分“当前能力”和“目标态能力”。

## 3. 当前测试覆盖摘要

### 已覆盖较好的能力

- 状态机与事件总线
- 基础 planner / scheduler / ownership
- gate 分类与部分 gate 行为
- RBAC / approval / persistence
- execution proxy 的局部逻辑
- report aggregator / template engine 的纯函数能力
- runtime 的 happy-path mocked integration

### 覆盖不足或未覆盖的关键能力

- 真实 `claude` CLI 执行
- 真实 worktree / sandbox_mode
- 真实 HTTP 控制面
- 真实 GitHub PR provider
- hidden eval 接线
- evidence producers 接线
- report template engine 主链接线
- absolute / relative root path 在 context 主链中的黑盒覆盖
- 并行批次下 gate 的真实资源竞争

## 4. 评审结论

当前 `parallel-harness` 不是“完全不可用”，也不是“已经达到全流程最强形态”，而是：

**一个代码实现主链已经打通、状态机和持久化骨架较完整，但基础语义、执行可信度、阶段合同和独立验证仍明显不足的并行 harness 原型。**

真正优先级最高的问题不是继续增加模块数量，而是先修复：

1. 路径语义与上下文包失效
2. 成本 / token / budget 混用
3. 默认 gate 并行下的全仓命令放大
4. latent modules 与对外 `GA` 宣称之间的落差
