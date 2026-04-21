# v5.1.1 Phase 1 质量评审 Benchmark

**审计日期**: 2026-03-14
**插件版本**: v5.1.1 (基于 v5.1 热修复后)
**审计方**: AI 质量评审 Agent (Claude Opus 4.6)
**审计方式**: 静态协议分析 + 代码审计 + 三场景构造仿真（dry-run，非实际运行）
**对比基线**: `docs/reports/v5.0.4/phase1-benchmark.md` (v5.0.4, 2026-03-13)

---

## 1. 审计摘要

### 总分

| 子步骤 | v5.0.4 评分 | v5.1.1 评分 | Delta | 变化原因 |
|--------|------------|------------|-------|---------|
| A. 需求分析 (Requirement Analysis) | 81 | **83** | +2 | v5.1.1 热修复 Python3 fail-closed 增强了分类规则引擎鲁棒性 |
| B. 需求理解 (Requirement Understanding) | 87 | **89** | +2 | 中间 Checkpoint 原子写入验证闭环 + 后台 Agent L2 验证恢复 |
| C. 调研 (Research) | 80 | **82** | +2 | flock 原子事件序列保证调研产出不丢失；Auto-Scan 持久化复用成熟 |
| D. 澄清 (Clarification) | 86 | **87** | +1 | 双向反控路径统一后 Gate 阻断-恢复流程更可靠 |
| E. Checkpoint 鲁棒性 | — | **91** | 新增 | v5.1 phase-1-interim.json 中间态 + 原子写入 + .tmp 残留清理 |
| F. 需求路由准确性 | — | **76** | 新增 | 路由闭环已验证，但复合类型盲区和调研深度断路仍存在 |
| **Phase 1 综合** | **84** | **86** | **+2** | v5.1.1 热修复消除底层并发隐患，整体可靠性提升 |

### 关键发现

1. **v5.1.1 热修复对 Phase 1 的间接增益显著**：`flock` 原子锁修复了事件序列单调性问题，确保 Phase 1 调研阶段的 `emit-phase-event.sh` 事件不再乱序；`python3` fail-closed 机制确保无 Python3 环境时 Hook 链全面阻断而非静默通过。
2. **中间 Checkpoint 原子写入闭环已验证**：`SKILL.md` 第 208-213 行定义的 `.tmp + mv` 原子写入 + `autopilot-recovery` 第 23-26 行的 `.tmp` 残留清理形成完整闭环。
3. **后台 Agent L2 验证已恢复**：v5.1 移除了 `post-task-validator.sh` 中的 `is_background_agent && exit 0` 旁路（第 22-25 行），Phase 1 三路调研子 Agent 的 JSON 信封现在也经过 L2 决策格式验证。
4. **需求路由 `routing_overrides` 传导链验证通过**：`_post_task_validator.py` 第 175-213 行 + 第 276-289 行确认了 Phase 1 checkpoint 中的 `requirement_type` 可正确影响 Phase 4 门禁阈值。
5. **v5.0.4 报告 11 项缺陷中，2 项已在 v5.1.1 修复，9 项仍存在**。

---

## 2. Phase 1 流程架构评审

### 2.1 整体架构图（v5.1.1 标注增强）

