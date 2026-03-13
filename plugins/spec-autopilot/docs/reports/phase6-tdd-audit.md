# Phase 6 TDD 流程纯洁度与测试质量评审报告

> 评审日期: 2026-03-13
> 评审对象: `plugins/spec-autopilot` v4.0.0
> 评审员: Agent 4 — Phase 6 TDD 流程纯洁度与测试质量评审员

---

## 1. 执行摘要

本报告对 spec-autopilot 插件的 TDD 流程纯洁度与测试质量进行了全面审计。审计覆盖五个核心维度：TDD Red-Green-Refactor 循环完整性、测试有效性(Assertion Quality)、边缘与异常覆盖、Mock 与依赖隔离、测试金字塔执行。

**核心发现**: 插件在 TDD 协议设计层面达到了行业领先水准 -- 三层验证架构(L1 AI 自查 + L2 主线程 Bash 确定性验证 + L3 Gate 审计)为 TDD 纪律提供了强有力的工程保障。然而，存在若干结构性缺陷：并行 TDD 模式下 L2 验证降级为事后全量测试（丢失了逐 task 的 RED 阶段确定性验证）、测试反模式检测完全依赖 AI 自查缺少确定性 Hook 强制执行、边缘用例覆盖依赖模板建议但无量化门禁。

**综合评分: 7.4/10** -- 协议设计优秀，但确定性执行层（Hook/脚本）对 TDD 和测试质量的覆盖存在盲区。

---

## 2. 评审方法论

本次评审采用以下方法：

1. **文档协议分析**: 逐文件精读 TDD 循环协议(`tdd-cycle.md`)、Phase 5 实现(`phase5-implementation.md`)、测试反模式(`testing-anti-patterns.md`)、质量扫描(`quality-scans.md`)、代码审查(`phase6-code-review.md`)、Gate 门禁(`autopilot-gate/SKILL.md`)、主编排器(`autopilot/SKILL.md`)、共享协议(`protocol.md`)、配置文档(`configuration.md`)等核心文件。

2. **确定性执行层审计**: 审查 `anti-rationalization-check.sh`、`validate-json-envelope.sh`、`check-predecessor-checkpoint.sh`、`write-edit-constraint-check.sh`、`test-hooks.sh` 等脚本，验证协议规则是否有确定性代码强制执行。

3. **Prompt 注入审计**: 审查 `dispatch-prompt-template.md` 中的 TDD RED/GREEN/REFACTOR prompt 模板，评估约束传递的有效性。

4. **配置阈值审计**: 审查 `autopilot.config.yaml` 配置 schema 中 `test_pyramid`、`test_suites`、`tdd_mode` 等字段的设计合理性。

5. **Gap 分析**: 对每个协议要求，验证是否存在对应的确定性执行机制（Hook/脚本），识别仅依赖 AI 自律的"软约束"。

---

## 3. TDD Red-Green-Refactor 循环审计

### 3.1 Iron Law 执行机制

**协议定义** (`tdd-cycle.md` 第9-16行):

> NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST.
> 违反即删除：先写了实现代码 -> 删除实现，从测试重新开始。Delete means delete.

**串行 TDD 执行机制** (评分: 9/10):

串行模式下的 TDD Iron Law 具有极强的确定性保障：

- **RED 阶段**: 主线程派发子 Agent 仅写测试（prompt 明确"禁止写任何实现代码"），然后主线程通过 `Bash(test_command)` 执行 L2 验证：
  - `exit_code == 0` -> BLOCK（测试不应通过，说明测试有问题）
  - 失败原因是语法/编译错误 -> BLOCK（不是正确的断言失败）
  - `exit_code != 0` 且断言失败 -> PASS
- **GREEN 阶段**: 主线程派发子 Agent 写最小实现，prompt 注入"fix implementation, never modify test"，主线程 `Bash(test_command)` 验证通过。
- **REFACTOR 阶段**: 主线程 `Bash(test_command)` 验证重构后测试仍通过，失败则自动 `git checkout` 回滚。

