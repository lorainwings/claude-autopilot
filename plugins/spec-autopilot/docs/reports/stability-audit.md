# 全模式稳定性与链路闭环审计报告

**审计日期**: 2026-03-13
**插件版本**: spec-autopilot (基于 v4.0.0-wave4 commit 08d346f)
**审计员**: Agent 1 — 全模式稳定性与链路闭环测试审计员

---

## 1. 执行摘要

本报告对 `spec-autopilot` 插件的三种执行模式（full/lite/minimal）进行了全链路稳定性审计，覆盖状态机流转、三层 Gate 系统、文件 IO 完整性、崩溃恢复及跨阶段数据传递。

**核心结论**: 系统架构设计成熟，三层门禁防御纵深完备，三种模式的状态机流转逻辑经代码验证均正确受控。发现 0 个 P0 缺陷、3 个 P1 缺陷、5 个 P2 缺陷。综合评分 **8.2/10**。

**关键发现**:
- 三层 Gate 系统在所有模式下工作一致，Hook 层对模式感知准确
- 崩溃恢复协议覆盖全面，包含 Phase 5 task 级细粒度恢复
- 上下文压缩恢复机制（PreCompact + SessionStart(compact)）设计完善
- 存在后台 Agent L2 校验绕过的设计权衡（有文档记录，非意外缺失）
- `validate-json-envelope.sh` 与 `post-task-validator.sh` 存在功能重叠

---

## 2. 审计方法论

### 2.1 审计范围

- **文件审查**: 7 个 SKILL.md 文件、1 个 hooks.json、10 个脚本文件、3 个 Python 模块、2 个参考文档
- **链路覆盖**: full (Phase 0-7)、lite (Phase 0/1/5/6/7)、minimal (Phase 0/1/5/7)
- **验证维度**: 状态机完整性、门禁有效性、文件 IO 正确性、崩溃恢复、数据传递连续性

### 2.2 审计方法

1. **静态代码审查**: 逐行审阅所有 Skill 文件和 Hook 脚本，提取状态转换规则
2. **模式矩阵验证**: 对每种模式，追踪从 Phase 0 到 Phase 7 的完整数据流
3. **防御层交叉验证**: 对比 Layer 1（TaskCreate blockedBy）、Layer 2（Hook 脚本）、Layer 3（AI Gate Skill）三层的模式感知逻辑是否一致
4. **边界条件分析**: 检查崩溃点、空状态、损坏文件等异常场景的处理

---

## 3. Full 模式审计结果

### 3.1 状态机流转分析

**预期流转**: Phase 0 -> 1 -> 2 -> 3 -> 4 -> 5 -> 6 -> 7

| 转换点 | 执行位置 | 控制机制 | 验证结果 |
|--------|---------|---------|---------|
| 0 -> 1 | Skill(autopilot-phase0) | Phase 0 输出 recovery_phase=1 | PASS |
| 1 -> 2 | 主线程 -> 统一调度模板 | Gate 8步 + checkpoint(phase-1) | PASS |
| 2 -> 3 | 主线程 -> 统一调度模板 | Gate 8步 + checkpoint(phase-2) | PASS |
| 3 -> 4 | 主线程 -> 统一调度模板 | Gate 8步 + checkpoint(phase-3) | PASS |
| 4 -> 5 | 主线程 -> 统一调度模板 | Gate 8步 + 特殊门禁(test_counts/dry_run/pyramid/coverage) | PASS |
| 5 -> 6 | 主线程 -> 统一调度模板 | Gate 8步 + 特殊门禁(zero_skip/tasks完成) | PASS |
| 6 -> 7 | 主线程 -> Skill(autopilot-phase7) | Gate 8步 + checkpoint(phase-6) | PASS |

**Phase 0 TaskCreate 链验证**: full 模式创建 Phase 1-7 共 7 个任务，blockedBy 依赖链为线性序列（Phase N+1 blockedBy Phase N）。验证通过。