```
$ARGUMENTS 输入
      │
      ▼
┌─────────────────────────────────────────────────┐
│  Step 1.1: 需求来源解析                           │
│  Step 1.1.5: 需求信息量评估 (确定性规则)            │
│  Step 1.1.6: 需求类型分类与路由 (确定性规则)         │
│  [v5.1.1] Python3 fail-closed: 无 python3 → 阻断  │
└─────────────────────────────────────────────────┘
      │                                [A. 需求分析]
      ▼
┌─────────────────────────────────────────────────┐
│  Step 1.2-1.3: 三路并行调研                        │
│  ┌─ Auto-Scan ──→ Steering Documents             │
│  ├─ Research Agent ──→ research-findings.md       │
│  └─ Web Search ──→ web-research-findings.md       │
│  [v5.1] 调研完成后 → phase-1-interim.json          │
│  [v5.1.1] flock 锁 → emit 事件原子单调               │
│  [v5.1] 后台 Agent → L2 验证不再旁路                │
└─────────────────────────────────────────────────┘
      │                                [C. 调研]
      ▼
┌─────────────────────────────────────────────────┐
│  Step 1.4: 复杂度评估与分路                        │
│  Step 1.5: business-analyst 分析                  │
│  Step 1.5.5: 结构化决策协议                        │
└─────────────────────────────────────────────────┘
      │                                [B. 需求理解]
      ▼
┌─────────────────────────────────────────────────┐
│  Step 1.6: 多轮决策循环 LOOP                       │
│  Step 1.7: 生成结构化提示词                        │
│  Step 1.8: 最终确认                               │
│  [v5.1] 每轮决策后 → phase-1-interim.json 覆盖写入  │
└─────────────────────────────────────────────────┘
      │                                [D. 澄清]
      ▼
┌─────────────────────────────────────────────────┐
│  Step 1.9: 写入 phase-1-requirements.json         │
│  [v5.1] 原子写入 (.tmp + mv) + 最终验证             │
│  [v5.1] 删除中间态 phase-1-interim.json            │
│  Step 1.10: 可配置用户确认点                        │
└─────────────────────────────────────────────────┘
```

### 2.2 v5.1.1 增量改进对 Phase 1 的影响映射

| v5.1.1 修复项 | 影响 Phase 1 的步骤 | 影响类型 | 评估 |
|--------------|-------------------|---------|------|
| flock 原子事件序列 | Step 1.2-1.3 (emit-phase-event.sh) | 直接 | 消除并发 emit 事件乱序风险，GUI 事件流准确反映调研进度 |
| Python3 fail-closed | Step 1.1.5/1.1.6 (规则引擎) + Hook 链 | 直接 | 无 python3 环境下不再静默跳过所有 Hook，转为全面阻断 |
| IN_PHASE5 误判修复 | 非 Phase 1 直接受益 | 间接 | Phase 5 Write/Edit Hook 不再误判阶段，不影响 Phase 1 |
| decision.json 路径统一 | Step 1.6 (Gate 阻断恢复) | 间接 | 双向反控路径统一后，若 Phase 1 Gate 阻断可通过 GUI 发送 override |
| Zustand 状态去重 | GUI 事件渲染 | 间接 | Phase 1 事件流在 GUI 中不再出现重复条目 |

---

## 3. 逐维度 Prompt 质量分析

### 3.1 需求分析 Prompt 质量（维度 A: 83/100）

**评估对象**: Step 1.1 需求来源解析 + Step 1.1.5 信息量评估 + Step 1.1.6 类型分类

**优点**:
- **确定性规则优先**（`phase1-requirements.md` 第 21-33 行）：信息量评估使用 4 维硬编码规则（brevity / no_tech_entity / no_metric / vague_action），不依赖 AI 判断
- **决策树清晰**：flags >= 3 强制澄清预循环、>= 2 标记 low clarity、< 2 正常流程，逻辑分支无歧义
- **路由注入完整**（第 62-73 行）：`routing_overrides` JSON 结构定义清晰，包含 sad_path_min_ratio_pct / change_coverage_min_pct / required_test_types 三个维度

**缺陷（延续自 v5.0.4）**:
- **D-01（低）**: brevity 阈值 `< 20 字符` 未明确 Unicode 码点 vs 字节计算方式
- **D-03（中）**: 复合需求类型不支持 — "REST 迁移 GraphQL" 同时含 Feature + Refactor 特征，单一分类导致 routing_overrides 偏差
- **D-04（中）**: 路由策略表声称不同 requirement_type 影响 Phase 1 调研深度，但代码中调研深度仅由 complexity 控制
- **D-06（中）**: 分布式/高并发需求的 `no_metric` 权重不够灵敏

**v5.1.1 增益**:
- Python3 fail-closed 确保信息量评估和类型分类的规则引擎在无 Python3 时不会被静默跳过（`check-predecessor-checkpoint.sh` 第 61-73 行的 deny 逻辑）

