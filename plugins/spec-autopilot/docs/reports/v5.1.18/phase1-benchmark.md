# Phase 1 需求质量评审 Benchmark 报告

> **版本**: v5.1.18 | **评审日期**: 2026-03-17 | **评审范围**: Phase 1 需求理解与多轮决策

---

## 执行摘要

**综合评分: 87/100**

Phase 1 作为 spec-autopilot 全自动交付流水线的入口阶段，承担需求理解、技术调研、用户决策三大核心职能。评审结论：该阶段设计成熟度高、流程完备度强，在需求分类路由（v4.2）、搜索策略引擎（v3.3.7）、结构化决策协议等方面体现了工业级设计水准。但在模糊需求澄清深度、跨系统需求调研覆盖率、小规模需求过度流程化三个维度上仍有提升空间。

| 审计维度 | 评分 | 等级 |
|----------|------|------|
| 需求分析能力（三维度综合） | 84/100 | B+ |
| Prompt 模板质量 | 90/100 | A |
| 门禁指标有效性 | 88/100 | A- |
| 需求路由机制 | 86/100 | B+ |
| 测试覆盖度 | 82/100 | B |

---

## 一、三维度需求分析能力评分矩阵

### 维度 A — 简单 CRUD 需求（"添加用户管理模块"类）

| 评估项 | 评分 | 评语 |
|--------|------|------|
| 需求理解准确度 | 90/100 | RAW_REQUIREMENT 解析 + 关键词提取机制（Step 1.1.5）能有效识别技术实体（"用户管理"→ CRUD 模式），并自动分类为 Feature 路由 |
| 隐藏约束挖掘能力 | 80/100 | Auto-Scan 的 existing-patterns.md 能发现现有的 CRUD 模式（路由定义、数据模型、组件注册），但对隐含的权限、审计日志等非功能约束依赖苏格拉底模式，small 复杂度默认禁用苏格拉底 |
| 存量代码调研覆盖率 | 92/100 | 三路并行调研（Auto-Scan + 技术调研 + 联网搜索）中，Auto-Scan 的 6 维扫描（技术栈/目录/模式/依赖/约束/测试）覆盖全面，能识别可复用模块 |
| 澄清问题的工程价值 | 78/100 | small 复杂度走"快速确认"路径（最多 1 轮 QA），决策卡片仅保留关键技术决策点。风险：对 CRUD 需求中隐含的批量操作、软删除、数据迁移等边界可能澄清不足 |

**维度 A 综合: 85/100**

**发现 A-1（中风险）**: small 复杂度的快速路径可能导致 CRUD 类需求的非功能约束（权限模型、数据校验规则、并发控制）被跳过。`min_qa_rounds` 默认值为 1，但 small 路径最多 1 轮，安全阀机制（"确实无遗漏时允许提前退出"）在实践中可能过于宽松。

**发现 A-2（低风险）**: 需求信息量评估（Step 1.1.5）的 4 个检测维度（文本过短、无技术实体、无量化指标、动作模糊）覆盖合理，`flags >= 3` 强制进入澄清预循环是有效的兜底机制。

---

### 维度 B — 复杂跨系统需求（"实现分布式缓存一致性"类）

| 评估项 | 评分 | 评语 |
|--------|------|------|
| 需求理解准确度 | 85/100 | 关键词匹配能识别"分布式"触发 large 复杂度升级因子，联网搜索强制执行（force_search: architecture_decision），Step 7 非功能需求质询被触发（含"分布式"关键词） |
| 隐藏约束挖掘能力 | 88/100 | large 复杂度强制启用苏格拉底模式的 7 步提问流程，含"挑战假设"、"探索替代方案"、"魔鬼代言人"等深度挖掘手段。v5.2 新增的 Step 7 非功能需求质询能覆盖 SLA/性能/可靠性 |
| 存量代码调研覆盖率 | 82/100 | deep 调研深度（任务 1-7 全部执行）含同类实现对比、依赖深度分析。但跨系统调研依赖 Research Agent 的自主方案探索能力，当需求涉及多个子系统时，单一 Research Agent 可能无法覆盖所有子系统的技术栈差异 |
| 澄清问题的工程价值 | 86/100 | 强制 3+ 轮 QA + scope creep 检查 + MVP 范围收敛建议。决策卡片包含完整字段（options/pros/cons/affected_components/rationale），调研数据引用规范 |