**TDD 模式分支**: 当 `tdd_mode: true` 时，Phase 4 写入 `phase-4-tdd-override.json` checkpoint（status=ok, tdd_mode_override=true），Phase 5 predecessor 回退为 Phase 3。`check-predecessor-checkpoint.sh` 第 240-243 行正确处理此分支。验证通过。

### 3.2 Gate 系统有效性

**Layer 1 (TaskCreate blockedBy)**:
- Phase 0 Step 7 创建 7 个任务，线性 blockedBy 链
- 任务系统自动阻断乱序执行
- **评估**: 有效

**Layer 2 (Hook 脚本)**:
- `check-predecessor-checkpoint.sh` (PreToolUse): 验证前置 checkpoint 存在且 status=ok/warning
  - full 模式 `get_predecessor_phase` 返回 `target - 1`（标准线性），TDD 模式 Phase 5 返回 3
  - Phase 2/3/4 在非 full 模式下直接 deny（第 253-273 行）
  - Phase 5 特殊门禁: full 模式要求 Phase 4 checkpoint status=ok（第 288-336 行）
  - Phase 6 特殊门禁: 验证 zero_skip_check.passed + tasks.md 完成度（第 339-380 行）
  - Wall-clock 超时保护: Phase 5 开始后检查运行时间（第 384-416 行）
- `post-task-validator.py` (PostToolUse): 5 合 1 验证器
  - Validator 1: JSON 信封结构验证 + 阶段专属字段
  - Validator 2: 反合理化检测（Phase 4/5/6）
  - Validator 3: 代码约束检查（Phase 4/5/6）
  - Validator 4: 并行合并守卫（Phase 5 worktree）
  - Validator 5: 决策格式验证（Phase 1）
- `write-edit-constraint-check.sh` (PostToolUse Write|Edit): Phase 5 直接写入约束检查
- **评估**: 有效，覆盖全面

**Layer 3 (AI Gate Skill)**:
- `autopilot-gate` SKILL.md: 8 步检查清单 + Step 5.5 CLAUDE.md 变更感知
- Phase 4->5 特殊门禁: test_counts/artifacts/dry_run_results + TDD 模式分支
- Phase 5->6 特殊门禁: test-results.json + zero_skip_check + tasks.md + TDD 审计
- **评估**: 有效

**三层一致性**: Layer 1 依赖链与 Layer 2/3 的阶段验证目标一致。Layer 2 是确定性硬阻断，Layer 3 是补充性 AI 检查。三层之间无冲突。

### 3.3 文件 IO 完整性

| 文件类型 | 路径模式 | 读写时机 | 验证结果 |
|---------|---------|---------|---------|
| 锁文件 | `openspec/changes/.autopilot-active` | Phase 0 创建，Phase 7 删除 | PASS |
| Checkpoint | `context/phase-results/phase-N-*.json` | 每阶段完成后写入 | PASS |
| Task Checkpoint | `context/phase-results/phase5-tasks/task-N.json` | Phase 5 每个 task 后写入 | PASS |
| 状态保存 | `context/autopilot-state.md` | PreCompact Hook 写入 | PASS |
| 配置文件 | `.claude/autopilot.config.yaml` | Phase 0 读取/生成 | PASS |
| 锚定 Commit | git empty commit | Phase 0 Step 10 创建 | PASS |
| .gitignore | 项目根 | Phase 0 Step 8 追加 `.autopilot-active` | PASS |

**Checkpoint 写入流程**: 统一调度模板 Step 5+7 使用后台 Agent 执行 Write + git fixup commit，避免主窗口上下文污染。后台 Agent 返回 checkpoint 文件名和 commit SHA。验证通过。

### 3.4 发现的问题

**[P2-F1] `validate-json-envelope.sh` 与 `post-task-validator.sh` 功能重叠**

