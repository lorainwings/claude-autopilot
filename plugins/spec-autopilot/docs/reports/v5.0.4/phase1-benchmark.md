# v5.0.4 Phase 1 质量评审 Benchmark

**审计日期**: 2026-03-13
**插件版本**: v5.0.4 (基于 v5.1 技术债清剿后)
**审计方**: AI 质量评审 Agent (Claude Opus 4.6)
**审计方式**: 静态协议分析 + 代码审计 + 三场景构造仿真（dry-run，非实际运行）
**对比基线**: `docs/reports/v5.0/phase1-benchmark.md` (v5.0.1, 2026-03-13)

---

## 1. 审计摘要

### 总分

| 子步骤 | 评分 | 较 v5.0 变化 |
|--------|------|-------------|
| A. 需求分析 (Requirement Analysis) | **81/100** | -1 (v5.0: 82) |
| B. 需求理解 (Requirement Understanding) | **87/100** | +2 (v5.0: 85) |
| C. 调研 (Research) | **80/100** | +2 (v5.0: 78) |
| D. 澄清 (Clarification) | **86/100** | -2 (v5.0: 88) |
| **Phase 1 综合** | **84/100** | **+1** (v5.0: 83) |

### 关键发现

1. **v5.1 中间 Checkpoint 是最大改进**: Phase 1 崩溃恢复从"全阶段重来"进化为"调研/决策粒度恢复"，直接修复了 v5.0 报告标记的 #4 缺口（"Phase 1 无中间 checkpoint"）。
2. **需求路由 `routing_overrides` 的 L2 闭环已验证**: `_post_task_validator.py` 第 175-213 行及第 276-289 行确认了 `requirement_type` 分类结果可正确传导到 Phase 4 门禁。但分类本身仍存在复合类型盲区。
3. **validate-decision-format.sh 已被标记 DEPRECATED**: 决策格式验证已合并入 `post-task-validator.sh` / `_post_task_validator.py` (v4.0)，但协议文档 `phase1-supplementary.md` 第 59 行仍引用旧脚本名称，存在文档-代码不一致。
4. **`min_qa_rounds` 配置存在但协议未消费**: 配置模板中定义了 `phases.requirements.min_qa_rounds: 1`，但 Phase 1 核心流程文档中无任何步骤引用此配置值来强制最低 QA 轮数。

---

## 2. Phase 1 四步流程架构分析

### 2.1 整体架构图

```
$ARGUMENTS 输入
      │
      ▼
┌─────────────────────────────────────────────┐
│  Step 1.1: 需求来源解析                       │
│  Step 1.1.5: 需求信息量评估 (确定性规则)        │
│  Step 1.1.6: 需求类型分类与路由 (确定性规则)     │
└─────────────────────────────────────────────┘
      │                                [A. 需求分析]
      ▼
┌─────────────────────────────────────────────┐
│  Step 1.2-1.3: 三路并行调研                    │
│  ┌─ Auto-Scan ──→ Steering Documents         │
│  ├─ Research Agent ──→ research-findings.md   │
│  └─ Web Search ──→ web-research-findings.md   │
│  v5.1: 调研完成后写入 phase-1-interim.json     │
└─────────────────────────────────────────────┘
      │                                [C. 调研]
      ▼
┌─────────────────────────────────────────────┐
│  Step 1.4: 复杂度评估与分路                    │
│  Step 1.5: business-analyst 分析              │
│  Step 1.5.5: 结构化决策协议                    │
└─────────────────────────────────────────────┘
      │                                [B. 需求理解]
      ▼
┌─────────────────────────────────────────────┐
│  Step 1.6: 多轮决策循环 LOOP                   │
│  Step 1.7: 生成结构化提示词                    │
│  Step 1.8: 最终确认                           │
│  v5.1: 每轮决策后写入 phase-1-interim.json     │
└─────────────────────────────────────────────┘
      │                                [D. 澄清]
      ▼
┌─────────────────────────────────────────────┐
│  Step 1.9: 写入 phase-1-requirements.json     │
│  Step 1.10: 可配置用户确认点                   │
└─────────────────────────────────────────────┘
```

### 2.2 核心设计原则审计

| 原则 | 实现状态 | 审计结论 | 引用位置 |
|------|---------|---------|---------|
| 绝不假设，始终用户决策 | 已实现 | 决策卡片机制 + AskUserQuestion 强制用户选择 | `phase1-requirements.md` 第 7 行 |
| 确定性规则优先于 AI 判断 | 部分实现 | 信息量评估和类型分类是确定性的；但搜索决策中 `has_precedent` 仍需 AI 提取关键词 | `phase1-requirements-detail.md` 第 260-268 行 |
| 子 Agent 后台化 + JSON 信封 | 已实现 | 四路子 Agent 均 `run_in_background: true`，主线程仅消费信封 | `SKILL.md` 第 124-127 行 |
| 崩溃恢复粒度 | **v5.1 显著增强** | 中间 checkpoint 支持 `research_complete` 和 `decision_round_N` 恢复 | `SKILL.md` 第 132-157 行 |