**维度 B 综合: 85/100**

**发现 B-1（中风险）**: Research Agent 是单一 Agent 执行所有调研任务（任务 1-7），对于跨系统需求（如涉及前端 + 后端 + 中间件的缓存一致性），单 Agent 的知识广度可能不足。建议考虑按子系统域拆分调研 Agent（类似 Phase 5 的域 Agent 策略）。

**发现 B-2（低风险）**: 联网搜索的关键词构造规则较为通用（"技术栈 + 功能关键词 + best practices 当前年份"），对于分布式系统特定的调研需求（CAP 理论、一致性协议对比），可能需要更精准的搜索模板。

**发现 B-3（优势）**: 额外调整因子机制（`feasibility.score == "low"` / 高风险 / 3+ 新依赖自动升级为 large）能有效捕获复杂需求，避免因文件数少而低估复杂度。

---

### 维度 C — 模糊/隐含需求（"系统性能优化"类）

| 评估项 | 评分 | 评语 |
|--------|------|------|
| 需求理解准确度 | 78/100 | "系统性能优化"触发 Step 1.1.5 检测：`no_metric`（无量化指标）+ `vague_action`（"优化"为模糊动词），flags = 2 → 标记 `requirement_clarity: "low"`。但仅标记为 low 不会强制进入澄清预循环（需 flags >= 3） |
| 隐藏约束挖掘能力 | 80/100 | 需求路由分类为 Refactor（含"优化性能"关键词），routing_overrides 提升 change_coverage 至 100%。但"性能优化"本身方向模糊（CPU/内存/IO/网络），调研范围界定依赖 Research Agent 的自主判断 |
| 存量代码调研覆盖率 | 75/100 | Auto-Scan 能产出现有测试基础设施和目录结构，但缺乏性能基线数据收集机制（如当前 P99 延迟、QPS 上限）。Research Agent 的影响分析基于文件数，无法准确评估性能瓶颈的分布 |
| 澄清问题的工程价值 | 82/100 | v5.2 Step 7 非功能需求质询（当含"性能"关键词时强制触发）能追问 QPS/TPS 目标、P99 延迟目标等量化指标。但首轮 flags = 2 仅触发"调研 Agent 优先范围界定"，不强制用户澄清，可能导致调研方向发散 |

**维度 C 综合: 79/100**

**发现 C-1（高风险）**: flags >= 2 但 < 3 的模糊需求处于"灰色地带"——不够模糊触发强制澄清，但也不够清晰支撑精准调研。"系统性能优化"（flags = 2: `no_metric` + `vague_action`）在未经澄清的情况下直接进入三路并行调研，可能产生高噪音的调研结果。

**建议 C-1**: 将 flags >= 2 的阈值行为从"标记 low"改为"触发 1-2 个定向澄清问题"（非完整的 3-5 个澄清预循环），在不增加过多用户负担的前提下收窄需求范围。

**发现 C-2（中风险）**: 需求信息量评估的 4 个检测维度缺少"无明确范围边界"维度。"系统性能优化"虽然有技术实体（"系统"）和具体动词（"优化"虽模糊但在动词列表中），但缺少"哪个系统"、"优化到什么程度"的范围界定。建议增加"无范围限定词"检测维度。

---

### 三维度评分矩阵汇总

| 维度 | 需求理解 | 约束挖掘 | 调研覆盖 | 澄清价值 | 综合 |
|------|----------|----------|----------|----------|------|
| A-简单CRUD | 90 | 80 | 92 | 78 | **85** |
| B-复杂跨系统 | 85 | 88 | 82 | 86 | **85** |
| C-模糊隐含 | 78 | 80 | 75 | 82 | **79** |
| **加权平均** | **84** | **83** | **83** | **82** | **83** |