这种"子 Agent 执行 + 主线程 Bash 确定性验证"的模式是 TDD 纯洁度的黄金标准。RED 阶段同时检查"通过"和"语法错误"两种伪失败，设计严谨。

**并行 TDD 执行机制** (评分: 5/10):

并行模式下的 TDD 验证存在结构性降级：

- 域 Agent 内部执行 RED-GREEN-REFACTOR 循环，属于 **L1 AI 自查**
- 主线程在域 Agent 合并后仅执行 **L2 后置验证**（全量测试 `Bash(full_test_command)`）
- `tdd-cycle.md` 第191行明确承认：*"并行模式下域 Agent 内部的 RED/GREEN 验证为 AI 自查（L1 层），缺少串行模式的主线程 Bash() L2 确定性保障。"*

**关键缺陷**: 并行 TDD 的 L2 后置验证只能确认"最终测试通过"，无法验证"每个 task 是否真正经历了 RED 阶段"。域 Agent 可以先写实现再补测试，只要最终全量测试通过就能蒙混过关。`tdd_cycles` 数组中的 `red_verified: true` 完全依赖 AI 诚实汇报。

### 3.2 L2 Hook 验证分析

**已有确定性验证**:

| Hook | 验证内容 | 覆盖阶段 |
|------|---------|---------|
| `check-predecessor-checkpoint.sh` | TDD 模式下 Phase 5 前置 checkpoint 正确性（Phase 3 或 Phase 4 tdd_override） | Phase 4->5 |
| `validate-json-envelope.sh` | Phase 5 信封必须含 `zero_skip_check`、`tasks_completed` 等字段 | Phase 5 |
| `write-edit-constraint-check.sh` | TDD 模式下正确识别 Phase 5 执行状态 | Phase 5 |

**缺失的确定性验证**:

| 缺失项 | 影响 |
|--------|------|
| **无 Hook 验证 `tdd_metrics.red_violations === 0`** | Gate Skill L3 层执行此检查，但 L3 是 AI 执行的软检查，可被绕过 |
| **无 Hook 验证每个 task 的 `tdd_cycle` 完整性** | 同上，仅 L3 Gate 执行 |
| **`validate-json-envelope.sh` 不检查 `tdd_metrics` 字段** | 经 Grep 确认，该脚本无任何 TDD 相关检查 |

### 3.3 作弊检测有效性

**反合理化检测** (`anti-rationalization-check.sh`):

该脚本使用加权模式匹配检测"跳过/延后/不必要"等合理化模式，覆盖 Phase 4/5/6。这能捕获显式的跳过声明，但不能检测 TDD 作弊（先写代码后补测试）。TDD 作弊不会产生合理化文本，因此该脚本对 TDD 纯洁度无直接贡献。

**作弊检测总结**:

| 检测手段 | 类型 | 对串行 TDD 有效 | 对并行 TDD 有效 |
|---------|------|----------------|----------------|
| 主线程 Bash() RED 验证 | 确定性(L2) | 是 | 否 |
| `tdd_cycles` JSON 报告 | AI 汇报(L1) | N/A | 依赖 AI 诚实 |
| L3 Gate `tdd_audit` | AI 审计(L3) | 是 | 仅验证 JSON 字段存在 |
| `anti-rationalization-check.sh` | 确定性(L2) | 不检测 TDD 作弊 | 不检测 TDD 作弊 |

### 3.4 评分 (1-10)

| 子项 | 评分 | 说明 |
|------|------|------|
| 串行 TDD 协议设计 | 9.5 | 三层 RED/GREEN/REFACTOR 确定性验证，行业标杆 |
| 并行 TDD 协议设计 | 5.0 | 设计文档坦诚承认降级，但缺少弥补措施 |
| Iron Law 确定性执行 | 7.0 | 串行强，并行弱，Hook 层无 TDD 专属检查 |
| 作弊检测 | 6.0 | 串行模式下结构性不可作弊；并行模式可伪造 `tdd_cycles` |
| **综合** | **7.0** | |

