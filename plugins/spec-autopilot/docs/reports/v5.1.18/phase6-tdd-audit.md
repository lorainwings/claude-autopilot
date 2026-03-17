# Phase 6 TDD 流程纯洁度与测试质量审计报告

> **审计版本**: v5.1.18
> **审计日期**: 2026-03-17
> **审计范围**: `plugins/spec-autopilot/` — TDD 流程 + Phase 6 测试报告阶段
> **审计员**: Agent 4（Phase 6 TDD 流程纯洁度与测试质量审计）

---

## 执行摘要

| 维度 | 评分 | 说明 |
|------|------|------|
| Red-Green-Refactor 循环验证 | 92/100 | 串行模式 L2 确定性保障优秀，并行模式存在 L1 自查信任缺口 |
| 断言质量检测机制 | 90/100 | 覆盖 JS/TS/Python/Java 四大语言族，但缺少 Go/Rust 等语言 |
| 边缘与异常覆盖 | 88/100 | sad_path 20% 地板 + 需求路由动态调节到位，但缺少运行时监控 |
| Mock 依赖隔离 | 85/100 | 反模式文档详尽，但缺少自动化 Mock 比例检测 |
| TDD Metrics 审计 | 91/100 | red_violations/green_retries/refactor_reverts 三维追踪完整 |
| Phase 6 测试报告 | 89/100 | 零跳过门禁 + suite_results 结构化输出良好 |
| **综合评分** | **89/100** | **工业级 TDD 框架，串行路径确定性优秀，并行路径需加固** |

---

## 1. Red-Green-Refactor 循环验证

### 1.1 RED 阶段 — "先写失败测试"的强制性

**证据链**:

| 层级 | 机制 | 文件路径 | 确定性 |
|------|------|----------|--------|
| L1 | `.tdd-stage` 文件写入 "red" | `scripts/unified-write-edit-check.sh` CHECK 1 (L148-181) | 确定性 |
| L2 | Hook 阻断实现文件写入 | 同上，`IS_TEST_FILE="no"` 时输出 `{"decision":"block",...}` | 确定性 |
| L2 | 主线程 Bash 验证 exit_code != 0 | `references/tdd-cycle.md` L86-94 | 确定性 |
| L2 | 语法错误 vs 断言失败区分 | `tdd-cycle.md` L89-91："语法/编译错误(非断言失败)→BLOCK" | 确定性 |

**测试覆盖**: `tests/test_tdd_isolation.sh` 提供了完整的 RED 阶段隔离测试：
- Case 52a: RED + 实现文件 → block（验证通过）
- Case 52b: RED + `*.test.ts` → pass（验证通过）
- Case 52c: RED + `__tests__/` 目录文件 → pass（验证通过）

**发现**: RED 阶段的 L2 Hook 实现了两层防线：
1. **文件类型隔离**: `unified-write-edit-check.sh` 通过 `.tdd-stage` 文件驱动，在 RED 阶段硬阻断所有非测试文件的 Write/Edit
2. **exit_code 验证**: 主线程在子 Agent 返回后，通过 `Bash("{test_command}")` 确定性验证测试必须失败

**风险 R-1（低）**: 测试文件识别依赖命名约定（`*.test.*`、`*.spec.*`、`*_test.*`、`*_spec.*`、`__tests__/`、`test/`、`tests/`），如果项目使用非标准命名（如 `*Check.java`），可能绕过隔离。

### 1.2 GREEN 阶段 — "禁止修改测试"的强制性

**证据链**:

| 层级 | 机制 | 确定性 |
|------|------|--------|
| L1 | `.tdd-stage` 写入 "green" | 确定性 |
| L2 | Hook 阻断测试文件写入 | `unified-write-edit-check.sh` L169-172: `IS_TEST_FILE="yes"` → block |
| L2 | 主线程 Bash 验证 exit_code == 0 | `tdd-cycle.md` L104-114 |
| L2 | 重试机制 | `max_retries_per_task` 配置控制，耗尽后 AskUserQuestion |

**测试覆盖**: `tests/test_tdd_isolation.sh`:
- Case 52d: GREEN + 测试文件 → block（验证通过）
- Case 52e: GREEN + 实现文件 → pass（验证通过）

**评估**: GREEN 阶段的"测试不可变"原则得到了 L2 Hook 层面的确定性保障。子 Agent 即使尝试修改测试文件，也会被 PostToolUse Hook 拦截。这是整个 TDD 框架中最关键的约束之一，实现质量优秀。

