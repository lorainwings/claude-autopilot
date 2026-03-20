# v5.0.4 稳定性审计报告

**插件**: spec-autopilot
**版本**: v5.0.4 (基于 v5.1 技术债务修复)
**审计日期**: 2026-03-13
**审计方**: Agent 1 — 全模式稳定性与链路闭环测试审计员 (Claude Opus 4.6)
**对比基线**: v5.0 稳定性审计报告 (`docs/reports/v5.0/stability-audit.md`)

---

## 1. 审计摘要

### 总分

| 审计维度 | 满分 | 得分 | 变化(vs v5.0) |
|---------|------|------|--------------|
| 状态机流转精准度 | 100 | 92 | +2 |
| Checkpoint 写入可靠性 | 100 | 88 | +23 |
| 3 层门禁联防 | 100 | 85 | +13 |
| 文件写入完整性 | 100 | 82 | 新维度 |
| 并行模式安全性 | 100 | 78 | +3 |
| Compact 恢复可靠性 | 100 | 85 | +15 |
| Hook 系统健壮性 | 100 | 79 | 新维度 |
| 事件发射一致性 | 100 | 74 | 新维度 |
| **加权总分** | **100** | **83** | **+7 (vs v5.0 的 76)** |

### 关键发现

| 严重度 | 数量 | 变化(vs v5.0) |
|--------|------|--------------|
| **Critical (致命)** | 1 | -1 (原 C-02 已修复) |
| **High (高危)** | 3 | -1 (原 H-01/H-02 已修复) |
| **Medium (中危)** | 5 | -1 |
| **Low (低危)** | 6 | +1 |
| **合计** | 15 | -2 |

**v5.1 关键改善**:
1. Checkpoint 原子写入 (.tmp -> rename) 已完整实现，消除了 v5.0 的 C-02 致命缺陷
2. 后台 Agent L2 验证已修复：PreToolUse 保留轻量级检查，PostToolUse 不再绕过
3. Phase 1 中间 Checkpoint 已实现（调研完成后 + 每轮决策后），消除了 v5.0 的 H-04
4. unified-write-edit-check.sh 统一替代 4 个独立脚本，子 Agent 状态隔离新增 L2 确定性阻断
5. TDD .tdd-stage 文件实现 RED/GREEN 写入隔离

**仍存在的关键问题**:
1. `check-predecessor-checkpoint.sh:289` 使用 `local` 关键字在函数外部（bash 语法错误）
2. `unified-write-edit-check.sh` Phase 5 检测逻辑在 full 模式 Phase 2/3 期间可能误判
3. 事件序列号 `next_event_sequence()` 存在 TOCTOU 竞态条件，文档声称线程安全但实际不是

---

## 2. 各维度详细评分与分析

### 2.1 状态机流转精准度 — 92/100

**Phase 顺序硬约束**

三层门禁在所有模式下均正确强制 Phase 顺序：

- **L1 (TaskCreate blockedBy)**: Phase 0 创建带依赖链的任务，由 Claude Code 任务系统自动强制。仅覆盖 Task-based 阶段 (Phase 2-6)。Phase 1 (主线程) 和 Phase 7 (Skill) 无 L1 覆盖 —— 这是架构约束而非缺陷，因为 Phase 1 无前驱，Phase 7 由编排器显式调用。
- **L2 (Hook)**: `check-predecessor-checkpoint.sh` 实现了完整的模式感知前驱检查。`get_predecessor_phase()` (行 218-249) 为三种模式定义了正确的前驱映射。
- **L3 (AI Gate)**: `autopilot-gate/SKILL.md` 8 步检查清单在每次阶段切换前执行。

**模式路由互斥性**

- full: 0->1->2->3->4->5->6->7 (SKILL.md:19)
- lite: 0->1->5->6->7, Phase 2/3/4 显式拒绝 (check-predecessor-checkpoint.sh:255-258, 270-274)
- minimal: 0->1->5->7, Phase 6 显式拒绝 (check-predecessor-checkpoint.sh:359-361)

**模式不可变性**: 模式在 Phase 0 确定后写入锁文件，后续由 Hook 从锁文件读取。模式不写入 checkpoint 文件，仍是单一存储点。

**TDD 模式下 Phase 5 前驱**: full + tdd_mode=true 时，Phase 5 前驱为 Phase 3 而非 Phase 4 (行 239-241)。Phase 4 写入 `phase-4-tdd-override.json` 标记跳过，L2 正确处理 (行 309-328)。

**降级条件**: 仅合并失败 > 3 文件、连续 2 组失败、用户显式选择时允许降级。降级逻辑由 AI 强制执行（SKILL.md 规范），无 L2 Hook 计数器。

**扣分原因 (-8)**:
- 模式仅存于锁文件，checkpoint 中无交叉验证 (-3)
- 降级逻辑无 L2 Hook 确定性强制 (-2)
- L1 不覆盖 Phase 1/7 (架构约束，风险低) (-3)

### 2.2 Checkpoint 写入可靠性 — 88/100

**v5.1 原子写入协议** (相比 v5.0 的 65 分大幅提升)

v5.1 在 SKILL.md 统一调度模板 Step 5+7 (行 202-217) 和 autopilot-gate/SKILL.md (行 278-302) 中定义了完整的原子写入协议：

