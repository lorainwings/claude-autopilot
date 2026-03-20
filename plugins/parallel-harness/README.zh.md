> [English](README.md) | 中文

# parallel-harness

> 并行 AI 平台 / AI 软件工程控制面插件 -- 面向 Claude Code 的任务图驱动编排引擎。

[![Version](https://img.shields.io/badge/version-0.1.0-blue.svg)](package.json)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

## 概述

**parallel-harness** 是 [lorainwings-plugins](https://github.com/lorainwings/claude-autopilot) 市场中的第二个插件，与 **spec-autopilot** 并列。spec-autopilot 聚焦于 *规范驱动的顺序交付流水线*（8 阶段工作流 + 3 层门禁），而 parallel-harness 解决另一个挑战：**复杂软件工程任务的智能分解与并行编排**。

### 核心设计原则

| 原则 | 含义 |
|------|------|
| **任务图优先 (Task-Graph-First)** | 所有用户意图在开始工作前先分解为有向无环任务图 |
| **模型路由感知 (Model-Routing-Aware)** | 根据任务复杂度将任务分派到最具成本效益的模型层级 (tier-1/2/3) |
| **验证器驱动 (Verifier-Driven)** | 任何结果必须通过验证 swarm（测试/评审/安全/性能）才被接受 |
| **CI/PR 就绪 (CI/PR Ready)** | 输出设计为可直接集成到 CI 流水线和 PR 工作流 |

## 核心特性

### 任务图引擎
- **意图分析器 (Intent Analyzer)**: 将自然语言解析为结构化工程意图，提取动作/范围/约束
- **任务图构建器 (Task Graph Builder)**: 将意图分解为 DAG 结构的任务节点，带类型化依赖
- **复杂度评分器 (Complexity Scorer)**: 多维评分（算法、集成、领域、歧义度）用于路由决策
- **所有权规划器 (Ownership Planner)**: 文件级隔离规划，冲突检测与合并守卫

### 调度器
- **并行执行**: 依赖感知的并行分派，可配置并发上限
- **优先策略**: FIFO、关键路径、成本优化三种调度策略
- **执行规划**: 预执行计划生成，含预估时间线和资源分配

### 模型路由器
- **分层路由**: 三层模型分类（tier-1: 旗舰级, tier-2: 均衡级, tier-3: 快速级）
- **成本估算**: 逐任务 token 预算估算与聚合成本追踪
- **升级策略**（预留）: 验证失败时自动升级到更高层级

### 验证 Swarm
- **测试验证器**: 自动化测试执行与结果验证
- **评审验证器**: 代码质量与风格一致性检查
- **安全验证器**: 漏洞模式扫描与依赖审计
- **性能验证器**: 基准回归检测
- **结果综合器**: 聚合多验证器结果为统一裁定

### 上下文打包器
- **最小上下文包**: 仅提取与每个任务相关的文件和符号
- **相关性评分**: 基于 TF-IDF 启发的评分机制，按相关性排序上下文片段
- **Token 管理**: 硬性 token 预算约束与优雅降级

## 架构

```
+------------------------------------------------------------------+
|                  第五层：工程控制面                                  |
|          (事件总线, 可观测性, 会话状态) [预留]                       |
+------------------------------------------------------------------+
|                  第四层：验证 Swarm                                 |
|    测试验证器 | 评审验证器 | 安全验证器 |                            |
|    性能验证器 | 结果综合器                                          |
+------------------------------------------------------------------+
|                  第三层：模型路由                                    |
|       模型路由器 | 成本控制器 | 升级策略                              |
+------------------------------------------------------------------+
|                  第二层：调度与执行                                  |
|    调度器 | Worker 分派 | 重试管理器 | 降级管理器                     |
+------------------------------------------------------------------+
|                  第一层：任务理解                                    |
|    意图分析器 | 任务图构建器 | 复杂度评分器 |                         |
|    所有权规划器                                                     |
+------------------------------------------------------------------+

数据流:
  用户输入 --> 意图分析器 --> 任务图构建器
       --> 复杂度评分器 --> 所有权规划器
       --> 调度器 --> 模型路由器 --> [执行]
       --> 验证 Swarm --> 结果综合器 --> 输出
```

## 快速开始

### 安装

```bash
# 克隆仓库
git clone https://github.com/lorainwings/claude-autopilot.git
cd claude-autopilot

# 安装依赖
cd plugins/parallel-harness
bun install

# 类型检查
bun run typecheck
```

### 基本使用

parallel-harness 通过 Claude Code 的插件系统激活。安装后，它会拦截复杂的多文件任务并自动：

1. 分析用户意图，将其分解为任务图
2. 评估复杂度并规划文件所有权
3. 以适当的模型层级调度任务并行执行
4. 通过验证 swarm 验证结果
5. 综合最终裁定并交付输出

## 项目结构

```
plugins/parallel-harness/
├── .claude-plugin/
│   └── plugin.json            # 插件清单
├── docs/
│   ├── architecture.zh.md     # 详细架构文档
│   └── mvp-scope.zh.md        # MVP 范围与路线图
├── runtime/
│   ├── models/                # 模型层级定义与路由
│   ├── orchestrator/          # 核心编排逻辑
│   │   ├── intent-analyzer.ts
│   │   ├── task-graph-builder.ts
│   │   ├── complexity-scorer.ts
│   │   ├── ownership-planner.ts
│   │   └── context-packager.ts
│   ├── scheduler/             # 并行调度引擎
│   │   └── scheduler.ts
│   ├── schemas/               # TypeScript 类型定义
│   │   ├── task-node.ts
│   │   ├── task-graph.ts
│   │   ├── intent.ts
│   │   ├── complexity.ts
│   │   ├── ownership.ts
│   │   └── verifier-result.ts
│   ├── session/               # 会话状态管理
│   │   └── session-store.ts
│   └── verifiers/             # 验证 swarm
│       ├── test-verifier.ts
│       ├── review-verifier.ts
│       ├── security-verifier.ts
│       ├── perf-verifier.ts
│       └── result-synthesizer.ts
├── skills/                    # Claude Code 技能定义
├── tests/                     # 测试套件
├── tools/                     # 构建与工具脚本
├── package.json
├── tsconfig.json
├── README.md                  # 英文版
└── README.zh.md               # 本文件（中文版）
```

## 与 spec-autopilot 的差异

| 维度 | spec-autopilot | parallel-harness |
|------|---------------|-----------------|
| **核心范式** | 规范驱动的顺序流水线 | 任务图驱动的并行编排 |
| **工作流** | 固定 8 阶段线性流 | 动态 DAG 任务调度 |
| **质量门禁** | 3 层门禁系统 (L1/L2/L3) | 验证 swarm（测试/评审/安全/性能） |
| **并行粒度** | 领域级（backend/frontend/node） | 任务级，依赖感知调度 |
| **模型策略** | 全程单一模型 | 按任务复杂度分层路由 |
| **文件安全** | 按领域强制所有权 | 细粒度文件级隔离 + 合并守卫 |
| **目标用户** | 完整交付生命周期自动化 | 复杂多文件工程任务 |
| **复杂度处理** | 需求路由（Feature/Bugfix/Refactor/Chore） | 多维复杂度评分 |
| **状态模型** | Phase 检查点 + 崩溃恢复 | 任务图状态 + 会话持久化 |

## 状态

**当前版本：0.1.0 (Alpha)**

这是初始 Alpha 版本，聚焦 MVP 功能集：

- 任务理解层（意图分析、任务图、复杂度评分、所有权规划）
- 基础调度与并行执行
- 模型路由器与分层分类
- 验证 swarm 与结果综合
- 上下文打包器与 token 管理

详见 [docs/mvp-scope.zh.md](docs/mvp-scope.zh.md) 了解完整 MVP 范围和路线图。

## 许可证

[MIT](LICENSE)