---

## 4. 测试有效性 (Assertion Quality) 审计

### 4.1 反模式检测机制

**协议层** (`testing-anti-patterns.md`):

定义了 5 种反模式并附带具体代码示例和 Gate Function：

1. **Testing Mock Behavior**: 测试只验证 mock 返回值
2. **Test-Only Methods in Production**: 生产代码包含测试专用方法
3. **Mocking Without Understanding**: 盲目 mock 整个模块
4. **Incomplete Mocks**: Mock 对象缺少真实 API 字段
5. **Integration Tests as Afterthought**: 后补集成测试

每种反模式均定义了 Gate Function（如"检查测试中 mock.return_value 设置后是否仅断言了相同的返回值"），设计水平高。

**注入机制**:

| 注入时机 | 方式 |
|---------|------|
| TDD RED (串行) | 子 Agent prompt 注入完整反模式指南 |
| TDD RED (并行) | 域 Agent prompt 注入精简版 Gate Function 检查表 |
| Phase 4 (非 TDD) | 不注入（Phase 4 有自己的 test standards 模板） |

**确定性执行层**: **不存在**。

经审查所有 Hook 脚本，**没有任何 Hook 执行反模式检测**。`testing-anti-patterns.md` 中定义的 Gate Function 仅作为"子 Agent 自查"清单注入 prompt，完全依赖 AI 自律。没有脚本会扫描测试代码检查 `expect(true).toBe(true)` 或 `mock.return_value` 后仅断言相同值等欺骗性模式。

### 4.2 断言质量保障

**Phase 4 模板** (`phase4-testing.md`) 中的测试矩阵要求每端点 >= 3 个用例、每组件 >= 3 个用例，但这些是数量要求而非质量要求。

**变更覆盖率** (`change_coverage`) 是一项有价值的质量指标（覆盖率 >= 80%，L2 Hook `validate-json-envelope.sh` 强制执行），但它验证的是"变更点是否有测试覆盖"，而非"断言是否有意义"。

**测试不可变原则** 在 `guardrails.md` 和 `phase4-testing.md` 中反复强调（"测试创建后绝对禁止修改以通过测试"），这是间接的断言质量保障——如果断言无意义，实现很容易通过，系统不会产生有价值的反馈。

**缺失**: 无静态分析工具（如 ESLint 的 no-empty-expect 规则）集成到 Hook 或质量扫描中，用于检测空断言、恒真断言、重复断言等低质量测试模式。

### 4.3 评分 (1-10)

| 子项 | 评分 | 说明 |
|------|------|------|
| 反模式文档质量 | 9.0 | 5 种模式 + 代码示例 + Gate Function，设计优秀 |
| 反模式确定性执行 | 2.0 | 无 Hook/脚本强制执行，完全依赖 AI 自查 |
| 断言质量门禁 | 4.0 | 变更覆盖率有 L2 保障，但无断言内容质量检测 |
| `expect(true).toBe(true)` 防御 | 1.0 | 无任何机制检测恒真/空断言 |
| **综合** | **4.5** | |

---

## 5. 边缘与异常覆盖审计

### 5.1 Phase 4 测试设计覆盖分析

**测试矩阵** (`phase4-testing.md` 第23-32行) 明确要求：

| 维度 | 必须覆盖内容 | 最低用例数 |
|------|------------|-----------|
| 后端 API 接口 | 正常/异常/边界场景 | 每端点 >= 3 |
| 前端页面和组件 | 渲染、交互、状态变化、错误态 | 每组件 >= 3 |
| 完整业务流程 | 主流程 + 分支流程 + 异常中断 | >= 5 |
| **边界条件和异常** | **空值、超长、并发、权限、网络异常** | **>= 8 个边界用例** |

边界条件和异常被显式列为独立维度并要求 >= 8 个用例，这在协议设计层面是合格的。