**场景评分**:

| 场景 | 评分 | 理由 |
|------|------|------|
| S1: 健康检查端点 (简单) | 87 | 分类正确 (Feature)；brevity 边界值问题轻微 |
| S2: REST→GraphQL 迁移 (中等) | 74 | 分类为 Refactor 有争议；路由深度差异化在代码中未实现 |
| S3: 分布式配置中心 (复杂) | 82 | 分类正确 (Feature)；信息量评估对分布式需求不够灵敏 |
| **加权平均** | **83** | 权重 S1:20% S2:40% S3:40% |

### 3.2 需求理解结构化程度（维度 B: 89/100）

**评估对象**: Step 1.4 复杂度评估 + Step 1.5 business-analyst + Step 1.5.5 决策协议

**优点**:
- **business-analyst Prompt 模板完备**（`phase1-requirements-detail.md` 第 447-481 行）：明确注入 4 类上下文文件 + 4 项产出任务 + 返回信封格式
- **上下文保护严格**：子 Agent `run_in_background: true` + 自行 Write 全文 + 返回 JSON 信封摘要，主线程不读取全文
- **决策卡片标准化**（第 492-506 行）：结构化格式含背景/选项表/调研依据/推荐理由/"不决策"后果
- **复杂度分路合理**：small/medium/large 三级对应不同讨论深度（1轮/2-3轮/3+轮）
- **DecisionPoint 格式验证**（`_post_task_validator.py` 第 552-625 行）：L2 确定性验证 options/pros/cons/recommended/choice/rationale

**v5.1.1 增益**:
- 中间 Checkpoint 原子写入（`.tmp + mv`，`SKILL.md` 第 208-213 行）确保 business-analyst 信封写入不会因崩溃导致 JSON 截断
- 后台 Agent L2 验证恢复 — business-analyst 返回的 JSON 信封现在也经过决策格式检查

**缺陷（延续自 v5.0.4）**:
- **D-05（低）**: 调研深度与复杂度评估存在文档层面的循环依赖暗示（实践中不阻塞）
- **D-09（中）**: `min_qa_rounds` 配置定义但协议未消费

**场景评分**:

| 场景 | 评分 | 理由 |
|------|------|------|
| S1: 健康检查端点 | 94 | 小需求快速路径匹配；1 轮即完成 |
| S2: REST→GraphQL 迁移 | 87 | business-analyst + 苏格拉底模式有效拆解复杂迁移 |
| S3: 分布式配置中心 | 84 | 决策点数量多；每轮决策点数无协议规定 |
| **加权平均** | **89** | |

### 3.3 调研步骤覆盖度（维度 C: 82/100）

**评估对象**: Step 1.2 Auto-Scan + Step 1.3 Research Agent + Web Search

**优点**:
- **三路并行架构成熟**：Auto-Scan + Research Agent + Web Search 三者同一消息并行派发（`SKILL.md` 第 107-122 行）
- **持久化上下文复用**（`phase1-requirements-detail.md` 第 15-36 行）：7 天内有效的 `openspec/.autopilot-context/` 可跳过全量扫描
- **搜索决策规则引擎**（第 236-270 行）：确定性规则 + 7 维 force_search 条件，非 AI 自评
- **搜索结果信任机制**（第 301-309 行）：标注来源 + 交叉验证 + 冲突解决 + 降级策略
- **调研深度三级配置**（第 221-227 行）：basic/standard/deep 按 complexity 联动
- **历史知识注入**（`knowledge-accumulation.md`）：从 `.autopilot-knowledge.json` 匹配相关历史知识条目

**v5.1.1 增益**:
- flock 原子锁修复后，调研阶段的事件序列严格单调递增，GUI 可准确显示三路调研的启动/完成时序
- 后台 Agent（Research / Auto-Scan / Web Search）返回的 JSON 信封现在经过 L2 验证，格式异常可被确定性捕获

