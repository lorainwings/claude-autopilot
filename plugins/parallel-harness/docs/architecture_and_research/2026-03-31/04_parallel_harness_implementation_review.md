# 04. parallel-harness 当前实现评审

## 1. 评审范围与口径

本报告评审的是 `2026-03-31` 当前工作区中的真实实现，不是 README 的目标态描述。

证据来源：

1. 源码审阅：`plugins/parallel-harness/runtime/**`
2. 本地验证：
   - `bun test` -> `268 pass / 0 fail / 601 expect()`
   - `bunx tsc --noEmit` -> 通过
3. 文档对照：`README.md`、`README.zh.md`、`docs/**`

本报告优先列问题与风险，不复述优点。

## 2. 总结结论

当前版本相较于 `2026-03-30` 已有两个明显改进：

- 类型检查已恢复为绿色
- `repo_root` 已接入 PR 创建路径，旧的高风险目录漂移问题已缓解

但如果目标是“覆盖产品设计、UI 设计、技术方案、前后端实现、测试质量和专业报告的最强 harness”，当前实现仍存在几类关键短板：

- 生命周期仍以代码执行为中心，而不是以阶段工件为中心
- 执行隔离仍以后验校验为主，不是强约束
- 上下文治理仍以路径过滤和静态截断为主，不是语义治理
- gate 体系仍混合了真实验证与启发式代理指标
- 报告专业性和证据追溯深度仍不足

## 3. Findings

### Critical-1. 全流程阶段工件尚未成为主链对象，当前系统仍然主要是“代码编排器”

**证据**

- `requirement-grounding.ts` 当前默认 `delivery_artifacts` 只有 `["code", "tests"]`
- `task-graph-builder.ts` 只围绕 sub-goals、domain、allowed_paths 构图
- `gate-system.ts` 的 gate 全部围绕代码、测试、评审、安全、覆盖率等工程态对象
- `report-aggregator.ts` 只聚合 run、gate、attestation，未聚合 PRD/UI/ADR/测试矩阵等阶段工件

**风险**

- 产品设计、UI 设计、技术方案阶段仍可能被跳过或弱化成自然语言摘要
- “全流程稳定性”在当前实现里还不是系统约束，只是目标表述

**建议**

- 引入 `StageContract` 体系，把 PRD、IA、UI state matrix、ADR、接口契约、测试矩阵、发布报告做成必交工件

### Critical-2. ExecutionProxy 仍不是强执行代理，隔离与可信 attestation 仍不足

**证据**

- `execution-proxy.ts` 的 `prepareExecution()` 只做模型/cwd/tool policy 序列化准备
- `finalizeExecution()` 主要根据 `WorkerOutput` 派生 `ExecutionAttestation`
- attestation 中 `tool_calls` 为空数组，`diff_ref` 缺失
- `executeTask()` 仍通过 `WorkerExecutionController` 调用 worker，`ExecutionProxy` 并未直接拦截真实工具调用

**风险**

- 当前系统更接近“执行后证明”，不是“执行中强约束”
- 当模型或工具链偏离 contract 时，系统仍以事后发现为主

**建议**

- 把 `ExecutionProxy` 升级为真实执行面：工作树、命令、工具调用、diff、stdout/stderr、路径策略都由它直接掌控

### High-1. Context packing 已接线，但仍然偏路径过滤和静态截断，相关性不足

**证据**

- `context-packager.ts` 的相关文件筛选主要基于 `allowed_paths`
- snippet 提取为“每个文件前 N 行”
- 压缩策略名义上有 summarize，实际触发后写入的是 `truncate`
- 未看到基于 symbol、dependency output、semantic retrieval 的优先级排序

**风险**

- 仓库变大后，context 质量会先于 context 体积成为瓶颈
- 容易把“路径内的前几个文件”误当成“任务真正需要的证据”

**建议**

- 引入 `ContextEnvelopeV2`，按阶段、角色和依赖产物做证据排序

### High-2. Requirement grounding 仍然过于启发式，无法稳定承载复杂需求理解

