# TDD Cycle Protocol — RED-GREEN-REFACTOR 确定性循环

> 本文档定义 autopilot Phase 5 TDD 模式的完整协议。
> 仅当 `config.phases.implementation.tdd_mode: true` **且** 执行模式为 `full` 时启用。
> 技术参考: Superpowers TDD skill + verification-before-completion + testing-anti-patterns。

---

## The Iron Law

**NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST.**

违反即删除：
- 先写了实现代码？ → **删除实现**，从测试重新开始
- 不保留为"参考"，不"改编"，不查看
- **Delete means delete**

---

## TDD 门禁结构

每个 TDD 周期 **必须** 记录以下字段，作为 Phase 5→6 gate 的真实门禁依据：

| 字段 | 说明 | 何时写入 | 门禁作用 |
|------|------|----------|----------|
| `test_intent` | 测试意图描述（被测行为/边界/错误路径） | RED 阶段派发前 | 必须非空，否则阻断 RED 派发 |
| `failing_signal` | RED 阶段测试失败的具体输出（exit_code + 断言消息） | RED 阶段 L2 验证后 | 必须存在且为断言失败（非编译错误） |
| `red.verified` | RED 验证通过标记 | RED L2 验证通过 | Phase 5→6 门禁检查 |
| `green.verified` | GREEN 验证通过标记 | GREEN L2 验证通过 | Phase 5→6 门禁检查 |
| `refactor.verified` | REFACTOR 验证通过标记 | REFACTOR L2 验证通过 | 审计记录（允许 reverted） |

### test_intent 规范

test_intent 必须明确回答：
1. **被测对象**: 哪个函数/模块/接口
2. **预期行为**: 输入什么，期望什么输出或副作用
3. **测试类别**: happy-path / sad-path / boundary / regression

示例（合格）:
```
"test_intent": "UserService.login() 在密码错误时返回 401 并记录审计日志 (sad-path)"
```

示例（不合格 → 阻断）:
```
"test_intent": "测试登录功能"  // 过于模糊，缺少具体行为描述
"test_intent": ""              // 空值，直接阻断
```

### failing_signal 规范

failing_signal 必须包含：
1. `exit_code`: 非零退出码
2. `assertion_message`: 断言失败的具体消息（非编译错误、非运行时崩溃）
3. `test_file`: 产生失败的测试文件路径

示例:
```json
{
  "exit_code": 1,
  "assertion_message": "AssertionError: expected 401 but got undefined",
  "test_file": "tests/test_login.py"
}
```

---

## 反合理化清单（13 种借口）

| # | 借口 | 现实 |
|---|------|------|
| 1 | "太简单不用测" | 简单代码也会坏。测试只需 30 秒。 |
| 2 | "我后面补测试" | 后补的测试立即通过，证明不了任何东西。 |
| 3 | "手动测过了" | 手动测试 ≠ 系统化。无记录，不可重放。 |
| 4 | "删除 X 小时的工作太浪费" | 沉没成本谬误。保留未验证代码才是技术债。 |
| 5 | "TDD 太教条了" | TDD 就是务实。务实的捷径 = 生产环境调试 = 更慢。 |
| 6 | "只是个小改动" | 小改动不代表不需要测试。小改动也能引入 bug。 |
| 7 | "测试框架不支持" | 找到方法测试，或者重构让代码可测试。 |
| 8 | "这是第三方代码" | 写集成测试验证第三方行为。 |
| 9 | "截止日期快到了" | 不写测试 → 生产 bug → 花更多时间修复。 |
| 10 | "这段代码要被重构" | 重构需要测试保护。先写测试。 |
| 11 | "我对这段代码很熟悉" | 经验不能替代自动化验证。 |
| 12 | "团队没人这样做" | 从你开始。展示价值。 |
| 13 | "架构还没确定" | TDD 帮你发现更好的架构。 |

## 红旗标记（13 种违规信号）