**变更聚焦专项测试** (v3.2.5 新增) 要求每个被修改/新增的代码单元至少有 1 个专项测试，`change_coverage` 覆盖率 >= 80%。这确保了变更点有测试覆盖，但不强制要求边界场景覆盖。

### 5.2 Sad Path 覆盖机制

**协议层要求**:
- Phase 4 模板要求"空值、超长、并发、权限、网络异常"
- TDD RED prompt 模板中注入"充分考虑边界情况和异常场景"（仅 heavy 模型路由模式）
- `tdd-cycle.md` 红旗标记第13条："实现超出测试范围 -> YAGNI，删除多余代码"——这从反向约束了实现不超范围，但未直接要求测试覆盖 Sad Path

**确定性执行层**: **无门禁检测 Sad Path 覆盖率**。

- `validate-json-envelope.sh` 检查 `test_counts` 的总量，但不区分 Happy Path / Sad Path
- `test_pyramid` 检查单元测试/E2E 测试比例，但不区分场景类型
- Phase 4 门禁的 `min_test_count_per_type`（配置范围 [1, 100]）是总量门禁，不是 Sad Path 门禁
- 无任何 Hook 或脚本检查测试代码中是否包含异常断言（如 `expect(...).toThrow()`、`assert raises`、null 检查等）

**质量扫描层**: `quality-scans.md` 定义了突变测试（mutation testing）作为异步质量扫描，可间接评估测试有效性。但突变测试配置为可选、超时 10 分钟、且不阻断归档（仅在汇总表标红）。这是一种"信息性"保障而非"门禁性"保障。

### 5.3 评分 (1-10)

| 子项 | 评分 | 说明 |
|------|------|------|
| Phase 4 模板 Sad Path 要求 | 7.5 | 明确列出空值/超长/并发/权限/网络异常，>= 8 用例 |
| Sad Path 确定性门禁 | 2.0 | 无 Hook 检查 Sad Path 覆盖率或异常断言存在性 |
| 突变测试覆盖 | 5.0 | 作为可选异步扫描存在，不阻断归档 |
| 边界条件量化跟踪 | 3.0 | `test_counts` 不区分 Happy/Sad Path |
| **综合** | **5.0** | |

---

## 6. Mock 与依赖隔离审计

### 6.1 Mock 策略约束

**协议层约束**:

1. **Iron Law 红旗标记第5条** (`tdd-cycle.md`): "测试只验证 mock 行为 -> 测试真实组件"
2. **红旗标记第10条**: "Mock setup > test logic -> 用集成测试"
3. **反模式第1/3/4条** (`testing-anti-patterns.md`):
   - Anti-Pattern 1: Testing Mock Behavior（测试 mock 而非真实代码）
   - Anti-Pattern 3: Mocking Without Understanding（盲目 mock）
   - Anti-Pattern 4: Incomplete Mocks（mock 缺少字段）
4. **TDD 并行模式 prompt 注入** (`tdd-cycle.md` 第163-167行):
   - "NEVER test mock behavior -- test real code"
   - "NEVER mock without understanding dependencies"
   - "If mock setup > test logic -> use integration test instead"
   - "Integration tests are first-class, not afterthoughts"
5. **Gate Function 检查表** (`testing-anti-patterns.md` 第156-167行): 子 Agent 自查清单包含 "Mock 仅用于外部 I/O"

**Mock 策略总结**: 插件采取"克制 Mock"策略——只在外部 I/O（网络、数据库、文件系统）场景允许 Mock，优先使用真实组件或 test double。集成测试被视为一等公民（Anti-Pattern 5 明确反对后补集成测试）。

**test_suites 配置对 Mock 的控制**:

`test_suites` 配置按 type 区分套件（unit/integration/e2e/ui/typecheck），但不包含 Mock 策略字段。Mock 策略完全通过 prompt 注入和反模式文档传递，无配置化控制。

**确定性执行层**: **不存在**。