`hooks.json` 中 PostToolUse(Task) 只注册了 `post-task-validator.sh`，但 `validate-json-envelope.sh` 和 `anti-rationalization-check.sh` 作为独立脚本依然存在于 scripts/ 目录中。`post-task-validator.py` 已将这 5 个验证器合并为一个 Python 进程。这些遗留脚本不会被执行但可能造成维护困惑。

**建议**: 在遗留脚本头部添加 `# DEPRECATED: Merged into post-task-validator.sh (v4.0)` 注释，或移入 `scripts/_deprecated/` 目录。

**[P2-F2] Phase 4 特殊门禁: `test_pyramid.unit_pct` 阈值在 L2 和 L3 不一致**

- L2 Hook (`post-task-validator.py` 第 166 行): `FLOOR_MIN_UNIT_PCT = 30`（Hook 底线）
- L3 Gate (`autopilot-gate` SKILL.md + `protocol.md`): `unit_pct >= 50%`（配置阈值）
- 这是设计意图（L2 宽松底线 + L3 严格阈值），但文档中未明确说明这一分层策略。

**建议**: 在 `protocol.md` 特殊门禁章节添加注释，说明 L2 Hook 使用宽松底线而 L3 使用配置阈值的分层设计。

---

## 4. Lite 模式审计结果

### 4.1 状态机流转分析

**预期流转**: Phase 0 -> 1 -> 5 -> 6 -> 7（跳过 Phase 2/3/4）

| 转换点 | 控制机制 | 验证结果 |
|--------|---------|---------|
| 0 -> 1 | Phase 0 输出 recovery_phase=1 | PASS |
| 1 -> 5 | Gate 模式感知: Phase 1 checkpoint 即可 | PASS |
| 5 -> 6 | Gate 8步 + 特殊门禁(zero_skip/tasks完成) | PASS |
| 6 -> 7 | Gate 8步 + checkpoint(phase-6) | PASS |

**Phase 0 TaskCreate 链验证**: lite 模式创建 Phase 1/5/6/7 共 4 个任务，Phase 5 blockedBy Phase 1，Phase 6 blockedBy Phase 5。验证通过。

**跳过阶段阻断验证**:
- `check-predecessor-checkpoint.sh` 第 253-257 行: Phase 2 在 lite 模式下直接 deny
- 第 269-273 行: Phase 3/4 在非 full 模式下直接 deny
- `get_predecessor_phase` lite 分支: Phase 5 返回 1，Phase 6 返回 5，Phase 7 返回 6
- **结论**: 跳过阶段的 dispatch 被 Hook 确定性阻断，无绕过可能

### 4.2 Gate 系统有效性

**Layer 1**: 4 个任务的 blockedBy 链正确（Phase 2/3/4 未创建任务，不存在于依赖链中）

**Layer 2**: `check-predecessor-checkpoint.sh` 的 `get_predecessor_phase` 函数对 lite 模式有独立 case 分支:
```
5) echo 1 ;;  # Phase 5 前置为 Phase 1（跳过 2/3/4）
6) echo 5 ;;  # Phase 6 前置为 Phase 5
7) echo 6 ;;  # Phase 7 前置为 Phase 6
```
验证通过。

**Layer 3**: `autopilot-gate` SKILL.md 模式对门禁影响表明确：Phase 1->2、2->3、3->4、4->5 门禁均标记为 "跳过"。Phase 1->5 门禁仅需 Phase 1 checkpoint。

**三层一致性**: 通过。

### 4.3 文件 IO 完整性

| 文件类型 | 差异点 | 验证结果 |
|---------|--------|---------|
| Checkpoint | 仅生成 phase-1/5/6/7 四个 checkpoint 文件 | PASS |
| 任务来源 | Phase 5 从 phase-1-requirements.json 自动拆分为 context/phase5-task-breakdown.md | PASS |
| tasks.md | 不存在（full 模式由 Phase 3 生成），使用 phase5-task-breakdown.md 替代 | PASS |
| OpenSpec 归档 | Phase 7 Step 4c: lite 模式跳过 OpenSpec 归档，仅做 git squash | PASS |

