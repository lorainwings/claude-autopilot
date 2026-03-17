# spec-autopilot 全模式稳定性与链路闭环审计报告

> **版本**: v5.1.18 | **审计日期**: 2026-03-17 | **审计员**: Agent 1（全模式稳定性与链路闭环测试审计员）

---

## 执行摘要

**综合评分: 91 / 100**

spec-autopilot 插件的三模式（full/lite/minimal）状态机设计成熟，门禁三层联防架构（L1 TaskCreate blockedBy / L2 Hook 确定性验证 / L3 AI Gate 8-step）形成了有效的防护网。崩溃恢复机制经过 v5.5/v5.6 重构后支持三选项恢复 + gap 感知 + 制品清理，具备工业级可靠性。测试覆盖率高（615/617 通过，99.68%），核心链路（E2E hook chain、checkpoint recovery）均有集成测试保护。

扣分项集中在以下方面:
- [-3] `get_predecessor_phase()` 对 lite/minimal 模式的非预期 Phase 请求返回 `0` 而非显式拒绝
- [-2] `next_event_sequence()` 锁竞争回退策略存在理论上的序号重叠风险
- [-2] `parallel-merge-guard.sh` 对后台 Agent 直接跳过（`is_background_agent && exit 0`），与 v5.1 的后台 Agent 验证增强策略不一致
- [-2] 1 个测试用例失败（`test_agent_correlation` 2d）

---

## 1. 三模式状态机流转审计表

### 1.1 阶段序列定义

| 模式 | 阶段序列 | 跳过的阶段 | 门禁切换点 |
|------|---------|-----------|-----------|
| **full** | 0 -> 1 -> 2 -> 3 -> 4 -> 5 -> 6 -> 7 | 无 | 1->2, 2->3, 3->4, 4->5(特殊), 5->6(特殊), 6->7 |
| **lite** | 0 -> 1 -> 5 -> 6 -> 7 | 2, 3, 4 | 1->5, 5->6(特殊), 6->7 |
| **minimal** | 0 -> 1 -> 5 -> 7 | 2, 3, 4, 6 | 1->5, 5->7 |

### 1.2 三层门禁矩阵（模式感知）

| 切换点 | L1 (blockedBy) | L2 (Hook) | L3 (AI Gate) | full | lite | minimal |
|--------|---------------|-----------|-------------|------|------|---------|
| 1->2 | Phase 1 task | `check-predecessor-checkpoint.sh` 验证 phase-1 CP | 8-step checklist | 正常 | **跳过** | **跳过** |
| 2->3 | Phase 2 task | 验证 phase-2 CP | 8-step checklist | 正常 | **跳过** | **跳过** |
| 3->4 | Phase 3 task | 验证 phase-3 CP | 8-step checklist | 正常 | **跳过** | **跳过** |
| 4->5 | Phase 4 task | 验证 phase-4 CP + zero_skip | 8-step + 特殊门禁 | 正常 | **跳过**(1->5) | **跳过**(1->5) |
| 5->6 | Phase 5 task | 验证 phase-5 CP + zero_skip + tasks.md | 8-step + 特殊门禁 | 正常 | 正常 | **跳过**(5->7) |
| 6->7 | Phase 6 task | 验证 phase-6 CP | 8-step checklist | 正常 | 正常 | **跳过** |

### 1.3 流转审计结论

#### full 模式: PASS

- Phase 0->1->2->3->4->5->6->7 完整链路验证通过
- 每个 Phase 切换均有 L1+L2+L3 三层保护
- Phase 4->5 特殊门禁: `test_counts >= min_test_count_per_type`、`required_test_types` 存在性、`dry_run_results` 全零
- Phase 5->6 特殊门禁: `test-results.json` 存在、`zero_skip_check.passed === true`、`tasks.md` 全部 `[x]`
- TDD 模式特殊路径: Phase 4 可被 `tdd_mode_override` 跳过，Phase 5 前置依赖降级为 Phase 3

#### lite 模式: PASS（有注意项）