| # | 信号 | 处理 |
|---|------|------|
| 1 | 先写代码再补测试 | → 删除代码，重新开始 |
| 2 | 测试立即通过 | → 测试有问题，修改测试 |
| 3 | 无法解释测试为何失败 | → 回到 RED |
| 4 | "只这一次跳过" | → 没有例外 |
| 5 | 测试只验证 mock 行为 | → 测试真实组件 |
| 6 | 测试文件中有实现逻辑 | → 分离到生产代码 |
| 7 | 单个测试验证多件事 | → 拆分为多个测试 |
| 8 | REFACTOR 改变了行为 | → 回滚，重新重构 |
| 9 | GREEN 阶段修改了测试 | → 禁止，修复实现 |
| 10 | Mock setup > test logic | → 用集成测试 |
| 11 | 测试依赖执行顺序 | → 让测试独立 |
| 12 | 注释掉失败的测试 | → 修复或删除 |
| 13 | 实现超出测试范围 | → YAGNI，删除多余代码 |

---

## 串行 TDD (`parallel.enabled: false` + `tdd_mode: true`)

### TDD 阶段状态文件（L2 确定性门禁）

主线程在每个 TDD 步骤派发前，**必须**写入 `.tdd-stage` 状态文件，供 `unified-write-edit-check.sh` L2 Hook 确定性拦截：

```
文件位置: openspec/changes/<name>/context/.tdd-stage
内容: "red" | "green" | "refactor"
```

| TDD 步骤 | 写入时机 | Hook 行为 |
|-----------|---------|-----------|
| RED | 派发 RED Task 前 | 硬阻断实现文件写入（仅允许测试文件） |
| GREEN | 派发 GREEN Task 前 | 硬阻断测试文件修改（仅允许实现文件） |
| REFACTOR | 派发 REFACTOR Task 前 | 放行所有写入（行为保持由 L2 Bash 验证） |
| 清理 | task 全部完成后 | 删除 `.tdd-stage` 文件 |

