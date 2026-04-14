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

## TDD 门禁结构（WS-E 治理强化）

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
  │ Step 2: 主线程确定性验证 (L2)                          │
  │   result = Bash("{test_command}")                      │
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
  │ Step 4: 主线程确定性验证 (L2)                          │
  │   result = Bash("{test_command}")                      │
  │   IF exit_code != 0:                                  │
  │     → 重试 (max_retries_per_task from config)         │
  │     → 耗尽重试 → AskUserQuestion                      │
  │   IF exit_code == 0:                                  │
  │     → PASS: 记录 tdd_cycle.green = { verified: true } │
  │   验证其他测试未被破坏:                                │
  │   full_result = Bash("{full_test_command}")            │
  │   IF 其他测试失败 → 修复实现，不修改测试               │
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
  │ Step 6: 主线程确定性验证 (L2)                          │
  │   result = Bash("{test_command}")                      │
  │   IF exit_code != 0:                                  │
  │     → 强制回滚: Bash("git checkout -- .")        │
  │       (全文件回滚，确保代码绝对不被污染)                │
  │     → 记录 tdd_cycle.refactor = { reverted: true }    │
  │   IF exit_code == 0:                                  │
  │     → PASS: 记录 tdd_cycle.refactor = {verified: true}│
  │                                                       │
  │ Step 6.5: 发射 REFACTOR 完成进度事件                    │
  │   Bash('bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/   │
  │     emit-task-progress.sh "task-{N}-{slug}"           │
  │     passed {N} {total} {mode} "refactor"')            │
  │   回滚时 status 改为 "failed"                           │
  └───────────────────────────────────────────────────────┘

  Checkpoint: phase5-tasks/task-N.json
    包含: tdd_cycle: { red: {...}, green: {...}, refactor: {...} }
```

### 测试命令解析

```
tdd_test_command 非空 → 使用 tdd_test_command
tdd_test_command 为空 → 从 test_suites 中提取：
  - task 内测试命令 = 子 Agent RED 返回的 test_command
  - full_test_command = 所有 test_suites 的 command 串联
```

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
- [ ] 每个 task 的 test_intent 非空且符合规范（WS-E 治理）
- [ ] 每个 task 的 failing_signal 存在且包含 assertion_message（WS-E 治理）
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