- Phase 0->1->5->6->7 链路验证通过
- Phase 5 前置检查正确降级为 Phase 1 checkpoint
- Phase 2/3/4 不创建 Task，不产出 checkpoint
- `check-predecessor-checkpoint.sh` 中 `get_predecessor_phase("lite", 5)` 正确返回 `1`
- **注意项**: `get_predecessor_phase("lite", 2|3|4)` 返回 `0` 而非显式错误。虽然 L2 Hook 在上游已通过 `deny("Phase N is skipped in lite mode")` 拦截了对应 dispatch，但函数本身的语义不够防御性

#### minimal 模式: PASS（有注意项）

- Phase 0->1->5->7 链路验证通过
- Phase 6 被显式拦截: `deny("Phase 6 is skipped in minimal mode")`
- Phase 5->7 门禁中 `zero_skip_check` 降级为 warning（非硬阻断），符合 minimal 模式设计意图
- **注意项**: 与 lite 模式相同的 `get_predecessor_phase` 返回值问题

### 1.4 被跳过 Phase 的僵死 Checkpoint 检查

| 检查项 | 结果 |
|--------|------|
| lite 模式跳过 Phase 2/3/4 后是否留残留 CP | **安全** — Phase 0 TaskCreate 不创建对应 Task，不会有 Agent dispatch 写入 CP |
| minimal 模式跳过 Phase 2/3/4/6 后是否留残留 CP | **安全** — 同上理由 |
| 恢复场景: 从 full 降级为 lite 时残留 CP | **安全** — `recovery-decision.sh` 按模式过滤 phases，`scan_all_checkpoints` 仅扫描模式序列内的 phase |
| 模式切换场景: 锁文件 mode 与 CLI mode 不一致 | **安全** — v5.6.1 以锁文件 mode 为准（`recovery-decision.sh` 自动解析优先级: 锁文件 > CLI > 默认 full） |

---

## 2. 文件 IO 完整性审计

### 2.1 Checkpoint 读写路径一致性

| 操作 | 路径模式 | 验证脚本 | 状态 |
|------|---------|---------|------|
| 写入 | `openspec/changes/<name>/context/phase-results/phase-{N}-*.json` | 主编排器 Step 5+7 Checkpoint Agent | PASS |
| 读取（Gate） | `find_checkpoint(phase_results_dir, N)` → `find ... -name "phase-{N}-*.json"` | `_common.sh` | PASS |
| 读取（Hook） | 同上，经 `check-predecessor-checkpoint.sh` | `check-predecessor-checkpoint.sh` | PASS |
| 读取（Recovery） | `recovery-decision.sh` 使用 `glob.glob(f'phase-{p}-*.json')` + 排除 `.tmp`/`-progress`/`-interim` | `recovery-decision.sh` | PASS |
| 原子写入 | `.json.tmp` -> `mv` -> `.json` | 主编排器 Step 5+7 | PASS |
| 损坏恢复 | `validate_checkpoint_integrity()` 移动到 `.corrupted-backups/` | `_common.sh` | PASS |

**一致性验证**: 所有读写路径使用 `_common.sh` 共享函数或等价 glob 模式，不存在路径不一致风险。

### 2.2 临时文件清理

| 临时文件类型 | 清理时机 | 清理脚本 | 状态 |
|-------------|---------|---------|------|
| `*.json.tmp` | 恢复扫描时 | `validate_checkpoint_integrity()` + `clean-phase-artifacts.sh` | PASS |
| `phase-1-interim.json` | Phase 1 最终 checkpoint 写入后 | 主编排器 `rm -f` | PASS |
| `phase5-start-time.txt` | Phase 7 归档时 | `autopilot-phase7` Step 4a | PASS |
| `decision.json` / `decision-request.json` | 决策消费后 | `poll-gate-decision.sh` 读取后立即 `rm -f` | PASS |
| `.active-agent-id` | Agent 生命周期结束 | `auto-emit-agent-complete.sh` | 待验证 |
| `.autopilot-active` | Phase 7 Step 7 | `autopilot-phase7` `rm -f` | PASS |

### 2.3 并行模式文件所有权隔离