```
1. mkdir -p phase-results/
2. python3 写入 phase-{N}-{slug}.json.tmp
3. python3 验证 .tmp 文件 JSON 合法性
4. mv .tmp -> .json (原子重命名)
5. 最终验证
```

**v5.1 关键改进**: Checkpoint 写入**必须使用 Bash 工具**（非 Write 工具），以绕过 Write/Edit Hook 的状态隔离检查 (SKILL.md:204)。这是架构层面的正确决策。

**崩溃恢复**: autopilot-recovery/SKILL.md 包含 `.tmp` 残留清理逻辑：`rm -f openspec/changes/*/context/phase-results/*.json.tmp`。

**断电安全分析**:
- 写入 .tmp 时崩溃 -> 正式文件不受影响
- mv 是 POSIX 原子操作 -> 不会产生半写 checkpoint
- 验证失败 -> 删除 .tmp，不覆盖正式文件

**Phase 1 中间 Checkpoint** (v5.1 新增):
- 调研完成后写入 `phase-1-interim.json` (SKILL.md:132-140)
- 每轮决策后覆盖写入 (SKILL.md:149-157)
- 最终 checkpoint 写入后删除中间文件 (SKILL.md:160)

**扣分原因 (-12)**:
- 原子写入协议仅在 SKILL.md (AI 指令) 中定义，无 Hook 确定性验证 checkpoint 是否通过原子路径写入 (-5)
- Phase 1 中间 checkpoint 使用后台 Agent 写入，仍依赖 AI 正确执行模板 (-3)
- `read_checkpoint_status()` (_common.sh:124-135) 对损坏 JSON 返回 "error" 触发 deny，但未尝试从 .tmp 恢复 (-2)
- checkpoint 文件无版本号或模式字段用于交叉验证 (-2)

### 2.3 三层门禁联防 — 85/100

**L1 (TaskCreate blockedBy)**:
- 覆盖 Phase 2-6 的 Task 派发
- Phase 1/7 不覆盖（架构约束）
- 独立阻断能力：是（Claude Code 任务系统自身强制）

**L2 (Hook 确定性验证)**:

v5.1 关键修复 — 后台 Agent 不再完全绕过 L2:
- **PreToolUse**: `check-predecessor-checkpoint.sh:49-58` 将 `IS_BACKGROUND=true` 标记但**不再 exit 0**。后台 Agent 仍接受前驱 checkpoint 存在性检查。注释 (行 49-53) 清晰说明修复意图。
- **PostToolUse**: `post-task-validator.sh` 不再包含 `is_background_agent && exit 0`。行 22-25 的注释明确说明 v5.1 修复。

v5.1 新增 — 子 Agent 状态隔离:
- `unified-write-edit-check.sh` CHECK 0 (行 86-113) 阻断 Phase 5 子 Agent 写入 `context/phase-results/*`、`openspec/changes/*/context/*.json`、`.autopilot-active`
- Checkpoint-writer 使用 Bash 工具绕过此 Hook（设计正确）

**L3 (AI Gate 8-step)**:
- 8 步检查清单在 autopilot-gate/SKILL.md 中定义
- 特殊门禁：Phase 4->5 (test_counts + dry_run)、Phase 5->6 (zero_skip + tasks completion)
- v5.1 双向反控：gate 阻断后启动 `poll-gate-decision.sh` 轮询 GUI 决策

**绕过路径分析**:

| 绕过向量 | L1 | L2 | L3 | 结论 |
|---------|----|----|-----|------|
| 跳过 Phase 顺序 | 阻断 (Task) | 阻断 (Hook) | 阻断 (Gate) | 无绕过 |
| Phase 4 返回 warning | N/A | 阻断 (_post_task_validator.py:157) | 阻断 (Gate) | 无绕过 |
| 子 Agent 修改 checkpoint | N/A | **阻断** (unified-write-edit-check CHECK 0) | N/A | v5.1 新增阻断 |
| 空 JSON 信封 | N/A | 阻断 (_post_task_validator.py:77-82) | 阻断 (Gate Step 1) | 无绕过 |
| 反合理化 | N/A | 阻断 (评分系统) | N/A | 后台 Agent 已覆盖 |
| Phase 6 跳过 (minimal) | N/A | 阻断 (check-predecessor:360) | 阻断 (Gate) | 无绕过 |

**扣分原因 (-15)**:
- L3 仍依赖 AI 自律执行 8 步检查，无 Hook 确定性验证 gate 输出格式 (-5)
- `poll-gate-decision.sh` 的 override 安全约束仅在 SKILL.md 中声明（Phase 4->5 和 5->6 不可 override），无 Hook 强制 (-4)
- Phase 1 主线程执行无 L1/L2 覆盖（仅 L3），理论上 AI 可跳过 Phase 1 直接 Phase 2 (-3)
- 反合理化模式仍可通过改写措辞规避（固有局限）(-3)

### 2.4 文件写入完整性 — 82/100

**unified-write-edit-check.sh 分析** (v5.1 统一替代 4 脚本)

架构：单入口 + 共享 preamble + 4 个检查层级：
- CHECK 0: 子 Agent 状态隔离 (纯 bash, ~1ms)
- CHECK 1: TDD Phase 隔离 (纯 bash, ~1ms)
- CHECK 2: Banned Patterns (grep, ~2ms)
- CHECK 3: Assertion Quality (grep, ~2ms)
- CHECK 4: Code Constraints (python3, Phase 5 only)