### 2.3 关键文件角色映射

| 文件 | 角色 | Phase 1 中的责任 |
|------|------|-----------------|
| `SKILL.md` 第 98-162 行 | 主编排协议 | Phase 1 概要流程 + 并行调度 + 中间 checkpoint |
| `phase1-requirements.md` | 核心流程 | 10 步详细流程骨架 |
| `phase1-requirements-detail.md` | 详细模板 | Prompt 模板 + 规则引擎 + 评估规则 |
| `phase1-supplementary.md` | 补充协议 | 苏格拉底模式 + 崩溃恢复 + 格式验证 |
| `config-schema.md` 第 22-62 行 | 配置模板 | `phases.requirements` 配置节 |
| `guardrails.md` | 护栏约束 | 结构化决策 + 并行编排 + 错误处理 |
| `post-task-validator.sh` / `_post_task_validator.py` 第 552-625 行 | L2 Hook | 决策格式确定性验证 |
| `rules-scanner.sh` | 规则扫描器 | Auto-Scan 阶段提取项目约束 |

---

## 3. 仿真场景评估矩阵

### 场景定义

| 场景 | 需求描述 | 预期路由 | 预期复杂度 |
|------|---------|---------|-----------|
| S1 (简单) | "给 Express 后端添加 /health 健康检查端点" | Feature | small |
| S2 (中等) | "将现有 REST API 迁移为 GraphQL，保持向后兼容" | Refactor | large |
| S3 (复杂) | "实现分布式配置中心客户端，支持热更新、灰度发布、多集群容灾" | Feature | large |

### 3.1 场景 S1: 健康检查端点 — 逐步仿真

**Step 1.1** — 需求来源：文本输入，直接作为 `RAW_REQUIREMENT`。

**Step 1.1.5** — 信息量评估（确定性规则检测）:

| 维度 | 检测 | 结果 |
|------|------|------|
| brevity (< 20 字) | "给 Express 后端添加 /health 健康检查端点" = 20 字符 | 边界值：恰好等于 20，不触发 |
| no_tech_entity | 含 "Express"、"/health" | 不触发 |
| no_metric | 无量化指标 | **触发** |
| vague_action | 含 "添加" | 不触发 |

**flags = 1 < 2** -> 正常流程。

**缺陷 D-01**: 第 25 行定义 brevity 阈值为 `< 20 字符`。本场景刚好 20 字符，但中文"字"和 ASCII"字符"计算方式不同（中文 1 字 = 3 bytes UTF-8）。如果使用 byte 计算，"给 Express 后端添加 /health 健康检查端点"远超 20 bytes。**协议未明确是字符还是字节**。
- **文件**: `phase1-requirements.md` 第 25 行
- **严重度**: 低

**Step 1.1.6** — 需求类型分类:

| 关键词匹配 | 结果 |
|-----------|------|
| Bugfix: "修复/fix/bug..." | 不匹配 |
| Refactor: "重构/refactor/迁移..." | 不匹配 |
| Chore: "配置/CI/CD..." | 不匹配 |
| Feature: 默认 | **匹配** |

分类结果: `requirement_type: "feature"` — 正确。

**Step 1.2-1.3** — 三路并行调研:

| Agent | 行为 | 预期产出 |
|-------|------|---------|
| Auto-Scan | 扫描 Express 项目结构、`package.json`、现有路由模式 | `project-context.md`（Express 版本、路由模式、中间件链） |
| Research Agent | depth=basic (小需求)，执行任务 1-4 | `research-findings.md`（影响 1-2 个文件，无新依赖） |
| Web Search | 规则引擎判定: `task_type = feature` -> 不满足 `skip_when_ALL_true` 的 `task_type in {bugfix, refactor}` 条件 -> **执行搜索** | `web-research-findings.md` |

**缺陷 D-02**: 对于"给 Express 添加 /health 端点"这种极简需求，Web 搜索的 ROI 很低（Express health check 是基础知识），但规则引擎因为 feature 类型不满足跳过条件，仍会执行搜索。**搜索决策缺少 "trivial complexity" 快速跳过路径**。
- **文件**: `phase1-requirements-detail.md` 第 236-254 行
- **严重度**: 低（浪费少量 Token，不影响正确性）

**Step 1.4** — 复杂度评估:

```
total_files = len(new_files:[]) + len(modified_files:["routes/health.js"或类似]) = 1
1 <= 2 (config.thresholds.small) → complexity = "small"
```

无额外升级因子。**结果正确**。

**Step 1.5-1.6** — business-analyst + 决策:

小复杂度快速路径: 合并为一次确认，最多 1 轮。预期决策点极少（可能仅"响应格式 JSON vs 纯文本"）。

**Step 1.7-1.10** — 提示词生成、确认、checkpoint。

**场景 S1 评估矩阵**:

| 步骤 | 评分 | 理由 |
|------|------|------|
| A. 需求分析 | 85 | 分类正确；brevity 边界值问题轻微；搜索浪费但不影响正确性 |
| B. 需求理解 | 92 | 小需求理解无障碍；快速路径匹配 |
| C. 调研 | 78 | Auto-Scan 有效；Research 合理；Web Search 对极简需求 ROI 低 |
| D. 澄清 | 95 | 1 轮快速确认足够；决策卡片格式匹配 |

---

### 3.2 场景 S2: REST API 迁移为 GraphQL — 逐步仿真

**Step 1.1.5** — 信息量评估:

| 维度 | 检测 | 结果 |
|------|------|------|
| brevity | "将现有 REST API 迁移为 GraphQL，保持向后兼容" > 20 字符 | 不触发 |
| no_tech_entity | 含 "REST API"、"GraphQL" | 不触发 |
| no_metric | 无量化指标 | **触发** |
| vague_action | 含 "迁移" | 不触发 |

**flags = 1 < 2** -> 正常流程。

**Step 1.1.6** — 需求类型分类:

| 关键词匹配 | 结果 |
|-----------|------|
| Bugfix | 不匹配 |
| Refactor | "迁移/migrate" -> **匹配** |

分类结果: `requirement_type: "refactor"` -> `routing_overrides: { change_coverage_min_pct: 100 }`

**缺陷 D-03**: 将 REST->GraphQL 迁移分类为纯 Refactor 存在争议。这不仅仅是代码重构——它引入了全新的查询范式（schema/resolver/subscription），本质上是 Feature + Refactor 的混合体。分类为 Refactor 会导致:
- Phase 4 要求 `change_coverage = 100%`（对全新 GraphQL 代码合理，但对保留的 REST 兼容层可能过严）
- 不要求 Feature 默认的完整三路并行调研深度（实际需要）
- **文件**: `phase1-requirements.md` 第 43-48 行
- **严重度**: 中

**缺陷 D-04**: Refactor 路由策略中 Phase 1 调研深度描述为"聚焦影响范围 + 回归风险"（第 54 行），但实际调研深度是由 `complexity_routing` 控制的（取决于 `total_files`），不是由 `requirement_type` 直接控制的。**路由策略表中 Phase 1 列的描述是意图性的而非实际行为，因为协议代码中没有基于 requirement_type 调整调研范围的逻辑**。
- **文件**: `phase1-requirements.md` 第 52-58 行（路由策略表）
- **文件**: `phase1-requirements-detail.md` 第 221-227 行（调研深度仅由 complexity 决定）
- **严重度**: 中 — 文档声称的差异化调研深度在协议层面未实现

**Step 1.2-1.3** — 三路并行调研:

| Agent | 行为 |
|-------|------|
| Auto-Scan | 扫描所有 REST 端点、路由定义、中间件、数据模型 |
| Research Agent | depth 由 complexity 后置确定；Web 搜索: `force_search` (architecture_decision: true, new_dependency: true for graphql) |
| Web Search | 搜索 "REST to GraphQL migration best practices 2026"、"GraphQL backward compatibility REST" |

**Step 1.4** — 复杂度评估:

```
total_files = REST 端点文件 + 新 GraphQL schema + resolvers + 客户端适配
估算: 10-20+ 文件 -> complexity = "large"
额外升级因子: architecture_decision (引入 GraphQL)
```

**结果正确**: large 复杂度。

**缺陷 D-05**: 复杂度评估中的 `total_files` 来自 Research Agent 信封中的 `impact_analysis`。但 Research Agent 的深度（basic/standard/deep）在此时尚未确定（Step 1.4 才评估复杂度，但 Step 1.3 的调研深度依赖复杂度）。这是**循环依赖**:
- Step 1.3 调研深度由 complexity 决定（`phase1-requirements-detail.md` 第 221-227 行）
- Step 1.4 complexity 由 Research Agent 的 `impact_analysis` 决定
- **解决方式**: Research Agent 始终返回 `impact_analysis`（不受深度控制），深度仅影响额外任务（5/6/7）。这意味着循环依赖在实践中不是阻塞性的，但协议文档的组织暗示了一个并不存在的线性依赖。
- **文件**: `phase1-requirements-detail.md` 第 221-227 行, 第 408-423 行
- **严重度**: 低（实际不阻塞，但文档组织有误导性）

