# 需求路由与 Socratic 引擎评估报告 (v5.3)

> 审计日期: 2026-03-14
> 审计范围: spec-autopilot v5.3 — 需求路由 (requirement_type routing)、Socratic 质询引擎、min_qa_rounds 强制消费机制
> 审计方法: 静态分析 SKILL.md 编排文件 + Hook 脚本源码 + 测试文件覆盖度扫描

---

## 执行摘要

spec-autopilot 的需求路由和 Socratic 引擎在设计层面展现了高度完备的架构。四类需求（Feature/Bugfix/Refactor/Chore）的路由矩阵在 SKILL 编排层和 L2 Hook 层均有实现。Socratic 质询引擎 7 步流程设计严密，v5.2 新增的 Step 7 非功能需求质询（SLA/性能/可靠性）覆盖了关键领域。`min_qa_rounds` 强制消费机制具备硬约束保护（配置校验 + 循环逻辑）。

**主要发现**:
- 路由矩阵设计完备，四类需求全覆盖，复合需求合并策略合理
- L2 Hook (`_post_task_validator.py`) 已实现 `routing_overrides` 动态阈值调整（change_coverage + sad_path）
- Socratic 引擎 7 步质询流程健全，Step 7 非功能需求质询有关键词强制触发机制
- `min_qa_rounds` 有配置验证（类型 + 范围），但**缺少 L2 Hook 硬约束**（依赖 AI 自律执行）
- **测试层面存在显著缺口**: 无针对 `requirement_type` 路由、Socratic 质询、`min_qa_rounds` 的专项测试文件

**总评**: 82/100 — 设计成熟、L2 覆盖大部分路由场景，但测试覆盖和 min_qa_rounds 硬约束是短板。

---

## 1. requirement_type 路由矩阵

### 1.1 分类规则分析

路由分类定义于 `skills/autopilot-phase1-requirements/references/phase1-requirements.md` Step 1.1.6，采用**确定性关键词匹配**（非 AI 判断）。

| 类别 | 识别关键词 | 优先级 | 标记 |
|------|-----------|--------|------|
| **Bugfix** | 修复/fix/bug/defect/issue/regression/报错/异常/崩溃/闪退 | 1（最高） | `requirement_type: "bugfix"` |
| **Refactor** | 重构/refactor/优化性能/clean up/migrate/迁移/升级依赖 | 2 | `requirement_type: "refactor"` |
| **Chore** | 配置/CI/CD/文档/lint/format/依赖更新/版本号/changelog | 3 | `requirement_type: "chore"` |
| **Feature** | 以上均不匹配（默认兜底） | 4（最低） | `requirement_type: "feature"` |

**评价**:
- 四类需求全部覆盖，优先级匹配顺序合理（Bugfix > Refactor > Chore > Feature 兜底）
- 关键词覆盖中英文双语，适配中文团队使用场景
- Feature 作为默认兜底类别，确保不会出现"未分类"状态

### 1.2 复合需求路由 (v5.2)

当需求同时命中多个分类时（如"重构登录模块并添加 SSO 支持"），`requirement_type` 使用数组表示：

```json
{
  "requirement_type": ["refactor", "feature"],
  "routing_overrides": {
    "sad_path_min_ratio_pct": 20,
    "change_coverage_min_pct": 100,
    "required_test_types": ["unit", "api", "integration"]
  }
}
```

**合并策略**:
- 数值型: 取 `max()`（最严格） — 如 Refactor(100%) + Feature(80%) = 100%
- 列表型: 取 `union()`（最全面） — 合并所有必需测试类型

**评价**: 合并策略设计合理，"取最严格"原则保证质量底线不因复合需求而降级。

### 1.3 差异化流水线严格度

| 维度 | Feature | Bugfix | Refactor | Chore |
|------|---------|--------|----------|-------|
| Phase 1 调研深度 | 完整三路并行 | 聚焦复现路径+根因 | 聚焦影响范围+回归 | 最小化（仅 Auto-Scan） |
| Phase 4 sad_path 比例 | 20% | **40%** | 20% | 10% |
| Phase 5 change_coverage | 80% | **100%** | **100%** | 60% |
| Phase 6 测试类型 | 全量 | 至少 regression | 至少 integration | typecheck 即可 |
| 强制附加测试 | 无 | 复现测试 | 行为保持测试 | 无 |