### 1.3 REFACTOR 阶段 — 回归保护的可靠性

**证据链**:

| 层级 | 机制 | 确定性 |
|------|------|--------|
| L2 | `.tdd-refactor-files` 文件跟踪 | `unified-write-edit-check.sh` L175-179: REFACTOR 阶段记录所有写入文件路径 |
| L2 | 测试验证 | 主线程 `Bash("{test_command}")` 验证重构未破坏测试 |
| L2 | 文件级回滚 | `scripts/tdd-refactor-rollback.sh`: 逐文件 `git checkout --`，非整体 `git checkout -- .` |

**tdd-refactor-rollback.sh 分析**:

回滚脚本实现了精细化文件级回滚（而非文档中描述的 `git checkout -- .` 全量回滚）：
1. 验证当前阶段确实是 REFACTOR（通过 `.tdd-stage` 文件）
2. 读取 `.tdd-refactor-files` 中记录的文件列表（去重）
3. 对已跟踪文件执行 `git checkout -- $file`，对新增文件执行 `rm`
4. 清理 `.tdd-refactor-files`

**测试覆盖**: `tests/test_tdd_rollback.sh`:
- Case 1a: 脚本可执行（验证通过）
- Case 1b: 无参数 → 错误 JSON（验证通过）
- Case 1c: 非 REFACTOR 阶段 → 拒绝（验证通过）
- Case 1d: 无 refactor-files → ok（验证通过）
- Case 1e: 2 个文件回滚，第 3 个文件未受影响（验证通过）

**额外发现**: `tests/test_unified_write_edit.sh` Case 53l 验证了 REFACTOR 阶段的文件跟踪机制正常工作。

**风险 R-2（中）**: REFACTOR 阶段不区分测试文件和实现文件（`unified-write-edit-check.sh` L174-179: "Track files written during REFACTOR for targeted rollback"），理论上允许修改测试文件。虽然主线程在 REFACTOR 后验证测试仍通过，但如果子 Agent 同时修改了测试和实现（使得修改后的测试仍然通过），就可能违反"测试不可变"原则。`tdd-cycle.md` L119 明确写"禁止修改测试文件"，但 Hook 层面 REFACTOR 阶段放行了所有写入。

### 1.4 并行模式 TDD 的 L2 缺口

**设计约束（已在文档中明确声明）**:

`tdd-cycle.md` L206-219 明确指出：
> "并行模式下域 Agent 内部的 RED/GREEN 验证为 AI 自查（L1 层），缺少串行模式的主线程 Bash() L2 确定性保障。"

**补偿机制**:
1. L2 后置验证: 合并后执行 `full_test_command`，若失败则阻断
2. L3 TDD 完整性审计: `autopilot-gate` Phase 5→6 门禁扫描所有 task checkpoint 的 `tdd_cycle` 字段

**风险 R-3（中高）**: 并行模式下域 Agent 的 `tdd_cycles` 报告为自报数据，缺少主线程级别的独立验证。域 Agent 理论上可以虚报 `red_verified: true`。后置全量测试仅验证最终结果，无法追溯 RED 阶段测试是否真正失败过。

---

## 2. 断言质量检测机制评审

### 2.1 恒真断言拦截

**实现**: `scripts/unified-write-edit-check.sh` CHECK 3 (L206-246)

覆盖的恒真断言模式：

| 语言 | 检测模式 | 正则表达式 |
|------|---------|-----------|
| JavaScript/TypeScript | `expect(true).toBe(true)`, `expect(false).toBeFalsy()` | `expect\((true\|false\|1\|0\|"[^"]*"\|'[^']*')\)\.(toBe\|toEqual\|toStrictEqual)\(\1\)` |
| JavaScript/TypeScript | `expect(true).toBeTruthy()` | `expect\(true\)\.toBeTruthy\(\)\|expect\(false\)\.toBeFalsy\(\)` |
| Python | `assert True`, `self.assertTrue(True)` | `assert\s+True\|assert\s+not\s+False\|self\.assert(True\|Equal)...` |
| Java/Kotlin | `assertTrue(true)`, `assertEquals(true, true)` | `(assertEquals\|assertSame)\s*\(...\)\|assertTrue\s*\(\s*true\s*\)` |
| 通用 | `true == true`, `1 == 1` | `(assert\|expect\|check).*\b(true\s*==\s*true\|...)` |