**CHECK 0 缺陷**: Phase 5 检测逻辑有误判风险。

文件 `unified-write-edit-check.sh` 行 42-71 的 IN_PHASE5 检测：
- **第一分支** (行 43): `PHASE4_CP` 存在 -> 检查 Phase 5 CP (full 模式标准路径)
- **第二分支** (行 51): `PHASE3_CP` 存在 + `PHASE1_CP` 存在 -> TDD 模式
- **第三分支** (行 62): `PHASE1_CP` 存在 -> lite/minimal 模式

**缺陷 [D-01, 高危]**: 在 full 模式 Phase 2/3 期间（Phase 1 完成，Phase 3/4 尚未完成），代码落入第三分支（`elif [ -n "$PHASE1_CP" ]`），错误地设置 `IN_PHASE5="yes"`。此时 CHECK 0 会阻断写入 `openspec/changes/*/context/*.json`。Phase 2 子 Agent 如果需要写入此模式的文件，会被误拦截。

**实际影响评估**: Phase 2/3 子 Agent 主要写入 OpenSpec 制品到 `openspec/changes/<name>/` 下的 .md 文件，而 CHECK 0 的保护路径模式为 `*openspec/changes/*/context/*.json` 和 `*context/phase-results/*`。Phase 2/3 通常不写 `.json` 到 `context/` 目录，因此实际触发概率低。但若 Phase 2/3 需要写入 context 目录的 JSON 文件（如 Auto-Scan 产出），则会被误拦截。

**CHECK 1 (TDD 隔离)**: 实现正确。读取 `.tdd-stage` 文件，RED 阶段阻断非测试文件，GREEN 阶段阻断测试文件。文件类型检测通过文件名模式 + 目录模式双重匹配 (行 125-130)。

**CHECK 2 (Banned Patterns)**: 正确跳过非源码文件 (.md/.json/.yaml 等)。扫描 `TODO:`/`FIXME:`/`HACK:` (带冒号)。冒号要求是降低误报的刻意权衡。

**CHECK 3 (Assertion Quality)**: 覆盖 JS/TS、Python、Java/Kotlin 恒真断言。模式覆盖主流情况。

**CHECK 4 (Code Constraints)**: 仅 Phase 5 激活。通过 `_constraint_loader.py` 加载约束。支持 forbidden_files、forbidden_patterns、allowed_dirs、max_lines。

**扣分原因 (-18)**:
- IN_PHASE5 检测逻辑在 full 模式 Phase 2/3 存在误判 (-8)
- CHECK 0 的保护路径仅覆盖 `.json` 和 `.autopilot-active`，不覆盖其他 openspec 关键文件 (-3)
- Banned Patterns 冒号要求允许 `TODO -` 或 `// TODO implement` 规避 (-3)
- Assertion Quality 模式不覆盖 Rust/Go/Swift 等语言 (-2)
- CHECK 4 仅 Phase 5 激活，Phase 4/6 的 Write/Edit 不受 code_constraints 保护 (-2)

### 2.5 并行模式安全性 — 78/100

**parallel-merge-guard 分析**

v5.1 将独立的 `parallel-merge-guard.sh` (仍存在) 整合进 `_post_task_validator.py` Validator 4 (行 410-549)。两处实现逻辑相同。

**三项检查**:
1. `git diff --check` 检测合并冲突标记 (行 419-439)
2. 范围验证：变更文件 vs 预期 artifacts (行 441-506)
3. Typecheck 执行：从 config 读取 `type: typecheck` 命令 (行 508-539)

**文件所有权强制**: `unified-write-edit-check.sh` CHECK 4 在 Phase 5 通过 `_constraint_loader.py` 的 `allowed_dirs` 检查提供文件级范围限制。子 Agent 内部的 Write/Edit 调用会触发此 Hook。

**独立的 parallel-merge-guard.sh 冗余问题** [D-02, 低危]:
`parallel-merge-guard.sh` 作为独立脚本仍存在，但未在 `hooks.json` 中注册为 Hook。它的功能已被 `_post_task_validator.py` Validator 4 覆盖。`parallel-merge-guard.sh:14` 仍使用旧的 `is_background_agent && exit 0` 逻辑 (行 14)，但由于未注册为 Hook，这不构成实际问题。

**合并守卫触发条件** — v5.0 遗留问题部分缓解:
`_post_task_validator.py:411-413` 中的正则匹配 `worktree.*merge|merge.*worktree|git\s+merge.*autopilot-task` 仍依赖文本模式。但 v5.1 将此检查整合到 post-task-validator 中，而非独立脚本，确保所有 Phase 5 Task 输出（包括后台）都经过检查。

**扣分原因 (-22)**:
- 合并守卫触发仍依赖文本模式匹配，不匹配的输出不会触发检查 (-8)
- 降级逻辑无 L2 Hook 确定性强制 (-4)
- `parallel-merge-guard.sh` 独立脚本未清理，存在代码冗余 (-2)
- Typecheck 配置解析使用正则而非 YAML 解析器，复杂配置格式可能解析失败 (-4)
- 文件所有权仅通过 `allowed_dirs` 粗粒度检查，非 per-file ownershipenforcement (-4)