> 加权策略: A/B/C 均等权重。实际场景中 C 类模糊需求占比更高，若按 A:B:C = 3:2:5 加权，综合得分为 82。

---

## 二、Phase 1 Prompt 模板质量评审

### 2.1 模板层次结构

Phase 1 的 Prompt 模板采用三层架构:

| 层级 | 文件 | 职责 |
|------|------|------|
| 核心流程 | `phase1-requirements.md` | 10 步主流程框架（常驻加载） |
| 详细模板 | `phase1-requirements-detail.md` | Agent Prompt 模板 + 规则引擎细节（按需加载） |
| 补充协议 | `phase1-supplementary.md` | 苏格拉底模式 + 崩溃恢复 + 格式验证 |

**评分: 92/100** — 三层按需加载策略在上下文窗口管理上是优秀设计，避免一次性灌入全部规范。

### 2.2 需求分析引导深度

**优势**:
- Research Agent Prompt 含 7 大调研任务（代码影响 → 依赖兼容 → 技术可行性 → 风险 → Web搜索 → 同类实现 → 依赖深度），按复杂度分级执行（basic/standard/deep）
- Business-Analyst Prompt 要求产出功能清单 + 疑问点 + 可行性判定 + 实施优先级 4 项结构化输出
- 决策协议注入（v2.4.0）在 medium/large 复杂度时追加结构化决策卡片要求

**不足**:
- Research Agent Prompt 中的"自主方案探索"（Step 0）描述偏抽象（"核心技术挑战是什么？"），对于 AI Agent 来说缺乏具体的输出格式约束，可能导致产出质量不稳定
- Business-Analyst Prompt 的返回信封中 `open_questions` 字段为可选，但未强制要求将所有疑问转化为 `decision_points`，可能遗漏需要用户决策的问题

**评分: 88/100**

### 2.3 需求分类引导

**优势**:
- Step 1.1.6 提供了 Feature/Bugfix/Refactor/Chore 四类确定性分类规则
- v5.2 复合需求路由支持多类型命中（数组表示），合并策略取最严格阈值
- 分类结果持久化到 Phase 1 JSON 信封的 `requirement_type` 和 `routing_overrides` 字段

**不足**:
- 分类规则完全依赖关键词匹配，缺少语义级分类能力。"提升用户体验"无法被关键词匹配到 Feature 以外的类别，但实际可能涉及 Refactor
- 向后兼容设计（`requirement_type` 为可选字段）意味着旧版本运行时所有需求等效 Feature，存在路由降级风险

**评分: 85/100**

### 2.4 存量代码调研引导

**优势**:
- Auto-Scan 的 6 维扫描覆盖全面（技术栈/目录/模式/依赖/约束/测试基础设施）
- 持久化上下文机制（7 天有效缓存）避免重复扫描
- 历史知识注入（v2.4.0）从 `.autopilot-knowledge.json` 注入前序会话的教训和决策
- Brownfield 验证协议提供三向一致性检查（设计-测试对齐 / 测试-实现就绪 / 实现-设计一致性）

**不足**:
- Auto-Scan 的扫描深度限制为 2 层目录，对于 monorepo 或深层嵌套的项目结构可能遗漏关键模块
- existing-patterns.md 的模式识别依赖 Grep 匹配（路由定义、API 端点、数据模型），对于非标准框架可能覆盖不足

**评分: 90/100**

### 模板质量综合评分: 90/100

---

## 三、门禁指标有效性评估

### 3.1 Phase 1 Checkpoint 必须字段

根据 `protocol.md` 定义，Phase 1 checkpoint 必须包含:

| 字段 | 类型 | 验证机制 | 评估 |
|------|------|----------|------|
| `requirements_summary` | string | L2 Hook（post-task-validator） | 有效 — 确保需求摘要不为空 |
| `decisions: [DecisionPoint]` | array | L2 Hook（validate-decision-format） | 有效 — 按复杂度分级验证格式完整性 |
| `change_name` | string | L2 Hook + Phase 2 依赖 | 有效 — 后续阶段创建 OpenSpec 必须用 |
| `complexity` | enum | L2 Hook 范围校验 | 有效 — 影响后续阶段调研深度和门禁阈值 |
| `research` | object | L2 Hook 存在性检查 | 部分有效 — 当 research 被 skip 时允许缺失 |