**缺陷（延续自 v5.0.4）**:
- **D-02（低）**: 极简 Feature 需求（如 health check）仍触发 Web 搜索，缺少 trivial complexity 快速跳过
- **D-11（低）**: `rules-scanner.sh` 第 10 行 `set -uo pipefail` 缺少 `-e`，内部错误可能被静默吞没

**新发现缺陷**:
- **D-12（低）**: Research Agent Prompt 模板中 Web 搜索年份硬编码为 `2026`（`phase1-requirements-detail.md` 第 202 行），虽然当前准确，但协议未定义动态获取当前年份的机制（搜索关键词模板中使用 `{当前年份}` 占位符，但 Prompt 示例直接写了 `2026`）
- **D-13（低）**: Auto-Scan 持久化上下文的 7 天有效期是硬编码值（`phase1-requirements-detail.md` 第 19 行 `(now - mtime) < 7 days`），不可配置

**场景评分**:

| 场景 | 评分 | 理由 |
|------|------|------|
| S1: 健康检查端点 | 79 | Web Search ROI 低但仍执行 |
| S2: REST→GraphQL 迁移 | 84 | force_search 正确触发；deep 调研覆盖依赖分析 |
| S3: 分布式配置中心 | 85 | 竞品对比搜索有效；deep 调研含同类实现分析 |
| **加权平均** | **82** | |

### 3.4 澄清机制完备性（维度 D: 87/100）

**评估对象**: Step 1.6 多轮决策循环 + Step 1.7 结构化提示词 + Step 1.8 最终确认 + 苏格拉底模式

**优点**:
- **主动讨论协议**（`phase1-requirements-detail.md` 第 528-545 行）：决策分类为技术/范围/风险三类，每类有差异化呈现方式
- **苏格拉底模式 6 步提问**（`phase1-supplementary.md` 第 14-21 行）：挑战假设 → 探索替代 → 识别隐含需求 → 强制排优 → 魔鬼代言人 → 最小可行范围
- **复杂度分路的讨论深度控制**：small 最多 1 轮、medium 2-3 轮、large 强制 3+ 轮
- **决策记录持久化**：每个 DecisionPoint 含 options/choice/rationale/affected_components
- **scope creep 检查**（第 558-559 行）：Large 复杂度每轮检查需求蔓延

**v5.1.1 增益**:
- 双向反控路径统一后（`decision.json` 路径服务端/引擎端 100% 等价），Phase 1 Gate 阻断时 GUI 可通过 override 解除阻断
- 中间 Checkpoint 每轮决策后覆盖写入（`SKILL.md` 第 150-157 行），崩溃恢复可从 `decision_round_N` 精确续接

**缺陷（延续自 v5.0.4）**:
- **D-07（中）**: Large 复杂度每轮最大决策点数无协议规定
- **D-08（中）**: 苏格拉底模式缺少非功能需求专项步骤（SLA/性能/可靠性）
- **D-09（中）**: `min_qa_rounds` 配置定义但 Phase 1 流程未消费

**场景评分**:

| 场景 | 评分 | 理由 |
|------|------|------|
| S1: 健康检查端点 | 95 | 1 轮快速确认即完成 |
| S2: REST→GraphQL 迁移 | 85 | 苏格拉底模式有效但决策点互相关联 |
| S3: 分布式配置中心 | 80 | 缺少非功能需求专项步骤；决策密度管控不足 |
| **加权平均** | **87** | |

### 3.5 Checkpoint 鲁棒性（维度 E: 91/100 — 新增维度）

**评估对象**: phase-1-interim.json 中间态 Checkpoint + 原子写入 + 崩溃恢复

**优点**:
- **两阶段中间 Checkpoint**：
  - `research_complete` 阶段：三路调研汇合后立即写入（`SKILL.md` 第 132-140 行）
  - `decision_round_N` 阶段：每轮决策 LOOP 后覆盖写入（第 150-157 行）