**Phase 6 特殊门禁中的 tasks 文件检测**:
`check-predecessor-checkpoint.sh` 第 364-379 行同时检查 `tasks.md` 和 `context/phase5-task-breakdown.md`，确保 lite 模式下也能正确验证任务完成度。验证通过。

### 4.4 发现的问题

**[P1-L1] lite 模式 Phase 5 任务拆分缺乏确定性保障**

lite 模式下 Phase 5 启动时从 `phase-1-requirements.json` 自动拆分为 `context/phase5-task-breakdown.md`。这个拆分过程是 AI 驱动的（由主编排器或 Phase 5 子 Agent 执行），而非确定性脚本。如果拆分质量不佳或缺失，Phase 5 将缺少任务清单。

- SKILL.md 中声明 "Phase 5 启动时从 phase-1-requirements.json 自动拆分"，但未定义拆分失败时的回退策略
- Hook 层不验证 `phase5-task-breakdown.md` 是否存在（仅在 Phase 6 门禁时验证完成度）

**建议**: 在 Phase 5 dispatch 模板中添加前置校验——检查 `phase5-task-breakdown.md` 是否已生成，若未生成则阻断并提示。或在 `autopilot-gate` Phase 1->5 门禁中增加此检查。

**[P2-L2] lite 模式 Summary Box 未展示跳过阶段说明**

Phase 7 Summary Box "仅展示实际执行的阶段"，但未向用户说明为何跳过了 Phase 2/3/4。对于首次使用 lite 模式的用户可能造成困惑。

**建议**: 在 Summary Box 中添加一行 `Mode: lite (Phase 2/3/4 skipped)` 说明。

---

## 5. Minimal 模式审计结果

### 5.1 状态机流转分析

**预期流转**: Phase 0 -> 1 -> 5 -> 7（跳过 Phase 2/3/4/6）

| 转换点 | 控制机制 | 验证结果 |
|--------|---------|---------|
| 0 -> 1 | Phase 0 输出 recovery_phase=1 | PASS |
| 1 -> 5 | Gate 模式感知: Phase 1 checkpoint 即可 | PASS |
| 5 -> 7 | Gate 模式感知: Phase 5 checkpoint 即可 | PASS |

**Phase 0 TaskCreate 链验证**: minimal 模式创建 Phase 1/5/7 共 3 个任务，Phase 5 blockedBy Phase 1。验证通过。

**跳过阶段阻断验证**:
- Phase 2/3/4: 同 lite 模式，被 Hook 确定性阻断
- Phase 6: `check-predecessor-checkpoint.sh` 第 341-343 行明确阻断 minimal 模式下的 Phase 6 dispatch
- `get_predecessor_phase` minimal 分支: Phase 5 返回 1，Phase 7 返回 5

### 5.2 Gate 系统有效性

**Layer 1**: 3 个任务的 blockedBy 链正确

**Layer 2**: `get_predecessor_phase` minimal 分支:
```
5) echo 1 ;;  # Phase 5 前置为 Phase 1
7) echo 5 ;;  # Phase 7 前置为 Phase 5（跳过 Phase 6）
```

**关键验证**: Phase 7 在 minimal 模式下的前置为 Phase 5（非 Phase 6）。`check-predecessor-checkpoint.sh` 第 276-284 行的通用顺序检查使用 `get_predecessor_phase` 返回值，因此 Phase 7 会检查 Phase 5 checkpoint 而非 Phase 6。验证通过。

**Layer 3**: `autopilot-gate` SKILL.md 的模式表明确: Phase 5->6 和 Phase 6->7 门禁在 minimal 模式下均标记为 "跳过"。

**三层一致性**: 通过。

### 5.3 文件 IO 完整性