**评价**: 差异化策略精准匹配各类需求特征 — Bugfix 强制 100% change_coverage + 复现测试，Refactor 强制行为保持测试，Chore 合理放宽。

### 1.4 L2 Hook 动态阈值实现

`scripts/_post_task_validator.py` (Validator 1, Phase 4 分支) 实现了 `routing_overrides` 的动态阈值读取:

```python
# Line 175-193: 从 Phase 1 checkpoint 读取 routing_overrides
_routing_overrides = _p1_data.get("routing_overrides", {})

# Line 207-213: 动态调整 change_coverage 阈值
_routing_cov = _routing_overrides.get("change_coverage_min_pct")
FLOOR_MIN_CHANGE_COV = max(FLOOR_MIN_CHANGE_COV, int(_routing_cov))

# Line 276-277: 动态调整 sad_path 阈值
_routing_sad = _routing_overrides.get("sad_path_min_ratio_pct")
FLOOR_MIN_SAD_PATH_RATIO = int(_routing_sad) if _routing_sad is not None else ...
```

**关键发现**: L2 Hook 通过读取 `.autopilot-active` 锁文件 → 定位 change_name → 读取 `phase-1-requirements.json` → 提取 `routing_overrides`，形成完整的路由到门禁的传递链。这是**确定性的硬约束**，AI 无法绕过。

### 1.5 路由缺口分析

| 检查项 | 状态 | 说明 |
|--------|------|------|
| 四类需求全覆盖 | PASS | Feature/Bugfix/Refactor/Chore 均有独立策略 |
| 复合需求合并 | PASS | 数组表示 + max/union 合并策略 |
| L2 动态阈值 (change_coverage) | PASS | `_post_task_validator.py` 已实现 |
| L2 动态阈值 (sad_path) | PASS | `_post_task_validator.py` 已实现 |
| L2 动态阈值 (required_test_types) | **GAP** | `routing_overrides.required_test_types` 在 L2 Hook 中未被消费，仅在 SKILL 编排层（L3）通过 dispatch prompt 注入 |
| CLAUDE.md 文档同步 | PASS | `CLAUDE.md` "需求路由 (v4.2)" 章节与实现一致 |
| protocol.md 字段定义 | PASS | Phase 1 额外字段中包含 `requirement_type` + `routing_overrides` |

---

## 2. Socratic 质询引擎分析

### 2.1 触发条件

定义于 `skills/autopilot-phase1-requirements/references/phase1-supplementary.md`:

| 触发条件 | 行为 |
|---------|------|
| `config.phases.requirements.mode == "socratic"` | 用户显式启用 |
| `complexity == "large"` | 强制激活（覆盖 config） |
| `current_round < min_qa_rounds` 且所有决策点已澄清 | 强制执行苏格拉底步骤（即使非 socratic 模式） |

**评价**: 三重触发机制确保大型需求和配置要求的场景均能激活质询引擎。

### 2.2 七步提问流程

| 步骤 | 目的 | 评估 |
|------|------|------|
| 1. 挑战假设 | 质疑隐含前提 | 有效 — 示例提问贴合实际 |
| 2. 探索替代方案 | 寻找未考虑路径 | 有效 |
| 3. 识别隐含需求 | 挖掘未明确需求 | 有效 |
| 4. 强制排优 | 功能过多时迫使取舍 | 有效 — 对 scope creep 有直接防御 |
| 5. 魔鬼代言人 | 从反对角度审视 | 有效 |
| 6. 最小可行范围 | 收敛到 MVP | 有效 |
| **7. 非功能需求质询 (v5.2)** | SLA/性能/可靠性 | **重点评估 — 见下** |

### 2.3 Step 7 非功能需求质询深度分析

**触发条件** (v5.2): 当 `RAW_REQUIREMENT` 包含以下正则匹配的关键词时**强制触发**:

```
并发|高并发|分布式|微服务|高可用|性能|吞吐|延迟|QPS|TPS|SLA|负载|扩容|弹性|
容错|降级|限流|熔断|concurrent|distributed|scalab|throughput|latency|
high.?avail|load.?balanc|fault.?toleran
```

**提问方向覆盖**:

| 方向 | 示例提问 | 覆盖范围 |
|------|---------|---------|
| 性能 | QPS/TPS 目标、P99 延迟 | 吞吐量 + 延迟指标 |
| 可靠性 | 降级策略、数据一致性 | 容错 + 一致性 |
| 可扩展性 | 水平扩容、峰值比 | 弹性伸缩 |
| SLA | 可用性目标（几个9）、维护窗口 | 运维指标 |

**评价**:
- **优点**: 关键词覆盖全面（28 个触发词），中英文双语，正则模式支持模糊匹配（如 `high.?avail`）
- **优点**: 强制触发机制确保含非功能需求关键词的需求不会跳过质询
- **缺口 1**: 安全相关非功能需求（如 `OWASP/渗透/加密/合规`）未在 Step 7 触发词中，虽在搜索策略的 `force_search_keywords` 中覆盖（`安全/auth/加密`），但 Socratic 质询层未覆盖安全治理质询
- **缺口 2**: 可观测性需求（如 `监控/日志/告警/tracing/metrics`）未在触发词中，分布式系统场景下这是关键非功能需求
- **缺口 3**: 触发后的提问是 AI 从 4 个方向中选择性提问，无确定性保证全覆盖

### 2.4 集成方式

苏格拉底模式集成在 Phase 1.6 多轮决策循环中：

```
FOR EACH undecided_point:
    1. 标准处理: AskUserQuestion 展示选项
    2. 苏格拉底追问: 从 7 步中选择 1-2 步（Step 7 关键词匹配时强制包含）
    3. 引用 research-findings.md 事实数据支撑
    4. 新决策点 → 回到循环
```

**评价**: 苏格拉底步骤与标准决策循环紧密耦合，每轮循环自然触发，不是独立的额外阶段。这种设计避免了"质询疲劳"。

---

## 3. min_qa_rounds 机制审查

### 3.1 设计规格

定义于 `skills/autopilot-phase1-requirements/references/phase1-requirements.md` Step 1.6:

```
current_round = 0
min_rounds = config.phases.requirements.min_qa_rounds || 1

LOOP:
  current_round += 1
  ...
  IF 所有决策点已澄清 AND current_round >= min_rounds:
    EXIT LOOP
  ELIF 所有决策点已澄清 AND current_round < min_rounds:
    执行苏格拉底步骤（即使非 socratic 模式）
    IF 未发现新决策点:
      EXIT LOOP  // 安全阀
```

### 3.2 配置验证

`scripts/_config_validator.py` 对 `min_qa_rounds` 实施以下验证:

| 验证层 | 检查项 | 状态 |
|--------|--------|------|
| 类型检查 | `phases.requirements.min_qa_rounds: (int, float)` | PASS (Line 109) |
| 范围检查 | 无专项范围约束 | **GAP** — 未在 `RANGE_RULES` 中定义上下限 |
| 必填检查 | 不在 `REQUIRED_NESTED` 中 | 可接受 — 有默认值 1 |

### 3.3 硬约束保护分析

| 保护层 | 机制 | 状态 |
|--------|------|------|
| L1 (Task blockedBy) | 不适用 — min_qa_rounds 是 Phase 1 内部逻辑 | N/A |
| L2 (Hook 确定性验证) | **无** — 没有 Hook 校验 Phase 1 checkpoint 中的实际 QA 轮数 | **GAP** |
| L3 (AI Gate) | 通过 SKILL.md 循环逻辑实施 | PASS（但依赖 AI 自律） |
| 配置校验 | `_config_validator.py` 类型检查 | 部分 PASS |

**关键发现**: `min_qa_rounds` 的强制消费**完全依赖 AI 自律执行循环逻辑**。没有 L2 Hook 验证 Phase 1 checkpoint 中的 `decisions` 数量或实际轮数是否满足 `min_qa_rounds`。这意味着：

1. AI 理论上可以在 1 轮后就写入 `phase-1-requirements.json` 并跳过后续轮次
2. Phase 1 的 `_post_task_validator.py` Validator 5 (Decision Format) 仅验证 `decisions` 数组非空和格式正确，不验证轮数

### 3.4 安全阀设计

循环中的安全阀（"确实无遗漏时允许提前退出"）设计合理，防止无意义的强制循环。但安全阀本身也是 AI 判断（"未发现新决策点"），没有确定性验证。

### 3.5 复杂度分路与 min_qa_rounds 的交互