### 2.6 Compact 恢复可靠性 — 85/100

**PreCompact -> SessionStart(compact) 配对**:

`save-state-before-compact.sh` (PreCompact):
- 扫描所有 checkpoint 文件 (行 98-116)
- 记录最后完成阶段、下一阶段、模式、anchor_sha、Phase 5 任务进度 (行 165-229)
- 写入 Markdown 格式的 `autopilot-state.md` (行 232-234)

`reinject-state-after-compact.sh` (SessionStart with `compact` matcher):
- 从锁文件查找活跃变更 (行 31-38)
- 回退到 mtime 搜索 (行 42-51)
- 输出状态文件内容到 stdout (行 59-65)

**v5.1 改善**: `save-state-before-compact.sh` 现在记录执行模式 (行 177) 和 anchor_sha (行 181)，为恢复提供更完整上下文。

**hooks.json 配置正确性**:
```json
"PreCompact": [{ "command": "bash .../save-state-before-compact.sh" }],
"SessionStart": [{ "matcher": "compact", "command": "bash .../reinject-state-after-compact.sh" }]
```
`compact` matcher 确保仅在压缩后的 SessionStart 触发恢复。

**无损性分析**:
- 状态文件是 Markdown 格式（人可读但非机器精确解析）
- 权威状态始终是磁盘上的 checkpoint JSON 文件
- 状态文件是补充性 AI 上下文，不参与 L2 Hook 决策

**扣分原因 (-15)**:
- 状态文件为 Markdown 格式，AI 可能误读恢复指令 (-5)
- 无结构化 JSON 状态备份文件 (-3)
- 重注入不验证状态文件与当前 checkpoint 的一致性 (-3)
- 多次快速压缩可能导致状态文件与 checkpoint 不同步 (-2)
- reinject 输出不含压缩前后 checkpoint 变化的 diff (-2)

### 2.7 Hook 系统健壮性 — 79/100

**_hook_preamble.sh Layer 0 bypass**:

行 38-39：`has_active_autopilot "$PROJECT_ROOT_QUICK" || exit 0`

`has_active_autopilot()` (_common.sh:12-23) 检查:
1. `openspec/changes/` 目录存在
2. `openspec/changes/.autopilot-active` 文件存在
3. 回退：`find` 搜索子目录下的 `.autopilot-active`

**Layer 0 安全性**: 无活跃 autopilot 会话时，所有 Hook 立即 exit 0（纯 bash，零 python3 开销）。这是性能优化而非安全机制 —— 非 autopilot 场景不需要 Hook 验证。

**stdin 解析可靠性**:

preamble 使用纯 bash 提取 `cwd` (行 33):
```bash
PROJECT_ROOT_QUICK=$(echo "$STDIN_DATA" | grep -o '"cwd"[[:space:]]*:[[:space:]]*"[^"]*"' | ...)
```

`check-predecessor-checkpoint.sh` 使用 python3 解析 stdin JSON (行 76-83):
```python
data = json.load(sys.stdin)
print(data.get('cwd', ''))
```

**缺陷 [D-03, 中危]**: `check-predecessor-checkpoint.sh:289` 在全局作用域使用 `local` 关键字。

`check-predecessor-checkpoint.sh` 行 287-302 的 minimal 模式 zero_skip_check 检查位于全局作用域（`if` 块内但不在函数内），行 289 使用了 `local zsc_passed`。在 bash 中，`local` 仅在函数内有效。在全局作用域中使用 `local` 的行为因 bash 版本而异：
- **bash 4.4+** (macOS Monterey 21.6.0 默认 bash 3.2): bash 3.2 中全局 `local` 会报错但可能不中断（因为 `set -uo pipefail` 但无 `set -e`）
- 实际影响：此错误可能被忽略（无 `set -e`），变量仍然创建。但这是一个代码质量问题。

**缺陷 [D-04, 低危]**: `has_phase_marker()` (_common.sh:316-319) 使用 grep 匹配 prompt 字段开头的标记。但如果 prompt 内容本身包含标记文本（如代码示例），可能产生假阳性。`check-predecessor-checkpoint.sh:45` 对此有相同的匹配逻辑，两处一致。

**python3 依赖处理**:
- `check-predecessor-checkpoint.sh:61-73`: python3 不存在时 fail-closed (deny)
- `post-task-validator.sh:28-29`: python3 不存在时 exit 0 (fail-open)
- `unified-write-edit-check.sh:230`: python3 不存在时 exit 0 (fail-open for CHECK 4 only)
- `_hook_preamble.sh`: 不依赖 python3（纯 bash）

**缺陷 [D-05, 中危]**: `post-task-validator.sh` 在 python3 不存在时 fail-open (行 28-29: `if ! require_python3; then exit 0; fi`)。这意味着如果 python3 意外不可用，所有 5 个 PostToolUse 验证器被静默跳过。`require_python3()` (_common.sh:327-351) 输出 block JSON 但返回 1，调用方 `exit 0` 丢弃了 block 输出。