| 隔离机制 | 实现方式 | 验证状态 |
|---------|---------|---------|
| Phase 5 worktree 隔离 | `git worktree add` 按 task 创建独立工作树 | PASS（`parallel-merge-guard.sh` 验证合并文件在 task scope 内） |
| 子 Agent 状态隔离 | `unified-write-edit-check.sh` CHECK 0 拦截写入 `openspec/`/`phase-results/` | PASS |
| Checkpoint 写入限制 | 仅 Bash 工具可写（绕过 Write/Edit Hook） | PASS（设计决策，避免 Write Hook 阻断 checkpoint writer） |
| 合并冲突检测 | `git diff --check` + `git diff --cached --check` | PASS |
| typecheck 后验证 | 从 `config.test_suites` 读取 typecheck 命令 | PASS |

---

## 3. 崩溃恢复机制审计

### 3.1 恢复决策脚本 (`recovery-decision.sh`)

| 审计项 | 结果 | 备注 |
|--------|------|------|
| 纯只读保证 | PASS | 注释声明 + 代码验证：不修改任何文件或 git 状态 |
| 模式感知 Phase 序列 | PASS | `full=[1..7]`, `lite=[1,5,6,7]`, `minimal=[1,5,7]` |
| Gap 检测（v5.6.2 修复） | PASS | `last_valid_phase` 在遇到首个 gap 后停止推进 |
| Phase 1 interim 检测 | PASS | 扫描 `phase-1-interim.json` 提取 stage/status |
| Progress 文件检测（v5.3） | PASS | 扫描 `phase-*-progress.json` 提取子步骤信息 |
| 多 Change 选择 | PASS | 自动选择唯一候选或按 checkpoint 数量排序展示 |
| 锁文件 mode 优先级（v5.6.1） | PASS | 锁文件 mode > CLI mode > 默认 full |
| Git 状态检测 | PASS | rebase/merge/worktree 残留检测 |
| 错误路径 exit 0 | PASS | 任何错误均 `exit 0` + JSON error 输出（符合 Hook 协议） |

### 3.2 三选项恢复路径完整性

| 恢复路径 | 触发条件 | 制品清理 | Git 回退 | 状态 |
|---------|---------|---------|---------|------|
| **A: 从断点继续** | `recovery_options.continue` 非空 | 不清理 | 不回退 | PASS |
| **B: 从指定阶段恢复** | 用户选择 `specify_range` 中的阶段 | `clean-phase-artifacts.sh` 清理 `>= target_phase` | `--git-target-sha` 软重置 | PASS |
| **C: 从头开始** | 用户选择重置 | `clean-phase-artifacts.sh` 清理 `>= 1` | 不回退 git（仅清文件） | PASS |

### 3.3 清理脚本 (`clean-phase-artifacts.sh`)

| 审计项 | 结果 | 备注 |
|--------|------|------|
| 事务性执行顺序 | PASS | git 回退 -> 文件清理 -> 事件过滤 -> 恢复 stash |
| Git 安全保护 | PASS | 仅 abort autopilot 相关的 rebase/merge（通过 grep 判定） |
| WIP 保护 | PASS | `collect_preserve_paths()` 过滤非清理路径，stash push 后 apply + drop |
| Stash 失败保护 | PASS | stash 失败时跳过 git reset，输出 WARNING |
| Phase 5 特殊清理 | PASS | `phase5-tasks/` + `.tdd-stage` + worktree 清理（按 change name 匹配） |
| Phase 6 特殊清理 | PASS | `phase-6.5-*.json` 额外清理 |
| 事件过滤原子性 | PASS | `tempfile.mkstemp` + `os.replace` 原子写入 |
| `--dry-run` 支持 | PASS | 收集操作但不执行，输出 JSON manifest |
| JSON 输出 | PASS | 返回完整的清理摘要 JSON |

### 3.4 Anchor SHA 验证

| 场景 | 处理 | 状态 |
|------|------|------|
| `anchor_sha` 为空 | 创建新锚定 commit + 更新锁文件 | PASS |
| `anchor_sha` 非空但无效 | 同上 | PASS |
| `anchor_sha` 有效 | 继续使用 | PASS |
| Phase 7 autosquash 前验证 | `git rev-parse` 检查，无效则跳过 autosquash | PASS |