**测试覆盖**: `tests/test_unified_write_edit.sh`:
- Case 53f: `expect(true).toBe(true)` → block（验证通过）
- Case 53g: Python `assert True` → block（验证通过）
- Case 53h: 合法断言 `expect(add(1,2)).toBe(3)` → pass（验证通过）

**发现 F-1**: 恒真断言检测仅在文件级别触发（PostToolUse Write/Edit），不对已存在的测试文件进行回溯扫描。如果测试文件在 autopilot 之外创建，或在启动前已包含恒真断言，则不会被拦截。

**发现 F-2（积极）**: 非源码文件（`.json`、`.yaml`、`.csv` 等）被正确跳过（Case 53i-53k），避免误报。

**风险 R-4（低）**: 缺少以下语言的恒真断言检测：
- Go: `assert.True(t, true)`
- Rust: `assert!(true)`
- C#: `Assert.IsTrue(true)`
- Ruby: `assert_equal true, true`

### 2.2 禁止模式（TODO/FIXME/HACK）

**实现**: `unified-write-edit-check.sh` CHECK 2 (L187-201)

**行为**: 在 Delivery Phase（Phase 4+）检测并阻断源码文件中的 `TODO:`、`FIXME:`、`HACK:` 占位符。`.md` 文件在 Delivery Phase 中也被检测，但在 Pre-delivery Phase 中豁免。

**测试覆盖**:
- Case 53a-53c: 源码文件中 TODO/FIXME/HACK → block
- Case 53d: Pre-delivery `.md` 中 TODO → pass
- Case 53m: Delivery phase `.md` 中 TODO → block
- Case 53n: Phase 1 only `.md` 中 TODO → pass

---

## 3. 边缘与异常覆盖评估

### 3.1 Sad Path 比例要求

**规则定义**: `CLAUDE.md` L32:
> "sad_path_counts 每类型 >= test_counts 同类型 20% (v4.2)"

**L2 实现**: `_post_task_validator.py` L296-323:
- 遍历 `sad_path_counts` 中每个测试类型
- 计算 `sad_ratio = (sad_count / total_for_type) * 100`
- `sad_ratio < FLOOR_MIN_SAD_PATH_RATIO` → block
- 空的 `sad_path_counts` + 非空 `test_counts` → block

**需求路由动态调节** (`CLAUDE.md` L36-41):
- Bugfix: `sad_path >= 40%`（双倍标准）
- Refactor: `change_coverage = 100%`
- Chore: 放宽至 `change_coverage >= 60%`

**实现验证**: `_post_task_validator.py` L228-233 通过 Phase 1 checkpoint 中的 `routing_overrides` 动态调整阈值。

**评估**: Sad path 比例在 L2 层面强制执行，且支持需求类型自适应。这是一个成熟的设计。

**风险 R-5（低）**: Sad path 的判定基于子 Agent 自报的 `sad_path_counts`，没有静态分析层面的独立验证（即无法确认 Agent 声称的 sad path 测试是否真正测试了异常路径）。

### 3.2 Phase 4 test_counts 门禁与 Phase 6 的联动

**Phase 4 门禁** (`_post_task_validator.py` L192-324):
- `test_pyramid` 验证: `unit_pct >= 30%`, `e2e_pct <= 40%`, `total >= 10`
- `change_coverage` 验证: `coverage_pct >= 80%`
- `test_traceability` 验证: `coverage_pct >= 80%`（L2 blocking）
- `sad_path_counts` 验证: 每类型 >= 20%
- Phase 4 不接受 `warning` 状态

**Phase 6 门禁** (`_post_task_validator.py` L104-108):
- 必需字段: `pass_rate`, `report_path`, `report_format`
- 推荐字段: `suite_results`, `anomaly_alerts`（非阻断）
- Phase 6 模板要求零跳过验证

**Phase 5→6 特殊门禁** (`autopilot-gate` SKILL.md):
- `test-results.json` 存在
- `zero_skip_check.passed === true`
- TDD 模式: `tdd_metrics.red_violations === 0`

**联动评估**: Phase 4 的 test_counts/sad_path_counts 在 Phase 4 门禁验证后写入 checkpoint，Phase 6 通过 `test-results.json` 中的实际运行结果进行独立验证。两个阶段的验证相互独立但互补：Phase 4 验证设计质量，Phase 6 验证执行质量。

---