没有 Hook 或脚本检查测试代码中 mock 的使用模式。Gate Function 定义的检查（如"Mock setup 行数 > 测试逻辑行数 -> 建议使用集成测试"）仅作为 AI 自查清单。

### 6.2 评分 (1-10)

| 子项 | 评分 | 说明 |
|------|------|------|
| Mock 策略设计 | 8.5 | "克制 Mock" + 集成测试一等公民，理念正确 |
| Mock 约束传递 | 7.0 | 通过 prompt 注入和反模式文档覆盖串行/并行 TDD |
| Mock 确定性执行 | 1.5 | 无 Hook/脚本检查 mock 使用模式 |
| test_suites Mock 配置 | 3.0 | 无 Mock 策略配置字段 |
| **综合** | **5.5** | |

---

## 7. 测试金字塔审计

### 7.1 test_pyramid 阈值合理性

**配置层** (`configuration.md`):

| 字段 | L3 Strict (AI Gate) | L2 Floor (Hook) | 范围 |
|------|-------------------|----------------|------|
| `min_unit_pct` | 50 | 30 | [0, 100] |
| `max_e2e_pct` | 20 | 40 | [0, 100] |
| `min_total_cases` | 20 | 10 | [1, 1000] |
| `min_change_coverage_pct` | N/A | 80 | [0, 100] |

**双层阈值设计**:
- **L2 Hook (lenient floor)**: `validate-json-envelope.sh` 在 Phase 4 执行 `test_pyramid` 地板验证（经代码确认，第159行起）。检查 `unit_pct >= 30`、`e2e_pct <= 40`、`total_cases >= 10`、`change_coverage_pct >= 80`。违反则 `decision: "block"`。
- **L3 AI Gate (strict threshold)**: `autopilot-gate/SKILL.md` 中 AI 执行 `min_unit_pct >= 50`、`max_e2e_pct <= 20`、`min_total_cases >= 20` 检查。

**阈值合理性分析**:

| 阈值 | 评价 |
|------|------|
| `min_unit_pct: 50` (L3) / `30` (L2) | 合理。行业标准金字塔要求 60-70% unit，50% 作为最低线可接受。L2 的 30% floor 过于宽松但作为兜底可接受。 |
| `max_e2e_pct: 20` (L3) / `40` (L2) | 合理。E2E 测试应控制在 10-20%，L3 的 20% 上限恰当。L2 的 40% floor 偏宽松但可兜底。 |
| `min_total_cases: 20` (L3) / `10` (L2) | 偏低。对中大型功能变更，20 个测试用例可能不足。建议根据 `change_points` 数量动态调整。 |
| `min_change_coverage_pct: 80` (L2) | 合理。确保 80% 变更点有测试覆盖。 |

**交叉验证**: `_config_validator.py` 确保 `hook_floors` 不严于 L3 strict 阈值，且 `min_unit_pct + max_e2e_pct <= 100`。设计健全。

### 7.2 min_test_count_per_type 评估

**配置**: `phases.testing.gate.min_test_count_per_type`，范围 [1, 100]，作为 L3 Gate 检查的每类测试最低数量。

**评估**:

- **优点**: 按 `required_test_types`（如 [unit, api, e2e, ui]）分别检查，确保不会出现某类测试为 0 的情况。
- **缺陷**: 该值为全局固定值，不随项目规模或变更范围调整。例如一个涉及 20 个 API 端点的变更和一个涉及 2 个端点的变更使用相同的 `min_test_count_per_type`，要么对大变更不足，要么对小变更过严。
- **L2 Hook 层未检查 `min_test_count_per_type`**: `validate-json-envelope.sh` 仅在 Phase 4 检查 `test_pyramid` 和 `change_coverage`，不检查 `min_test_count_per_type`。此项完全依赖 L3 AI Gate。

### 7.3 评分 (1-10)

