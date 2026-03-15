---
name: autopilot-gate
description: "[ONLY for autopilot orchestrator] Gate verification + checkpoint management for autopilot phase transitions. Enforces 8-step checklist, special gates, and manages phase-results checkpoint files."
user-invocable: false
---

# Autopilot Gate — 门禁验证 + Checkpoint 管理协议

> **前置条件自检**：本 Skill 仅在 autopilot 编排主线程中使用。如果当前上下文不是 autopilot 编排流程，请立即停止并忽略本 Skill。

阶段切换时的 AI 侧验证清单 + Checkpoint 状态持久化。Layer 1（Task blockedBy）和 Layer 2（磁盘 checkpoint）已由 Hooks 确定性执行，本 Skill 负责 Layer 3（AI 执行的补充检查清单）以及 Checkpoint 文件的读写管理。

> JSON 信封契约、状态规则、特殊门禁阈值等详见：`autopilot/references/protocol.md`

### 共享基础设施依赖

本 Skill 依赖 `scripts/_common.sh` 提供的以下共享函数，**不重复实现**配置/锁文件/checkpoint 逻辑：

| 函数 | 用途 |
|------|------|
| `read_config_value(project_root, key_path, default)` | 读取 `autopilot.config.yaml` 标量配置值 |
| `read_lock_json_field(lock_file, field, default)` | 提取锁文件 JSON 字段（用于执行模式感知） |
| `read_checkpoint_status(file_path)` | 提取 checkpoint JSON 的 status 字段 |
| `find_checkpoint(phase_results_dir, phase_number)` | 查找指定阶段的最新 checkpoint 文件 |
| `validate_checkpoint_integrity(checkpoint_file)` | 验证 checkpoint JSON 完整性（自动清理损坏文件） |
| `scan_all_checkpoints(phase_results_dir, mode)` | 按阶段顺序扫描全部 checkpoint（崩溃恢复用） |
| `get_last_valid_phase(phase_results_dir, mode)` | 返回最后一个 status=ok/warning 的阶段编号 |

> 上述函数的实现和参数说明详见 `scripts/_common.sh`。

**执行前读取**: `autopilot/references/log-format.md`（日志格式规范）

## 三层门禁架构

| 层级 | 机制 | 执行者 |
|------|------|--------|
| Layer 1 | TaskCreate + blockedBy 依赖 | 任务系统（自动） |
| Layer 2 | 磁盘 checkpoint JSON 校验 | Hook 脚本（确定性） |
| **Layer 3** | **8 步切换清单 + 特殊门禁** | **本 Skill（AI 执行）** |

## 8 步阶段切换检查清单

每次从 Phase N 切换到 Phase N+1 时，**必须**执行：

```
- [ ] Step 1: 确认阶段 N 的子 Agent 已返回 JSON 信封
- [ ] Step 2: 验证 JSON status 为 "ok" 或 "warning"
- [ ] Step 3: 将 JSON 写入 phase-results/phase-N-*.json（由本 Skill checkpoint 管理执行）
- [ ] Step 4: TaskUpdate 将阶段 N 标记为 completed
- [ ] Step 5: TaskGet 阶段 N+1 的任务，确认 blockedBy 为空
- [ ] Step 5.5: CLAUDE.md 变更检测（v4.0）— 检查 CLAUDE.md 修改时间是否比 Phase 0 缓存的规则更新，是则重新扫描规则
- [ ] Step 6: 读取 phase-results/phase-N-*.json 确认文件存在且可解析
- [ ] Step 7: TaskUpdate 将阶段 N+1 标记为 in_progress
- [ ] Step 8: 准备 dispatch 子 Agent（由 dispatch Skill 执行）
```

### Step 5.5 CLAUDE.md 变更感知（v4.0 新增）

在每次阶段切换时检查项目 CLAUDE.md 是否在运行期间被修改：

```bash
# 比较 CLAUDE.md 修改时间与 Phase 0 缓存时间
CLAUDE_MD_MTIME=$(stat -f "%m" "${session_cwd}/CLAUDE.md" 2>/dev/null || echo 0)
CACHED_MTIME=$(cat "${change_dir}context/.rules-scan-mtime" 2>/dev/null || echo 0)
```

如果修改时间不同：
1. 重新执行 `rules-scanner.sh` 扫描 CLAUDE.md + `.claude/rules/`
2. 更新缓存时间戳
3. 将新规则注入后续子 Agent prompt