**评分: 90/100** — 必须字段设计合理，覆盖了后续阶段的关键依赖。

### 3.2 决策格式验证（validate-decision-format.sh）

该 Hook（已合入 `post-task-validator.sh`）按复杂度分级验证:

- **medium/large**: 完整 DecisionPoint 格式（options >= 2 / 每个含 label/description/pros/cons / 至少一个 recommended:true / choice + rationale）
- **small**: 简化格式（`{point, choice}` 可接受）

**评分: 92/100** — 分级验证策略在严格性和灵活性之间取得了良好平衡。

### 3.3 门禁拦截低质量需求的有效性

| 低质量场景 | 拦截机制 | 有效性 |
|-----------|----------|--------|
| 需求摘要为空 | `requirements_summary` 字段必须存在 | 有效 |
| 零决策点 | `decisions` 数组非空验证 | 有效 |
| 决策不充分 | DecisionPoint 格式验证（medium/large 需完整 options） | 有效 |
| QA 轮数不足 | `min_qa_rounds` L2 硬阻断（配置范围 1-10） | 有效 |
| 模糊需求直通 | Step 1.1.5 信息量评估（flags >= 3 强制澄清） | 部分有效（flags = 2 灰区） |
| 调研未执行 | 文件存在性检查（`test -s context/research-findings.md`） | 有效 |
| 调研质量低 | Research Agent 信封校验（status/decision_points/feasibility/output_file） | 有效 |

**发现 G-1（低风险）**: Phase 1 checkpoint 缺乏对需求范围量化的门禁。`estimated_loc` 在 research 子对象中为可选字段，但未设置上限告警。一个预估影响 10000+ LOC 的需求可能直接进入后续阶段，而无"范围过大"警告。

**评分: 88/100**

### 3.4 中间态 Checkpoint 机制

v5.1 引入的中间态 checkpoint（`phase-1-interim.json`）在以下时机写入:
- 三路调研汇合后（`stage: "research_complete"`）
- 每轮决策 LOOP 完成后（`stage: "decision_round_N"`）

**评分: 95/100** — 细粒度崩溃恢复点设计优秀，能避免长时间 Phase 1 执行中的调研进度丢失。

### 门禁有效性综合评分: 88/100

---

## 四、需求路由机制评审（v4.2）

### 4.1 路由规则完整性

CLAUDE.md 定义的四类路由:

| 类别 | 门禁差异化 | 评估 |
|------|-----------|------|
| **Feature** | 完整三路并行调研 / sad_path >= 20% / change_coverage >= 80% | 基线设置合理 |
| **Bugfix** | 聚焦复现路径 + 根因分析 / sad_path >= **40%** / change_coverage = **100%** / 必须含复现测试 | 严格且合理 — bug 修复必须完全覆盖 |
| **Refactor** | 聚焦影响范围 + 回归风险 / change_coverage = **100%** / 必须含行为保持测试 | 严格且合理 — 重构不可丢失行为 |
| **Chore** | 最小化（仅 Auto-Scan）/ change_coverage >= **60%** / typecheck 即可 | 宽松合理 — 配置/CI 类变更低风险 |

**评分: 90/100** — 四类路由的阈值差异化设计体现了工程经验，Bugfix/Refactor 的 100% 覆盖率要求是行业最佳实践。

### 4.2 路由决策对后续 Phase 的影响链

```
Phase 1 requirement_type → routing_overrides
  → Phase 4: L2 Hook 动态调整 sad_path/change_coverage 阈值
  → Phase 5: change_coverage 验证
  → Phase 6: required_test_types 验证
```