| 文件类型 | 差异点 | 验证结果 |
|---------|--------|---------|
| Checkpoint | 仅生成 phase-1/5/7 三个 checkpoint 文件 | PASS |
| Phase 6 结果 | 不存在。Phase 7 Step 1 中子 Agent 检测到缺失则跳过测试报告部分 | PASS |
| Phase 7 三路收集 | Step 2 标注 "minimal 模式跳过此步骤" | PASS |
| 归档 | 同 lite: 跳过 OpenSpec 归档，仅做 git squash | PASS |

### 5.4 发现的问题

**[P1-M1] minimal 模式无测试验证即进入归档**

minimal 模式跳过 Phase 4（测试设计）和 Phase 6（测试报告），Phase 5 虽然执行实施但其门禁（Phase 5->7）不包含 zero_skip_check 验证。这意味着代码可能在没有任何测试通过验证的情况下进入归档。

- Phase 5->6 特殊门禁要求 zero_skip_check，但 minimal 模式跳过 Phase 6 所以不触发此门禁
- Phase 5->7 在 minimal 模式下仅检查 Phase 5 checkpoint 存在且 status=ok，不验证测试通过

**SKILL.md 设计意图**: "minimal 适用于极简需求，跳过规范和测试报告"。这是有意的设计选择，但存在质量风险。

**建议**: 在 minimal 模式文档中添加明确的风险警示，或在 autopilot-gate 的 Phase 5->7 门禁中增加可配置的最低测试通过率检查（即使在 minimal 模式下也验证 Phase 5 的 zero_skip_check）。

**[P2-M2] minimal 模式 `get_predecessor_phase` 的 fallback 分支不安全**

`check-predecessor-checkpoint.sh` 第 234-236 行:
```bash
minimal)
  case "$target" in
    5) echo 1 ;;
    7) echo 5 ;;
    *) echo $((target - 1)) ;;  # fallback
  esac
```

对于 minimal 模式，只有 Phase 1/5/7 应该被 dispatch。如果意外 dispatch Phase 2（target=2），fallback 返回 `$((2-1))=1`，即检查 Phase 1 checkpoint。如果 Phase 1 已完成，此检查会通过——但上方第 269-273 行的独立检查会拦截 Phase 3/4（`if [ "$EXEC_MODE" != "full" ]; then deny`），Phase 2 也有类似检查（第 253-257 行）。因此 fallback 不会被实际触达，但其逻辑在语义上不正确。

**建议**: 将 `*) echo $((target - 1))` 改为 `*) echo 0`（或直接 deny），使 fallback 行为更安全。当前虽然上游有独立检查保护，但防御性编程应消除此隐患。

---

## 6. Crash Recovery 审计

### 6.1 恢复流程验证

**autopilot-recovery SKILL.md 恢复协议**:

| 步骤 | 逻辑 | 验证结果 |
|------|------|---------|
| 1. 扫描 Checkpoint | `ls openspec/changes/*/context/phase-results/*.json` | PASS |
| 2. 选择目标 Change | 单个自动选中，多个 AskUserQuestion | PASS |
| 3. 确定最后完成阶段 | 按序扫描 phase-1 到 phase-7 | PASS |
| 4. 用户决策 | 从断点继续或从头开始 | PASS |
| 5. Mode 恢复 | 从锁文件读取 mode 字段 | PASS |

**模式感知恢复**:
- 锁文件包含 `mode` 字段，恢复时读取并传递给主线程
- Task 系统重建按模式创建正确的任务链（full 7个，lite 4个，minimal 3个）
- 已完成阶段直接标记 completed

### 6.2 Phase 5 细粒度恢复

Phase 5 的 task 级 checkpoint 存储在 `phase-results/phase5-tasks/task-N.json`，恢复时:
- 扫描所有 `task-*.json`
- 找到第一个非 "ok" 的 task
- 非连续恢复约束：不跳过失败的 task