如果修改时间相同：跳过，使用 Phase 0 缓存的规则。

**任何 Step 失败 → 硬阻断，禁止启动下一阶段。**

### 门禁通过后输出

8 步检查清单全部通过后，**必须**输出以下格式化日志（遵循 `autopilot/references/log-format.md`）：

```
── Phase {N+1}: {phase_name} ──

[GATE] Phase {N} → {N+1}: PASSED (8/8)
```

阶段名称映射：

| Phase | name |
|-------|------|
| 1 | Requirements |
| 2 | OpenSpec |
| 3 | Fast-Forward |
| 4 | Test Design |
| 5 | Implementation |
| 6 | Test Report |
| 7 | Archive |

门禁失败时输出：

```
[GATE] Phase {N} → {N+1}: BLOCKED at Step {M} — {reason}
```

### 双向反控：Gate 阻断后决策轮询（v5.1 新增）

当门禁阻断时，在输出 `[GATE] BLOCKED` 日志 **之后**，必须启动 GUI 决策轮询循环，使 GUI 用户可通过 `decision.json` 发送 Override/Retry/Fix 指令。

**流程：**

1. 发射 `gate_block` 事件（已有逻辑）
2. 调用决策轮询脚本：
   ```bash
   DECISION=$(bash ${PLUGIN_ROOT}/scripts/poll-gate-decision.sh "${change_dir}/" "${PHASE}" "${MODE}" '{"blocked_step":M,"error_message":"..."}')
   POLL_EXIT=$?
   ```
3. 根据轮询结果分支处理：

| `POLL_EXIT` | `action` | 处理 |
|-------------|----------|------|
| 0 | `override` | 记录日志 `[GATE] Override accepted: {reason}` → 视为通过，继续下一阶段 |
| 0 | `retry` | 记录日志 `[GATE] Retry requested: {reason}` → 重新执行完整 8 步检查清单 |
| 0 | `fix` | 记录日志 `[GATE] Fix requested` → 将 `fix_instructions` 展示给用户，等待修复后重新执行 8 步检查清单 |
| 1 | `timeout` | 轮询超时（默认 300 秒），回退到原有行为：向用户展示阻断信息，通过 AskUserQuestion 请求决策 |

**decision.json 格式**（由 GUI 写入 `openspec/changes/<name>/context/decision.json`）：

```json
{
  "action": "override | retry | fix",
  "phase": 4,
  "timestamp": "ISO-8601",
  "reason": "用户/GUI 提供的说明",
  "fix_instructions": "仅 fix 动作时填写 — 具体修复指导"
}
```

**安全约束**：
- `override` 不可在 Phase 4→5 和 Phase 5→6 特殊门禁中使用（这些门禁的失败条件涉及测试质量底线，不允许绕过）
- 决策文件在读取后立即删除，防止重复消费
- 轮询超时可通过 `config.gui.decision_poll_timeout` 配置（单位：秒，默认 300）

## 特殊门禁：Phase 4 → Phase 5

除通用 8 步校验外，额外验证（从 `autopilot.config.yaml` 读取阈值）：

**非 TDD 模式**（`tdd_mode: false` 或未设置）：
```
- [ ] phase-4-testing.json 中 test_counts 的每个字段 ≥ config.phases.testing.gate.min_test_count_per_type
- [ ] artifacts 列表中包含 config.phases.testing.gate.required_test_types 对应的文件
- [ ] dry_run_results 的所有字段全部为 0（exit code）
```

**TDD 模式**（`tdd_mode: true` 且模式为 `full`）：
```
- [ ] phase-4-tdd-override.json 存在且 tdd_mode_override === true
- [ ] 跳过 test_counts / dry_run 验证（测试在 Phase 5 per-task 创建）
```

任何条件不满足 → 阻断 Phase 5，要求重新执行 Phase 4。

## 特殊门禁：Phase 5 → Phase 6

除通用 8 步校验外，额外验证：

```
- [ ] test-results.json 存在
- [ ] zero_skip_check.passed === true
- [ ] tasks.md 中所有任务标记为 [x]
```

**TDD 模式额外验证**（当 `tdd_mode: true`）：
```
- [ ] tdd_metrics 存在
- [ ] tdd_metrics.red_violations === 0（零 RED 违规）
- [ ] 每个 task 的 tdd_cycle 完整（red + green 都 verified）
```

任何条件不满足 → 阻断 Phase 6。

