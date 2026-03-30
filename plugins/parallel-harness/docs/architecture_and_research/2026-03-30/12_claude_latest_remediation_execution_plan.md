# 12. Claude 最新详细修复执行方案

## 1. 文档定位

本文是面向 **Claude / Claude Code / Claude agent** 的最新施工单，基于 `2026-03-30` 当前仓库真实状态编写，目标是让 Claude 可以直接按文档执行修复，而不再重复过期 workstream。

这份文档的优先级高于以下历史文档：

- `08_claude_followup_remediation_execution_plan.md`
- `09_claude_followup_remediation_prompt.md`
- `11_claude_precision_remediation_prompt.md`

原因很简单：上述文档里有一部分问题在当前源码里已经修过，继续按旧文档施工会浪费时间，甚至会把已修复能力重新打散。

## 2. Claude 必须先知道的当前事实

在开始施工前，Claude 必须先接受下面这些事实，避免修错方向。

### 2.1 已经接入主链的能力

以下能力 **已经进入主链**，不要再把它们当成“完全未接线问题”：

1. `Requirement Grounding` 已进入 `planPhase()`
2. `MergeGuard` 已进入 runtime 主链终态判定前
3. `packContext()` 已通过 `evidence-loader` 获取真实文件
4. `max_model_tier` 会在每次 retry attempt 继续生效
5. `RunResult` 会在 PR artifacts 收敛后再持久化
6. run-level gates 已经接入主链

### 2.2 当前仍然存在的关键缺口

Claude 本轮真正要修的是：

1. worker 执行边界仍然是软约束
2. `ExecutionProxy` 仍然只是事后 attestation 包装，不是真执行代理
3. PR/GitHub 集成没有显式 `repo_root/cwd` 绑定
4. `routeModel().context_budget` 没有和 `packContext()` 打通
5. `Requirement Grounding` 的大部分输出还没有被消费
6. gate 系统还没有完成 hard gate / signal gate 分层
7. hook / instruction / skill 还没有影响 runtime 主链决策
8. `bunx tsc --noEmit` 当前失败，类型环境未闭环
9. 高风险路径缺少端到端测试
10. README / 架构文档仍然可能与实现继续漂移

## 3. Claude 开工前必须阅读的文档

在动手前，Claude 必须完整阅读以下文档，并以它们作为统一施工依据：

- `plugins/parallel-harness/docs/architecture_and_research/2026-03-30/01_lifecycle_architecture_design.md`
- `plugins/parallel-harness/docs/architecture_and_research/2026-03-30/04_parallel_harness_implementation_review.md`
- `plugins/parallel-harness/docs/architecture_and_research/2026-03-30/05_parallel_harness_enhancement_blueprint.md`
- `plugins/parallel-harness/docs/architecture_and_research/2026-03-30/12_claude_latest_remediation_execution_plan.md`

如果 Claude 还需要读取历史文档，最多只把 `08/09/10/11` 当作历史背景，而不能把它们当成本轮唯一真相源。

## 4. 本轮总体目标

本轮修复不是继续做“表层补丁”，而是要完成下面四条主线：

1. 把执行边界从软约束升级为真实控制项
2. 把需求、上下文、验证这三条线真正闭环
3. 把 PR/Git/类型检查/测试变成可信交付链
4. 把扩展层和控制面从“旁路对象”升级为“主链效果对象”

## 5. 本轮禁止事项

### 禁止 1

禁止再去修已经修过的旧问题，例如：

- “把 MergeGuard 接入主链”
- “把 evidence-loader 接到 packContext”
- “让 retry 路径继续 obey `max_model_tier`”
- “让 `RunResult` 在 PR 之后再保存”

本轮可以增强这些能力，但不能把它们重新当成“完全未实现”。

### 禁止 2

禁止新增新的孤立模块或 helper，然后不接入主链。

### 禁止 3

禁止只补 unit test，不修 runtime 真相源。

### 禁止 4

禁止只修 happy path。每个 workstream 都必须覆盖：

- 正常路径
- 阻断路径
- 失败路径
- 恢复/持久化/控制面读取路径

### 禁止 5

禁止用 README 降级或润色文案来替代实现修复。

## 6. 执行顺序

Claude 必须按下面的顺序施工，不建议跳序。