```
for each task in task_list:

  ┌─── RED ──────────────────────────────────────────────┐
  │ Step 0: 记录 test_intent (门禁前置条件)               │
  │   - 主线程写入 test_intent 到当前 task context          │
  │   - test_intent 为空 → BLOCK: 禁止派发 RED Task        │
  │                                                       │
  │ Step 0.5: 发射 RED 开始进度事件                         │
  │   Bash('bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/   │
  │     emit-task-progress.sh "task-{N}-{slug}"           │
  │     running {N} {total} {mode} "red"')                │
  │                                                       │
  │ Step 1: Task(prompt: "TDD RED — 写失败测试")           │
  │   - 子 Agent 仅写测试文件，禁止写实现代码              │
  │   - prompt 注入 Iron Law + 反合理化 + 反模式指南       │
  │   - prompt 注入 test_intent（被测行为描述）            │
  │   - 返回: { test_file, test_command }                 │
  │                                                       │
  │ Step 2: 主线程确定性验证 (L2) — 带输出捕获              │
  │   result = Bash("{test_command} 2>&1")                 │
  │   test_output = result.stdout                          │
  │   test_tail = test_output 最后 30 行                    │
  │                                                       │
  │   IF exit_code == 0:                                  │
  │     → BLOCK: "TDD RED 违规: 测试在无实现的情况下通过。   │
  │       测试必须验证尚不存在的新行为。"                    │
  │   IF 失败原因是语法/编译错误(非断言失败):               │
  │     → BLOCK: "测试有语法错误，不是正确的失败断言。"      │
  │   IF exit_code != 0 AND 断言失败:                      │
  │     → PASS: 记录 tdd_cycle.red = { verified: true }   │
  │     → 记录 failing_signal = {                          │
  │         exit_code, assertion_message, test_file        │
  │       }                                                │
  │                                                       │
  │   ── RED 阶段评估摘要（主线程输出） ──                   │
  │   输出结构化评估结果:                                   │
  │     [TDD-EVAL] RED task-{N}:                           │
  │       状态: {PASS|BLOCK}                                │
  │       退出码: {exit_code}                               │
  │       断言消息: {assertion_message}                      │
  │       测试文件: {test_file}                              │
  │       测试输出 (尾部 5 行):                              │
  │         {test_tail 最后 5 行，缩进显示}                  │
  │     记录: tdd_cycle.red.eval_summary = {                │
  │       exit_code, assertion_message,                    │
  │       output_tail: "最后 5 行测试输出"                   │
  │     }                                                  │
  │                                                       │
  │ Step 2.5: 发射 RED 完成进度事件                         │
  │   Bash('bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/   │
  │     emit-task-progress.sh "task-{N}-{slug}"           │
  │     passed {N} {total} {mode} "red"')                 │
  │   失败时 status 改为 "failed"                           │
  └───────────────────────────────────────────────────────┘

  ┌─── GREEN ────────────────────────────────────────────┐
  │ Step 2.6: 发射 GREEN 开始进度事件                       │
  │   Bash('bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/   │
  │     emit-task-progress.sh "task-{N}-{slug}"           │
  │     running {N} {total} {mode} "green"')              │
  │                                                       │
  │ Step 3: Task(prompt: "TDD GREEN — 写最小实现")         │
  │   - 子 Agent 写最小代码让测试通过                      │
  │   - Iron Law: 禁止过度设计（YAGNI）                    │
  │   - prompt 注入测试文件路径 + "fix implementation,     │
  │     never modify test"                                │
  │   - 返回: { impl_files, summary }                     │
  │                                                       │
  │ Step 4: 主线程确定性验证 (L2) — 带输出捕获              │
  │   result = Bash("{test_command} 2>&1")                 │
  │   test_output = result.stdout                          │
  │   test_tail = test_output 最后 30 行                    │
  │                                                       │
  │   IF exit_code != 0:                                  │
  │     → 重试 (max_retries_per_task from config)         │
  │     → 耗尽重试 → AskUserQuestion                      │
  │   IF exit_code == 0:                                  │
  │     → PASS: 记录 tdd_cycle.green = { verified: true } │
  │   验证其他测试未被破坏:                                │
  │   full_result = Bash("{full_test_command} 2>&1")       │
  │   IF 其他测试失败 → 修复实现，不修改测试               │
  │                                                       │
  │   ── GREEN 阶段评估摘要（主线程输出） ──                 │
  │   从 test_output 中提取测试统计:                        │
  │     pass_count = 正则匹配测试框架输出中的通过数          │
  │     fail_count = 正则匹配测试框架输出中的失败数          │
  │     total_count = pass_count + fail_count               │
  │   输出结构化评估结果:                                   │
  │     [TDD-EVAL] GREEN task-{N}:                         │
  │       状态: {PASS|FAIL|RETRY}                           │
  │       退出码: {exit_code}                               │
  │       测试统计: {pass_count}/{total_count} 通过          │
  │       全量测试: {full_test_pass ? "通过" : "失败"}       │
  │       测试输出 (尾部 5 行):                              │
  │         {test_tail 最后 5 行，缩进显示}                  │
  │     记录: tdd_cycle.green.eval_summary = {              │
  │       exit_code, pass_count, total_count,              │
  │       full_test_passed: bool,                          │
  │       output_tail: "最后 5 行测试输出"                   │
  │     }                                                  │
  │                                                       │
  │ Step 4.5: 发射 GREEN 完成进度事件                       │
  │   Bash('bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/   │
  │     emit-task-progress.sh "task-{N}-{slug}"           │
  │     passed {N} {total} {mode} "green"')               │
  │   失败时 status 改为 "failed"                           │
  └───────────────────────────────────────────────────────┘

  ┌─── REFACTOR (当 tdd_refactor: true) ─────────────────┐
  │ Step 4.6: 发射 REFACTOR 开始进度事件                    │
  │   Bash('bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/   │
  │     emit-task-progress.sh "task-{N}-{slug}"           │
  │     running {N} {total} {mode} "refactor"')           │
  │                                                       │
  │ Step 5: Task(prompt: "TDD REFACTOR — 清理代码")        │
  │   - 删除重复、改善命名、提取辅助函数                   │
  │   - 禁止改变行为、禁止修改测试文件                     │
  │                                                       │
  │ Step 6: 主线程确定性验证 (L2) — 带输出捕获              │
  │   result = Bash("{test_command} 2>&1")                 │
  │   test_output = result.stdout                          │
  │   test_tail = test_output 最后 30 行                    │
  │                                                       │
  │   IF exit_code != 0:                                  │
  │     → 强制回滚: Bash("git checkout -- .")        │
  │       (全文件回滚，确保代码绝对不被污染)                │
  │     → 记录 tdd_cycle.refactor = { reverted: true }    │
  │   IF exit_code == 0:                                  │
  │     → PASS: 记录 tdd_cycle.refactor = {verified: true}│
  │                                                       │
  │   ── REFACTOR 阶段评估摘要（主线程输出） ──              │
  │   从 test_output 中提取测试统计:                        │
  │     pass_count = 正则匹配通过数                         │
  │     与 GREEN 阶段 pass_count 对比                       │
  │   输出结构化评估结果:                                   │
  │     [TDD-EVAL] REFACTOR task-{N}:                      │
  │       状态: {PASS|REVERTED}                             │
  │       退出码: {exit_code}                               │
  │       测试统计: {pass_count}/{total_count} 通过          │
  │       与 GREEN 对比: {pass_count 不变 ? "一致" : "变化"}│
  │       测试输出 (尾部 5 行):                              │
  │         {test_tail 最后 5 行，缩进显示}                  │
  │     记录: tdd_cycle.refactor.eval_summary = {           │
  │       exit_code, pass_count, total_count,              │
  │       green_pass_count_match: bool,                    │
  │       output_tail: "最后 5 行测试输出"                   │
  │     }                                                  │
  │                                                       │
  │ Step 6.5: 发射 REFACTOR 完成进度事件                    │
  │   Bash('bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/   │
  │     emit-task-progress.sh "task-{N}-{slug}"           │
  │     passed {N} {total} {mode} "refactor"')            │
  │   回滚时 status 改为 "failed"                           │
  └───────────────────────────────────────────────────────┘

  Checkpoint: phase5-tasks/task-N.json
    包含: tdd_cycle: {
      red: { verified, eval_summary: { exit_code, assertion_message, output_tail } },
      green: { verified, eval_summary: { exit_code, pass_count, total_count, full_test_passed, output_tail } },
      refactor: { verified|reverted, eval_summary: { exit_code, pass_count, green_pass_count_match, output_tail } }
    }
```