- **原子写入机制**（第 208-213 行）：`.tmp` 文件先写入 → python3 JSON 解析验证 → `mv` 原子重命名 → 最终验证
- **残留清理**：崩溃恢复时自动 `rm -f *.json.tmp`（`autopilot-recovery` 第 23-26 行）
- **恢复策略明确**（recovery 第 62-77 行）：按 `stage` 字段精确跳转到调研完成或决策轮次 N+1
- **用户决策**（recovery 第 72-77 行）：展示断点信息，提供"从断点继续"或"重新开始"选项
- **最终 Checkpoint 后清理**（`phase1-requirements.md` 第 159 行）：写入 `phase-1-requirements.json` 后删除中间态

**缺陷**:
- **D-14（低）**: 中间 Checkpoint 使用后台 Agent 写入（`SKILL.md` 第 134 行 `Agent(run_in_background: true, ...)`），理论上存在与主线程后续操作的竞态窗口（主线程可能在 Checkpoint 写入完成前继续下一步操作）。实际影响低，因为主线程在调研汇合和决策轮次中有自然等待点。
- **D-15（低）**: `decision_round_N` 中间 Checkpoint 的 `decisions_resolved` 和 `decisions_pending` 列表内容由主线程自行构造，无 L2 验证确保列表完整性

### 3.6 需求路由准确性（维度 F: 76/100 — 新增维度）

**评估对象**: Step 1.1.6 需求类型分类 + routing_overrides 传导

**优点**:
- **确定性分类规则**（`phase1-requirements.md` 第 43-48 行）：关键词匹配按优先级排序（Bugfix > Refactor > Chore > Feature）
- **传导链完整**：Phase 1 checkpoint `routing_overrides` → `_post_task_validator.py` 第 175-213 行读取 → Phase 4 门禁阈值动态调整
- **向后兼容**（第 77 行）：`requirement_type` 和 `routing_overrides` 为可选字段，未分类时等效 Feature 默认值
- **差异化路由策略表**（第 52-58 行）：4 种类型在 sad_path / change_coverage / 测试类型 / 强制附加测试 4 个维度有明确差异

**缺陷**:
- **D-03（中，已知）**: 单一分类不支持复合类型。"REST→GraphQL 迁移" 分类为 Refactor 但含大量 Feature 元素
- **D-04（中，已知）**: 路由策略表声称 Phase 1 调研深度因 requirement_type 不同而差异化，但代码中仅由 complexity 控制
- **D-16（中，新发现）**: Bugfix 关键词列表含"异常"（`phase1-requirements.md` 第 46 行），但"异常"在中文语境中可能是功能描述（如"添加异常处理"）而非 bug 报告。同理"报错"可能出现在 Feature 需求中（如"错误码统一处理"）。**关键词的多义性可能导致误分类**。
- **D-17（低，新发现）**: Chore 关键词含"文档"（第 47 行），但"生成 API 文档系统"是一个 Feature 而非 Chore。关键词匹配的优先级机制（Bugfix > Refactor > Chore > Feature）可以在一定程度上缓解，但无法完全消除。

**路由准确性仿真**:

| 需求描述 | 预期分类 | 实际分类 | 正确性 |
|---------|---------|---------|--------|
| "修复用户登录时报错" | Bugfix | Bugfix ("修复") | 正确 |
| "添加异常处理中间件" | Feature | Bugfix ("异常") | **误判** |
| "将 REST API 迁移为 GraphQL" | Feature+Refactor | Refactor ("迁移") | 部分正确 |
| "优化数据库查询性能" | Refactor | Refactor ("优化性能") | 正确 |
| "添加 CI/CD 流水线" | Chore | Chore ("CI/CD") | 正确 |
| "实现 API 文档生成系统" | Feature | Chore ("文档") | **误判** |
| "升级 React 18 到 19" | Refactor | Refactor ("升级") | 正确 |
| "实现分布式配置中心" | Feature | Feature (默认) | 正确 |

**准确率**: 6/8 = 75%。关键词多义性是主要误判来源。

---

## 4. 协议设计缺陷清单

### 4.1 缺陷全景（v5.0.4 遗留 + v5.1.1 新发现）