| 复杂度 | 预计 QA 轮数 | min_qa_rounds 下限 | 实际约束 |
|--------|-------------|-------------------|---------|
| small | 1 轮 | config 值 (默认 1) | 取 max(1, config 值) |
| medium | 2-3 轮 | config 值 | 取 max(2, config 值) |
| large | 3+ 轮 | config 值 | 取 max(3, config 值) |

**评价**: 复杂度自带的最低轮数与 `min_qa_rounds` 取较大值的交互逻辑合理，但这一交互逻辑在 SKILL 文档中**未显式说明**，仅能从 `phase1-requirements-detail.md` 的分路策略和 `phase1-requirements.md` 的 min_qa_rounds 逻辑间接推导。

---

## 4. 门禁阈值动态调整验证

### 4.1 传递链完整性

```
Phase 1 分类
  → requirement_type + routing_overrides 写入 phase-1-requirements.json
    → L2 Hook (_post_task_validator.py) 读取 .autopilot-active → 定位 change_name
      → 读取 phase-1-requirements.json → 提取 routing_overrides
        → 动态调整 FLOOR_MIN_CHANGE_COV 和 FLOOR_MIN_SAD_PATH_RATIO
```

**验证结果**: 传递链完整，从分类到门禁执行全链路可追溯。

### 4.2 各门禁点动态调整明细

| 门禁点 | 默认阈值 | Bugfix 阈值 | Refactor 阈值 | Chore 阈值 | L2 实现 |
|--------|---------|------------|-------------|-----------|---------|
| change_coverage_min_pct | 80% | 100% | 100% | 60% | PASS — `max()` 合并 |
| sad_path_min_ratio_pct | 20% | 40% | 20% | 10% | PASS — 路由覆盖 |
| required_test_types | [unit,api,e2e,ui] | +regression | +integration | typecheck | **GAP** — L3 only |
| Phase 4 warning 处理 | 强制 blocked | 同 | 同 | 同 | PASS — 不受路由影响 |

### 4.3 容错设计

L2 Hook 中 `routing_overrides` 读取包裹在 `try-except` 中，任何异常（锁文件不存在、JSON 解析失败、字段缺失）均静默降级为默认阈值。这种容错设计确保路由失败不会阻断流水线，但可能导致 Bugfix/Refactor 场景下门禁意外放宽。

---

## 5. 测试覆盖度

### 5.1 现有测试文件扫描

对 `plugins/spec-autopilot/tests/` 目录下 50+ 个测试文件进行关键词搜索:

| 搜索关键词 | 匹配文件数 | 说明 |
|-----------|-----------|------|
| `requirement_type` | **0** | 无路由分类专项测试 |
| `routing_overrides` | **0** | 无路由覆盖专项测试 |
| `min_qa_rounds` | **0** | 无最低轮数专项测试 |
| `socratic` / `质询` | **0** | 无苏格拉底引擎专项测试 |
| `change_coverage` | **1** | `test_change_coverage.sh` — 验证 Phase 4 change_coverage 门禁 |
| `sad_path` | **0** (推断) | 无 sad_path 动态阈值专项测试 |
| `pyramid` | **1** | `test_pyramid_threshold.sh` — 验证 test_pyramid floor |

### 5.2 间接覆盖分析

虽然无专项测试，部分路由逻辑被**间接覆盖**:

| 功能 | 间接覆盖来源 | 覆盖程度 |
|------|------------|---------|
| change_coverage 门禁 | `test_change_coverage.sh` (5 个用例) | 中 — 测试默认 80% 阈值，未测试路由动态调整后的 100% |
| test_pyramid floor | `test_pyramid_threshold.sh` (4 个用例) | 中 — 测试默认阈值，未测试路由覆盖 |
| Phase 1 决策格式 | `_post_task_validator.py` Validator 5 被 `test_json_envelope.sh` 覆盖 | 低 — 仅测试格式，不测试轮数 |
| config 校验 | `test_validate_config.sh` + `test_validate_config_v11.sh` | 低 — 测试 schema 完整性，不测试 min_qa_rounds 语义 |

### 5.3 测试缺口汇总