## TDD 完整性审计（L3 层保障）

当 `tdd_mode: true` 时，Phase 5→6 门禁执行额外的 TDD 审计：

1. 扫描所有 `phase5-tasks/task-N.json` 文件
2. 验证每个 task 包含 `tdd_cycle` 字段
3. 验证 `tdd_cycle.red.verified === true` 和 `tdd_cycle.green.verified === true`
4. 记录 `refactor_reverts` 总数（允许 > 0，仅审计记录）
5. 汇总为 `tdd_audit` 输出：
   ```json
   {
     "total_tasks": 10,
     "tdd_complete": 10,
     "red_violations": 0,
     "refactor_reverts": 1,
     "audit_passed": true
   }
   ```
6. `audit_passed === false` → 阻断 Phase 6

## Phase 6.5 代码审查门禁（可选，v3.2.2 三路并行）

当 `config.phases.code_review.enabled = true` 时，Phase 7 步骤 2.a 收集代码审查结果后检查：

```
- [ ] phase-6.5-code-review.json 存在（由 Phase 7 步骤 2.a 写入）
- [ ] findings 中 critical 数量为 0（当 block_on_critical = true 时）
- [ ] status 为 "ok" 或 "warning"（用户已确认）
```

当 `code_review.enabled = false` 时，**跳过此门禁**，不要求 checkpoint 存在。

Phase 6.5 是可选步骤，不影响 Layer 1（TaskCreate blockedBy）和 Layer 2（Hook predecessor check）。
Phase 6.5 与 Phase 6 **并行执行**（v3.2.2 三路并行），其结果在 Phase 7 汇合点收集。

## 可选 Layer 3 补充：语义验证

> 详见：`autopilot/references/semantic-validation.md`

在 8 步检查清单的 Step 6 之后，可选执行语义验证：

1. 读取 `references/semantic-validation.md` 中对应阶段的检查清单
2. 逐项验证（读取相关文件确认）
3. 不通过项记录为 `warning`（不硬阻断，除非发现严重不一致）
4. 输出语义验证摘要

**注意**: 语义验证为 AI 执行的软检查，不替代 Layer 2 Hook 的确定性验证。

## 可选 Layer 3 补充：Brownfield 验证

> 详见：`autopilot/references/brownfield-validation.md`
> 通过 `config.brownfield_validation.enabled` 控制（v4.0 起默认开启，greenfield 项目 Phase 0 自动关闭）。

当启用时，在特定阶段切换时执行额外的三向一致性检查：

| 切换点 | 检查内容 |
|--------|---------|
| Phase 4 → Phase 5 | 设计-测试对齐 |
| Phase 5 启动 | 测试-实现就绪 |
| Phase 5 → Phase 6 | 实现-设计一致性 |

`strict_mode: true` 时不一致直接阻断；`false` 时仅 warning。

## 执行模式感知

本 Skill 在执行门禁检查时，需感知当前执行模式。通过共享函数 `read_lock_json_field()` 从锁文件读取 `mode` 字段（注意使用绝对路径 `${session_cwd}/openspec/changes/.autopilot-active`）。

### 模式对门禁的影响

| 切换点 | full 模式 | lite 模式 | minimal 模式 |
|--------|----------|----------|-------------|
| Phase 1 → Phase 2 | 正常检查 | **跳过**（Phase 2 不执行） | **跳过** |
| Phase 2 → Phase 3 | 正常检查 | **跳过** | **跳过** |
| Phase 3 → Phase 4 | 正常检查 | **跳过** | **跳过** |
| Phase 4 → Phase 5 | 正常检查 + 特殊门禁 | **跳过**（Phase 1 → Phase 5） | **跳过**（Phase 1 → Phase 5） |
| Phase 5 → Phase 6 | 正常检查 + 特殊门禁 | 正常检查 + 特殊门禁 | **跳过**（Phase 5 → Phase 7） |
| Phase 6 → Phase 7 | 正常检查 | 正常检查 | **跳过** |

### lite/minimal 的 Phase 1 → Phase 5 门禁

当 mode 为 lite 或 minimal 时，Phase 5 的前置检查为：
- Phase 1 checkpoint（`phase-1-requirements.json`）存在且 status 为 ok 或 warning
- Phase 2/3/4 checkpoint **不需要存在**（已被跳过）

## 阶段强制执行保障