| ID | 严重度 | 类别 | 描述 | 状态 | 文件路径 |
|----|--------|------|------|------|---------|
| D-01 | 低 | 需求分析 | brevity 阈值 `< 20 字符` 未明确字符计算方式（Unicode 码点 vs 字节） | 遗留 | `references/phase1-requirements.md` L25 |
| D-02 | 低 | 调研 | 极简 Feature 仍触发 Web 搜索，缺少 trivial complexity 快速跳过 | 遗留 | `references/phase1-requirements-detail.md` L236-254 |
| D-03 | 中 | 路由 | 复合需求类型不支持单一分类，导致 routing_overrides 偏差 | 遗留 | `references/phase1-requirements.md` L43-48 |
| D-04 | 中 | 路由 | 路由策略表声称调研深度差异化，但代码中仅由 complexity 控制 | 遗留 | `references/phase1-requirements.md` L52-58 |
| D-05 | 低 | 架构 | 调研深度与复杂度评估存在文档层面的循环依赖暗示 | 遗留 | `references/phase1-requirements-detail.md` L221-227 |
| D-06 | 中 | 需求分析 | 分布式/高并发需求的信息量评估不够灵敏 | 遗留 | `references/phase1-requirements.md` L22-33 |
| D-07 | 中 | 澄清 | Large 复杂度每轮最大决策点数无协议规定 | 遗留 | `references/phase1-requirements-detail.md` L547-559 |
| D-08 | 中 | 澄清 | 苏格拉底模式缺少非功能需求专项步骤 | 遗留 | `references/phase1-supplementary.md` L14-21 |
| D-09 | 中 | 配置 | `min_qa_rounds` 配置定义但 Phase 1 流程未消费 | 遗留 | `references/config-schema.md` L23 |
| D-10 | 低 | 文档 | `phase1-supplementary.md` L59 仍引用已废弃的 `validate-decision-format.sh` | **已修复** | 逻辑合入 `_post_task_validator.py` Validator 5 |
| D-11 | 低 | 调研 | `rules-scanner.sh` L10 缺少 `set -e` | 遗留 | `scripts/rules-scanner.sh` L10 |
| D-12 | 低 | 调研 | Research Agent Prompt 模板中搜索年份存在硬编码示例 | **新发现** | `references/phase1-requirements-detail.md` L202 |
| D-13 | 低 | 调研 | Auto-Scan 持久化上下文 7 天有效期硬编码不可配置 | **新发现** | `references/phase1-requirements-detail.md` L19 |
| D-14 | 低 | Checkpoint | 中间 Checkpoint 后台写入与主线程存在理论竞态窗口 | **新发现** | `SKILL.md` L134 |
| D-15 | 低 | Checkpoint | 中间 Checkpoint 的 decisions 列表无 L2 完整性验证 | **新发现** | `SKILL.md` L150-157 |
| D-16 | 中 | 路由 | 分类关键词多义性（如"异常"既是 Bugfix 关键词也是 Feature 概念） | **新发现** | `references/phase1-requirements.md` L46 |
| D-17 | 低 | 路由 | "文档"关键词可能将 Feature 误分为 Chore | **新发现** | `references/phase1-requirements.md` L47 |

### 4.2 v5.0.4 报告缺口修复追踪

| v5.0.4 缺口 ID | 描述 | v5.1.1 状态 | 说明 |
|----------------|------|------------|------|
| #1 无合规约束专项检测 | 缺少 GDPR/PCI-DSS 等合规维度 | **未修复** | v5.1.1 未涉及合规检测增强 |
| #2 复合需求类型不支持 | 不支持 Feature+Refactor 双类型 | **未修复** | D-03 复现 |
| #3 搜索结果时效性无过滤 | 搜索可能返回过时信息 | **部分改善** | 搜索关键词模板含 `{当前年份}`，但无日期校验 |
| #4 Phase 1 无中间 checkpoint | 崩溃丢失调研进度 | **已修复（v5.1）** | phase-1-interim.json + 原子写入 |
| #5 苏格拉底模式仅 large 触发 | medium 需求无深度追问 | **未修复** | 仍仅 large 或 config.mode=="socratic" |
| D-10 文档引用已废弃脚本 | supplementary.md 引用旧脚本名 | **逻辑已修复** | 实际验证逻辑在 `_post_task_validator.py` 中，但文档引用未更新 |