**TDD 恢复逻辑**:
- 检查 `tdd_cycle` 字段确定每个 task 的 TDD 阶段
- 支持从 RED/GREEN/REFACTOR 任意阶段恢复
- GREEN/REFACTOR 恢复时验证测试文件存在

### 6.3 上下文压缩恢复

**PreCompact Hook** (`save-state-before-compact.sh`):
- 扫描所有 checkpoint，生成 `autopilot-state.md`
- 包含: change_name、last_completed_phase、next_phase、execution_mode、anchor_sha、tasks_progress、Phase 5 task 详情
- 包含恢复指令

**SessionStart(compact) Hook** (`reinject-state-after-compact.sh`):
- 优先从锁文件定位活跃 change，回退到 mtime 搜索
- 输出 `=== AUTOPILOT STATE RESTORED ===` 标记
- 主线程收到标记后按 guardrails.md 恢复协议继续

### 6.4 发现的问题

**[P1-R1] 崩溃恢复时 anchor_sha 可能丢失导致 autosquash 失败**

Phase 0 Step 9 创建锁文件时 `anchor_sha` 为空字符串，Step 10 创建锚定 commit 后更新。如果在 Step 9 和 Step 10 之间崩溃:
- 锁文件存在但 `anchor_sha` 为空
- 恢复时 `autopilot-recovery` 不检查 `anchor_sha` 有效性
- Phase 7 autosquash 前验证 `anchor_sha` 非空且有效（Phase 7 Step 4b），无效则跳过 autosquash 并警告

虽然 Phase 7 有保护性检查，但整个流程期间所有 fixup commit 都依赖 `ANCHOR_SHA`。如果 anchor_sha 为空但流程继续，Phase 1-6 的 checkpoint Agent 会执行 `git commit --fixup=`（空 SHA），导致 git 命令失败。

**Phase 0 SKILL.md** 第 121 行声明: "如果 Step 10 之前崩溃，恢复时检测到 anchor_sha 为空 -> 重新创建锚定 commit 并更新"。但 `autopilot-recovery` SKILL.md 中没有对应的 anchor_sha 校验步骤。

**建议**: 在 `autopilot-recovery` SKILL.md 的恢复流程第 5 步后，添加 anchor_sha 有效性检查：如果为空或 `git rev-parse` 失败，重新创建锚定 commit。

**[P2-R2] `scan-checkpoints-on-start.sh` 不感知执行模式**

SessionStart Hook 扫描 checkpoint 时，对所有 change 按 phase-1 到 phase-7 线性展示，不感知该 change 使用的模式。在 lite/minimal 模式下，"Suggested resume: Phase 2"（在 Phase 1 完成后）是错误的——应建议 Phase 5。

**建议**: 读取锁文件的 mode 字段，按模式计算正确的 suggested resume phase。

---

## 7. 跨阶段数据传递风险分析

### 7.1 数据流图

```
Phase 0 ──> mode, session_id, ANCHOR_SHA, config
              │
Phase 1 ──> phase-1-requirements.json (requirements_summary, decisions, change_name, complexity)
              │
         ┌────┤ [full only]
         │    │
Phase 2 ──> phase-2-openspec.json + OpenSpec 目录结构
Phase 3 ──> phase-3-ff.json + proposal/design/specs/tasks.md
Phase 4 ──> phase-4-testing.json (test_counts, dry_run_results, test_pyramid, change_coverage)
         │    │
         └────┤
              │
Phase 5 ──> phase-5-implement.json (test_results_path, tasks_completed, zero_skip_check)
         │   + phase5-tasks/task-N.json
         │
Phase 6 ──> phase-6-report.json (pass_rate, report_path, report_format)  [not minimal]
              │
Phase 7 ──> phase-7-summary.json + 归档
```

### 7.2 关键数据传递点