1. Workstream A：类型环境与工程基线闭环
2. Workstream B：执行平面硬化与 attestation 真相化
3. Workstream C：PR/Git 仓库隔离
4. Workstream D：context budget 闭环
5. Workstream E：Requirement Grounding 消费闭环
6. Workstream F：GateSystem 分层与证据聚合
7. Workstream G：Hook / Instruction / Skill effect 化
8. Workstream H：高风险路径测试与文档一致性闭环

## 7. Workstream A：类型环境与工程基线闭环

### 问题

当前 `bun test` 全绿，但 `bunx tsc --noEmit` 失败。这意味着最基础的工程 gate 还是红的。

### 必改文件

- `plugins/parallel-harness/tsconfig.json`
- `plugins/parallel-harness/package.json`
- 必要时新增类型声明文件，例如：
  - `plugins/parallel-harness/types/**/*.d.ts`
  - 或 `plugins/parallel-harness/runtime/**/*.d.ts`
- 视实现需要修正：
  - `runtime/engine/orchestrator-runtime.ts`
  - `runtime/session/evidence-loader.ts`
  - `runtime/persistence/session-persistence.ts`
  - `runtime/gates/gate-system.ts`
  - `runtime/integrations/pr-provider.ts`
  - `runtime/workers/worker-runtime.ts`
  - `tests/**/*.ts`

### 必须完成

1. 补齐 Bun/Node 类型环境配置。
2. 处理 `require`、`process`、`Bun`、`fs/path/node:fs`、`bun:test` 类型问题。
3. 如果某些文件混用了 ESM 与 Node/Bun API，要明确统一策略。
4. 将 `typecheck` 作为后续所有 workstream 的必跑验证。

### 验收标准

- `cd plugins/parallel-harness && bunx tsc --noEmit` 通过
- `cd plugins/parallel-harness && bun test` 仍通过

## 8. Workstream B：执行平面硬化与 Attestation 真相化

### 问题

当前 runtime 虽然有 `WorkerExecutionController`、git snapshot、diff merge、post-check，但真实执行仍主要依赖：

- `LocalWorkerAdapter` 的 `claude -p`
- prompt 约束
- 执行后的路径校验

`ExecutionProxy` 目前也只是事后包装 attestation。

### 必改文件

- `plugins/parallel-harness/runtime/workers/execution-proxy.ts`
- `plugins/parallel-harness/runtime/workers/worker-runtime.ts`
- `plugins/parallel-harness/runtime/engine/orchestrator-runtime.ts`
- `plugins/parallel-harness/runtime/orchestrator/role-contracts.ts`
- `plugins/parallel-harness/runtime/integrations/report-aggregator.ts`
- 必要时扩展：
  - `plugins/parallel-harness/runtime/schemas/ga-schemas.ts`

### 设计要求

1. `ExecutionProxy` 必须变成真正的执行入口之一，而不是 finalize 阶段补对象。
2. 明确职责拆分：
   - `ExecutionProxy`：模型/provider 绑定、tool policy、repo/cwd/sandbox/worktree 绑定、attestation 采集
   - `WorkerExecutionController`：attempt 生命周期、超时、snapshot、diff merge、输出校验
3. Attestation 必须来源于真实执行过程，而不是事后猜测。
4. 如果当前无法做到工具级精确拦截，至少要先做到：
   - 真实 model/provider identity
   - 真实 cwd/repo_root
   - 真实 diff ref/hash
   - 真实输出与路径校验
   - 明确记录 tool policy 是否强制生效

### 最低可接受实现

本轮不要求一次性做完最强 sandbox，但必须做到：

1. runtime 主链显式走 `ExecutionProxy`
2. 每个成功/失败 attempt 都产出可追溯 attestation
3. attestation 能进入：
   - audit
   - result/report
   - control-plane 查询模型

### 必测场景

- runtime 主链确实调用 `ExecutionProxy`
- attestation 被保存或能通过 result/audit 读到
- retry 路径里 `max_model_tier` 仍生效
- allowlist / denylist 至少对 adapter 输入或执行元数据有实质影响

### 验收标准

- `ExecutionProxy` 不再是 finalize 后的孤立包装器
- execution attestation 成为 durable truth 的一部分

## 9. Workstream C：PR/Git 仓库隔离