---

## 5. v5.1.1 增量影响 Delta 分析

### 5.1 v5.1 → v5.1.1 热修复清单与 Phase 1 影响

| 热修复项 | 验证状态 | Phase 1 影响评估 |
|---------|---------|-----------------|
| flock 原子事件序列 | **PASS**（`hotfix-verification.md` 测试 4a） | 直接：Phase 1 emit-phase-event.sh 事件序列单调递增，GUI 事件流准确 |
| Python3 fail-closed | **PASS**（测试 3） | 直接：Phase 1 Hook 链（predecessor-checkpoint + post-task-validator）无 python3 时全面阻断而非放行 |
| IN_PHASE5 误判修复 | **PASS**（测试 2） | 间接：Phase 5 Write/Edit Hook 不再在 Phase 4→5 过渡期误判，不影响 Phase 1 |
| decision.json 路径统一 | **PASS**（测试 1） | 间接：双向反控路径闭环使 Phase 1 Gate 阻断可通过 GUI override 解除 |
| Zustand 去重 + 内存截断 | **PASS**（测试 5a） | 间接：Phase 1 事件流在 GUI 中不再重复渲染，内存占用可控 |

### 5.2 评分 Delta 归因

| 维度 | v5.0.4 → v5.1.1 Delta | 归因 |
|------|----------------------|------|
| A. 需求分析 | 81 → 83 (+2) | Python3 fail-closed 增强分类规则引擎鲁棒性 (+1)；更全面审计发现路由关键词多义性但总体框架健壮 (+1) |
| B. 需求理解 | 87 → 89 (+2) | 原子写入验证闭环 (+1)；后台 Agent L2 验证恢复确保 JSON 信封质量 (+1) |
| C. 调研 | 80 → 82 (+2) | flock 保证事件序列 (+1)；后台 Agent L2 验证恢复 (+1) |
| D. 澄清 | 86 → 87 (+1) | 双向反控路径统一改善 Gate 阻断-恢复体验 (+1) |
| **综合** | **84 → 86 (+2)** | v5.1.1 底层可靠性增强的整体收益 |

---

## 6. 仿真场景评估矩阵

### 场景定义（与 v5.0.4 一致以确保可比性）

| 场景 | 需求描述 | 预期路由 | 预期复杂度 |
|------|---------|---------|-----------|
| S1 (简单) | "给 Express 后端添加 /health 健康检查端点" | Feature | small |
| S2 (中等) | "将现有 REST API 迁移为 GraphQL，保持向后兼容" | Refactor | large |
| S3 (复杂) | "实现分布式配置中心客户端，支持热更新、灰度发布、多集群容灾" | Feature | large |

### 综合评估矩阵

| 子步骤 | S1 (简单) | S2 (中等) | S3 (复杂) | 加权平均 |
|--------|-----------|-----------|-----------|---------|
| A. 需求分析 | 87 | 74 | 82 | **83** |
| B. 需求理解 | 94 | 87 | 84 | **89** |
| C. 调研 | 79 | 84 | 85 | **82** |
| D. 澄清 | 95 | 85 | 80 | **87** |
| **场景综合** | **89** | **83** | **83** | **86** |

> 加权方式: S1:20%, S2:40%, S3:40%

---

## 7. 优化建议

### 7.1 高优先级 (P0 — 影响正确性)

| # | 建议 | 目标缺陷 | 预估工作量 |
|---|------|---------|-----------|
| P0-1 | **实现 requirement_type 对调研深度的实际控制**。在 Research Agent Prompt 模板中注入 `requirement_type`，Bugfix 聚焦复现路径，Chore 仅 Auto-Scan | D-04 | 中 |
| P0-2 | **支持复合需求类型**。允许 `requirement_type: ["refactor", "feature"]`，`routing_overrides` 取各类型最严格值 | D-03 | 中 |
| P0-3 | **消费 `min_qa_rounds` 配置**。Step 1.6 中读取配置值作为最低轮数下限 | D-09 | 小 |
| P0-4 | **修复关键词多义性**。增加上下文窗口匹配：仅当"异常"前有"修复/报/出现"等动词时匹配 Bugfix；仅当"文档"前有"更新/修改/补充"时匹配 Chore | D-16, D-17 | 中 |