阶段跳过由 Hook（`check-predecessor-checkpoint.sh`）+ TaskCreate blockedBy 依赖链确定性阻断，AI 无需自我审查。在 full 模式下 8 个阶段是不可分割整体；在 lite/minimal 模式下，跳过的阶段由 Phase 0 的 TaskCreate 链控制，不需要产出 checkpoint。非跳过的阶段产出为空时应产出 "N/A with justification" 而非跳过。

---

## Checkpoint 管理（原 autopilot-checkpoint，v4.0 合入）

管理 `openspec/changes/<name>/context/phase-results/` 目录下的 checkpoint 文件。

> JSON 信封格式、阶段额外字段、Checkpoint 命名等详见：`autopilot/references/protocol.md`

### Checkpoint 文件命名

```
phase-results/
├── phase-1-requirements.json
├── phase-2-openspec.json
├── phase-3-ff.json
├── phase-4-testing.json
├── phase-5-implement.json
├── phase-6-report.json
└── phase-7-summary.json
```

### 写入 Checkpoint

阶段完成后，将子 Agent 返回的 JSON 信封写入对应文件：

1. 确保 `context/phase-results/` 目录存在（不存在则创建）
2. **v5.1 原子性写入**: 将完整 JSON 信封写入临时文件 `phase-{N}-{slug}.json.tmp`
3. 验证临时文件 JSON 格式合法（读回并解析）
4. 执行原子重命名：`mv phase-{N}-{slug}.json.tmp phase-{N}-{slug}.json`
5. 验证最终文件存在且可解析

**写入流程**（所有 checkpoint 写入必须遵循此原子模式）：
```bash
# Step 1: Write to temp file
Write JSON → phase-{N}-{slug}.json.tmp

# Step 2: Validate temp file
python3 -c "import json; json.load(open('phase-{N}-{slug}.json.tmp'))"
# If validation fails → delete .tmp, report error, do NOT overwrite existing checkpoint

# Step 3: Atomic rename
mv phase-{N}-{slug}.json.tmp phase-{N}-{slug}.json

# Step 4: Final verification
Read phase-{N}-{slug}.json → parse JSON → confirm status field exists
```

**断电/崩溃安全**：
- 写入 `.tmp` 时崩溃 → 正式文件不受影响，恢复时忽略 `.tmp` 文件
- `mv` 是文件系统原子操作 → 不会产生半写的 checkpoint
- 恢复时：扫描并删除所有 `.tmp` 残留文件

#### JSON 格式

> 完整的 JSON 信封格式定义详见 `autopilot/references/protocol.md`。

核心字段：`status`（ok/warning/blocked/failed）、`summary`、`artifacts`、`risks`、`next_ready`。
`_metrics` 和 `timestamp` 由主线程写入时附加。

#### 写入确认输出

Checkpoint 写入成功后，**必须**输出以下格式化日志（遵循 `autopilot/references/log-format.md`）：

```
[CP] phase-{N}-{slug}.json | commit: {short_sha}
```

写入失败时输出：

```
[ERROR] Checkpoint write failed: phase-{N}-{slug}.json — {reason}
```

### 读取 Checkpoint

验证前置阶段状态：

1. 构造路径：`phase-results/phase-{N}-*.json`
2. 读取并解析 JSON
3. 判定规则：
   - `status === "ok" || "warning"` → 校验通过
   - `status === "blocked" || "failed"` → 硬阻断
   - 文件不存在 → 硬阻断（阶段未完成）

### Task 级 Checkpoint（Phase 5 专用）

Phase 5 长时间实施中，每个 task 完成后写入独立 checkpoint，支持细粒度恢复。

```
phase-results/phase5-tasks/
├── task-1.json
├── task-2.json
└── ...
```

- 确保 `context/phase-results/phase5-tasks/` 目录存在
- 写入 `task-{N}.json`（格式同主 checkpoint，额外含 `task_number` 和 `task_title`）
- 恢复 Phase 5 时：扫描 `phase5-tasks/task-*.json`，找到第一个非 `"ok"` 的 task 重新开始
- **非连续恢复约束**：不跳过失败的 task

### 扫描所有 Checkpoint

用于崩溃恢复，调用 `scan_all_checkpoints(phase_results_dir, mode)` 按阶段顺序扫描 phase-1 → phase-7。调用 `get_last_valid_phase(phase_results_dir, mode)` 返回最后一个 `status: "ok"` 或 `"warning"` 的阶段编号。