### 问题

`GitHubPRProvider` 里执行 `git` / `gh` 时，没有显式绑定目标仓库 `cwd`，存在在错误仓库执行命令的风险。

### 必改文件

- `plugins/parallel-harness/runtime/integrations/pr-provider.ts`
- `plugins/parallel-harness/runtime/engine/orchestrator-runtime.ts`
- 必要时补：
  - `plugins/parallel-harness/tests/unit/context-pr-capability.test.ts`
  - `plugins/parallel-harness/tests/integration/runtime.test.ts`

### 必须完成

1. `CreatePRRequest` 增加 `repo_root` 或等价字段。
2. `execGh()` / `execShellForGit()` 支持并强制使用 `cwd`。
3. runtime 调 `createPR()` 时显式传入项目根目录。
4. 增加 repository identity 校验，例如：
   - 当前目录是否是 git repo
   - 当前 remote 是否匹配预期
   - branch 状态是否可创建 PR
5. PR 创建前做 dry-run / preflight check。

### 必测场景

- `createPR()` 使用显式 `repo_root`
- 非 repo 目录或 repo identity 异常时 fail-fast
- 正常路径下 review comments / check status 仍可工作

### 验收标准

- 所有 git / gh 操作都显式绑定目标仓库
- 不再依赖调用进程的当前工作目录碰运气

## 10. Workstream D：Context Budget 闭环

### 问题

`routeModel()` 已经能返回 `context_budget`，但 `packContext()` 仍使用自己的默认预算，导致路由与上下文治理是两套平行系统。

### 必改文件

- `plugins/parallel-harness/runtime/models/model-router.ts`
- `plugins/parallel-harness/runtime/session/context-pack.ts`
- `plugins/parallel-harness/runtime/session/context-packager.ts`
- `plugins/parallel-harness/runtime/engine/orchestrator-runtime.ts`
- 必要时补：
  - `plugins/parallel-harness/runtime/integrations/report-aggregator.ts`
  - `plugins/parallel-harness/tests/unit/context-pr-capability.test.ts`
  - `plugins/parallel-harness/tests/unit/model-router.test.ts`
  - `plugins/parallel-harness/tests/integration/runtime.test.ts`

### 必须完成

1. 把 `RoutingResult.context_budget` 传入 `packContext()`。
2. 给 `ContextPack` 增加至少这些字段：
   - `occupancy_ratio`
   - `loaded_files_count`
   - `loaded_snippets_count`
   - `compaction_policy`
3. 重试时允许上下文策略改变，而不仅仅是模型 tier 改变。
4. author context 和 verifier context 要能分开建模，哪怕先做最小实现。

### 必测场景

- 不同 routing 决策会影响 context budget
- 超预算时会记录压缩策略
- report / audit 可以看到上下文占用信息

### 验收标准

- 路由与上下文不再脱节
- 上下文退化风险变成可观测、可审计字段

## 11. Workstream E：Requirement Grounding 消费闭环

### 问题

`Requirement Grounding` 已进入 `RunPlan`，但当前多数输出仍未真正下沉到 task contract、审批矩阵、gate、报告。

### 必改文件

- `plugins/parallel-harness/runtime/orchestrator/requirement-grounding.ts`
- `plugins/parallel-harness/runtime/orchestrator/task-graph-builder.ts`
- `plugins/parallel-harness/runtime/session/context-pack.ts`
- `plugins/parallel-harness/runtime/session/context-packager.ts`
- `plugins/parallel-harness/runtime/engine/orchestrator-runtime.ts`
- `plugins/parallel-harness/runtime/gates/gate-system.ts`
- `plugins/parallel-harness/runtime/integrations/report-aggregator.ts`
- 必要时补：
  - `plugins/parallel-harness/runtime/schemas/ga-schemas.ts`

### 必须完成

1. 把 `acceptance_matrix` 下沉到 task 级 contract 或 verifier plan。
2. 把 `required_approvals` 映射到 runtime 审批逻辑，而不是仅作为字段存在。
3. 把 `impacted_modules` 反馈给 planner 或 test obligation。
4. 把 `delivery_artifacts` 纳入报告和 release readiness 语义。
5. 对高歧义需求，保持当前 block 语义可用，但补充更细的治理输出，不让它只是“入口处一次性截断”。

