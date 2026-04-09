# Parallel-Harness — 任务图驱动的并行 AI 工程控制面

> **一句话定位**：业界首个将 DAG 任务图调度、文件所有权隔离、多层门禁、RBAC 治理融为一体的
> Claude Code 并行工程插件，让多 Agent 协作从"碰运气"变成"工程化"。

---

## 目录

1. [为什么我们需要这个插件](#1-为什么我们需要这个插件)
2. [它能解决什么问题](#2-它能解决什么问题)
3. [系统架构与实现原理](#3-系统架构与实现原理)
4. [核心执行流程详解](#4-核心执行流程详解)
5. [如何保证效率提升](#5-如何保证效率提升)
6. [如何保证工程稳定性](#6-如何保证工程稳定性)
7. [与市面工具的差异化对比](#7-与市面工具的差异化对比)
8. [更多产品优势](#8-更多产品优势)
9. [关键数据一览](#9-关键数据一览)

---

## 1. 为什么我们需要这个插件

### 1.1 行业趋势：多 Agent 协作是 AI 编程的下一个战场

2025-2026 年，AI 编程领域正在经历两次范式转移：

```mermaid
graph TB
    subgraph shift1["第一次范式转移 (已发生)"]
        A1["补全 Copilot"] --> A2["Agent Cursor/Claude Code"]
    end
    subgraph shift2["第二次范式转移 (正在发生)"]
        B1["单 Agent 串行"] --> B2["多 Agent 并行工程化"]
    end
```

Cursor Background Agent、GitHub Copilot Workspace、Devin 等产品都在探索多 Agent 并行开发。但它们面临一个共同的核心挑战：

> **多个 AI Agent 同时修改同一个代码库，如何保证不冲突、不越界、不失控？**

### 1.2 痛点：多 Agent 协作的四大难题

```mermaid
graph TB
    P[多 Agent 并行的四大难题]

    P1[🔀 合并冲突<br/>多个 Agent 同时修改<br/>重叠文件导致冲突]
    P2[💸 成本失控<br/>所有任务都用最贵模型<br/>Token 消耗无法预测]
    P3[🏗️ 架构不一致<br/>各 Agent 自行其是<br/>代码风格/模式冲突]
    P4[🔍 过程不可控<br/>Agent 执行是黑盒<br/>出问题无法定位]

    P --- P1
    P --- P2
    P --- P3
    P --- P4

    style P1 fill:#ff6b6b,color:#fff
    style P2 fill:#ff922b,color:#fff
    style P3 fill:#fcc419,color:#333
    style P4 fill:#748ffc,color:#fff
```

### 1.3 现有工具为什么解决不了

| 工具 | 方式 | 问题 |
|------|------|------|
| **oh-my-claudecode** | 直接开多个 Agent | 没有任务依赖管理，文件冲突靠运气 |
| **claude-task-master** | 任务分解 | 只拆任务不做所有权隔离和验证 |
| **get-shit-done** | 最小上下文 | 缺少验证器和质量度量 |
| **Devin** | 内部多 Agent | 黑盒架构，不可定制，$500/月 |

### 1.4 我们的答案：Task Graph First

**Parallel-Harness 的核心哲学**：**先建图再调度** —— 禁止直接开 Worker，必须先将复杂任务分解为 DAG（有向无环图），规划好文件所有权，然后才允许并行执行。

```mermaid
graph LR
    subgraph "❌ 传统方式"
        A1[需求] --> B1[直接开 Agent 1]
        A1 --> C1[直接开 Agent 2]
        A1 --> D1[直接开 Agent 3]
        B1 --> E1[合并冲突!]
        C1 --> E1
        D1 --> E1
    end

    subgraph "✅ Parallel-Harness"
        A2[需求] --> B2[意图分析]
        B2 --> C2[构建 DAG]
        C2 --> D2[所有权规划]
        D2 --> E2[模型路由]
        E2 --> F2[安全并行执行]
        F2 --> G2[合并守卫验证]
        G2 --> H2[✅ 无冲突交付]
    end

    style E1 fill:#ff6b6b,color:#fff
    style H2 fill:#51cf66,color:#fff
```

---

## 2. 它能解决什么问题

### 2.1 核心问题矩阵

| 问题域 | 具体问题 | Parallel-Harness 解决方案 |
|--------|---------|-------------------------|
| **任务编排混乱** | 多 Agent 无依赖关系管理 | DAG 任务图 + 拓扑排序 + 关键路径调度 |
| **文件合并冲突** | 多 Agent 修改同一文件 | 文件所有权隔离（独占/共享读/禁止）+ Merge Guard |
| **成本不可控** | 所有任务用同一模型 | 三层模型自动路由（tier-1/2/3）+ 成本账本 + 预算上限 |
| **质量不可控** | Agent 输出无法验证 | 9 类 Gate System + 真实执行（bun test / tsc） |
| **治理缺失** | 谁有权做什么不清楚 | RBAC（4 角色 12 权限）+ 审批工作流 + 策略引擎 |
| **安全隐患** | Agent 可能修改敏感文件 | PathSandbox + ToolPolicy + Security Gate + Policy Engine |
| **过程不透明** | 执行过程无法追踪 | 38 种事件 + EventBus + 审计追踪 + Web GUI |
| **失败不可恢** | 任务失败后无法继续 | Checkpoint + ReplayEngine + 自动重试/降级 |

### 2.2 一个典型场景

> 架构师说："我们需要同时重构用户认证模块、订单支付模块和报表导出模块"

**没有 Parallel-Harness**：三个 Agent 同时开工 → 认证模块的 API 变更导致订单模块调用失败 → 报表模块引用了已删除的工具函数 → 最终合并时大量冲突，手动解决花费比串行还多

**使用 Parallel-Harness**：

```mermaid
graph TD
    A[输入: 重构三个模块] --> B[意图分析器]
    B --> C[识别三个工作域:<br/>auth / order / report]

    C --> D[构建 DAG]
    D --> E[所有权规划]

    E --> F{冲突检测}
    F -->|auth API 被 order 依赖| G[建立依赖边:<br/>auth → order]
    F -->|report 独立| H[report 可并行]

    G --> I[调度计划]
    H --> I

    I --> J[Batch 1: auth + report 并行]
    J --> K[Batch 2: order 串行<br/>等待 auth 完成]
    K --> L[Merge Guard 验证]
    L --> M[9 类 Gate 检查]
    M --> N[✅ 安全交付]

    style N fill:#51cf66,color:#fff
```

---

## 3. 系统架构与实现原理

### 3.1 十六模块分层架构

```mermaid
graph TB
    subgraph "🎯 编排层 (Orchestrator)"
        OA[意图分析器<br/>IntentAnalyzer]
        OB[任务图构建器<br/>TaskGraphBuilder]
        OC[复杂度评分器<br/>ComplexityScorer]
        OD[所有权规划器<br/>OwnershipPlanner]
        OE[角色契约<br/>RoleContracts]
    end

    subgraph "📊 调度层 (Scheduler)"
        SA[DAG 调度器<br/>批次生成 + 优先级排序]
    end

    subgraph "🤖 执行层 (Workers)"
        WA[Worker 运行时<br/>能力注册 + 路径沙箱]
        WB[重试管理器<br/>指数退避 + 模型升级]
        WC[降级管理器<br/>串行化 + tier 提升]
    end

    subgraph "🔍 验证层 (Gates & Guards)"
        GA[9 类 Gate System<br/>test/lint/review/security/...]
        GB[Merge Guard<br/>所有权 + 冲突 + 策略 + 契约]
    end

    subgraph "🏛️ 治理层 (Governance)"
        VA[RBAC Engine<br/>4 角色 12 权限]
        VB[审批工作流<br/>ApprovalWorkflow]
        VC[策略引擎<br/>PolicyEngine]
    end

    subgraph "💾 基础设施层"
        PA[Session 持久化]
        PB[审计追踪 AuditTrail]
        PC[EventBus 38 种事件]
        PD[模型路由器 3-Tier]
        PE[上下文打包器]
        PF[PR 集成 GitHub]
        PG[Control Plane GUI]
    end

    OA --> OB --> OD --> SA
    OC --> OB
    SA --> WA
    WA --> GA
    GA --> GB
    WA --> WB
    WA --> WC
    VA --> WA
    VB --> SA
    VC --> GA
    PA --> PB
    PC --> PG
```

### 3.2 八条核心法则

| # | 法则 | 实现机制 |
|---|------|---------|
| 1 | **先建图再调度** | TaskGraphBuilder 强制 DAG 构建 |
| 2 | **文件所有权强制** | OwnershipPlanner + PathSandbox |
| 3 | **实现与验证分离** | Worker 不能自我验证，必须过 Gate |
| 4 | **最小上下文原则** | ContextPackager 30K Token 预算 |
| 5 | **成本感知路由** | ModelRouter 三层自动决策 |
| 6 | **策略即代码** | PolicyEngine 声明式规则 |
| 7 | **审计优先** | AuditTrail 全事件记录 |
| 8 | **RBAC 治理** | GovernanceEngine 角色授权 |

### 3.3 状态机体系

**Run 生命周期（12 状态）**：

```mermaid
stateDiagram-v2
    [*] --> pending
    pending --> planned : 图构建完成
    planned --> awaiting_approval : 需要审批
    planned --> scheduled : 自动审批
    awaiting_approval --> scheduled : 审批通过
    awaiting_approval --> cancelled : 审批拒绝
    scheduled --> running : 开始执行
    running --> verifying : 任务完成
    verifying --> succeeded : Gate 全部通过
    verifying --> failed : 关键 Gate 失败
    verifying --> partially_failed : 部分失败
    verifying --> blocked : 需要人工介入
    succeeded --> archived
    failed --> archived
    partially_failed --> archived
```

---

## 4. 核心执行流程详解

### 4.1 完整生命周期

```mermaid
sequenceDiagram
    participant U as 用户
    participant O as 编排器
    participant IA as 意图分析器
    participant TG as 任务图构建器
    participant OP as 所有权规划器
    participant MR as 模型路由器
    participant S as 调度器
    participant W as Worker
    participant G as Gate System
    participant MG as Merge Guard
    participant PR as PR Provider

    U->>O: 提交需求
    O->>IA: 分析意图
    IA-->>O: 子目标 + 工作域 + 风险
    O->>TG: 构建 DAG
    TG-->>O: 任务图 + 依赖边 + 关键路径
    O->>OP: 规划所有权
    OP-->>O: 独占/共享/禁止路径
    O->>MR: 路由模型
    MR-->>O: 每任务 Tier 分配

    Note over O: 审批检查 (如需)

    loop 每个批次
        O->>S: 获取下一批次
        S-->>O: Ready 任务列表
        par 并行执行
            O->>W: Worker 1 (PathSandbox)
            O->>W: Worker 2 (PathSandbox)
            O->>W: Worker N (PathSandbox)
        end
        W-->>O: 执行结果 + 实际 Diff
        O->>G: Task-level Gate 验证
        G-->>O: pass / retry / block
    end

    O->>G: Run-level Gate 验证
    O->>MG: Merge Guard 检查
    MG-->>O: 所有权 + 冲突 + 策略 + 契约
    O->>PR: 生成 PR
    PR-->>U: PR URL + Gate 报告
```

### 4.2 DAG 调度算法

```mermaid
graph TD
    A[构建入度表] --> B{是否有 Ready 任务?}
    B -->|是| C[按优先级排序:<br/>1. 关键路径优先<br/>2. 低风险优先<br/>3. 低复杂度优先]
    C --> D{是否高风险?}
    D -->|是| E[并发限制: max 2]
    D -->|否| F[并发限制: max 5]
    E --> G[生成批次]
    F --> G
    G --> H[Promise.all 并行执行]
    H --> I[更新入度表]
    I --> B
    B -->|否| J{全部完成?}
    J -->|是| K[✅ 调度结束]
    J -->|否| L[⚠️ 死锁检测<br/>强制取第一个]
    L --> G

    style K fill:#51cf66,color:#fff
    style L fill:#ffa94d,color:#fff
```

### 4.3 文件所有权模型

```mermaid
graph LR
    subgraph "Task A: 认证模块"
        A_E[独占: src/auth/**]
        A_R[共享读: src/shared/types.ts]
        A_F[禁止: src/order/**]
    end

    subgraph "Task B: 订单模块"
        B_E[独占: src/order/**]
        B_R[共享读: src/shared/types.ts]
        B_F[禁止: src/auth/**]
    end

    subgraph "Task C: 报表模块"
        C_E[独占: src/report/**]
        C_R[共享读: src/shared/types.ts]
        C_F[禁止: src/auth/**<br/>src/order/**]
    end

    A_E -.->|写写冲突检测| CHECK{OwnershipPlanner}
    B_E -.-> CHECK
    C_E -.-> CHECK
    CHECK -->|无冲突| OK[✅ 可并行]
    CHECK -->|有冲突| SERIAL[⚠️ 建议串行化]

    style OK fill:#51cf66,color:#fff
    style SERIAL fill:#ffa94d,color:#fff
```

---

## 5. 如何保证效率提升

### 5.1 三维效率优化体系

```mermaid
graph TB
    subgraph "维度一: 执行并行化"
        E1[DAG 依赖分析<br/>无依赖任务并行]
        E2[批次调度<br/>最大并发 5]
        E3[关键路径优先<br/>缩短总耗时]
        E4[低风险先行<br/>高风险限流]
    end

    subgraph "维度二: 成本智能化"
        C1[Tier-1: 简单任务<br/>搜索/格式化<br/>成本 1x]
        C2[Tier-2: 中等任务<br/>实现/测试<br/>成本 5x]
        C3[Tier-3: 复杂任务<br/>架构/安全<br/>成本 25x]
        C4[预算账本<br/>实时追踪]
    end

    subgraph "维度三: 上下文精简化"
        X1[最小上下文包<br/>只喂相关文件]
        X2[输入预算 30K<br/>超预算自动摘要]
        X3[重试时压缩<br/>第3次起自动瘦身]
    end
```

### 5.2 模型路由决策树

```mermaid
graph TD
    A[新任务到达] --> B{复杂度评分}
    B -->|0-30| C[基础: Tier-1]
    B -->|31-70| D[基础: Tier-2]
    B -->|71-100| E[基础: Tier-3]

    C --> F{风险等级?}
    D --> F
    E --> F
    F -->|high/critical| G[提升一级]
    F -->|low/medium| H[保持]

    G --> I{重试次数?}
    H --> I
    I -->|≥ 2| J[再提升一级]
    I -->|< 2| K[保持]

    J --> L{预算检查}
    K --> L
    L -->|超限| M[受限于 max_model_tier]
    L -->|正常| N[最终 Tier 分配]

    style C fill:#51cf66,color:#fff
    style D fill:#fcc419,color:#333
    style E fill:#ff6b6b,color:#fff
```

### 5.3 效率数据对比

| 场景 | 串行执行 | Parallel-Harness | 提升 |
|------|---------|-----------------|------|
| 3 个独立模块重构 | 3T (串行) | T (全并行) | **3x** |
| 5 个有依赖的任务 | 5T | 2T (3 批次) | **2.5x** |
| 混合复杂度任务 | 全用 Tier-3 成本 | 自动路由 | **成本降低 60-80%** |
| 大型上下文任务 | 全量 200K 喂入 | 30K 精准包 | **Token 节省 85%** |

### 5.4 批量审计写入

AuditTrail 采用批量写入策略：缓冲 100 条事件后一次性持久化，FileStore 带内存缓存避免重复 IO。对比逐条写入，IO 次数降低 **99%**。

---

## 6. 如何保证工程稳定性

### 6.1 九类门禁系统

```mermaid
graph TB
    subgraph "🚫 阻断性 Gate（必须通过）"
        G1[test<br/>真实执行 bun test<br/>解析失败数和文件]
        G2[lint_type<br/>真实执行 tsc + ruff<br/>类型/格式检查]
        G3[security<br/>8 种敏感模式检测<br/>.env/credentials/secret]
        G4[policy<br/>PolicyEngine 评估<br/>策略合规检查]
        G5[release_readiness<br/>所有任务完成检查]
    end

    subgraph "⚠️ 警告性 Gate（建议修复）"
        G6[review<br/>摘要长度/修改范围<br/>源码改动无测试警告]
        G7[perf<br/>Token/耗时/文件数<br/>性能基线检查]
        G8[coverage<br/>bun test --coverage<br/>覆盖率百分比]
        G9[documentation<br/>新增产出无文档更新<br/>文档完整性]
    end

    G1 --> VERDICT{综合判定}
    G2 --> VERDICT
    G3 --> VERDICT
    G4 --> VERDICT
    G5 --> VERDICT
    G6 --> VERDICT
    G7 --> VERDICT
    G8 --> VERDICT
    G9 --> VERDICT

    VERDICT -->|全部通过| PASS[✅ pass]
    VERDICT -->|可重试| RETRY[🔄 retry]
    VERDICT -->|阻断| BLOCK[🚫 block]
    VERDICT -->|建议降级| DOWN[⬇️ downgrade]

    style PASS fill:#51cf66,color:#fff
    style BLOCK fill:#ff6b6b,color:#fff
    style RETRY fill:#fcc419,color:#333
    style DOWN fill:#748ffc,color:#fff
```

### 6.2 四层 Merge Guard

合并前执行四层安全检查：

| 层次 | 检查内容 | 失败处理 |
|------|---------|---------|
| **路径所有权** | Worker 是否写入了禁止路径 | 阻断 + 报告越界文件 |
| **文件冲突** | 多个 Worker 修改同一文件 | schema/config→手动; test→自动合并; doc→last_write_wins |
| **策略合规** | PolicyEngine 全面评估 | 按策略配置执行（block/warn/log） |
| **接口契约** | 上游产出是否满足下游期望 | 阻断 + 报告缺失产出 |

### 6.3 失败分类与自动处置

```mermaid
graph LR
    F[任务失败] --> C{失败分类}

    C -->|临时工具故障| R1[🔄 自动重试<br/>指数退避 1-30s]
    C -->|验证失败| R2[🔄 重试 + 升级模型]
    C -->|超时| R3[🔄 重试 + 升级模型]
    C -->|所有权冲突| R4[⬇️ 降级为串行]
    C -->|预算耗尽| R5[⬇️ 降级 + 通知人工]
    C -->|策略违反| R6[🚫 阻断 + 通知人工]
    C -->|审批拒绝| R7[🚫 阻断 + 通知人工]
    C -->|未知错误| R8[🔄 重试 + 通知人工]

    style R1 fill:#51cf66,color:#fff
    style R2 fill:#51cf66,color:#fff
    style R3 fill:#51cf66,color:#fff
    style R4 fill:#fcc419,color:#333
    style R5 fill:#fcc419,color:#333
    style R6 fill:#ff6b6b,color:#fff
    style R7 fill:#ff6b6b,color:#fff
    style R8 fill:#ffa94d,color:#fff
```

### 6.4 动态降级策略

系统在运行时根据执行情况自动调整策略：

| 触发条件 | 降级动作 | 目的 |
|---------|---------|------|
| 冲突率 > 30% | 半串行模式 | 减少文件冲突 |
| 连续 3 次 Gate 阻断 | 串行 + Tier-3 | 用最强模型确保通过 |
| 关键路径阻塞 > 2 轮 | 优先串行处理 | 疏通关键路径 |

### 6.5 完整恢复链路

```mermaid
graph LR
    A[系统崩溃] --> B[Checkpoint 持久化<br/>crash 时也写入]
    B --> C[ReplayEngine<br/>从审计日志重建]
    C --> D[找到最后成功任务]
    D --> E[从断点恢复执行]
    E --> F[跳过已完成任务]

    style A fill:#ff6b6b,color:#fff
    style F fill:#51cf66,color:#fff
```

### 6.6 测试保障

| 指标 | 数据 |
|------|------|
| 测试文件 | 13 个，覆盖全部 16 个运行时模块 |
| 测试用例 | **295 个** |
| 断言数 | **649 个** |
| 失败数 | **0** |
| 覆盖范围 | 图构建、DAG 验证、所有权、冲突检测、调度、路由、上下文、Gate、Guard、RBAC、审批、持久化、审计、PR、EventBus、Worker、状态机 |

---

## 7. 与市面工具的差异化对比

### 7.1 竞品能力矩阵

| 能力维度 | Parallel-Harness | oh-my-claudecode | claude-task-master | Devin | AutoGen |
|---------|:---:|:---:|:---:|:---:|:---:|
| **DAG 任务图调度** | ✅ 拓扑排序+关键路径 | ❌ 直接开 Agent | ⚠️ 任务拆分 | ⚠️ 内部 | ❌ 无 |
| **文件所有权隔离** | ✅ 独占/共享/禁止 | ❌ 无 | ❌ 无 | ❌ 无 | ❌ 无 |
| **9 类 Gate System** | ✅ 真实执行 | ❌ 无 | ❌ 无 | ⚠️ 内部 | ❌ 无 |
| **三层模型自动路由** | ✅ 成本感知 | ❌ 无 | ❌ 无 | ❌ 固定 | ⚠️ 可配置 |
| **RBAC + 审批** | ✅ 4 角色 12 权限 | ❌ 无 | ❌ 无 | ❌ 无 | ❌ 无 |
| **策略引擎** | ✅ 声明式规则 | ❌ 无 | ❌ 无 | ❌ 无 | ❌ 无 |
| **审计追踪** | ✅ 32 种事件+回放 | ❌ 无 | ❌ 无 | ⚠️ 有限 | ❌ 无 |
| **Web 控制面板** | ✅ 内置 GUI | ❌ 无 | ❌ 无 | ✅ Web | ❌ 无 |
| **重试/降级策略** | ✅ 11 种失败分类 | ❌ 无 | ❌ 无 | ⚠️ 内部 | ❌ 无 |
| **PR 自动生成** | ✅ 结构化 PR | ❌ 无 | ❌ 无 | ✅ 有 | ❌ 无 |
| **开源/可定制** | ✅ 完全可定制 | ✅ 开源 | ✅ 开源 | ❌ 闭源 | ✅ 开源 |
| **价格** | 仅 API 费用 | 免费 | 免费 | $500/月 | 免费 |

### 7.2 差异化设计灵感与超越

我们在设计时系统性地研究了业界 7 个知名项目，提取了它们的优点，并针对它们的缺陷进行了**反向增强**：

| 来源 | 借鉴 | 我们的超越 |
|------|------|----------|
| **claude-task-master** | 任务分解 + 依赖 | 加了所有权隔离和 Verifier 联动 |
| **oh-my-claudecode** | 多 Agent 调度 | 强制 DAG-first，不允许直接开 Agent |
| **BMAD-METHOD** | 四角色方法论 | 方法论映射为运行时接口 |
| **claude-code-switch** | 模型 Tier 定义 | 不只手动切换，做自动路由 + 失败升级 |
| **get-shit-done** | 最小上下文 | 加了 Verifier 和 Metrics |
| **Harness CI** | CI/PR 闭环 | 接任务历史和验证历史 |
| **superpowers** | 低摩擦能力入口 | 能力清单化 + 注册表 |

### 7.3 核心差异化总结

```mermaid
graph TB
    CENTER[Parallel-Harness<br/>核心差异化]

    A[📊 DAG-First<br/>强制先建图再调度<br/>拓扑排序 + 关键路径]
    B[🔒 所有权隔离<br/>独占/共享/禁止三级<br/>规划→执行→验证全链路]
    C[💰 成本感知<br/>三层自动路由<br/>预算账本 + 动态升降]
    D[🛡️ 九类门禁<br/>真实执行 test/lint<br/>不是模拟检查]
    E[🏛️ 企业治理<br/>RBAC + 审批 + 策略<br/>审计追踪 + 回放]
    F[🖥️ Control Plane<br/>内置 Web GUI<br/>API + 实时仪表盘]

    CENTER --- A
    CENTER --- B
    CENTER --- C
    CENTER --- D
    CENTER --- E
    CENTER --- F
```

---

## 8. 更多产品优势

### 8.1 声明式策略引擎

通过 JSON 配置定义安全策略，无需编写代码：

```json
{
  "rules": [
    {"name": "禁止修改 .env", "action": "block", "condition": {"type": "path_match", "pattern": "**/.env*"}},
    {"name": "高风险需审批", "action": "require_approval", "condition": {"type": "risk_level", "min": "high"}},
    {"name": "预算警告", "action": "warn", "condition": {"type": "budget_threshold", "percentage": 80}}
  ]
}
```

支持 9 种规则类别、6 种条件类型、4 种执行动作，覆盖企业级安全合规需求。

### 8.2 10 阶段 Hook 系统

| Hook 阶段 | 触发时机 | 典型用途 |
|----------|---------|---------|
| pre_plan | 规划前 | 预检环境 |
| post_plan | 规划后 | 审查 DAG |
| pre_dispatch | 调度前 | 预算检查 |
| post_dispatch | 调度后 | 通知 |
| pre_verify | 验证前 | 自定义预检 |
| post_verify | 验证后 | 结果采集 |
| pre_merge | 合并前 | 冲突预检 |
| post_merge | 合并后 | 集成测试 |
| pre_pr | PR 前 | 模板检查 |
| post_pr | PR 后 | 通知 |

### 8.3 内置 Web 控制面板

HTTP API + 嵌入式 Web GUI（端口 9800，GitHub 暗色主题）：

- **Run 列表视图**：所有执行记录一览
- **Run 详情视图**：概览面板 + Gate 结果 + Task Graph 可视化 + 任务列表 + 时间线
- **API 端点**：支持 Run 查看 / 取消 / 任务重试 / 审批通过或拒绝
- **API Token 鉴权**：POST 和非 health GET 请求需要认证

### 8.4 四层指令继承

```mermaid
graph TD
    A[Org 级指令<br/>组织通用规范] --> B[Repo 级指令<br/>仓库特有约束]
    B --> C[Path 级指令<br/>模块级覆盖]
    C --> D[Language 级指令<br/>语言特有规范]
    D --> E[最终合并指令]

    style E fill:#51cf66,color:#fff
```

### 8.5 PR 自动化

- **结构化 PR 描述**：任务摘要 + Walkthrough + Gate 结果 + 成本汇总
- **行级评论**：将 Gate Findings 转换为 PR 代码行级评论
- **CI 故障解析**：自动分类 CI 失败类型（build/test/lint/type_check/deploy）
- **映射追踪**：维护 Run ↔ Issue ↔ PR ↔ CI 的完整关联

---

## 9. 关键数据一览

| 维度 | 数据 |
|------|------|
| 产品版本 | v1.0.3 (GA) |
| Schema 版本 | 1.0.0 |
| 技术栈 | TypeScript + Bun |
| 运行时模块 | **16 个** |
| 代码量 | **5000+ 行** TypeScript 运行时 |
| 测试用例 | **295 个** |
| 断言数 | **649 个** |
| 测试通过率 | **100%** |
| 状态数 | Run: 12 个, Task Attempt: 8 个 |
| Gate 类型 | **9 种** |
| 事件类型 | **38 种** |
| 审计事件类型 | **32 种** |
| RBAC 角色 | 4 个（admin/developer/reviewer/viewer） |
| RBAC 权限 | **12 种** |
| 失败分类 | **11 种** |
| Hook 阶段 | **10 个** |
| 策略条件类型 | 6 种 |
| 策略执行动作 | 4 种 |
| Skill 数量 | 4 个 |
| 设计参考来源 | 7 个知名项目 |
| 配置 Schema 校验 | JSON Schema 验证 |

---

> **Parallel-Harness** — 不是简单地开多个 Agent，而是让多 Agent 协作成为一门可控的工程学科。

---

*文档版本: v1.0 | 最后更新: 2026-03-25*