**验证**: `test_routing_overrides.sh` 覆盖了以下场景:
- 51a: Bugfix 路由 sad_path 30% < override 40% → block
- 51b: Bugfix 路由 sad_path 40% >= override 40% → pass
- 51c: Bugfix 路由 coverage 90% < override 100% → block
- 51d: 无路由覆盖 → 默认阈值生效

**发现 R-1（低风险）**: 路由覆盖值从 Phase 1 checkpoint 传递到 Phase 4 L2 Hook，但传递机制依赖 Phase 4 Hook 主动从 `phase-1-requirements.json` 读取。如果 Phase 1 checkpoint 被崩溃恢复覆盖或手动修改，Phase 4 Hook 会静默使用默认值（向后兼容设计），而不是报错。

**发现 R-2（中风险）**: v5.2 复合需求路由（`requirement_type` 为数组时取最严格阈值）的合并策略（数值取 max、列表取 union）在理论上合理，但缺少专门的测试用例覆盖。`test_routing_overrides.sh` 仅测试了单类型（bugfix）和无类型场景，未测试 `["refactor", "feature"]` 复合路由。

### 4.3 路由分类的边界情况

| 边界场景 | 当前行为 | 评估 |
|---------|---------|------|
| "优化数据库查询性能" | 匹配 Refactor（含"优化性能"） | 可能误分类 — 可能是 Feature（新增索引）而非 Refactor |
| "修复并重构登录模块" | v5.2 复合路由 `["bugfix", "refactor"]` | 正确处理 |
| "更新 CI 配置并添加新测试" | 匹配 Chore（含"CI/配置"） | 可能遗漏 Feature 特征（"新测试"） |
| 纯英文需求 "implement caching layer" | 匹配 Feature（默认） | 正确 — 关键词列表含英文 |

**评分: 86/100**

### 需求路由综合评分: 86/100

---

## 五、测试覆盖评审

### 5.1 Phase 1 相关测试清单

| 测试文件 | 覆盖范围 | 评估 |
|---------|---------|------|
| `test_phase1_compat.sh` | Phase 1 checkpoint 兼容性（predecessor scan / SessionStart scan / PreCompact state） | 基础覆盖 |
| `test_min_qa_rounds.sh` | `min_qa_rounds` 配置范围验证 + L2 阻断逻辑 | 充分 |
| `test_routing_overrides.sh` | Phase 4 动态阈值调整（sad_path / change_coverage） | 核心路径覆盖良好 |
| `test_search_policy.sh` | 搜索策略规则引擎（11 种任务类型 + 3 个边界） + SKILL.md 断言 | 覆盖全面 |

### 5.2 测试覆盖缺口

| 缺口 | 风险等级 | 说明 |
|------|---------|------|
| **复合需求路由** | 中 | `test_routing_overrides.sh` 未覆盖 `requirement_type` 为数组时的合并策略 |
| **需求信息量评估** | 中 | 缺少 Step 1.1.5 flags 计算逻辑的单元测试 |
| **复杂度升级因子** | 低 | 缺少 `feasibility.score == "low"` / 高风险 / 3+ 新依赖自动升级为 large 的测试 |
| **决策格式 Hook** | 低 | `validate-decision-format.sh` 已标记 DEPRECATED（合入 post-task-validator），但缺少专门的 Phase 1 决策格式集成测试 |
| **苏格拉底模式** | 低 | 无自动化测试验证苏格拉底 7 步提问流程的触发条件 |
| **中间态 Checkpoint** | 低 | 缺少 `phase-1-interim.json` 写入/删除时机的测试 |

**测试覆盖评分: 82/100**

---

## 六、风险发现与改进建议

### 高优先级

| ID | 风险 | 当前状态 | 建议 |
|----|------|---------|------|
| P1-H1 | flags=2 模糊需求灰区直通调研 | Step 1.1.5 仅标记 `requirement_clarity: "low"` | 增加 flags=2 时的 1-2 个定向澄清问题，在"完整预循环"和"直通"之间增设中间态 |
| P1-H2 | 缺少范围量化上限告警 | `estimated_loc` 为可选字段无上限 | 在 Phase 1 checkpoint 写入时增加 `estimated_loc > 5000` 的 warning 级告警 |