**扣分原因 (-21)**:
- `local` 在函数外使用 (D-03) (-3)
- PostToolUse python3 缺失时 fail-open 而非 fail-closed (-6)
- 标记检测可能假阳性 (-2)
- stdin JSON 解析在 preamble 中使用正则而非 JSON 解析器 (-3)
- PreToolUse fail-closed 但 PostToolUse fail-open，不一致的失败策略 (-4)
- `parallel-merge-guard.sh` 独立脚本仍使用旧的后台 Agent 绕过逻辑 (-3)

### 2.8 事件发射一致性 — 74/100

**事件类型覆盖**:

`emit-phase-event.sh` 支持: `phase_start`、`phase_end`、`error`、`gate_decision_pending`、`gate_decision_received`
`emit-gate-event.sh` 支持: `gate_pass`、`gate_block`

**配对性分析**:

按 SKILL.md 统一调度模板 (行 170-229):
- Step 0: `phase_start` 发射
- Step 1: gate 检查后发射 `gate_pass` 或 `gate_block`
- Step 6.5: `phase_end` 发射

配对保障：`phase_start` 和 `phase_end` 在统一调度模板中成对出现。但如果 gate 阻断且用户选择放弃，`phase_start` 已发射但 `phase_end` 不会发射，导致事件不成对。

**sequence 单调递增分析**:

`next_event_sequence()` (_common.sh:290-302):
```bash
local current=0
[ -f "$seq_file" ] && current=$(cat "$seq_file" ...) || true
local next=$((current + 1))
echo "$next" > "$seq_file"
```

**缺陷 [D-06, 中危]**: **TOCTOU 竞态条件**。读取 seq_file (行 296) 和写入 (行 300) 之间无锁。如果两个事件脚本并发执行（如 `phase_end` 和 `gate_pass` 同时发射），可能读到相同的 current 值并写入相同的 next 值，导致 sequence 重复。函数注释 (行 289) 声称 "Thread-safe via atomic write"，但 `echo "$next" > "$seq_file"` 只是写入的原子性，不解决 read-modify-write 的竞态。

**缺陷 [D-07, 低危]**: `emit-phase-event.sh:37` 的 event_type 验证包含 `gate_decision_pending|gate_decision_received` 但错误信息 (行 38) 仅列出 `phase_start|phase_end|error`，未包含新增类型。

**事件 JSON 构造**: 两个脚本使用相同的 python3 构造逻辑，但代码完全重复（emit-phase-event.sh:70-95 vs emit-gate-event.sh:70-95），未提取为共享函数。

**扣分原因 (-26)**:
- sequence 竞态条件导致可能重复 (-8)
- gate 阻断放弃场景 phase_start/phase_end 不成对 (-6)
- 错误信息与实际支持的事件类型不一致 (-2)
- 两个事件脚本大量代码重复 (-4)
- 事件发射失败 (python3 出错) 时仅 stderr 警告，不影响主流程 (-3)
- 无事件 schema 验证机制确保字段完整性 (-3)

---

## 3. 逐模式测试矩阵

### full 模式

| 审计项 | Phase 0 | Phase 1 | Phase 2 | Phase 3 | Phase 4 | Phase 5 | Phase 6 | Phase 7 |
|--------|---------|---------|---------|---------|---------|---------|---------|---------|
| L1 阻断 | N/A(Skill) | N/A(主线程) | OK | OK | OK | OK | OK | N/A(Skill) |
| L2 PreToolUse | N/A | N/A | OK(v5.1) | OK(v5.1) | OK(v5.1) | OK | OK(v5.1) | N/A |
| L2 PostToolUse | N/A | N/A | OK(v5.1) | OK(v5.1) | OK | OK | OK(v5.1) | N/A |
| L3 Gate | N/A | N/A | OK | OK | OK | OK+特殊 | OK+特殊 | OK |
| Checkpoint 原子写入 | N/A | OK(v5.1) | OK | OK | OK | OK | OK | OK |
| Phase 1 中间 CP | N/A | OK(v5.1) | N/A | N/A | N/A | N/A | N/A | N/A |
| 状态隔离 CHECK 0 | N/A | N/A | **误判风险** | **误判风险** | OK | OK | OK | N/A |
| TDD 隔离 CHECK 1 | N/A | N/A | N/A | N/A | N/A | OK(tdd) | N/A | N/A |
| Banned Patterns | N/A | N/A | OK | OK | OK | OK | OK | N/A |
| Anti-Rationalization | N/A | N/A | N/A | N/A | OK(v5.1) | OK(v5.1) | OK(v5.1) | N/A |
| phase_start/end 配对 | N/A | N/A | OK | OK | OK | OK | OK | N/A |
| gate_pass/block | N/A | N/A | OK | OK | OK | OK | OK | OK |

### lite 模式

| 审计项 | Phase 0 | Phase 1 | Phase 5 | Phase 6 | Phase 7 |
|--------|---------|---------|---------|---------|---------|
| L1 阻断 | N/A | N/A | OK | OK | N/A |
| L2 PreToolUse | N/A | N/A | OK | OK(v5.1) | N/A |
| L2 PostToolUse | N/A | N/A | OK | OK(v5.1) | N/A |
| L3 Gate | N/A | N/A | OK | OK+特殊 | OK |
| Checkpoint 原子写入 | N/A | OK(v5.1) | OK | OK | OK |
| Phase 跳过阻断 | N/A | N/A | N/A(2/3/4 显式拒绝) | N/A | N/A |
| 状态隔离 CHECK 0 | N/A | N/A | OK | OK | N/A |
| phase_start/end 配对 | N/A | N/A | OK | OK | N/A |