### 测试命令解析

```
tdd_test_command 非空 → 使用 tdd_test_command
tdd_test_command 为空 → 从 test_suites 中提取：
  - task 内测试命令 = 子 Agent RED 返回的 test_command
  - full_test_command = 所有 test_suites 的 command 串联
```

### TDD 测试命令 Allure 增强

> **条件**: 当 `config.phases.reporting.format === "allure"` 时启用。
> **设计意图**: TDD 各阶段的测试执行同样产出 Allure 结果，使 Phase 6 的 Allure 报告包含完整的 RED→GREEN 变迁记录，而非仅有 Phase 6 重跑的快照。

```
ALLURE_RESULTS_DIR="openspec/changes/{change_name}/reports/allure-results/tdd"
mkdir -p "$ALLURE_RESULTS_DIR"

# 将 allure_args 注入到 TDD 测试命令中
tdd_allure_command 构造规则:
  1. tdd_test_command 非空且已包含 --alluredir → 直接使用
  2. tdd_test_command 非空但不含 allure 参数 → 追加 allure_args
  3. test_suites[].allure_args 非空 → 使用 suite 级 allure_args
  4. 以上均无 → 按框架默认追加:
     - pytest:      追加 --alluredir=$ALLURE_RESULTS_DIR
     - playwright:  设置环境变量 ALLURE_RESULTS_DIR=$ALLURE_RESULTS_DIR
     - jest:        追加 --reporters=allure-jest --testEnvironment=allure-jest/node
     - vitest:      追加 --reporter=allure-vitest
     - 其他:        跳过 Allure 增强，仅使用原始命令

# RED 阶段: 使用 allure 增强命令（失败结果也写入 Allure，记录初始 RED 状态）
# GREEN 阶段: 使用 allure 增强命令（通过结果写入 Allure，记录 GREEN 转变）
# REFACTOR 阶段: 使用 allure 增强命令（验证重构后测试仍通过）
```