**证据**

- `groundRequirement()` 主要基于关键词和长度判断
- impacted modules 通过固定关键词表推断
- 歧义阻断主要依赖 `ambiguity_items.length > 2`

**风险**

- 对复杂业务需求、非功能需求、多模块联动需求的理解仍不稳定
- 需求理解不到位的问题只能被粗粒度阻断，难以被持续跟踪

**建议**

- 将 grounding 升级为多阶段合同和 clarification loop，而不是单次启发式扫描

### High-3. Gate 体系覆盖广，但真实性分层不够清晰

**证据**

- `test` 和部分 `lint_type` 属于真实命令执行
- `review`、`security`、`coverage`、`documentation`、`perf`、`release_readiness` 仍包含较多启发式规则
- 当前 gate 还没有专门的设计评审、架构评审、测试设计充分性评审

**风险**

- 外部读者容易把“9 类 gates”误读为“9 类同等级硬门禁”
- 奖励挟持和表面合规仍有较大空间

**建议**

- 将 gate 正式分成 `hard gates` 与 `signal gates`
- 引入 stage-specific gates 与 hidden verification

### High-4. PR 集成已修复 repo_root 绑定，但仍直接操作主工作区分支

**证据**

- `pr-provider.ts` 中 `createPR()` 仍会执行 `git checkout -b`、`git add`、`git commit`、`git push`
- 当前没有 worktree 级隔离，也没有“每个 run 独立沙箱仓库”的抽象

**风险**

- 多 run 并发、脏工作区、开发中分支共存时仍可能产生操作风险
- 与“并行 harness”目标不完全一致

**建议**

- 对高风险或并行 run 默认切独立 worktree
- PR provider 只面向 run-owned worktree 操作

### Medium-1. Control Plane 写模型仍不完整

**证据**

- `control-plane.ts` 中 `retryTask()` 明确返回“尚未实现”
- `listRuns()` 的 `task_count` 仍以 `completed_attempts` 为主，不是完整 `task_graph`

**风险**

- 运维侧无法真正对失败节点做安全重调度
- 查询视图与计划视图仍可能不一致

**建议**

- 实现 graph-aware retry
- 让 control plane 读模型以 `RunPlan` 为真相源

### Medium-2. 报告聚合仍偏工程摘要，距离“专业报告生成”有明显差距

**证据**

- `report-aggregator.ts` 的 `RunReport` 结构仍偏轻量摘要
- 目前没有：
  - 管理摘要模板
  - 设计决策索引
  - 风险关闭清单
  - 残余风险清单
  - 工件引用规范

**风险**

- 最终报告更像运行结果摘要，而不是专业交付文档

**建议**

- 引入报告模板系统，按 audience 区分工程版、管理版、审计版

### Medium-3. 文档和对外宣称与当前状态不完全一致

**证据**

- `README.md`、`README.zh.md`、`docs/marketplace-readiness*.md` 仍写 `219 pass / 0 fail / 499 expect()`
- 多份文档继续以“GA / production-ready”描述整体系统
- 实际本地验证已是 `268 pass / 0 fail / 601 expect()`，而且关键问题已经从类型错误转到执行硬化和阶段合同缺失

**风险**

- 外部理解会把当前系统当成“功能与治理都已定型”
- 团队内部也会低估剩余工程量

**建议**

- 更新对外文档中的测试数据与成熟度表述
- 把“当前已实现”与“目标态能力”明确分开

## 4. 评审结论

当前 `parallel-harness` 最准确的定义不是“还没做出来”，也不是“已经完成最强形态”，而是：

**一个主链已经打通、治理骨架明确、测试基线健康，但仍需把阶段合同、执行隔离、独立验证和专业报告做成硬能力的并行工程 harness。**

换句话说：

- 代码骨架和状态机基础已经足够好
- 真正的短板已经从“有没有”转向“够不够硬、够不够专业、够不够全流程”

这也是后续增强方案应聚焦的方向。