### minimal 模式

| 审计项 | Phase 0 | Phase 1 | Phase 5 | Phase 7 |
|--------|---------|---------|---------|---------|
| L1 阻断 | N/A | N/A | OK | N/A |
| L2 PreToolUse | N/A | N/A | OK | N/A |
| L2 PostToolUse | N/A | N/A | OK | N/A |
| L3 Gate | N/A | N/A | OK | OK |
| Phase 跳过阻断 | N/A | N/A | N/A(2/3/4/6 显式拒绝) | N/A |
| zero_skip_check | N/A | N/A | OK(warning) | N/A |
| Checkpoint 原子写入 | N/A | OK(v5.1) | OK | OK |
| 状态隔离 CHECK 0 | N/A | N/A | OK | N/A |

---

## 4. 关键代码缺陷清单

### D-01 [高危] — unified-write-edit-check.sh Phase 5 检测逻辑误判

**文件**: `plugins/spec-autopilot/scripts/unified-write-edit-check.sh`
**行号**: 42-71 (IN_PHASE5 检测逻辑)
**模式**: full
**描述**: 在 full 模式 Phase 2/3 期间（Phase 1 完成，Phase 3/4 尚未完成），代码落入第三分支 `elif [ -n "$PHASE1_CP" ]` (行 62)，错误设置 `IN_PHASE5="yes"`。随后 CHECK 0 (行 88-113) 会阻断写入 `*openspec/changes/*/context/*.json` 和 `*context/phase-results/*`。
**影响**: Phase 2/3 子 Agent 写入 `context/` 目录下的 JSON 文件会被误拦截。Checkpoint-writer 使用 Bash 工具不受影响，但其他 context JSON 文件（如 Auto-Scan 产出）可能受影响。
**修复建议**: 在第三分支添加模式检查，或增加 Phase 2/3 checkpoint 不存在的额外条件：
```bash
elif [ -n "$PHASE1_CP" ]; then
  # 需要确认当前不在 Phase 2/3/4 (full 模式)
  LOCK_FILE_PATH="$CHANGES_DIR/.autopilot-active"
  CURRENT_MODE=$(read_lock_json_field "$LOCK_FILE_PATH" "mode" "full")
  if [ "$CURRENT_MODE" != "full" ] || [ -n "$PHASE3_CP" ]; then
    # lite/minimal 或 full 且已过 Phase 3
    ...
  fi
fi
```

### D-02 [低危] — parallel-merge-guard.sh 独立脚本残留

**文件**: `plugins/spec-autopilot/scripts/parallel-merge-guard.sh`
**行号**: 14
**描述**: 独立脚本未在 hooks.json 注册，功能已由 `_post_task_validator.py` Validator 4 覆盖。但脚本仍包含旧的 `is_background_agent && exit 0` 绕过逻辑 (行 14)。如果未来有人将其重新注册为 Hook，会引入后台 Agent 绕过。
**修复建议**: 删除此脚本或添加 deprecation 注释。

### D-03 [中危] — check-predecessor-checkpoint.sh 全局 `local` 关键字

**文件**: `plugins/spec-autopilot/scripts/check-predecessor-checkpoint.sh`
**行号**: 289
**描述**: `local zsc_passed` 在全局作用域使用（if 块内但不在函数内）。bash 3.2 (macOS 默认) 中 `local` 在函数外使用会报错。由于脚本使用 `set -uo pipefail` 但无 `set -e`，此错误可能被忽略。
**影响**: 在 macOS bash 3.2 上可能产生 stderr 错误输出，但变量仍然创建，不影响功能。在使用 `#!/usr/bin/env bash` 且系统安装了 bash 5.x 的环境下行为正常。
**修复建议**: 删除 `local` 关键字，直接使用 `zsc_passed=...`。

### D-04 [低危] — has_phase_marker 假阳性

**文件**: `plugins/spec-autopilot/scripts/_common.sh`
**行号**: 316-319
**描述**: `has_phase_marker()` 使用 grep 匹配 stdin 中的 `"prompt"` 字段后跟 `<!-- autopilot-phase:N`。如果 prompt 内容本身包含此标记文本（如代码示例或文档引用），会产生假阳性。
**影响**: 非 autopilot Task 的 prompt 中如果包含标记文本引用，会误触发 Hook 验证。概率极低。
**修复建议**: 改用 python3 JSON 解析提取 prompt 字段后检查首行。

### D-05 [中危] — post-task-validator.sh python3 缺失时 fail-open

**文件**: `plugins/spec-autopilot/scripts/post-task-validator.sh`
**行号**: 28-29
**描述**: `require_python3()` 返回 1 时输出 block JSON 到 stdout，但调用方 `if ! require_python3; then exit 0; fi` 在返回 1 时执行 `exit 0`。这导致 block JSON 被输出到 stdout **后** 脚本仍以 exit 0 退出。Claude Code 可能先读到 block JSON 再看到 exit 0，行为取决于 Claude Code 的 hook 输出解析实现。
**影响**: 如果 Claude Code 优先使用 exit code 判断，则 exit 0 意味着 allow，block JSON 被忽略 -> fail-open。如果 Claude Code 优先解析 stdout JSON，则仍能 block -> 实际 fail-closed。
**修复建议**: 将逻辑改为：`require_python3 || exit 0` 改为 `if ! command -v python3 &>/dev/null; then echo '{"decision":"block","reason":"python3 required"}'; exit 0; fi`，确保 block JSON 被输出且 exit 0 让 Claude Code 读取 stdout。或改为 `exit 1` 让 Claude Code 进入 fail-closed 默认行为。