## 4. Mock 依赖隔离评审

### 4.1 反模式文档

**文件**: `references/testing-anti-patterns.md`

定义了 5 种核心反模式及其 Gate Function 检查表：

| # | 反模式 | Gate Function |
|---|--------|--------------|
| 1 | Testing Mock Behavior | 检查 mock.return_value 后是否仅断言了相同返回值 |
| 2 | Test-Only Methods in Production | 搜索 `_test`/`forTesting`/`@VisibleForTesting` |
| 3 | Mocking Without Understanding | Mock setup 行数 > 测试逻辑行数 → 建议集成测试 |
| 4 | Incomplete Mocks | 比对 mock 对象 key 与真实 API schema |
| 5 | Integration Tests as Afterthought | 检查 integration 占比 > 0 |

**TDD 子 Agent 自查清单** (7 项):
1. 测试验证真实行为，不是 mock 行为
2. 生产代码无测试专用方法
3. Mock 仅用于外部 I/O
4. Mock 对象镜像完整 API
5. 测试独立运行
6. 清晰的 Arrange-Act-Assert 结构
7. 每个测试只验证一件事

**注入时机**: TDD RED 串行 → 完整指南; TDD RED 并行 → 精简版 Gate Function

**风险 R-6（中）**: Gate Function 检查表以文档形式存在，作为 AI 自查的指导而非确定性 Hook 验证。以下检测项目目前没有自动化实现：
- Mock setup 行数 vs 测试逻辑行数的比对
- `_test`/`forTesting` 方法在生产代码中的扫描
- Mock 对象 key 与真实 API schema 的比对

这些检测依赖子 Agent 的 L1 自查，缺少 L2 层面的确定性保障。

### 4.2 TDD 模板中的 Mock 规范

`tdd-cycle.md` 并行模式 prompt 注入中明确声明（L179-185）：

```
## Anti-Patterns to AVOID
1. NEVER test mock behavior — test real code
2. NEVER add test-only methods to production classes
3. NEVER mock without understanding dependencies
4. If mock setup > test logic → use integration test instead
5. Integration tests are first-class, not afterthoughts
```

**红旗标记 #5**: "测试只验证 mock 行为" → 标记要求测试真实组件
**红旗标记 #10**: "Mock setup > test logic" → 用集成测试

---

## 5. TDD Metrics 审计

### 5.1 追踪指标

**并行模式信封** (`tdd-cycle.md` L190-204):

```json
{
  "tdd_metrics": {
    "total_cycles": 5,
    "red_violations": 0,
    "green_retries": 1,
    "refactor_reverts": 0
  },
  "tdd_cycles": [
    { "task": "task-1", "red_verified": true, "green_verified": true, "refactor_verified": true }
  ]
}
```

**串行模式 Checkpoint** (`tdd-cycle.md` L131-133):
```
tdd_cycle: { red: {...}, green: {...}, refactor: {...} }
```

### 5.2 post-task-validator 中的 TDD 指标验证

**文件**: `_post_task_validator.py` L116-166

**验证流程**:

1. **TDD 必需字段检测** (L116-133):
   - 检查锁文件或配置中 `tdd_mode` 是否为 true
   - 若 true，将 `tdd_metrics` 加入 Phase 5 必需字段列表
   - 缺少 `tdd_metrics` → block

2. **red_violations 零容忍** (L155-160):
   ```python
   red_violations = tdd_metrics.get("red_violations", -1)
   if red_violations != 0:
       output_block(...)
   ```
   任何 RED 违规 → 阻断。默认值为 -1（缺失时也阻断）。

3. **cycles_completed 最低要求** (L161-166):
   ```python
   cycles_completed = tdd_metrics.get("cycles_completed", 0)
   if cycles_completed < 1:
       output_block(...)
   ```
   至少完成 1 个完整 RED-GREEN-REFACTOR 循环。

### 5.3 L3 Gate 层 TDD 审计

**文件**: `autopilot-gate` SKILL.md "TDD 完整性审计" 部分

1. 扫描所有 `phase5-tasks/task-N.json`
2. 验证每个 task 含 `tdd_cycle` 字段
3. 验证 `red.verified === true` 和 `green.verified === true`
4. 记录 `refactor_reverts` 总数
5. 汇总为 `tdd_audit` JSON，`audit_passed === false` → 阻断 Phase 6