| 缺失测试 | 优先级 | 说明 |
|---------|--------|------|
| `test_requirement_routing.sh` | **P0** | 验证 Bugfix/Refactor/Chore/Feature 四类分类正确性 |
| `test_routing_overrides.sh` | **P0** | 验证 routing_overrides 动态调整后 L2 门禁的实际阈值变化 |
| `test_compound_routing.sh` | **P1** | 验证复合需求 (数组类型) 的 max/union 合并策略 |
| `test_sad_path_routing.sh` | **P1** | 验证 Bugfix 场景下 sad_path 阈值提升至 40% |
| `test_min_qa_rounds.sh` | **P1** | 验证 min_qa_rounds 配置校验范围约束 |
| `test_socratic_trigger.sh` | **P2** | 验证 Socratic 模式触发条件（complexity=large, config, min_qa_rounds） |

---

## 6. 评分

| 维度 | 得分 | 满分 | 说明 |
|------|------|------|------|
| 路由完备度（四类需求全覆盖） | 24 | 25 | 四类全覆盖 + 复合路由 + L2 动态阈值；扣 1 分: `required_test_types` 仅 L3 覆盖 |
| Socratic 质询深度（非功能需求、SLA） | 21 | 25 | 7 步流程完整，Step 7 覆盖性能/SLA/可靠性/扩展性；扣 2 分: 安全/可观测性未覆盖；扣 2 分: 质询执行为 AI 选择性提问，无确定性保证 |
| min_qa_rounds 强制消费机制 | 17 | 25 | 设计逻辑完整 + 安全阀合理 + 配置类型校验；扣 5 分: 无 L2 硬约束，依赖 AI 自律；扣 2 分: 无范围校验；扣 1 分: 复杂度交互逻辑未显式文档化 |
| 测试覆盖率 | 20 | 25 | 间接覆盖 change_coverage + pyramid；扣 5 分: 无路由专项测试 (P0 缺口) |
| **总计** | **82** | **100** | |

---

## 7. 改进建议

### P0 — 高优先级

1. **新增路由动态阈值测试** (`test_routing_overrides.sh`)
   - 场景: 写入 Phase 1 checkpoint 含 `routing_overrides: {change_coverage_min_pct: 100}`，验证 Phase 4 的 L2 Hook 使用 100% 而非默认 80%
   - 场景: 写入 `routing_overrides: {sad_path_min_ratio_pct: 40}`，验证 Phase 4 sad_path 门禁动态提升

2. **为 `min_qa_rounds` 添加范围约束**
   - 在 `_config_validator.py` 的 `RANGE_RULES` 中添加: `"phases.requirements.min_qa_rounds": (1, 10)`
   - 防止配置为 0（绕过质询）或过大值（无意义循环）

### P1 — 中优先级

3. **新增 `required_test_types` L2 Hook 验证**
   - 在 `_post_task_validator.py` Phase 4 分支中，读取 `routing_overrides.required_test_types`，验证 Phase 4 信封的 `test_counts` 中对应类型的值 > 0
   - 当前仅在 dispatch prompt 中注入（L3），AI 理论上可忽略

4. **为 min_qa_rounds 添加 L2 后置验证**
   - 在 Phase 1 的 `_post_task_validator.py` Validator 5 中，增加: 从 `decisions` 数组推断实际轮数（通过决策点数量或时间戳差异），与 `min_qa_rounds` 配置值对比
   - 这可以从"AI 自律"提升为"确定性验证"

5. **扩展 Step 7 非功能需求触发词**
   - 添加安全相关: `OWASP|渗透|合规|compliance|audit|encryption|TLS|WAF`
   - 添加可观测性相关: `监控|告警|日志|tracing|metrics|observability|APM|Prometheus|Grafana`

### P2 — 低优先级

6. **文档化复杂度与 min_qa_rounds 交互规则**
   - 在 `phase1-requirements.md` Step 1.6 中显式说明: "实际最低轮数 = max(复杂度预设轮数, config.min_qa_rounds)"
   - 避免实现者对两个独立约束的交互产生歧义

7. **增加路由分类的可扩展性接口**
   - 当前分类关键词硬编码在 SKILL.md 中，考虑迁移到 `autopilot.config.yaml` 的 `requirement_routing.keywords` 节
   - 允许项目自定义分类关键词（如域特定术语）

8. **Socratic 质询日志记录**
   - 在 Phase 1 checkpoint 中记录苏格拉底质询的实际执行情况（触发了哪些步骤、产生了多少新决策点）
   - 为后续审计和质量度量提供数据支撑