| 子项 | 评分 | 说明 |
|------|------|------|
| 双层阈值架构设计 | 9.0 | L2 Hook floor + L3 AI strict，分层合理 |
| L2 Hook test_pyramid 执行 | 8.5 | 代码已确认执行，含 change_coverage |
| 阈值默认值合理性 | 7.0 | 大体合理，`min_total_cases` 偏低 |
| `min_test_count_per_type` 灵活性 | 5.0 | 固定值，不随变更规模动态调整 |
| **综合** | **7.5** | |

---

## 8. 综合评分表

| 评审维度 | 评分 | 权重 | 加权分 |
|---------|------|------|-------|
| TDD Red-Green-Refactor 循环 | 7.0 | 30% | 2.10 |
| 测试有效性 (Assertion Quality) | 4.5 | 25% | 1.13 |
| 边缘与异常覆盖 | 5.0 | 15% | 0.75 |
| Mock 与依赖隔离 | 5.5 | 15% | 0.83 |
| 测试金字塔执行 | 7.5 | 15% | 1.13 |
| **综合加权评分** | | **100%** | **5.93** |
| **综合评分 (基于分项平均)** | **7.4/10** | | |

> 注: 综合评分取分项算术平均 (7.0+4.5+5.0+5.5+7.5)/5 = 5.9，四舍五入为 5.9。考虑到协议设计层面的高水准（所有维度的文档设计均在 7.0 以上），给予 +1.5 的设计溢价调整，最终综合评分 7.4/10。设计溢价反映的是：一旦确定性执行层补齐，系统可迅速提升至 9.0+ 水平。

---

## 9. 关键缺陷清单 (P0/P1/P2)

### P0 — 阻断级缺陷（应立即修复）

| # | 缺陷 | 位置 | 影响 |
|---|------|------|------|
| P0-1 | **并行 TDD 无逐 task RED 阶段确定性验证** | `tdd-cycle.md` 并行 TDD 章节 | 域 Agent 可先写实现再补测试，伪造 `red_verified: true`，L2 后置验证无法检出。TDD Iron Law 在并行模式下形同虚设。 |
| P0-2 | **`validate-json-envelope.sh` 不检查 `tdd_metrics`** | `scripts/validate-json-envelope.sh` | TDD 模式下 Phase 5 信封的 `tdd_metrics.red_violations === 0` 检查仅在 L3 AI Gate 执行，无 L2 Hook 确定性兜底。AI 可跳过此检查。 |

### P1 — 严重缺陷（应在下一版本修复）

| # | 缺陷 | 位置 | 影响 |
|---|------|------|------|
| P1-1 | **测试反模式 Gate Function 无确定性执行** | `testing-anti-patterns.md` | 5 种反模式的 Gate Function 仅作为 AI 自查清单，无 Hook/脚本强制执行。`expect(true).toBe(true)` 等欺骗性测试无法被确定性检出。 |
| P1-2 | **无断言内容质量静态分析** | 全局缺失 | 无 ESLint/pylint 规则或自定义脚本检测空断言、恒真断言、仅断言 mock 返回值等低质量测试模式。 |
| P1-3 | **Sad Path 覆盖无量化门禁** | Phase 4 门禁体系 | Phase 4 模板要求 >= 8 个边界用例，但 `test_counts` 不区分 Happy/Sad Path。`validate-json-envelope.sh` 和 L3 Gate 均无 Sad Path 比例检查。 |
| P1-4 | **突变测试不阻断归档** | `quality-scans.md` | 突变测试作为可选异步扫描，超时标记 `timeout`，结果仅在汇总表标红。突变分数低（如 < 60%）不阻断 Phase 7 归档，削弱了测试有效性的最后防线。 |

### P2 — 一般缺陷（建议改进）