**Step 1.5-1.6** — business-analyst + 决策:

large 复杂度 -> 强制苏格拉底模式 + 3+ 轮决策。

预期决策点:
1. GraphQL 引擎选型 (Apollo Server vs Mercurius vs Yoga)
2. Schema 设计策略 (schema-first vs code-first)
3. 向后兼容策略 (双运行 REST+GraphQL vs GraphQL wrapper over REST)
4. 客户端迁移策略 (一次性 vs 渐进式)
5. N+1 查询优化 (DataLoader 配置)
6. 认证/授权迁移 (REST middleware -> GraphQL context)
7. 实时订阅需求 (WebSocket vs SSE)

苏格拉底追问示例:
- "你提到保持向后兼容——是允许 REST 客户端无限期访问，还是有废弃时间线？"
- "如果只迁移最常用的 5 个端点作为 MVP，你能接受吗？"

**场景 S2 评估矩阵**:

| 步骤 | 评分 | 理由 |
|------|------|------|
| A. 需求分析 | 72 | 类型分类为 Refactor 有争议；路由策略表的调研深度差异化在代码中未实现 |
| B. 需求理解 | 85 | business-analyst + 苏格拉底模式能有效拆解复杂迁移 |
| C. 调研 | 82 | Web 搜索 force_search 正确触发；deep 调研覆盖同类实现对比 |
| D. 澄清 | 83 | 决策点多且互相关联；苏格拉底模式有效但 3+ 轮可能不够 |

---

### 3.3 场景 S3: 分布式配置中心客户端 — 逐步仿真

**Step 1.1.5** — 信息量评估:

| 维度 | 检测 | 结果 |
|------|------|------|
| brevity | "实现分布式配置中心客户端，支持热更新、灰度发布、多集群容灾" > 20 字符 | 不触发 |
| no_tech_entity | 含 "配置中心客户端" | 不触发 |
| no_metric | 无量化指标（无 SLA、延迟要求、集群数） | **触发** |
| vague_action | 含 "实现" | 不触发 |

**flags = 1 < 2** -> 正常流程。

**缺陷 D-06**: 该需求的 `no_metric` 标记虽然触发了（flags=1），但不足以进入澄清预循环（需 >= 3）。然而，对于分布式系统需求，缺少量化指标（如 "配置推送延迟 < 1s"、"支持 3+ 集群"、"灰度比例粒度"）是严重信息缺失。**当前规则对分布式/性能敏感需求的信息量检测不够灵敏**。建议增加 "distributed/分布式/集群/容灾" 关键词时自动升级 `no_metric` 的权重。
- **文件**: `phase1-requirements.md` 第 22-33 行
- **严重度**: 中

**Step 1.1.6** — 需求类型分类:

| 关键词匹配 | 结果 |
|-----------|------|
| Bugfix | 不匹配 |
| Refactor | 不匹配（"实现"不在 Refactor 关键词中） |
| Chore | 不匹配 |
| Feature | 默认 **匹配** |

分类结果: `requirement_type: "feature"` — **正确**。

**Step 1.2-1.3** — 三路并行调研:

| Agent | 行为 |
|-------|------|
| Auto-Scan | 扫描项目现有配置管理方式（本地文件/环境变量/已有配置库） |
| Research Agent | `force_search`: `new_feature: true`, `architecture_decision: true` -> 强制搜索 |
| Web Search | 竞品搜索: "Nacos vs Apollo vs etcd config center comparison 2026"；技术搜索: "distributed config hot reload client SDK best practices" |

**Step 1.4** — 复杂度评估:

```
total_files = SDK 核心(5+) + 热更新(3+) + 灰度(3+) + 容灾(3+) + 测试
估算: 15-25 文件 -> complexity = "large"
额外升级因子: 3+ 新依赖（gRPC/HTTP 长连接库、灰度策略库、集群管理）
```

**结果正确**: large 复杂度。

**Step 1.5-1.6** — business-analyst + 决策:

large 复杂度 -> 强制苏格拉底模式 + 3+ 轮决策。

预期决策点（估计 8-12 个）:
1. 配置中心选型 (Nacos vs Apollo vs etcd vs 自建)
2. 通信协议 (gRPC vs HTTP Long Polling vs WebSocket)
3. 客户端缓存策略 (本地文件 vs 内存 + 持久化)
4. 热更新机制 (Push vs Pull vs Push+Pull 混合)
5. 灰度发布粒度 (IP 规则 vs 用户标签 vs 百分比)
6. 多集群容灾模式 (主从 vs 多主 vs 读写分离)
7. 配置格式 (YAML vs JSON vs Properties)
8. 版本管理 (配置版本回滚机制)
9. 客户端 SDK API 设计 (注解注入 vs 手动获取)
10. 监控告警 (配置变更通知 + 推送失败告警)

