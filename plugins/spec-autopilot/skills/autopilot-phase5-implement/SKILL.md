---
name: autopilot-phase5-implement
description: "[ONLY for autopilot orchestrator] Phase 5 orchestration: path selection (parallel/serial/TDD), Phase 4 test file extraction, non-TDD L2 verification, and CLAUDE.md change detection."
user-invocable: false
---

# Autopilot Phase 5 Orchestrator — 实施编排

> **前置条件自检**：本 Skill 仅在 autopilot 编排主线程中使用。如果当前上下文不是 autopilot 编排流程，请立即停止并忽略本 Skill。

Phase 5 是流水线中最复杂的阶段，具有三条互斥执行路径。本 Skill 负责主线程编排层的路径选择、测试驱动验证和特殊检测逻辑。

> dispatch 的具体 prompt 构造逻辑保持在 `autopilot-dispatch` 中。

## Phase 5 主线程职责边界（v5.7 上下文节制化）

主线程在 Phase 5 中**仅执行最小编排**，禁止读取实施相关参考文档：

- ✅ 调用 `Skill("spec-autopilot:autopilot-dispatch")` 构造 dispatch prompt
- ✅ 调用 `generate-parallel-plan.sh` 生成并行计划
- ✅ 派发 Task + 等待完成 + 解析 JSON 信封 + 写 checkpoint
- ✅ 合并 worktree + 全量测试
- ✅ **当 mode=full 且非 TDD 模式时**：从 Phase 4 checkpoint 提取测试文件列表，传递给 dispatch skill
- ❌ **禁止**主线程 Read `autopilot/references/phase5-implementation.md`（由 dispatch skill 内部读取）
- ❌ **禁止**主线程 Read `autopilot/references/parallel-phase5.md`（由 dispatch skill 内部读取）
- ❌ **禁止**主线程自行分析任务依赖（由 generate-parallel-plan.sh 确定性计算）

> **设计意图**: Phase 5 实施细节全部下沉到 dispatch skill 和子 Agent，保护主线程上下文窗口。

## Phase 4 测试文件提取（full 模式测试驱动增强）

当 `mode === "full"` 且 `tdd_mode !== true` 时，Phase 5 dispatch **前**执行：

1. 读取 Phase 4 checkpoint（`phase-4-testing.json`）
2. 提取 `artifacts` 字段中的测试文件路径列表（`phase4_test_files`）
3. 提取 `test_traceability` 字段（`[{test, requirement}]`，可选）用于 task 级映射
4. 将 `phase4_test_files` 和 `phase4_test_traceability` 作为参数传递给 dispatch skill
5. dispatch skill 在构造子 Agent prompt 时：
   - 如果 `test_traceability` 可用：按 task 描述与 `requirement` 字段匹配，仅注入与当前 task 相关的测试文件
   - 如果 `test_traceability` 不可用（向后兼容）：注入全部 `phase4_test_files`，由子 Agent 自行判断相关性

> 如果 Phase 4 checkpoint 不存在或 artifacts 为空（lite/minimal 模式），则 `phase4_test_files` 为空数组，子 Agent prompt 中不注入测试驱动段落。

## 非 TDD 模式测试驱动 L2 验证（full 模式增强）

当 `mode === "full"` 且 `tdd_mode !== true` 且 `phase4_test_files` 非空时，主线程对每个 task 执行 L2 测试驱动验证（详见 `autopilot/references/phase5-implementation.md` 非 TDD L2 验证章节）：

### 串行模式每 task 流程

```
FOR each task IN tasks:
  # === L2 RED 验证（dispatch 前，主线程确定性执行） ===
  # 使用 test_traceability 匹配当前 task 的相关测试文件
  relevant_tests = match(phase4_test_traceability, task) || phase4_test_files
  RED_EXIT_CODE = Bash('{test_command} {relevant_tests}')
  IF RED_EXIT_CODE == 0:
    red_verified = false
    red_skipped_reason = "test_already_passing"
    输出: [WARN] task-{N}: Phase 4 测试已通过，RED→GREEN 转变不可验证
  ELSE:
    red_verified = true
    输出: [TDD-L2] task-{N}: RED 验证通过（测试正确失败）

  # === 正常 dispatch（传入 red_verified 状态） ===
  dispatch Task (含 phase4_test_files + red_status)

  # === L2 GREEN 验证（task 完成后，主线程确定性执行） ===
  GREEN_EXIT_CODE = Bash('{test_command} {relevant_tests}')
  IF GREEN_EXIT_CODE != 0:
    green_verified = false
    输出: [WARN] task-{N}: GREEN 验证失败，Phase 4 测试未通过
  ELSE:
    green_verified = true
    输出: [TDD-L2] task-{N}: GREEN 验证通过（测试成功通过）

  # === 写入 task checkpoint 时包含主线程 L2 验证结果 ===
  task_checkpoint.test_driven_evidence = {
    red_verified, green_verified, red_skipped_reason,
    verification_layer: "L2_main_thread"
  }

  # === L2 验证闭环（写入 checkpoint 后立即调用） ===
  VERIFY_RESULT = Bash('bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/verify-test-driven-l2.sh {task_checkpoint_path}')
  # VERIFY_RESULT 为 JSON: {"status":"ok|warn","message":"...","red_verified":bool,"green_verified":bool}
  # status=warn 时输出 message，不阻断流程
  # 连续 3 个 task warn → AskUserQuestion 决策是否继续
END FOR
```