**评估**: TDD Metrics 的三层验证链（L1 子 Agent 自报 → L2 post-task-validator 字段检查 → L3 Gate TDD 审计）构成了完整的审计闭环。

**风险 R-7（低）**: `green_retries` 和 `refactor_reverts` 指标仅记录和审计，不阻断。高 green_retries 可能暗示测试设计不佳，高 refactor_reverts 可能暗示重构过于激进，但当前没有阈值告警机制。

---

## 6. Phase 6 测试报告阶段评审

### 6.1 零跳过验证

**模板**: `templates/phase6-reporting.md` 定义了零跳过验证为第一步硬阻断：
- `test-results.json` 不存在 → failed
- 任何 suite `skipped > 0` → failed
- `known_issues` 中用户批准的已知问题 → 不算跳过

**L2 验证**: `_post_task_validator.py` L144-150:
```python
if phase_num == 5 and envelope.get("status") == "ok":
    zsc = envelope.get("zero_skip_check", {})
    if isinstance(zsc, dict) and zsc.get("passed") is not True:
        output_block(...)
```

**测试覆盖**: `test_post_task_validator.sh` Case 33h: `zero_skip_check.passed=false` → block

### 6.2 Phase 6 信封验证

**必需字段**: `pass_rate`, `report_path`, `report_format`

**测试覆盖**:
- `test_phase6_allure.sh` Case 17a-17c: Allure/Custom 格式、缺失 report_format → block
- `test_phase6_suite_results.sh` Case 28a-28b: suite_results 为推荐字段，缺失不阻断
- `test_phase6_independent.sh` Case 35a: Phase 6 不依赖 Phase 6.5 字段

### 6.3 Allure 报告集成

**支持框架**:
- pytest: `--alluredir=allure-results/{suite_name}`
- Playwright: `ALLURE_RESULTS_DIR=... --reporter=list,allure-playwright`
- Gradle/JUnit: 复制 XML 到 `allure-results/`
- Vitest: `--reporter=allure --outputDir=...`

**降级**: Allure 不可用时自动降级为 custom 格式。

### 6.4 Phase 6 与 Phase 4 的数据一致性

Phase 6 模板要求对比 `test-results.json` 与 Phase 4 的 `test_counts`：
- 重新运行失败的 suite 或未包含的 suite
- 超过 30 分钟未运行的 suite

**评估**: Phase 6 的报告生成流程设计合理，零跳过门禁在 L2 和 L3 两层验证。但 Phase 6 模板本身是 AI 指令（L3 层），实际测试执行依赖子 Agent 遵从模板指令。

---

## 7. 风险发现列表

| ID | 严重度 | 风险描述 | 影响 |
|----|--------|---------|------|
| R-1 | 低 | 测试文件识别依赖命名约定，非标准命名可能绕过 TDD 隔离 | RED/GREEN 阶段文件类型隔离被绕过 |
| R-2 | 中 | REFACTOR 阶段 Hook 不区分测试/实现文件，允许修改测试 | 违反"测试不可变"原则的可能性 |
| R-3 | 中高 | 并行模式 TDD 的 tdd_cycles 为域 Agent 自报，缺少独立 L2 验证 | 域 Agent 可虚报 red_verified |
| R-4 | 低 | 恒真断言检测缺少 Go/Rust/C#/Ruby 语言支持 | 特定语言项目中恒真断言无法拦截 |
| R-5 | 低 | sad_path_counts 为子 Agent 自报，无静态分析验证 | sad path 测试可能名不副实 |
| R-6 | 中 | Mock 反模式 Gate Function 仅为文档指导，无自动化检测 | Mock 过度风险依赖 AI 自律 |
| R-7 | 低 | green_retries/refactor_reverts 无阈值告警 | 异常指标无早期预警 |
| R-8 | 低 | Phase 6 零跳过验证在 Phase 5 checkpoint 的 `zero_skip_check` 字段执行，Phase 6 模板中的零跳过验证为 L3 AI 执行 | 存在两层验证但语义略有重叠 |

---

## 8. 改进建议

### 8.1 高优先级

**B-1: REFACTOR 阶段测试文件保护**

在 `unified-write-edit-check.sh` CHECK 1 REFACTOR 分支中，对测试文件修改增加 warn 或 soft-block：

```bash
refactor)
  # 记录所有文件用于回滚
  echo "$FILE_PATH" >> "$REFACTOR_FILES"
  # 新增：测试文件修改告警
  if [ "$IS_TEST_FILE" = "yes" ]; then
    echo '{"decision":"warn","reason":"REFACTOR stage: modifying test file '"$BASENAME"'. TDD protocol prohibits test modifications during REFACTOR."}'
  fi
  ;;
```