每个 TDD 阶段的 Allure 结果写入独立子目录以区分来源:

```
allure-results/tdd/red/     ← RED 阶段（预期失败的测试结果）
allure-results/tdd/green/   ← GREEN 阶段（测试通过的结果）
allure-results/tdd/refactor/ ← REFACTOR 阶段（重构后验证结果）
```

> **Phase 6 联动**: Phase 6 Allure 收集时会扫描 `allure-results/tdd/` 子目录，将 TDD 过程中的测试结果合并到统一 Allure 报告中。详见 Phase 6 SKILL.md Step A2.5。

### TDD 阶段评估摘要规范

每个 TDD 阶段（RED/GREEN/REFACTOR）的 L2 验证完成后，主线程**必须**输出结构化评估摘要，确保 TDD 效果可评估、可追溯：

```
评估摘要格式:
  [TDD-EVAL] {STAGE} task-{N}:
    状态: {PASS|BLOCK|FAIL|RETRY|REVERTED}
    退出码: {exit_code}
    断言/统计: {阶段特定信息}
    测试输出 (尾部 5 行):
      {缩进的测试输出}

评估摘要写入 checkpoint:
  tdd_cycle.{stage}.eval_summary = {
    exit_code: number,
    output_tail: string,       // 最后 5 行测试输出
    ...阶段特定字段
  }

RED 特定字段:   assertion_message, test_file
GREEN 特定字段:  pass_count, total_count, full_test_passed
REFACTOR 特定字段: pass_count, total_count, green_pass_count_match
```

> **GUI 联动**: `emit-task-progress.sh` 的 `tdd_step` 事件可携带 `eval_summary` 字段，GUI ParallelKanban 组件可展示每个 TDD 步骤的评估详情。

---

## 并行 TDD (`parallel.enabled: true` + `tdd_mode: true`)

域 Agent prompt 注入完整 TDD 纪律文档：

```markdown
## TDD Mode: RED-GREEN-REFACTOR (MANDATORY)

Read and internalize the Iron Law:
NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST.
Code written before tests must be DELETED entirely.

For each task in your domain:

### RED: Write ONE failing test
- Test real behavior (no mocks unless unavoidable)
- Run: {test_command} → MUST FAIL with assertion error
- If test passes → your test is wrong, fix it
- If test has syntax error → fix error, re-run

### GREEN: Write MINIMAL code to pass
- Simplest possible implementation
- No YAGNI (don't add features beyond the test)
- Run: {test_command} → MUST PASS
- Run: {full_test_command} → ALL tests must pass
- If fails → fix implementation, NEVER modify test

### REFACTOR: Clean up (when tdd_refactor: true)
- Remove duplication, improve names, extract helpers
- Run: {test_command} → MUST still PASS
- If fails → revert refactor

Report per-task: tdd_cycles: [{ task, red_verified, green_verified, refactor_verified }]

## Anti-Patterns to AVOID
1. NEVER test mock behavior — test real code
2. NEVER add test-only methods to production classes
3. NEVER mock without understanding dependencies
4. If mock setup > test logic → use integration test instead
5. Integration tests are first-class, not afterthoughts
```

### 并行 TDD Checkpoint