### D-06 [中危] — next_event_sequence TOCTOU 竞态

**文件**: `plugins/spec-autopilot/scripts/_common.sh`
**行号**: 290-302
**描述**: `next_event_sequence()` 的 read (行 296) 和 write (行 300) 之间无文件锁。并发调用可能导致 sequence 重复。注释 (行 289) 声称 "Thread-safe via atomic write" 但实际不是。
**影响**: 并发事件发射可能产生相同 sequence 号，导致 GUI 消费者无法正确排序事件。
**修复建议**: 使用 `flock` 实现文件锁：
```bash
(
  flock -n 9 || { echo "0"; return; }
  local current=0
  [ -f "$seq_file" ] && current=$(cat "$seq_file" | tr -d '[:space:]')
  local next=$((current + 1))
  echo "$next" > "$seq_file"
  echo "$next"
) 9>"$seq_file.lock"
```

### D-07 [低危] — emit-phase-event.sh 错误信息不完整

**文件**: `plugins/spec-autopilot/scripts/emit-phase-event.sh`
**行号**: 37-38
**描述**: event_type 验证的 case 语句 (行 34-39) 接受 `gate_decision_pending|gate_decision_received`，但错误信息 (行 37) 仅列出 `phase_start|phase_end|error`。
**修复建议**: 更新行 37 的错误信息为 `"Must be: phase_start|phase_end|error|gate_decision_pending|gate_decision_received"`。

### D-08 [低危] — emit-phase-event.sh 和 emit-gate-event.sh 代码重复

**文件**:
- `plugins/spec-autopilot/scripts/emit-phase-event.sh` (行 70-95)
- `plugins/spec-autopilot/scripts/emit-gate-event.sh` (行 70-95)
**描述**: 两个脚本的事件 JSON 构造 python3 代码完全相同（26 行），以及上下文解析 (change_name, session_id, phase_label 等) 也完全相同 (行 48-68)。
**修复建议**: 提取为 `_emit_event_common.sh` 共享函数或合并为单一 `emit-event.sh` 脚本。

### D-09 [低危] — poll-gate-decision.sh override 安全约束未 Hook 强制

**文件**: `plugins/spec-autopilot/scripts/poll-gate-decision.sh`
**行号**: 全文
**描述**: autopilot-gate/SKILL.md:122 声明 "override 不可在 Phase 4->5 和 Phase 5->6 特殊门禁中使用"，但 `poll-gate-decision.sh` 不检查 phase 号来拒绝 override。此约束仅依赖 AI (L3) 遵守。
**修复建议**: 在 `poll-gate-decision.sh` 中添加 phase 检查：当 `action=override` 且 `PHASE` 为 5 或 6 时，将其视为无效 action，返回错误。

### D-10 [低危] — save-state-before-compact.sh config 路径计算

**文件**: `plugins/spec-autopilot/scripts/save-state-before-compact.sh`
**行号**: 159
**描述**: config 文件路径使用 `os.path.join(change_dir, '..', '..', '..', '.claude', 'autopilot.config.yaml')` 计算，假定 change_dir 是 `openspec/changes/<name>/` 的绝对路径。如果目录层级变化，此相对路径计算会失败。
**修复建议**: 直接从 PROJECT_ROOT 构造路径，而非从 change_dir 反向推导。

---

## 5. 与 v5.0 报告对比

### 已修复的 v5.0 问题

| v5.0 ID | 严重度 | 描述 | v5.1 修复状态 |
|---------|--------|------|-------------|
| C-02 | 致命 | Checkpoint 写入非原子性 | **已修复**: SKILL.md 定义 .tmp -> rename 协议，recovery 脚本清理 .tmp 残留 |
| H-01 | 高危 | 后台 Agent 绕过 L2 PreToolUse | **已修复**: check-predecessor-checkpoint.sh:49-58 后台 Agent 仍接受轻量级检查 |
| H-02 | 高危 | 后台 Agent 绕过 L2 PostToolUse | **已修复**: post-task-validator.sh:22-25 移除了 `is_background_agent && exit 0` |
| H-04 | 高危 | Phase 1 无中间 checkpoint | **已修复**: SKILL.md:132-140 调研完成后 + 149-157 每轮决策后写入中间 CP |
| M-03 | 中危 | 状态文件非机器可解析 | **部分改善**: 增加了模式和 anchor_sha 字段，但仍为 Markdown 格式 |

### 仍存在的 v5.0 问题