**缺陷 D-07**: 决策点数量预计 8-12 个，但多轮决策循环中每轮处理多少决策点无明确协议规定。`phase1-requirements-detail.md` 中 Large 路径描述为"强制 3+ 轮"（第 558-559 行），但没有规定每轮的最大决策点数。如果每轮处理过多决策点，用户认知负担过重；如果每轮只处理 1-2 个，则需要 5-6 轮，流程过长。
- **文件**: `phase1-requirements-detail.md` 第 547-559 行
- **严重度**: 中

苏格拉底追问示例:
- "你提到多集群容灾——是需要跨地域（如中美同步），还是同一数据中心内的多副本？"
- "热更新的一致性要求是什么？所有节点必须同时生效（强一致），还是允许短暂不一致（最终一致）？"
- "如果第一个版本只实现对接 Nacos + 本地缓存 + 热更新，灰度和容灾放到后续迭代，你能接受吗？"

**缺陷 D-08**: 苏格拉底模式的 6 步提问中缺少**非功能需求专项挖掘步骤**。对于分布式系统，SLA、延迟、吞吐量、故障恢复时间等非功能需求往往决定架构选型。当前 6 步（挑战假设/探索替代/识别隐含需求/强制排优/魔鬼代言人/最小可行范围）偏向功能维度，对非功能需求的覆盖依赖 AI 在"识别隐含需求"步骤中的自主能力。
- **文件**: `phase1-supplementary.md` 第 14-21 行
- **严重度**: 中

**场景 S3 评估矩阵**:

| 步骤 | 评分 | 理由 |
|------|------|------|
| A. 需求分析 | 80 | 分类正确；信息量评估对分布式需求缺乏敏感度 |
| B. 需求理解 | 82 | 决策点数量多，每轮决策点数无协议规定；business-analyst 依赖 AI 理解分布式系统 |
| C. 调研 | 83 | Web 搜索正确触发竞品对比；deep 调研覆盖依赖深度分析 |
| D. 澄清 | 78 | 苏格拉底模式缺少非功能需求专项步骤；决策点互相关联性高 |

---

### 3.4 综合评估矩阵

| 子步骤 | S1 (简单) | S2 (中等) | S3 (复杂) | 加权平均 |
|--------|-----------|-----------|-----------|---------|
| A. 需求分析 | 85 | 72 | 80 | **81** |
| B. 需求理解 | 92 | 85 | 82 | **87** |
| C. 调研 | 78 | 82 | 83 | **80** |
| D. 澄清 | 95 | 83 | 78 | **86** |
| **场景综合** | **88** | **81** | **81** | **84** |

> 加权方式: S1:20%, S2:40%, S3:40% (中大型需求在实际使用中更能暴露问题)

---

## 4. 协议设计缺陷清单

### 4.1 已确认缺陷