### 必测场景

- grounding 内容出现在 `RunPlan`
- acceptance matrix 能被后续阶段引用
- required approvals 能驱动审批逻辑
- report 能引用 grounding 证据

### 验收标准

- grounding 不再只是 plan 开头的一次性检查
- 成为后续实现、验证、报告的真实上游

## 12. Workstream F：GateSystem 分层与证据聚合

### 问题

当前 9 类 gate 都已注册，但强弱混合：

- `test` / `lint_type` 更接近真实 hard gate
- `review` / `perf` / `documentation` / `coverage` 等有不少启发式代理成分

### 必改文件

- `plugins/parallel-harness/runtime/gates/gate-system.ts`
- `plugins/parallel-harness/runtime/integrations/report-aggregator.ts`
- `plugins/parallel-harness/runtime/engine/orchestrator-runtime.ts`
- 必要时补：
  - `plugins/parallel-harness/runtime/schemas/ga-schemas.ts`
  - `plugins/parallel-harness/tests/unit/gate-governance-persistence.test.ts`
  - `plugins/parallel-harness/tests/unit/remediation.test.ts`
  - `plugins/parallel-harness/tests/integration/runtime.test.ts`

### 必须完成

1. 把 gate 明确分成：
   - `hard gates`
   - `signal gates`
2. 报告与控制面必须清晰展示：
   - 哪些 gate 会真正阻断
   - 哪些 gate 只是风险信号
3. 在 run-level gate 之前引入或增强证据聚合，聚合内容至少包括：
   - gate evidence
   - execution attestation
   - modified files / artifacts
4. 对 `coverage`、`security`、`release_readiness` 这种 currently heuristic 的 gate，至少明确其当前可信度，不再伪装成同等级强门禁。

### 必测场景

- hard gate 失败会阻断
- signal gate 失败不会阻断，但会出现在报告中
- report 聚合不只包含 gate，还包含 attestation / artifact 引用

### 验收标准

- gate 的“阻断语义”和“风险语义”不再混淆

## 13. Workstream G：Hook / Instruction / Skill effect 化

### 问题

当前：

- `HookRegistry` 会在阶段边界触发
- `InstructionRegistry` / `SkillRegistry` 能注册和查询

但这些返回值基本没有真正影响 planner、scheduler、contract、approval、gate。

### 必改文件

- `plugins/parallel-harness/runtime/capabilities/capability-registry.ts`
- `plugins/parallel-harness/runtime/engine/orchestrator-runtime.ts`
- 必要时补：
  - `plugins/parallel-harness/runtime/session/context-packager.ts`
  - `plugins/parallel-harness/runtime/gates/gate-system.ts`
  - `plugins/parallel-harness/tests/unit/context-pr-capability.test.ts`
  - `plugins/parallel-harness/tests/integration/runtime.test.ts`

### 必须完成

1. 将 hook 返回值从简单 `HookResult` 升级为可消费 effect，至少支持：
   - 补充 contract
   - 追加 gate
   - 强制审批
   - 降低并发
2. `InstructionRegistry.resolve()` 的结果必须在至少一个真实主链阶段被注入：
   - planner
   - context pack
   - worker contract
   - report synthesis
3. `SkillRegistry` 至少要能影响 capability 选择或 contract 元数据，而不是只停留在 registry 层。

### 必测场景

- hook 能真正改变 runtime 行为
- instruction 命中结果能进入 contract 或 report
- skill 命中结果能在审计或执行元数据中看到

### 验收标准

- 扩展层不再只是“能注册”，而是“能生效”

## 14. Workstream H：高风险路径测试与文档一致性闭环

### 问题

当前测试更偏 helper / happy path，文档也有持续漂移风险。

### 必改文件

- `plugins/parallel-harness/tests/integration/runtime.test.ts`
- 视需要新增：
  - `plugins/parallel-harness/tests/integration/control-plane.test.ts`
  - `plugins/parallel-harness/tests/integration/pr-provider.test.ts`
- 文档：
  - `plugins/parallel-harness/README.md`
  - `plugins/parallel-harness/README.zh.md`
  - `plugins/parallel-harness/docs/architecture/overview.md`
  - `plugins/parallel-harness/docs/architecture/overview.zh.md`