**B-2: 并行 TDD 后置验证加固**

在并行模式合并后，除全量测试外，增加 per-task 的 RED 验证回溯：
1. 对每个域 Agent 报告的 `tdd_cycles`，随机抽取 N 个 task
2. 还原到 RED 阶段的代码状态（checkout test file only），重新运行测试命令
3. 验证测试确实失败（RED 验证回溯）

### 8.2 中优先级

**B-3: Mock 比例自动化检测**

在 `unified-write-edit-check.sh` 中新增 CHECK 5，对测试文件执行 Mock 行数比例检测：

```bash
# CHECK 5: Mock setup ratio (test files only)
MOCK_LINES=$(grep -cE '(mock|Mock|jest\.fn|sinon\.|stub|spy|patch)' "$FILE_PATH" 2>/dev/null || echo 0)
TOTAL_LINES=$(wc -l < "$FILE_PATH" 2>/dev/null || echo 1)
MOCK_RATIO=$((MOCK_LINES * 100 / TOTAL_LINES))
if [ "$MOCK_RATIO" -gt 60 ]; then
  # warn, not block
fi
```

**B-4: green_retries/refactor_reverts 阈值告警**

在 `_post_task_validator.py` 中为 `tdd_metrics` 增加软告警：
- `green_retries > total_cycles * 2` → stderr warn
- `refactor_reverts > total_cycles * 0.5` → stderr warn

**B-5: 扩展恒真断言检测语言覆盖**

为 Go、Rust、C#、Ruby 添加恒真断言检测正则。

### 8.3 低优先级

**B-6: 测试文件识别增强**

支持通过 `autopilot.config.yaml` 配置额外的测试文件模式：

```yaml
test_file_patterns:
  - "*Check.java"
  - "*IT.java"
  - "test_*.rb"
```

**B-7: Sad Path 静态分析**

通过对测试文件内容的简单模式匹配（如 `expect.*throw`、`assert.*Error`、`raises`、`reject`），独立验证 sad_path_counts 的合理性。

---

## 附录: 审计文件索引

| 文件 | 审计作用 |
|------|---------|
| `skills/autopilot/references/tdd-cycle.md` | TDD 完整协议定义（核心文档） |
| `CLAUDE.md` | Iron Law + 代码质量硬约束 |
| `scripts/unified-write-edit-check.sh` | L2 Hook: TDD 隔离 + 禁止模式 + 断言质量 |
| `scripts/write-edit-constraint-check.sh` | v5.1 前的独立实现（已废弃，仅参考） |
| `scripts/tdd-refactor-rollback.sh` | REFACTOR 回滚脚本 |
| `scripts/_post_task_validator.py` | L2 PostToolUse(Task) 统一验证器 |
| `scripts/collect-metrics.sh` | Phase 7 指标收集 |
| `skills/autopilot/templates/phase6-reporting.md` | Phase 6 内置模板 |
| `skills/autopilot/templates/phase4-testing.md` | Phase 4 内置模板 |
| `skills/autopilot/references/testing-anti-patterns.md` | Mock 反模式指南 |
| `skills/autopilot/references/phase5-implementation.md` | Phase 5 详细流程 |
| `skills/autopilot-gate/SKILL.md` | 门禁验证协议 |
| `tests/test_tdd_isolation.sh` | TDD RED/GREEN/REFACTOR 隔离测试 |
| `tests/test_tdd_rollback.sh` | REFACTOR 回滚测试 |
| `tests/test_unified_write_edit.sh` | 统一 Hook 端到端测试 |
| `tests/test_post_task_validator.sh` | 统一验证器测试 |
| `tests/test_phase6_allure.sh` | Phase 6 Allure 字段测试 |
| `tests/test_phase6_suite_results.sh` | Phase 6 suite_results 测试 |
| `tests/test_phase6_independent.sh` | Phase 6 独立性测试 |
| `tests/test_phase65_bypass.sh` | Phase 6.5 跳过测试 |
| `tests/test_anti_rationalization.sh` | 反合理化检测测试 |
| `tests/test_pyramid_threshold.sh` | 测试金字塔阈值测试 |
| `tests/test_change_coverage.sh` | 变更覆盖率测试 |