| 传递路径 | 数据 | 传递机制 | 风险评估 |
|---------|------|---------|---------|
| Phase 0 -> 全局 | ANCHOR_SHA | 主线程变量 + 锁文件 | 低（Phase 7 有验证） |
| Phase 0 -> 全局 | config | 主线程变量 | 低（Phase 0 校验完整性） |
| Phase 0 -> 全局 | mode | 主线程变量 + 锁文件 | 低（锁文件持久化） |
| Phase 1 -> Phase 2-7 | change_name | checkpoint JSON + 锁文件 | 低 |
| Phase 1 -> Phase 5 (lite/minimal) | 任务清单 | phase-1-requirements.json -> 自动拆分 | **中**（见 P1-L1） |
| Phase 1 -> Phase 2-6 | context/ 文件 | 子 Agent 直接 Read 磁盘文件 | 低 |
| Phase 3 -> Phase 4/5 | tasks.md | 磁盘文件 | 低 |
| Phase 4 -> Phase 5 | 测试文件 | 磁盘文件 | 低 |
| Phase 5 -> Phase 6 | test-results.json | 磁盘文件 + checkpoint | 低 |
| Phase 5 -> Phase 7 | 实施代码 | git commits | 低 |

### 7.3 跨阶段断裂风险

**风险 1: 子 Agent 上下文隔离导致信息丢失**（低风险）

子 Agent 通过 Task 工具派发，其内部上下文不返回主线程。关键信息通过 JSON 信封的 summary 字段精简传递。子 Agent 的详细产出写入磁盘文件（context/ 目录），后续阶段的子 Agent 直接 Read 这些文件。

**缓解措施**:
- JSON 信封契约保证最低必要信息传递
- Hook 层验证信封完整性（Validator 1）
- 磁盘文件作为持久化传递通道

**风险 2: 后台 Agent 的 L2 验证空白**（已知设计权衡）

`check-predecessor-checkpoint.sh` 第 49-59 行: `run_in_background: true` 的 Task 跳过所有 L2 检查。这影响 Phase 2/3/4(非并行)/6 路径 A。

**缓解措施**（已文档记录，第 53-56 行注释）:
- Layer 3 (autopilot-gate Skill) 在主线程 dispatch 前已执行完整验证
- 后台 Agent 在 launch 时 Hook 触发，但此时 Agent 尚未产出输出，L2 无法验证
- 这是架构限制的正确处理

**风险 3: 上下文压缩后编排状态部分丢失**（低风险）

`save-state-before-compact.sh` 保存状态到 `autopilot-state.md`，但不保存:
- 主线程中正在执行的 dispatch 中间状态
- 等待中的后台 Agent 引用

**缓解措施**:
- guardrails.md 恢复协议指示主线程从下一个未完成阶段重新执行
- Phase 5 task 级 checkpoint 确保不丢失已完成的 task

---

## 8. 综合评分 (1-10)

| 维度 | 分数 | 说明 |
|------|------|------|
| 状态机正确性 | 9.0 | 三种模式流转逻辑完全正确，分支覆盖全面 |
| Gate 系统有效性 | 8.5 | 三层防御纵深完备，后台 Agent 绕过有文档记录 |
| 文件 IO 完整性 | 8.5 | 读写路径清晰，目录创建有保障 |
| 崩溃恢复 | 7.5 | 整体完善但 anchor_sha 恢复有缺口 |
| 跨阶段数据传递 | 8.0 | 磁盘文件 + checkpoint 双通道，lite 模式任务拆分有隐患 |
| 代码质量 | 8.5 | 共享模块抽象良好，Hook 性能优化到位（5合1） |

**综合评分: 8.2/10**

---

## 9. 关键缺陷清单 (P0/P1/P2)

### P0 (阻断级) — 无

无 P0 缺陷。

### P1 (重要级)