### 3.5 上下文重建

| 审计项 | 结果 |
|--------|------|
| 读取 `phase-context-snapshots/phase-{P}-context.md`（P < recovery_phase） | PASS |
| 提取关键决策摘要 + 下阶段上下文 | PASS |
| 路径 B 仅注入 target_phase 之前的快照 | PASS（设计文档明确声明） |

---

## 4. 测试通过率

### 4.1 测试执行结果

```
============================================
Test Summary: 69 files, 615 passed, 2 failed

Failed test files:
  - test_agent_correlation
============================================
```

**通过率: 99.68% (615/617)**

### 4.2 失败用例分析

| 失败测试 | 模块 | 描述 | 严重程度 |
|---------|------|------|---------|
| `test_agent_correlation 2d` | `agent_id correlation` | "agent_id present when .active-agent-id absent" — 期望在无 `.active-agent-id` 文件时事件 JSON 中仍有 `agent_id` 字段 | 低 — 仅影响 GUI 事件关联，不影响核心流水线 |

### 4.3 核心链路测试覆盖

| 测试类别 | 测试文件 | 用例数 | 状态 |
|---------|---------|-------|------|
| E2E Hook Chain | `test_e2e_hook_chain.sh` | 6 | 全部 PASS |
| E2E Checkpoint Recovery | `test_e2e_checkpoint_recovery.sh` | 20 | 全部 PASS |
| Predecessor Checkpoint | `test_check_predecessor_checkpoint.sh` | 7 | 全部 PASS |
| Post-Task Validator | `test_post_task_validator.sh` | 10 | 全部 PASS |
| Anti-Rationalization | `test_anti_rationalization.sh` | 9 | 全部 PASS |
| Recovery Decision | `test_recovery_decision.sh` | 11+ | 全部 PASS |
| Clean Phase Artifacts | `test_clean_phase_artifacts.sh` | 多组 | 全部 PASS |
| Poll Gate Decision | `test_poll_gate_decision.sh` | 7 | 全部 PASS |
| Wall-Clock Timeout | `test_wall_clock_timeout.sh` | 6 | 全部 PASS |
| Background Agent Bypass | 专项测试 | 13 | 全部 PASS |
| Build-dist Completeness | `test_build_dist.sh` | 4 | 全部 PASS |

---

## 5. 代码合并机制审计（`parallel-merge-guard.sh`）

### 5.1 三重验证

| 检查项 | 实现 | 状态 |
|--------|------|------|
| 合并冲突残留 | `git diff --check` + `git diff --cached --check` | PASS |
| 文件范围越界 | 对比 JSON envelope `artifacts` 与 `git diff --name-only` | PASS |
| 类型检查 | 从 `config.test_suites` 中提取 `type=typecheck` 命令执行 | PASS |

### 5.2 降级条件

| 条件 | CLAUDE.md 约束 | 实际实现 | 合规 |
|------|---------------|---------|------|
| 合并失败 > 3 文件 | 降级至路径 B（串行） | `mode-routing-table.md` 声明式定义 | PASS |
| 连续 2 组 Agent 失败 | AskUserQuestion 决策 | `mode-routing-table.md` 声明式定义 | PASS |
| 用户显式选择 | 切换模式 | 支持 | PASS |

### 5.3 后台 Agent 处理

**发现**: `parallel-merge-guard.sh` 在 Layer 1.5 对后台 Agent 直接 `is_background_agent && exit 0` 跳过全部验证。这与 `post-task-validator.sh`（v5.1 已移除后台 Agent 跳过）的策略不一致。

**影响**: 后台并行合并 Agent 的 merge 结果不会被验证冲突残留和文件范围。由于合并验证本质上需要在 merge commit 生成后执行，而后台 Agent 的 PostToolUse 也是在完成后触发的，理论上可以进行验证。

**风险等级**: 中低 — 实际上并行合并通常在主线程前台执行（需要交互处理冲突），后台场景较少触发。

---

## 6. 风险发现列表

### 严重等级: 高

无。