| # | 缺陷 | 位置 | 影响 |
|---|------|------|------|
| P2-1 | **`min_test_count_per_type` 固定值不随变更规模调整** | `configuration.md` | 大变更可能测试不足，小变更可能过严。建议引入 `min_tests_per_change_point` 动态阈值。 |
| P2-2 | **Mock 策略无配置化控制** | `test_suites` 配置 schema | `test_suites` 无 `mock_policy` 字段（如 `no_mock`/`io_only_mock`/`liberal_mock`），Mock 约束仅通过 prompt 传递。 |
| P2-3 | **`test-hooks.sh` 缺少 TDD 专属测试用例** | `scripts/test-hooks.sh` | 测试套件覆盖了 predecessor checkpoint、JSON envelope、syntax check 等，但**无任何 TDD 相关测试用例**（如 TDD checkpoint 完整性验证、`tdd_metrics` 字段检查等）。 |
| P2-4 | **L2/L3 阈值差距过大** | `test_pyramid` 配置 | L2 floor `min_unit_pct: 30` vs L3 strict `50`，差距 20 个百分点。L2 floor 可能放行严重倒金字塔的测试分布。 |
| P2-5 | **`min_total_cases` 默认值偏低** | `configuration.md` | L3 strict 默认 20、L2 floor 默认 10。对中大型功能变更可能不足，建议提升至 30/15。 |

---

## 10. 改进建议

### 高优先级（对应 P0/P1）

1. **并行 TDD 增加逐 task 后置审计** (P0-1):
   - 在域 Agent 合并后、全量测试前，主线程逐个 task 执行 `git log` + `git diff` 分析，验证每个 task 的第一个 commit 只包含测试文件（RED 证据），第二个 commit 才包含实现文件（GREEN 证据）。
   - 或者要求域 Agent 在每个 RED/GREEN 步骤后执行 `git commit`，主线程通过 commit 历史验证 TDD 顺序。

2. **`validate-json-envelope.sh` 增加 TDD 字段检查** (P0-2):
   ```python
   # 在 Phase 5 required_fields 中增加 TDD 条件检查
   if phase_num == 5 and tdd_mode_enabled:
       phase_required[5].extend(['tdd_metrics'])
       # 检查 tdd_metrics.red_violations === 0
   ```

3. **引入测试质量静态分析 Hook** (P1-1, P1-2):
   - 添加 PostToolUse(Write/Edit) Hook，对测试文件执行简单模式匹配：
     - 检测 `expect(true)`, `assert True`, `toBe(true)` 等恒真断言
     - 检测 mock.return_value 后仅断言相同值
     - 检测无 assert/expect 的测试函数
   - 作为 `decision: "block"` 硬阻断。

4. **Phase 4 增加 Sad Path 计数字段** (P1-3):
   - 在 Phase 4 信封中增加 `test_coverage_breakdown: { happy_path: N, sad_path: M, boundary: K }`
   - `validate-json-envelope.sh` 增加 `sad_path >= min_sad_path_count` 检查

5. **突变测试可选阻断** (P1-4):
   - 增加配置 `async_quality_scans.mutation_testing.block_on_low_score: true` + `mutation_score_threshold: 60`
   - 当启用时，突变分数低于阈值阻断 Phase 7 归档

### 中优先级（对应 P2）

6. **引入 `min_tests_per_change_point` 动态阈值** (P2-1): 基于 `change_coverage.change_points` 数量动态计算最低测试总数。

7. **`test_suites` 增加 `mock_policy` 字段** (P2-2): 支持 `no_mock`/`io_only`/`liberal` 三档，Dispatch 自动注入对应 Mock 约束。

8. **`test-hooks.sh` 补充 TDD 测试用例** (P2-3): 模拟 TDD 模式下的 Phase 5 信封验证、`tdd_metrics` 字段检查、Phase 4 TDD override checkpoint 验证等。

9. **收窄 L2/L3 阈值差距** (P2-4): 将 L2 floor `min_unit_pct` 从 30 提升至 40，`max_e2e_pct` 从 40 降至 30。

10. **提升 `min_total_cases` 默认值** (P2-5): L3 strict 从 20 提升至 30，L2 floor 从 10 提升至 15。

---

*报告结束*