每个域 Agent 返回的 JSON 信封包含：
```json
{
  "status": "ok",
  "tdd_metrics": {
    "total_cycles": 5,
    "red_violations": 0,
    "green_retries": 1,
    "refactor_reverts": 0
  },
  "tdd_cycles": [
    {
      "task": "task-1",
      "test_intent": "UserService.login() 在密码错误时返回 401 (sad-path)",
      "failing_signal": {
        "exit_code": 1,
        "assertion_message": "AssertionError: expected 401 but got undefined",
        "test_file": "tests/test_login.py"
      },
      "red_verified": true,
      "green_verified": true,
      "refactor_verified": true
    }
  ]
}
```

### 并行 TDD L2 后置验证

> **设计约束**: 并行模式下域 Agent 内部的 RED/GREEN 验证为 AI 自查（L1 层），缺少串行模式的主线程 Bash() L2 确定性保障。
> 为弥补此差距，主线程在域 Agent 合并后执行 **L2 后置验证**：

```
合并完成后:
  result = Bash("{full_test_command}")
  IF exit_code != 0:
    → BLOCK: "并行 TDD 合并后全量测试失败。域 Agent 可能虚报 green_verified。"
    → 检查各域 tdd_cycles 与实际失败测试的对应关系
  IF exit_code == 0:
    → PASS: L2 后置验证通过，tdd_metrics 可信
```

#### Per-Domain L2 Verification

并行模式下，每个 domain agent 完成后、worktree 合并前，主线程执行 L2 验证：

1. 调用 `verify-parallel-tdd-l2.sh --worktree-path <wt> --test-command <cmd> --task-checkpoint <cp>`
2. 验证 checkpoint 中每个 tdd_cycle 的 test_intent 和 failing_signal 完整性
3. 在 worktree 中独立运行测试确认 GREEN 状态
4. status=blocked 时拒绝合并该 domain 的代码

这将并行 TDD 的 per-task 验证从 L1（agent 自报）提升到 L2（确定性 Bash 验证）。

---

## TDD 崩溃恢复

扫描 `phase5-tasks/task-N.json` 的 `tdd_cycle` 字段：

| tdd_cycle 状态 | 恢复点 |
|----------------|--------|
| 无 tdd_cycle | 从 RED 开始 |
| red.verified = true，无 green | 从 GREEN 恢复（测试文件已写好） |
| green.verified = true，无 refactor | 从 REFACTOR 恢复（当 tdd_refactor: true） |
| tdd_cycle 完整 | 下一个 task |

恢复时：
1. 扫描 `phase5-tasks/` 目录找到最后一个完整的 task checkpoint
2. 读取 `tdd_cycle` 字段确定中断位置
3. RED 恢复：直接从 RED step 开始（测试文件可能不存在）
4. GREEN 恢复：验证测试文件存在 → 直接从 GREEN step 开始
5. REFACTOR 恢复：验证测试通过 → 直接从 REFACTOR step 开始

---

## L3 Checkpoint 审计（Gate Skill 执行）

Phase 5→6 门禁额外验证（当 `tdd_mode: true`）：

```
- [ ] tdd_metrics 存在
- [ ] tdd_metrics.red_violations === 0（零 RED 违规）
- [ ] 每个 task 的 tdd_cycle 完整（red + green 都 verified）
- [ ] 每个 task 的 test_intent 非空且符合规范
- [ ] 每个 task 的 failing_signal 存在且包含 assertion_message
- [ ] refactor_reverts 记录在案（允许 > 0，仅审计）
```

任何条件不满足 → 阻断 Phase 6。

### test_intent + failing_signal 门禁逻辑

```
for each task_checkpoint in phase5-tasks/:
  IF tdd_cycle exists:
    IF test_intent is empty or missing:
      → BLOCK: "Task #{N} 缺少 test_intent，无法证明 TDD 意图。"
    IF failing_signal is missing:
      → BLOCK: "Task #{N} 缺少 failing_signal，无法证明 RED 阶段的前置失败。"
    IF failing_signal.assertion_message is empty:
      → BLOCK: "Task #{N} 的 failing_signal 缺少断言消息，可能是编译错误而非真正的测试失败。"
```