| ID | 严重度 | 类别 | 描述 | 文件路径 | 行号 |
|----|--------|------|------|---------|------|
| D-01 | 低 | 需求分析 | brevity 阈值 `< 20 字符` 未明确"字符"定义（Unicode 码点 vs 字节），中英文混合输入行为不确定 | `references/phase1-requirements.md` | 第 25 行 |
| D-02 | 低 | 调研 | 极简 Feature 需求（如 health check）仍触发 Web 搜索，缺少 trivial complexity 快速跳过路径 | `references/phase1-requirements-detail.md` | 第 236-254 行 |
| D-03 | 中 | 需求分析 | 复合需求类型（Feature+Refactor）只能单一分类，导致 routing_overrides 偏差。S2 场景 "REST->GraphQL 迁移" 被分类为 Refactor，但本质含大量 Feature 元素 | `references/phase1-requirements.md` | 第 43-48 行 |
| D-04 | 中 | 需求分析 | 路由策略表声称不同 requirement_type 有差异化 Phase 1 调研深度，但实际调研深度仅由 complexity 控制，requirement_type 不影响调研行为。文档描述与代码行为不一致 | `references/phase1-requirements.md` 第 52-58 行 / `references/phase1-requirements-detail.md` 第 221-227 行 | — |
| D-05 | 低 | 架构 | Step 1.3 调研深度依赖 complexity，而 Step 1.4 complexity 依赖调研结果中的 impact_analysis，存在文档层面的循环依赖暗示。实际不阻塞（impact_analysis 在所有深度级别都返回），但文档组织有误导性 | `references/phase1-requirements-detail.md` | 第 221-227 行, 第 408-423 行 |
| D-06 | 中 | 需求分析 | 信息量评估对分布式/性能敏感需求不够灵敏。缺少量化指标（SLA/延迟/集群数）对此类需求是严重信息缺失，但 flags 仅增加 1 不足以触发澄清预循环 | `references/phase1-requirements.md` | 第 22-33 行 |
| D-07 | 中 | 澄清 | Large 复杂度"强制 3+ 轮"但未规定每轮最大决策点数，可能导致单轮决策密度过高（用户过载）或轮数过多（流程拖沓） | `references/phase1-requirements-detail.md` | 第 547-559 行 |
| D-08 | 中 | 澄清 | 苏格拉底模式 6 步提问缺少非功能需求专项步骤（SLA/性能/可靠性），对分布式/高并发系统需求的隐含约束挖掘能力不足 | `references/phase1-supplementary.md` | 第 14-21 行 |
| D-09 | 中 | 配置 | `min_qa_rounds` 在 `config-schema.md` 第 23 行定义，但 Phase 1 核心流程（`phase1-requirements.md` + `phase1-requirements-detail.md`）中无任何步骤读取或使用此配置。复杂度分路中的轮数限制是硬编码的（small:1, medium:2-3, large:3+），不受 `min_qa_rounds` 控制 | `references/config-schema.md` 第 23 行 / `references/phase1-requirements.md` 全文 | — |
| D-10 | 低 | 文档一致性 | `phase1-supplementary.md` 第 59 行引用 `validate-decision-format.sh`，但该脚本第 2 行已标记 DEPRECATED，实际逻辑在 `post-task-validator.sh` / `_post_task_validator.py` 中 | `references/phase1-supplementary.md` 第 59 行 / `scripts/validate-decision-format.sh` 第 2 行 | — |
| D-11 | 低 | 调研 | rules-scanner.sh 第 10 行 `set -uo pipefail` 缺少 `-e`（errexit），虽然脚本最终 `exit 0`，但 python3 内部错误可能被静默吞没（由 `except Exception: continue` 兜底）。整体影响低，因为 Auto-Scan 对 rules-scanner 失败有降级策略 | `scripts/rules-scanner.sh` | 第 10 行 |

### 4.2 v5.0 报告缺口修复状态跟踪

| v5.0 缺口 ID | 描述 | v5.0.4 状态 | 说明 |
|-------------|------|------------|------|
| #1 无合规约束专项检测 | 缺少 GDPR/PCI-DSS 等合规维度 | **未修复** | v5.1 未涉及合规检测增强 |
| #2 复合需求类型不支持 | 不支持 Feature+Refactor 双类型 | **未修复** | 本报告 D-03 复现 |
| #3 搜索结果时效性无过滤 | 搜索可能返回过时信息 | **部分改善** | 搜索关键词模板中已含 `{当前年份}`（`phase1-requirements-detail.md` 第 202 行），但信任机制中仍无日期校验 |
| #4 Phase 1 无中间 checkpoint | 崩溃丢失调研进度 | **已修复** | v5.1 新增 `phase-1-interim.json`，支持 `research_complete` 和 `decision_round_N` 恢复（`SKILL.md` 第 132-157 行, `autopilot-recovery/SKILL.md` 第 62-77 行） |
| #5 苏格拉底模式仅 large 触发 | medium 需求无深度追问 | **未修复** | 仍仅在 `complexity == "large"` 或 `config.mode == "socratic"` 时激活 |

---

## 5. 隐藏约束挖掘能力评估

### 5.1 约束分类与检测机制映射

| 约束类型 | 主要检测机制 | 确定性程度 | S1 覆盖 | S2 覆盖 | S3 覆盖 |
|---------|------------|-----------|---------|---------|---------|
| **技术约束** (版本冲突/API 限制) | Research Agent 任务 2+3, Auto-Scan tech-constraints.md | 中（依赖 AI 分析） | 高 | 高 | 高 |
| **编码约束** (项目规则) | rules-scanner.sh 确定性提取 + Auto-Scan 注入 | 高（纯解析） | 高 | 高 | 高 |
| **业务约束** (隐含规则/边界) | business-analyst + 苏格拉底模式 | 低（纯 AI） | 中 | 高 | 高 |
| **性能约束** (并发/延迟/资源) | Research Agent 任务 4（风险识别） | 低（AI 自评） | 不适用 | 中 | **低** |
| **安全约束** (认证/授权) | Web Search `security_related` force | 中（关键词触发搜索是确定性的，但搜索结果理解是 AI 行为） | 不适用 | 中 | 不适用 |
| **合规约束** (GDPR/PCI-DSS) | **无专项检测** | 无 | 不适用 | 不适用 | **缺失** |
| **运维约束** (部署/监控/回滚) | 无专项检测 | 无 | 不适用 | 低 | **缺失** |

