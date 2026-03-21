# parallel-harness 架构概览

## 1. 系统定位

`parallel-harness` 是一个 Claude Code 插件，提供任务图驱动的并行 AI 工程控制面。

核心设计原则：
- 先建图，再调度，再验证
- 实现与验证分离
- 成本感知的自动模型路由
- 最小上下文包
- 文件所有权严格隔离

## 2. 架构层次

```
┌─────────────────────────────────────────────┐
│             用户意图 (User Intent)           │
└───────────────┬─────────────────────────────┘
                ▼
┌─────────────────────────────────────────────┐
│  编排层 (Orchestrator)                       │
│  ┌──────────────┐  ┌────────────────────┐   │
│  │Intent Analyzer│  │Task Graph Builder  │   │
│  └──────┬───────┘  └────────┬───────────┘   │
│         ▼                   ▼               │
│  ┌──────────────┐  ┌────────────────────┐   │
│  │Complexity    │  │Ownership Planner   │   │
│  │Scorer        │  │                    │   │
│  └──────────────┘  └────────────────────┘   │
└───────────────┬─────────────────────────────┘
                ▼
┌─────────────────────────────────────────────┐
│  调度层 (Scheduler)                          │
│  ┌──────────────┐  ┌────────────────────┐   │
│  │Scheduler MVP │  │Worker Dispatch     │   │
│  └──────┬───────┘  └────────┬───────────┘   │
│         ▼                   ▼               │
│  ┌──────────────┐  ┌────────────────────┐   │
│  │Retry Manager │  │Downgrade Manager   │   │
│  └──────────────┘  └────────────────────┘   │
└───────────────┬─────────────────────────────┘
                ▼
┌─────────────────────────────────────────────┐
│  模型路由层 (Model Router)                   │
│  ┌──────────────┐  ┌────────────────────┐   │
│  │Model Router  │  │Escalation Policy   │   │
│  └──────────────┘  └────────────────────┘   │
└───────────────┬─────────────────────────────┘
                ▼
┌─────────────────────────────────────────────┐
│  上下文层 (Context)                          │
│  ┌──────────────┐  ┌────────────────────┐   │
│  │Context       │  │Task Contract       │   │
│  │Packager      │  │Builder             │   │
│  └──────────────┘  └────────────────────┘   │
└───────────────┬─────────────────────────────┘
                ▼
┌─────────────────────────────────────────────┐
│  Worker 执行层                               │
│  ┌────────┐  ┌────────┐  ┌────────┐        │
│  │Worker 1│  │Worker 2│  │Worker N│        │
│  └────┬───┘  └────┬───┘  └────┬───┘        │
└───────┼───────────┼───────────┼─────────────┘
        ▼           ▼           ▼
┌─────────────────────────────────────────────┐
│  验证层 (Verifier Swarm)                     │
│  ┌─────────┐ ┌─────────┐ ┌─────────┐       │
│  │Test     │ │Review   │ │Security │       │
│  │Verifier │ │Verifier │ │Verifier │       │
│  └────┬────┘ └────┬────┘ └────┬────┘       │
│       └──────┬────┘───────────┘             │
│              ▼                              │
│  ┌──────────────────────┐                   │
│  │Result Synthesizer    │                   │
│  └──────────────────────┘                   │
└───────────────┬─────────────────────────────┘
                ▼
┌─────────────────────────────────────────────┐
│  可观测性层 (Observability)                   │
│  ┌──────────┐  ┌────────────┐               │
│  │Event Bus │  │Metrics     │               │
│  └──────────┘  └────────────┘               │
└─────────────────────────────────────────────┘
```

## 3. 核心数据流

```
用户输入 -> Intent Analyzer -> IntentAnalysis
IntentAnalysis -> Task Graph Builder -> TaskGraph (DAG)
TaskGraph -> Ownership Planner -> OwnershipPlan
TaskGraph -> Scheduler -> SchedulePlan (批次)
TaskNode + OwnershipAssignment -> Context Packager -> ContextPack
TaskNode + Complexity -> Model Router -> RoutingResult
ContextPack + RoutingResult -> TaskContract
TaskContract -> Worker -> WorkerOutput
WorkerOutput -> Verifier Swarm -> VerificationResult
VerificationResult -> Result Synthesizer -> SynthesizerOutput
```

## 4. 四类一等角色 (来自 BMAD-METHOD 增强)

| 角色 | 职责 | 输入 | 输出 |
|------|------|------|------|
| Planner | 理解意图，构建任务图 | 用户意图 + 项目上下文 | TaskGraph |
| Worker | 执行具体任务 | TaskContract | WorkerOutput |
| Verifier | 独立验证结果 | Task + WorkerOutput | VerificationResult |
| Synthesizer | 综合所有结果 | 所有 outputs + verifications | SynthesizerOutput |

## 5. 模型 Tier 策略 (来自 claude-code-switch 增强)

| Tier | 适用场景 | 上下文预算 | 成本 |
|------|---------|-----------|------|
| tier-1 | search, format, rename, lint-fix | 16K | 低 |
| tier-2 | implementation, test, general review | 64K | 中 |
| tier-3 | planning, design, critical review | 200K | 高 |

自动路由规则：
- 基于任务复杂度选择基础 tier
- 高风险提升一级
- 每次重试提升一级
- tier-3 为封顶

## 6. MVP 范围

已实现（v0.1.0）：
- Task Graph Schema（完整类型定义）
- Intent Analyzer（基于规则的意图分析）
- Task Graph Builder（DAG 构建 + 环检测 + 关键路径）
- Complexity Scorer（多维度复杂度评分）
- Ownership Planner（路径隔离 + 冲突检测 + 越界验证）
- Context Packager（最小上下文包 + 自动摘要）
- Model Router（3-tier 自动路由 + 升级策略）
- Scheduler MVP（基于依赖的批次调度）
- Event Bus（可观测性基础设施）
- Role Contracts（四类角色标准接口）
- Verifier Result Schema（统一验证结果结构）

接口预留（后续实现）：
- Worker Dispatch（实际派发到 Claude Code 子 Agent）
- Merge Guard（合并前冲突检测）
- Retry Manager（局部重试策略执行）
- Downgrade Manager（自动降级串行）
- Verifier 具体实现（test/review/security/perf）
- Result Synthesizer 具体实现
- Observability Server（HTTP/WS 服务）
- GUI 面板
- CI/PR 集成