### 中优先级

| ID | 风险 | 当前状态 | 建议 |
|----|------|---------|------|
| P1-M1 | 复合需求路由缺少测试 | 仅覆盖单类型和无类型 | 在 `test_routing_overrides.sh` 中增加 `requirement_type: ["refactor", "feature"]` 测试用例 |
| P1-M2 | Research Agent 单点覆盖不足 | 跨系统需求由单一 Agent 调研 | 考虑支持按子系统域拆分调研 Agent 的配置项 |
| P1-M3 | 需求分类关键词匹配可能误分类 | "优化性能"→ Refactor 但可能是 Feature | 增加二次确认机制：当关键词匹配与 AI 语义分析结果不一致时，提示用户确认分类 |
| P1-M4 | `open_questions` 字段可选但未与 `decision_points` 强绑定 | BA Agent 可能遗漏疑问转化 | 在 BA Agent Prompt 中增加显式要求: "所有 open_questions 必须对应一个 decision_point" |

### 低优先级

| ID | 风险 | 当前状态 | 建议 |
|----|------|---------|------|
| P1-L1 | Auto-Scan 2 层目录深度限制 | 深层嵌套项目可能遗漏 | 增加可配置的扫描深度（`config.phases.requirements.scan_depth`） |
| P1-L2 | 历史知识注入依赖 tag 匹配 | 首次运行无历史数据 | 增加冷启动提示（建议用户提供参考项目的历史知识） |
| P1-L3 | 决策格式 Hook 标记 DEPRECATED | 核心逻辑已合入但独立 Hook 保留 | 确认 `post-task-validator.sh` 完全覆盖了决策格式验证能力 |

---

## 七、架构亮点（值得推广的设计模式）

1. **三层按需加载文档架构**: 核心流程（常驻）+ 详细模板（按需）+ 补充协议（条件触发），有效控制 AI 上下文窗口占用

2. **确定性规则引擎 + AI 补充的混合策略**: 搜索决策（v3.3.7）通过可编程检测执行规则，仅在关键词提取时使用 AI，避免了"AI 评估 AI 知识"的不可靠性

3. **中间态 Checkpoint 细粒度恢复**: Phase 1 三个恢复点（调研完成 / 每轮决策后 / 最终 checkpoint）确保长会话不丢失进度

4. **v5.2 复合需求路由**: 多类型命中取最严格阈值的合并策略，避免了"一刀切"分类的局限性

5. **搜索结果信任机制**: 项目规范 > 搜索结果 > AI 内置知识的优先级链，以及交叉验证 + 来源标注要求

---

## 附录：审计文件清单

| 文件 | 路径 |
|------|------|
| SKILL.md（主编排器） | `skills/autopilot/SKILL.md` |
| Dispatch 协议 | `skills/autopilot-dispatch/SKILL.md` |
| Phase 1 核心流程 | `skills/autopilot-phase1-requirements/references/phase1-requirements.md` |
| Phase 1 详细模板 | `skills/autopilot-phase1-requirements/references/phase1-requirements-detail.md` |
| Phase 1 补充协议 | `skills/autopilot-phase1-requirements/references/phase1-supplementary.md` |
| Phase 1 并行配置 | `skills/autopilot-phase1-requirements/references/parallel-phase1.md` |
| 共享协议 | `skills/autopilot/references/protocol.md` |
| Brownfield 验证 | `skills/autopilot-gate/references/brownfield-validation.md` |
| Gate 门禁协议 | `skills/autopilot-gate/SKILL.md` |
| CLAUDE.md（工程法则） | `CLAUDE.md` |
| 决策格式验证脚本 | `scripts/validate-decision-format.sh` |
| test_phase1_compat | `tests/test_phase1_compat.sh` |
| test_min_qa_rounds | `tests/test_min_qa_rounds.sh` |
| test_routing_overrides | `tests/test_routing_overrides.sh` |
| test_search_policy | `tests/test_search_policy.sh` |