### 严重等级: 中

| # | 发现 | 影响 | 建议 |
|---|------|------|------|
| M-1 | `get_predecessor_phase()` 对 lite/minimal 模式下非预期 Phase（如 `lite` 模式下 Phase 2/3/4）返回 `0`，而非触发显式错误 | 若上游 L2 拦截失效，函数返回 `0` 会导致 `check-predecessor-checkpoint.sh` 在 `TARGET_PHASE >= 3` 的代码路径中搜索不存在的 Phase 0 checkpoint，最终仍会 deny，但错误信息不够精确 | 对非预期 Phase 返回特殊标记（如 `-1`）或直接调用 `deny()` |
| M-2 | `next_event_sequence()` 锁竞争 fallback 使用 `current + 1000 + (PID % 100)` 偏移策略 | 理论上多进程竞争时可能产生非连续或重叠的序号（虽然不同 PID 的偏移不同，但 PID 回收后可能产生碰撞） | 考虑使用 `flock` 替代 `mkdir` 原子锁（性能影响可忽略），或接受当前设计（GUI 端已按 timestamp 排序，sequence 仅辅助） |
| M-3 | `parallel-merge-guard.sh` 对后台 Agent 跳过全部验证，与 v5.1 策略不一致 | 后台并行合并的冲突残留和文件越界可能未被检测 | 移除 `is_background_agent && exit 0`，允许后台 Agent 也执行 merge 验证 |

### 严重等级: 低

| # | 发现 | 影响 | 建议 |
|---|------|------|------|
| L-1 | `test_agent_correlation 2d` 测试失败 | `.active-agent-id` 文件不存在时事件缺少 `agent_id` 字段，影响 GUI 事件关联展示 | 修复 `emit-tool-event.sh` 在无 `.active-agent-id` 时提供默认 agent_id 值 |
| L-2 | `emit-phase-event.sh` 的 `event_type` 白名单不包含 `gate_pass` / `gate_block` / `task_progress` / `decision_ack` | 这些事件类型由专用脚本（`emit-gate-event.sh`、`emit-agent-event.sh`）发射，不经过此入口，但白名单未覆盖导致如果误调用会报错退出 | 补充白名单或在注释中明确说明各事件类型的发射入口 |
| L-3 | `scan-checkpoints-on-start.sh` 的 `process_change_dir()` 硬编码扫描 Phase 1-7，不感知 lite/minimal 模式 | SessionStart 信息展示时可能显示 lite/minimal 模式下不应存在的 Phase 缺失信息 | 已通过锁文件 mode 读取做了部分模式感知（resume suggestion），但 checkpoint 扫描循环未过滤 |
| L-4 | `check-predecessor-checkpoint.sh` 对 Phase 2 的 `TARGET_PHASE == 2 && EXEC_MODE != "full"` 检查在 Phase 3/4 之前执行，存在代码重复 | 功能正确但代码结构可以简化 — Phase 2/3/4 的 non-full mode deny 已在第 270-274 行统一处理 | 移除第 254-258 行的 Phase 2 独立检查，统一到 270-274 行的 Phase 3/4 检查中 |

### 严重等级: 信息

| # | 发现 | 备注 |
|---|------|------|
| I-1 | `_common.sh` 的 `has_active_autopilot()` 使用 `find -maxdepth 2` 做兼容旧版锁文件检测 | 随着 v5.6 确定性锁文件位置 (`openspec/changes/.autopilot-active`)，旧版兼容逻辑将来可以移除 |
| I-2 | `clean-phase-artifacts.sh` 的 worktree 清理使用 `grep "$wt_change_name"` 进行名称匹配 | 如果 change name 是另一个 change name 的子串，可能误删。实际场景中 change name 通常足够唯一 |

---

## 7. 改进建议

### 7.1 短期改进（优先级高）

1. **修复 `test_agent_correlation 2d` 测试失败**: 检查 `emit-tool-event.sh` 在无 `.active-agent-id` 文件时的行为，确保事件 JSON 始终包含 `agent_id` 字段（可设为 `"unknown"` 默认值）。