| v5.0 ID | 严重度 | 描述 | v5.1 状态 |
|---------|--------|------|----------|
| C-01 | 致命 | L1 仅覆盖 Task 阶段 (2-6) | **未变**: 架构约束，Phase 1/7 仍无 L1 |
| H-03 | 高危 | 合并守卫依赖文本模式匹配 | **未变**: _post_task_validator.py:411-413 相同正则 |
| M-01 | 中危 | 模式仅存锁文件无交叉验证 | **未变** |
| M-02 | 中危 | L3 依赖 AI 自律 | **未变** |
| M-04 | 中危 | 所有权检查依赖阶段检测启发式 | **部分变化**: unified-write-edit-check.sh 替代但启发式逻辑相同 |
| M-06 | 中危 | 批次调度崩溃丢失重试队列 | **未变** |
| L-01 | 低危 | 锁文件 PID 竞态 | **未变** |
| L-04 | 低危 | 反合理化可改写措辞规避 | **未变** |
| L-05 | 低危 | TODO 冒号要求允许规避 | **未变** |

### v5.1 新增问题

| ID | 严重度 | 描述 | 来源 |
|----|--------|------|------|
| D-01 | 高危 | unified-write-edit-check IN_PHASE5 误判 | v5.1 新脚本引入 |
| D-03 | 中危 | check-predecessor-checkpoint `local` 语法错误 | v4.1 引入，v5.1 未修复 |
| D-05 | 中危 | post-task-validator python3 fail-open | 行为变化（v5.1 移除后台绕过后更关键） |
| D-06 | 中危 | next_event_sequence 竞态条件 | v5.0 引入，v5.1 未修复 |
| D-09 | 低危 | poll-gate-decision override 无 Hook 强制 | v5.1 新功能引入 |

### 评分变化总结

| 维度 | v5.0 得分 | v5.1 得分 | 变化 | 原因 |
|------|----------|----------|------|------|
| 状态机正确性 | 90 | 92 | +2 | TDD 前驱逻辑改进 |
| 门禁覆盖率 | 72 | 85 | +13 | 后台 Agent L2 修复 + 状态隔离 |
| 文件完整性 | 65 | 88 (CP) / 82 (写入) | +23/+17 | 原子写入协议 + 统一 Hook |
| 并行安全 | 75 | 78 | +3 | 后台验证覆盖 |
| 崩溃恢复 | 70 | 85 | +15 | Phase 1 中间 CP + .tmp 清理 |
| 反规避 | 78 | — | 并入其他维度 | — |

---

## 6. 修复建议优先级排序

### P0 — 立即修复（阻断风险）

| 编号 | 缺陷 | 文件 | 修复工作量 | 影响 |
|------|------|------|----------|------|
| **P0-1** | D-01: IN_PHASE5 检测逻辑在 full 模式 Phase 2/3 误判 | `unified-write-edit-check.sh:42-71` | 小 (增加模式检查) | Phase 2/3 子 Agent context JSON 写入被误拦截 |
| **P0-2** | D-03: `local` 在函数外使用 | `check-predecessor-checkpoint.sh:289` | 极小 (删除 `local`) | bash 3.2 报错，可能影响 minimal 模式 Phase 7 前置检查 |

### P1 — 高优先级（安全性改善）

| 编号 | 缺陷 | 文件 | 修复工作量 | 影响 |
|------|------|------|----------|------|
| **P1-1** | D-05: PostToolUse python3 fail-open | `post-task-validator.sh:28-29` | 小 | 所有 5 个验证器被跳过 |
| **P1-2** | D-06: event sequence TOCTOU 竞态 | `_common.sh:290-302` | 中 (flock) | 事件排序错误 |
| **P1-3** | D-09: poll-gate-decision override 无强制 | `poll-gate-decision.sh` | 小 | Phase 4->5/5->6 override 绕过 |
| **P1-4** | v5.0-H-03: 合并守卫文本模式依赖 | `_post_task_validator.py:411-413` | 中 | worktree 合并检测不可靠 |

### P2 — 中优先级（代码质量）

| 编号 | 缺陷 | 文件 | 修复工作量 | 影响 |
|------|------|------|----------|------|
| **P2-1** | D-07: 错误信息不完整 | `emit-phase-event.sh:37-38` | 极小 | 开发者困惑 |
| **P2-2** | D-08: 事件脚本代码重复 | `emit-phase-event.sh` + `emit-gate-event.sh` | 中 | 维护成本 |
| **P2-3** | D-02: parallel-merge-guard 残留 | `parallel-merge-guard.sh` | 极小 (删除或标注) | 代码整洁 |
| **P2-4** | D-10: config 路径反向推导 | `save-state-before-compact.sh:159` | 小 | 目录结构变化时失败 |
| **P2-5** | v5.0-M-01: 模式无交叉验证 | checkpoint 写入逻辑 | 中 | 锁文件篡改风险 |

### P3 — 低优先级（已知局限）

| 编号 | 缺陷 | 描述 | 评估 |
|------|------|------|------|
| **P3-1** | v5.0-C-01 | L1 不覆盖 Phase 1/7 | 架构约束，风险低 |
| **P3-2** | v5.0-M-02 | L3 依赖 AI 自律 | L2 提供确定性兜底 |
| **P3-3** | v5.0-L-04 | 反合理化可规避 | 评分系统提供纵深防御 |
| **P3-4** | D-04 | has_phase_marker 假阳性 | 概率极低 |

---

*审计报告结束。*
*审计范围: 20 个目标文件 + 2 个依赖模块 (_envelope_parser.py, _constraint_loader.py)。所有发现均基于代码精读，附具体文件路径和行号。*