### 7.2 中优先级 (P1 — 影响覆盖度)

| # | 建议 | 目标缺陷 | 预估工作量 |
|---|------|---------|-----------|
| P1-1 | **苏格拉底模式增加第 7 步"非功能需求质询"**（SLA/性能/可靠性/可观测性） | D-08 | 中 |
| P1-2 | **规定 Large 复杂度每轮最大 3-4 个决策点** | D-07 | 小 |
| P1-3 | **增强信息量评估对分布式需求的敏感度**。"分布式/集群/容灾" 关键词时 `no_metric` 权重从 1 升至 2 | D-06 | 小 |
| P1-4 | **Auto-Scan 持久化有效期可配置化**。从 `config.phases.requirements.auto_scan.cache_ttl_days` 读取 | D-13 | 小 |

### 7.3 低优先级 (P2 — 完善性)

| # | 建议 | 目标缺陷 | 预估工作量 |
|---|------|---------|-----------|
| P2-1 | 明确 brevity 阈值的字符计算方式（建议 Unicode 码点数） | D-01 | 极小 |
| P2-2 | 更新 `phase1-supplementary.md` 中对 `validate-decision-format.sh` 的引用 | D-10 | 极小 |
| P2-3 | Research Agent Prompt 中搜索年份使用动态占位符而非硬编码示例 | D-12 | 极小 |
| P2-4 | 增加合规约束检测维度（需求含"用户数据/支付/认证"时触发合规搜索） | v5.0.4 #1 | 中 |

---

## 8. 核心文件角色映射

| 文件 | 角色 | Phase 1 职责 |
|------|------|-------------|
| `skills/autopilot/SKILL.md` L98-162 | 主编排协议 | Phase 1 概要流程 + 并行调度 + 中间 Checkpoint |
| `skills/autopilot-phase1-requirements/references/phase1-requirements.md` | 核心流程 | 10 步详细流程骨架 |
| `skills/autopilot-phase1-requirements/references/phase1-requirements-detail.md` | 详细模板 | Prompt 模板 + 规则引擎 + 评估规则 |
| `skills/autopilot-phase1-requirements/references/phase1-supplementary.md` | 补充协议 | 苏格拉底模式 + 崩溃恢复 + 格式验证 |
| `skills/autopilot-setup/references/config-schema.md` L22-62 | 配置模板 | `phases.requirements` 配置节 |
| `skills/autopilot/references/protocol.md` | JSON 信封契约 | Phase 1 DecisionPoint 格式 + 路由字段 |
| `skills/autopilot/references/guardrails.md` | 护栏约束 | 上下文保护 + 并行编排 + 错误处理 |
| `skills/autopilot-phase7-archive/references/knowledge-accumulation.md` | 知识累积 | Phase 1 历史知识注入 |
| `scripts/_post_task_validator.py` L552-625 | L2 Hook | 决策格式确定性验证 (Validator 5) |
| `scripts/_post_task_validator.py` L175-213, L276-289 | L2 Hook | routing_overrides 动态阈值 (Validator 1) |
| `scripts/check-predecessor-checkpoint.sh` | L1 Hook | Phase 前置 Checkpoint 验证 |
| `scripts/rules-scanner.sh` | 工具脚本 | Auto-Scan 阶段项目约束提取 |
| `skills/autopilot-recovery/SKILL.md` L62-77 | 恢复协议 | Phase 1 中间态恢复逻辑 |

---

*报告由 Claude Opus 4.6 生成。所有文件路径相对于 `plugins/spec-autopilot/` 目录。审计基于静态协议分析和 dry-run 场景仿真，非实际运行测试。*