### 5.2 rules-scanner.sh 深度审计

`rules-scanner.sh` 是 Phase 1 唯一的确定性约束提取器。审计其模式匹配能力:

**覆盖的模式** (已验证):
- 禁止表格行: `| \`xxx\` | \`yyy\` |` 格式 (第 58-69 行)
- 禁止行标记: `禁止xxx` / `xxx` (第 72-78 行)
- 必须使用标记: `必须xxx` / `xxx` (第 81-87 行)
- 命名约定: kebab-case / camelCase / PascalCase / snake_case (第 90-94 行)
- CLAUDE.md 核心约束表格: `| **key** | value |` (第 117-123 行)

**未覆盖的模式** (缺口):
- 条件性约束: "当 X 时必须 Y"（条件分支规则无法用简单正则捕获）
- 列表格式约束: `- 禁止 xxx`（仅匹配 backtick 包裹的模式，纯文本列表会遗漏）
- 英文 rules 文件中的 "Do not use"/"Always use" 模式
- 嵌套引用约束（rules 文件中 `see also: xxx.md` 的传递性约束）

**评分**: 编码约束提取能力 75/100 — 对中文项目规则覆盖良好，对英文 rules 文件覆盖不足。

### 5.3 场景特定隐藏约束评估

**S3 (分布式配置中心) 的关键隐藏约束**:

| 隐藏约束 | 是否被当前流程捕获 | 捕获机制 |
|---------|-----------------|---------|
| 配置推送延迟 SLA (如 < 1s) | 可能 | 依赖苏格拉底模式"识别隐含需求"步骤中 AI 主动追问 |
| 配置格式向后兼容 (旧配置文件迁移) | 可能 | 依赖 business-analyst 识别 |
| 灰度比例粒度 (1% vs 10% vs 50%) | 不太可能 | 需用户主动提供，流程无专项追问 |
| 集群间网络分区容错 | 不太可能 | 非功能需求盲区 |
| 客户端 SDK 线程安全要求 | 不太可能 | 技术深度依赖 Research Agent 质量 |
| 配置加密传输/存储 (安全) | 可能 | `security_related` 搜索可能覆盖 |
| 配置变更审计日志合规要求 | 不太可能 | 合规检测缺失 |

**结论**: 当前流程对技术约束和编码约束的挖掘能力**较强**（确定性工具支撑），对业务和性能约束**中等**（依赖 AI），对合规和运维约束**较弱**（无专项机制）。

---

## 6. 与 v5.0 报告对比

### 6.1 评分对比

| 维度 | v5.0 评分 | v5.0.4 评分 | 变化 | 原因 |
|------|----------|------------|------|------|
| A. 需求分析 | 82 | 81 | -1 | 本轮更严格评估复合类型问题和路由策略文档-代码不一致 (D-03, D-04) |
| B. 需求理解 | 85 | 87 | +2 | v5.1 中间 checkpoint 增强了流程鲁棒性；business-analyst 后台化架构成熟 |
| C. 调研 | 78 | 80 | +2 | 搜索关键词模板含年份改善时效性；Auto-Scan 持久化复用机制验证有效 |
| D. 澄清 | 88 | 86 | -2 | 本轮发现每轮决策点数无协议规定 (D-07)、苏格拉底缺少非功能需求步骤 (D-08)、min_qa_rounds 配置空悬 (D-09) |
| **综合** | **83** | **84** | **+1** | v5.1 改进（中间 checkpoint、unified hook）抵消了更严格审计暴露的新缺陷 |

### 6.2 场景差异对比

v5.0 报告使用了不同的测试场景（"按日期排序"/"WebSocket 通知"/"OAuth 迁移"），本报告使用了指定的新场景。关键差异:

| 对比维度 | v5.0 场景 | v5.0.4 场景 | 发现差异 |
|---------|----------|------------|---------|
| 简单场景 | 页面内排序（纯前端） | Health 端点（后端 API） | S1 路由结果一致（Feature），Web 搜索 ROI 问题在两者中均存在 |
| 中等场景 | WebSocket 通知（新功能） | REST->GraphQL 迁移（重构+新功能） | **S2 暴露了 v5.0 未发现的复合类型问题**（Refactor+Feature 混合） |
| 复杂场景 | OAuth 迁移（安全+重构） | 分布式配置中心（新功能+分布式） | S3 暴露了非功能需求挖掘盲区（v5.0 侧重合规约束缺失） |

### 6.3 v5.1 技术债清剿对 Phase 1 的影响