| 编号 | 描述 | 影响模式 | 位置 |
|------|------|---------|------|
| P1-L1 | lite/minimal 模式 Phase 5 任务拆分缺乏确定性保障，无 Hook 层前置验证 | lite, minimal | `SKILL.md` Phase 5 任务来源章节 |
| P1-M1 | minimal 模式无测试验证即进入归档，Phase 5->7 门禁不含 zero_skip_check | minimal | `check-predecessor-checkpoint.sh`, `autopilot-gate` SKILL.md |
| P1-R1 | 崩溃恢复时 anchor_sha 为空的处理逻辑在 recovery Skill 中缺失 | 全模式 | `autopilot-recovery` SKILL.md |

### P2 (建议级)

| 编号 | 描述 | 影响模式 | 位置 |
|------|------|---------|------|
| P2-F1 | `validate-json-envelope.sh` 等遗留脚本与 `post-task-validator.sh` 功能重叠 | 全模式 | `scripts/` 目录 |
| P2-F2 | L2/L3 test_pyramid 阈值分层设计未在 protocol.md 中说明 | full | `protocol.md` |
| P2-L2 | lite 模式 Summary Box 未展示跳过阶段说明 | lite | `autopilot-phase7` SKILL.md |
| P2-M2 | minimal 模式 `get_predecessor_phase` fallback 分支语义不安全 | minimal | `check-predecessor-checkpoint.sh` 第 234-236 行 |
| P2-R2 | `scan-checkpoints-on-start.sh` 不感知执行模式，suggested resume 可能错误 | lite, minimal | `scripts/scan-checkpoints-on-start.sh` |

---

## 10. 改进建议

### 10.1 高优先级（建议 v4.1 实施）

1. **P1-L1 修复**: 在 `autopilot-gate` 的 Phase 1->5 门禁（lite/minimal 模式）中增加检查——验证 Phase 5 子 Agent dispatch 前 `phase5-task-breakdown.md` 已生成，或在 Phase 5 dispatch 模板中添加前置生成 + 验证步骤。

2. **P1-M1 修复**: 提供两种策略（二选一）:
   - **策略 A**: 在 minimal 模式的 Phase 5->7 门禁中添加可配置的 `minimal_zero_skip_check`（默认 true），验证 Phase 5 checkpoint 的 `zero_skip_check.passed`
   - **策略 B**: 在文档中添加明确的质量风险警示，并在 Phase 7 Summary Box 中标注 "Testing: skipped (minimal mode)"

3. **P1-R1 修复**: 在 `autopilot-recovery` SKILL.md 的恢复流程末尾（Step 5 之后）添加:
   ```
   ### 6. Anchor SHA 验证
   从锁文件读取 anchor_sha:
   - 空字符串 → 创建新锚定 commit 并更新锁文件
   - 非空但 git rev-parse 失败 → 创建新锚定 commit 并更新锁文件
   - 有效 → 继续使用
   ```

### 10.2 中优先级（建议 v4.2 实施）

4. **P2-M2 修复**: 将 `get_predecessor_phase` 各模式的 `*) echo $((target - 1))` fallback 改为 `*) echo 0`，使非法阶段的前置检查必然失败。

5. **P2-R2 修复**: 在 `scan-checkpoints-on-start.sh` 中读取锁文件 mode 字段，使用模式感知的 next-phase 计算:
   ```bash
   case "$mode" in
     lite) phases_sequence=(1 5 6 7) ;;
     minimal) phases_sequence=(1 5 7) ;;
     *) phases_sequence=(1 2 3 4 5 6 7) ;;
   esac
   ```

6. **P2-F1 修复**: 在 `validate-json-envelope.sh`、`anti-rationalization-check.sh` 等已合并的独立脚本头部添加 deprecation 注释。

### 10.3 低优先级（建议长期维护）

7. 考虑将 `check-predecessor-checkpoint.sh` 也迁移到 Python 统一入口（类似 PostToolUse 的 5合1 方案），进一步减少 PreToolUse Hook 的 shell+python3 混合调用开销。

8. 为 Hook 脚本添加集成测试（模拟 JSON stdin 输入，验证各模式下的 allow/deny 输出），确保版本迭代不引入回归。