### 并行模式

主线程无法对域 Agent 内部逐 task L2 验证。改为**合并后全量验证**：

- 合并所有域 worktree 后，主线程运行 Phase 4 全部测试 `Bash('{test_command} {phase4_test_files}')`
- 全部通过 = GREEN 验证 ok，写入 phase-5 checkpoint 的 `test_driven_evidence`（聚合级别）
- 未通过 = 记录 WARN，不阻断

## 任务来源（模式感知）

> 详见 `autopilot/references/mode-routing-table.md` § 3。

## 执行模式决策（互斥分支）

读取 `config.phases.implementation.parallel.enabled` + `tdd_mode`，按 `autopilot/references/mode-routing-table.md` § 4 确定路径：

### 【路径 A — 并行模式】（`parallel.enabled = true`）

> **ABSOLUTE HARD CONSTRAINT — 禁止自主降级**:
> 当 `config.phases.implementation.parallel.enabled = true` 时，主线程**严禁**以任何理由
>（包括但不限于"任务量大"、"有强依赖"、"复杂度高"、"安全起见"）自主决定切换为串行模式。
> 降级**仅允许**在以下确定性条件下触发：
>
> 1. `generate-parallel-plan.sh` 输出 `fallback_to_serial=true`（确定性脚本判定）
> 2. worktree 创建失败（runtime 错误）
> 3. 单组合并冲突 > 3 文件
> 4. 连续 2 组合并失败
> 5. 用户通过 AskUserQuestion 显式选择"切换串行"
>
> **违反此约束等同于违反 CLAUDE.md 状态机硬约束第 3 条。**

解析任务 → **生成 `parallel_plan.json`**（v5.4: 调用 `generate-parallel-plan.sh` 确定性调度器） → 按 batch 分区 → worktree 并行 → 按编号合并 → 全量测试。详见 `autopilot/references/parallel-phase5.md`。

### 【路径 B — 串行模式】（`parallel.enabled = false` 或降级）

逐个前台 Task → JSON 信封 → task checkpoint。**v5.4**: 串行模式也调用 `generate-parallel-plan.sh` 生成计划，Batch Scheduler 消费 `batches` 字段执行。详见 `autopilot/references/phase5-implementation.md` 串行模式章节。

**v5.8 串行模式 CLAUDE.md 变更检测**: 串行模式下，每个 task dispatch 前执行轻量 CLAUDE.md 变更检测：

```bash
# 在每个 task dispatch 前（与 Gate Step 5.5 相同逻辑）
CLAUDE_MD_MTIME=$(stat -f "%m" "${session_cwd}/CLAUDE.md" 2>/dev/null || echo 0)
CACHED_MTIME=$(cat "${change_dir}context/.rules-scan-mtime" 2>/dev/null || echo 0)
if [ "$CLAUDE_MD_MTIME" != "$CACHED_MTIME" ]; then
  # 重新扫描规则并更新缓存
  Bash('bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/rules-scanner.sh ${session_cwd}')
  echo "$CLAUDE_MD_MTIME" > "${change_dir}context/.rules-scan-mtime"
  # 使用新规则构造 dispatch prompt
fi
```

> 此检测仅在串行模式生效（并行模式的域 Agent 在 dispatch 时已注入完整规则，中途不可更新）。

### 【路径 C — TDD 模式】（`tdd_mode: true` 且模式为 `full`）

**优先于路径 A/B，与 parallel.enabled 配合使用。**
**执行前读取**: `autopilot/references/tdd-cycle.md` + `autopilot/references/testing-anti-patterns.md`

- **串行 TDD**（`parallel.enabled: false`）：每个 task 3 个 sequential Task (RED→GREEN→REFACTOR)。主线程写入 `.tdd-stage` 文件供 L2 Hook 确定性拦截。详见 `autopilot/references/tdd-cycle.md` 串行 TDD 章节。
- **并行 TDD**（`parallel.enabled: true`）：域 Agent prompt 注入完整 TDD 纪律。合并后主线程执行全量测试验证。详见 `autopilot/references/tdd-cycle.md` 并行 TDD 章节。

TDD 护栏：先测试后实现 | RED 必须失败 | GREEN 必须通过 | 测试不可变 | REFACTOR 回归保护

> **强制约束**：路径 A/B **互斥**。Phase 5 JSON 信封构造详见 `autopilot/references/protocol.md`。

### Phase 5→6 特殊门禁

> **仅 full 和 lite 模式执行**。minimal 模式跳过 Phase 6。

autopilot-gate 额外验证：`test-results.json` 存在、`zero_skip_check.passed === true`、任务清单中所有任务标记为 `[x]`

**dispatch skill 执行时自行读取**: `autopilot/references/phase5-implementation.md` + `autopilot/references/parallel-phase5.md` + `autopilot/references/mode-routing-table.md`