| v5.1 修复项 | 对 Phase 1 的影响 |
|------------|-----------------|
| 中间 Checkpoint (`phase-1-interim.json`) | **直接改善**: 修复 v5.0 #4 缺口，崩溃恢复粒度从阶段级提升到步骤级 |
| unified-write-edit-check.sh 合并 | **间接改善**: Phase 5 状态隔离更严格，不影响 Phase 1 本身 |
| post-task-validator.sh 背景 Agent 验证 | **直接改善**: Phase 1 后台子 Agent（Research/Auto-Scan/Web Search）返回的 JSON 信封现在也经过 L2 验证（v5.1 移除了 `is_background_agent && exit 0`，见 `post-task-validator.sh` 第 22-25 行） |
| 原子写入 checkpoint | **直接改善**: checkpoint 写入使用 .tmp + mv 原子操作（`SKILL.md` 第 208-213 行），防止部分写入导致的 JSON 解析失败 |

---

## 7. 优化建议

### 7.1 高优先级 (影响正确性)

| # | 建议 | 目标缺陷 | 预估工作量 | 受影响文件 |
|---|------|---------|-----------|-----------|
| P0-1 | **实现 requirement_type 对调研深度的实际控制**。当前路由策略表声称 Bugfix "聚焦复现路径"、Chore "最小化调研"，但调研深度仅由 complexity 控制。建议在 Research Agent Prompt 模板中注入 requirement_type，并为 Bugfix/Chore 定义专用调研任务子集 | D-04 | 中 | `phase1-requirements-detail.md` 第 149-219 行 (Research Agent Prompt) |
| P0-2 | **支持复合需求类型**。允许需求同时标记为多个 type（如 `["refactor", "feature"]`），routing_overrides 取各类型的最严格值 | D-03 | 中 | `phase1-requirements.md` 第 43-77 行, `_post_task_validator.py` 第 175-213 行 |
| P0-3 | **让 `min_qa_rounds` 配置生效**。在 Step 1.6 多轮决策循环中读取 `config.phases.requirements.min_qa_rounds`，作为最低轮数下限（覆盖 complexity 分路的硬编码轮数，取两者最大值） | D-09 | 小 | `phase1-requirements.md` 第 123-131 行, `phase1-requirements-detail.md` 第 526-559 行 |

### 7.2 中优先级 (影响效率/覆盖)

| # | 建议 | 目标缺陷 | 预估工作量 | 受影响文件 |
|---|------|---------|-----------|-----------|
| P1-1 | **增加非功能需求专项挖掘步骤**。在苏格拉底模式 6 步基础上增加第 7 步"非功能需求质询"（SLA/性能/可靠性/可观测性），在检测到分布式/高并发关键词时强制触发 | D-08 | 中 | `phase1-supplementary.md` 第 14-21 行 |
| P1-2 | **为极简 Feature 增加 Web 搜索快速跳过路径**。在 `skip_when_ALL_true` 条件中增加 `estimated_complexity: "small"` 条件，允许 small Feature 在 Auto-Scan 发现项目内有同类实现时跳过搜索 | D-02 | 小 | `phase1-requirements-detail.md` 第 236-254 行, `config-schema.md` 第 34-54 行 |
| P1-3 | **规定 Large 复杂度每轮最大决策点数**。建议每轮不超过 3-4 个决策点，超出则自动拆分到下一轮 | D-07 | 小 | `phase1-requirements-detail.md` 第 547-559 行 |
| P1-4 | **增强信息量评估对分布式需求的敏感度**。当需求含 "分布式/集群/容灾/高可用/高并发" 关键词时，`no_metric` 标记权重从 1 升至 2 | D-06 | 小 | `phase1-requirements.md` 第 22-33 行 |

### 7.3 低优先级 (完善性)

| # | 建议 | 目标缺陷 | 预估工作量 |
|---|------|---------|-----------|
| P2-1 | 明确 brevity 阈值的字符计算方式（建议使用 Unicode 码点数） | D-01 | 极小 |
| P2-2 | 更新 `phase1-supplementary.md` 中对 `validate-decision-format.sh` 的引用为 `post-task-validator.sh` | D-10 | 极小 |
| P2-3 | rules-scanner.sh 增加英文 "Do not use"/"Always use"/"Never" 模式匹配 | D-11 附带 | 小 |
| P2-4 | 增加合规约束检测维度（需求含 "用户数据/支付/认证/个人信息" 时触发合规关键词搜索） | v5.0 #1 | 中 |

---

*报告由 Claude Opus 4.6 生成。所有文件路径相对于 `plugins/spec-autopilot/skills/autopilot/` 目录，除非另有标注。脚本文件路径相对于 `plugins/spec-autopilot/`。*
