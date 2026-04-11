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

### 条件化参考文件读取（v8.0 上下文优化）

不同阶段过渡所需的参考文件不同。**按需加载**以减少主窗口上下文占用：

| 切换点 | 必读文件 | 条件读取 |
|--------|---------|---------|
| Phase 1→2（联合快速路径） | `log-format.md` + `gate-checkpoint-ops.md` | 无需读取 decision-polling/special-gates/optional-validation |
| Phase 2→3（快速路径内联） | 由快速路径内联处理，**不调用本 Skill** | — |
| Phase 3→4, 6→7 | `log-format.md` + `gate-checkpoint-ops.md` + `gate-decision-polling.md` | 无需 special-gates |
| Phase 4→5, Phase 5→6 | **全部 5 个文件** | 含特殊门禁 |

> Phase 2→3 过渡由主编排器的联合调度快速路径直接处理，不触发本 Skill。Phase 3 的前置验证由 Hook L2 自动完成。

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

当门禁阻断时启动 GUI 决策轮询（override/retry/fix/auto_continue 自动推进/timeout）。

**v6.0 自动推进语义**: 门禁通过时，默认自动推进到下一阶段，不弹出用户确认。

**条件读取**: `autopilot/references/gate-decision-polling.md`（仅 Phase 3→4, 4→5, 5→6, 6→7 过渡时读取；Phase 1→2 由快速路径处理，不需要）

### 特殊门禁

除通用 8 步校验外，以下切换点有额外验证：

- **Phase 4→5**: 非 TDD 模式验证 test_counts/artifacts/dry_run；TDD 模式验证 tdd-override.json
- **Phase 5→6**: 验证 test-results.json + zero_skip_check + tasks 完成度；TDD 模式额外验证 tdd_metrics
- **TDD 完整性审计 (L3)**: 扫描 `phase5-tasks/task-N.json` 验证 tdd_cycle 完整性
- **Phase 6.5 代码审查 (Advisory Gate)**: 可选门禁，不阻断 Phase 7 predecessor，结果在 Phase 7 汇合

**条件读取**: `autopilot/references/gate-special-gates.md`（仅 Phase 4→5, Phase 5→6 过渡时读取，其他过渡无特殊门禁）

### 可选验证

语义验证（soft check）和 Brownfield 三向一致性检查。

**条件读取**: `autopilot/references/gate-optional-validation.md`（仅 Phase 4→5, Phase 5→6 过渡时读取）

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

### 读取 Checkpoint

验证前置阶段状态：

1. 构造路径：`phase-results/phase-{N}-*.json`
2. 读取并解析 JSON
3. 判定规则：
   - `status === "ok" || "warning"` → 校验通过
   - `status === "blocked" || "failed"` → 硬阻断
   - 文件不存在 → 硬阻断（阶段未完成）

### Task 级 Checkpoint（Phase 5 专用）

Phase 5 的每个 task 完成后写入独立 checkpoint（`phase5-tasks/task-N.json`），支持细粒度恢复。

**执行前读取**: `autopilot/references/gate-checkpoint-ops.md`（完整的原子写入流程 + 断电安全 + Phase 5 task 级）