### 必须完成

1. 补齐高风险路径测试：
   - control plane 真实读取 runtime 数据
   - approval / resume
   - execution attestation 可查询
   - PR provider repo_root 路径
   - run-level gate + report evidence
2. 对 README 和架构文档做事实校准：
   - 不宣传未落地能力
   - 测试数量、事件数、执行链路与当前源码一致
3. 如有必要，增加文档中的 “As-Is / To-Be” 明确分层，避免再次把目标态写成现状。

### 验收标准

- `bun test` 覆盖新增高风险路径
- README / architecture docs 与当前实现一致

## 15. 每个 Workstream 的统一收尾动作

Claude 每完成一个 workstream，都必须做下面四步：

1. 跑相关单测和集成测试
2. 跑 `bunx tsc --noEmit`
3. 更新必要文档
4. 记录本 workstream 仍未解决的风险

## 16. 最终必须执行的验证命令

Claude 在全部修改完成后，必须至少执行：

```bash
cd plugins/parallel-harness && bun test
cd plugins/parallel-harness && bunx tsc --noEmit
```

如果新增了独立集成测试文件，也必须显式执行对应测试文件。

## 17. Claude 最终输出格式要求

Claude 最终回复必须包含以下内容：

1. 完成了哪些 workstream
2. 每个 workstream 修改了哪些文件
3. 新增了哪些测试
4. `bun test` 结果
5. `bunx tsc --noEmit` 结果
6. 还剩哪些风险没有在本轮关闭

## 18. 可直接交给 Claude 的执行提示词

下面整段可以直接粘给 Claude 使用。

---

你现在需要修复 `plugins/parallel-harness`，不要重新做宏观分析，不要只写文档，不要只补测试。你必须直接改代码、补测试、运行验证，并把所有修改落到仓库里。

先完整阅读以下文档：

- `plugins/parallel-harness/docs/architecture_and_research/2026-03-30/01_lifecycle_architecture_design.md`
- `plugins/parallel-harness/docs/architecture_and_research/2026-03-30/04_parallel_harness_implementation_review.md`
- `plugins/parallel-harness/docs/architecture_and_research/2026-03-30/05_parallel_harness_enhancement_blueprint.md`
- `plugins/parallel-harness/docs/architecture_and_research/2026-03-30/12_claude_latest_remediation_execution_plan.md`

重要：不要再按 `08/09/11` 的旧问题列表施工，那几份文档包含已经修过或已经进入主链的内容。你必须以 `12_claude_latest_remediation_execution_plan.md` 为唯一执行施工单。

你的目标是按以下顺序完成全部修复：

1. 类型环境与工程基线闭环
2. 执行平面硬化与 attestation 真相化
3. PR/Git 仓库隔离
4. context budget 闭环
5. Requirement Grounding 消费闭环
6. GateSystem 分层与证据聚合
7. Hook / Instruction / Skill effect 化
8. 高风险路径测试与文档一致性闭环

禁止事项：

- 禁止只补测试，不修实现
- 禁止新增不接主链的孤立模块
- 禁止修已经修过的旧问题
- 禁止只修 happy path
- 禁止用 README 文案替代实现修复

每个 workstream 完成后，你都必须：

1. 运行相关测试
2. 运行 `cd plugins/parallel-harness && bunx tsc --noEmit`
3. 更新必要文档
4. 记录剩余风险

全部完成后，你必须至少运行：

```bash
cd plugins/parallel-harness && bun test
cd plugins/parallel-harness && bunx tsc --noEmit
```

最终输出必须包含：

1. 完成了哪些 workstream
2. 修改了哪些文件
3. 新增了哪些测试
4. 测试结果
5. 类型检查结果
6. 仍存在的风险

---

## 19. 这份文档的完成定义

如果 Claude 严格按本文档执行，最终应达到的状态是：

- 类型环境闭环
- 执行代理从软约束升级为真实控制项
- PR/Git 操作不再依赖错误目录
- 上下文预算变成运行时真实字段
- grounding 成为后续环节真相源
- gate 体系完成强弱分层
- 扩展层可以实际影响主链
- 高风险路径有测试与文档闭环

这才是当前版本 `parallel-harness` 进入下一轮稳定演进的正确起点。