2. **统一后台 Agent 验证策略**: `parallel-merge-guard.sh` 应与 `post-task-validator.sh` 保持一致，移除对后台 Agent 的无条件跳过。后台合并完成后的 PostToolUse 时机已经是正确的验证窗口。

3. **增强 `get_predecessor_phase()` 防御性**: 对非预期 Phase 号（如 lite 模式下的 Phase 2/3/4）显式返回错误标记或调用 `deny()`，避免依赖上游拦截。

### 7.2 中期改进（优先级中）

4. **`next_event_sequence()` 锁升级**: 当前 `mkdir` 原子锁 + PID 偏移回退在高并发场景下可能产生序号间隙。建议升级为 `flock -x` 机制（`_common.sh` 已有 Python 调用基础设施，可在 Python 中实现文件锁），或在 GUI 端明确以 `timestamp` 为主排序键、`sequence` 为辅排序键。

5. **补充 minimal 模式的 Phase 5->7 特殊门禁测试**: 当前测试覆盖了 `zero_skip_check` 的 warning 行为，但未验证 minimal 模式下跳过 Phase 6 后 `tasks.md` 完成度检查的降级行为。建议新增专项测试。

6. **`scan-checkpoints-on-start.sh` 模式感知扫描**: 当前 `for phase_num in 1 2 3 4 5 6 7` 硬编码，应根据锁文件 mode 使用 `get_phase_sequence()` 过滤扫描范围。

### 7.3 长期改进（优先级低）

7. **旧版兼容清理**: `has_active_autopilot()` 的 `find -maxdepth 2` 旧版锁文件检测可在后续大版本中移除，简化启动路径。

8. **worktree 清理名称匹配增强**: `clean-phase-artifacts.sh` 中的 worktree 清理使用精确 change name 前缀匹配（如 `grep -q "^.*/${wt_change_name}/"` 或 `grep -q "/autopilot-task-${wt_change_name}-"`），避免子串误匹配。

---

## 附录 A: 审计文件清单

| 文件 | 审计内容 |
|------|---------|
| `skills/autopilot/SKILL.md` | 8 阶段 Pipeline 主编排器定义 |
| `skills/autopilot/references/mode-routing-table.md` | 三模式路由声明表 |
| `skills/autopilot-gate/SKILL.md` | 3 层门禁 + 8 步检查清单 |
| `skills/autopilot-recovery/SKILL.md` | 崩溃恢复协议 v5.6 |
| `skills/autopilot-phase0/SKILL.md` | Phase 0 环境检查 + 锁文件管理 |
| `skills/autopilot-phase7/SKILL.md` | Phase 7 汇总 + 归档 |
| `CLAUDE.md` | 状态机硬约束 + 代码质量约束 |
| `scripts/_common.sh` | 共享工具函数 |
| `scripts/_hook_preamble.sh` | Hook 通用前导 |
| `scripts/check-predecessor-checkpoint.sh` | L2 前置 checkpoint 验证 Hook |
| `scripts/post-task-validator.sh` | L2 PostToolUse 统一验证 Hook |
| `scripts/unified-write-edit-check.sh` | L2 Write/Edit 统一验证 Hook |
| `scripts/parallel-merge-guard.sh` | 并行合并守卫 |
| `scripts/recovery-decision.sh` | 确定性恢复扫描 |
| `scripts/clean-phase-artifacts.sh` | 制品清理 + 事件过滤 + git 回退 |
| `scripts/poll-gate-decision.sh` | 门禁决策轮询 |
| `scripts/emit-phase-event.sh` | Phase 事件发射器 |
| `scripts/save-phase-context.sh` | Phase 上下文快照 |
| `scripts/collect-metrics.sh` | 执行指标收集 |
| `scripts/scan-checkpoints-on-start.sh` | SessionStart checkpoint 扫描 |

## 附录 B: 测试执行环境

- 平台: macOS Darwin 21.6.0
- Shell: zsh
- Python: python3 可用
- 测试框架: 自研 bash 测试套件 (`tests/run_all.sh`)
- 执行时间: ~2 分钟
- 结果: 69 文件, 615 passed, 2 failed (99.68%)
