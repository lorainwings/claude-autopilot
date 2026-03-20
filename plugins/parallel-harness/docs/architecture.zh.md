# parallel-harness 架构概览

## 五层能力架构

### 第一层：任务理解层
- **intent-analyzer**: 从用户输入提取结构化意图（task_type, scope, complexity, model_tier 推荐）
- **task-graph-builder**: 从意图分析结果构建 DAG 任务图（支持 file-based/feature-based/layer-based 拆分策略）
- **complexity-scorer**: 多维度加权评分（文件数15%、行数10%、依赖数20%、风险25%、跨切15%、测试15%）
- **ownership-planner**: 文件所有权规划，确保并行任务不冲突（冲突检测 + 序列化/合并守卫/拆分解决策略）

### 第二层：调度执行层
- **scheduler** ✅: 最小调度器 MVP，支持 FIFO/复杂度/风险三种优先策略，分层执行计划
- worker-dispatch 🔲: 预留
- retry-manager 🔲: 预留
- downgrade-manager 🔲: 预留

### 第三层：模型路由层
- **model-router** ✅: 三层模型路由（tier-1 haiku 搜索/格式化, tier-2 sonnet 实现/审查, tier-3 opus 规划/设计），成本估算
- cost-controller 🔲: 预留
- escalation-policy 🔲: 预留

### 第四层：验证 swarm 层
- **test-verifier** ✅: 测试文件存在性/覆盖率检查
- **review-verifier** ✅: 代码质量审查（超长函数、调试代码、硬编码密钥）
- **security-verifier** ✅: 安全扫描（eval/exec、SQL 注入、路径遍历、ReDoS）
- **perf-verifier** ✅: 性能反模式检测（N+1、循环 await、同步 I/O）
- **result-synthesizer** ✅: 结果综合（加权评分 test:30% review:25% security:30% perf:15%）

### 第五层：工程控制面层（预留）
- event-bus 🔲
- observability-server 🔲
- session-state 🔲

## 数据流

用户输入 → IntentAnalyzer → IntentAnalysis
    → TaskGraphBuilder → TaskGraph (DAG)
    → ComplexityScorer → 带评分的 TaskGraph
    → OwnershipPlanner → 带所有权的 TaskGraph
    → Scheduler → 分层执行计划
    → [ModelRouter 路由模型] → Worker 并行执行
    → [VerifierSwarm 验证] → SynthesizedResult
    → [MergeGuard 合并守卫] → 最终输出

## 角色合同系统

四类一等角色，每类都有 input/output contract、失败语义、资源边界：

| 角色 | 输入 | 输出 | 失败策略 | 资源边界 |
|------|------|------|----------|----------|
| Planner | 用户意图 | TaskGraph | 重试2次, abort | 全文件只读 |
| Worker | TaskNode+ContextPack | 文件变更 | 重试3次, escalate | 仅 allowed_paths |
| Verifier | TaskNode+文件变更 | VerifierResult | 重试1次, skip | 只读 |
| Synthesizer | VerifierResult[] | SynthesizedResult | 不重试, escalate | 只读 |

## 核心 Schema

- **TaskNode**: 任务节点（id, title, goal, dependencies, risk_level, allowed/forbidden_paths, acceptance_criteria, required_tests, model_tier, verifier_set）
- **TaskGraph**: 任务图 DAG（节点集合 + 状态 + 时间戳）
- **ContextPack**: 最小上下文包（任务专属文件集 + 约束 + 引用）
- **VerifierResult**: 验证结果（类型, 状态, 分数, 发现列表）
- **RoleContract**: 角色合同（输入输出 schema + 失败语义 + 资源边界）

## 与 spec-autopilot 的架构边界

| 维度 | spec-autopilot | parallel-harness |
|------|---------------|-----------------|
| 核心模型 | 8 阶段线性工作流 | DAG 任务图 |
| 执行模式 | 串行 | 并行 |
| 文件控制 | 无显式所有权 | 所有权规划 + 冲突检测 |
| 模型使用 | 单一模型 | 三层路由 |
| 验证 | Hook 门禁 | Verifier Swarm |
| 成本控制 | 无 | 模型路由 + 成本估算 |
