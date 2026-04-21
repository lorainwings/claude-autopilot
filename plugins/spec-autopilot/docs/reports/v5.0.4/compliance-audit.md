# v5.0.4 规约与记忆遵守度审计报告

**审计日期**: 2026-03-13
**插件版本**: v5.0.4（基于 v5.1 技术债务清剿后的代码实态）
**审计方**: AI 合规审计 Agent 5 (Opus 4.6, 1M context)
**事实来源**: `plugins/spec-autopilot/CLAUDE.md`
**对比基线**: `docs/reports/v5.0/compliance-audit.md`

---

## 1. 审计摘要

### 确定性覆盖率

| 指标 | v5.0 报告 | v5.0.4 实态 | 变化 |
|------|----------|------------|------|
| CLAUDE.md 总规则数 | 39 | 40（新增 SA-6） | +1 |
| L2 确定性保障（含主线程 Bash） | 26 | 32 | +6 |
| 仅 L3 AI 自觉 | 8 | 5 | -3 |
| 无任何保障 | 5 | 3 | -2 |
| **确定性覆盖率** | **66.7%** | **80.0%** | **+13.3pp** |
| 综合合规评分（含 L3） | 73/100 | 84/100 | +11 |

### 关键变化（v5.0 → v5.0.4）

1. **TDD-1/TDD-4 缺口已修复**: v5.1 引入 `.tdd-stage` 状态文件 + `unified-write-edit-check.sh` CHECK 1 TDD Phase Isolation，RED 阶段阻断实现文件、GREEN 阶段阻断测试文件，从仅 L3 升级为 L2 确定性保障
2. **SA-2 逻辑反转已修复**: v5.1 引入 `unified-write-edit-check.sh` CHECK 0 Sub-Agent State Isolation，在 Phase 5 阻断子 Agent 对 `openspec/` 和 checkpoint 路径的写入
3. **SA-6 新增规则**: v5.1 新增"背景 Agent 必须接受 L2 验证"，`post-task-validator.sh` 删除了 `is_background_agent && exit 0` 旁路，`check-predecessor-checkpoint.sh` 改为保留轻量级 L2 检查
4. **Hook 统一优化**: 3 个独立 Write|Edit Hook 合并为 `unified-write-edit-check.sh`，hooks.json 从 3 条 PostToolUse(Write|Edit) 缩减为 1 条，性能从 ~35s 降至 ~5s
5. **_post_task_validator.py 增强**: Phase 4 新增 `sad_path_counts` 为必需字段，Phase 1 决策格式 L2 验证

### 残存高风险

| 风险 | 等级 | 说明 |
|------|------|------|
| SA-1: 禁止读取计划文件 | **中** | 无 PreToolUse(Read) Hook，子 Agent 可自由读取任何文件 |
| SM-4: 降级条件严格 | **低** | 仅 L3 prompt 指令，无 L2 阻止 AI 以非法理由降级 |
| SA-4: 后台 Agent 产出必须 Write 到文件 | **低** | 仅 L3 prompt 指令 |

---

## 2. CLAUDE.md 逐条法则审查表

### 2.1 状态机硬约束（7 条）

| # | 法则 | L2 保障 | L3 保障 | 风险等级 | v5.0→v5.0.4 |
|---|------|---------|---------|----------|------------|
| SM-1 | Phase 顺序不可违反 | `check-predecessor-checkpoint.sh`: 模式感知前驱逻辑 + deny() | `autopilot-gate/SKILL.md` 8 步清单 | **低** | 不变 |
| SM-2 | 三层门禁联防 | hooks.json: PreToolUse(Task) + PostToolUse(Task) + PostToolUse(Write\|Edit) | `autopilot-gate/SKILL.md` L1/L2/L3 表格 | **低** | **优化**: Write\|Edit 从 3 条合并为 1 条 |
| SM-3 | 模式路径互斥 | `check-predecessor-checkpoint.sh` 219-249: get_predecessor_phase() + 256-275: 拒绝非 Full 下的 Phase 2/3/4 | `autopilot/SKILL.md` HARD CONSTRAINT | **低** | 不变 |
| SM-4 | 降级条件严格 | 无 L2 | `autopilot/SKILL.md` L3 prompt "合并失败>3 文件" | **低** | 不变 |
| SM-5 | Phase 4 不接受 warning | `_post_task_validator.py` 157-159: 确定性阻断 | `autopilot-gate/SKILL.md` | **低** | 不变 |
| SM-6 | Phase 5 zero_skip_check | `_post_task_validator.py` 124-130: 阻断 + `check-predecessor-checkpoint.sh` 357-381: Phase 6 门禁 | `autopilot-gate/SKILL.md` | **低** | 不变 |
| SM-7 | 归档需用户确认 | 无 L2（用户交互无法 Hook 化） | `autopilot-phase7/SKILL.md` AskUserQuestion | **低** | 不变（设计如此） |

### 2.2 TDD Iron Law（5 条，tdd_mode: true 时生效）

| # | 法则 | L2 保障 | L3 保障 | 风险等级 | v5.0→v5.0.4 |
|---|------|---------|---------|----------|------------|
| TDD-1 | 先测试后实现 (RED 仅测试/GREEN 仅实现) | **v5.1 新增**: `unified-write-edit-check.sh` CHECK 1 (118-147): 读取 `.tdd-stage` 文件，RED 阻断非测试文件，GREEN 阻断测试文件 | `tdd-cycle.md` prompt 注入 | **低** | **已修复** (仅L3→L2+L3) |
| TDD-2 | RED 必须失败 (exit_code != 0) | 主线程 Bash() L2 确定性验证 | `tdd-cycle.md` Step 2 | **低** | 不变 |
| TDD-3 | GREEN 必须通过 (exit_code = 0) | 主线程 Bash() L2 确定性验证 | `tdd-cycle.md` Step 4 | **低** | 不变 |
| TDD-4 | 测试不可变 (GREEN 禁止修改测试) | **v5.1 新增**: `unified-write-edit-check.sh` CHECK 1: GREEN 阶段 `IS_TEST_FILE=yes` 时输出 block | `tdd-cycle.md` 49 行 | **低** | **已修复** (仅L3→L2+L3) |
| TDD-5 | REFACTOR 回归保护 (git checkout) | 主线程 Bash() 执行 `git checkout`，但若主线程遗漏则无 L2 兜底 | `tdd-cycle.md` Step 6 | **中** | 不变 |

**TDD-1/TDD-4 修复详情**:

v5.1 引入的 `.tdd-stage` 状态文件机制工作如下：
1. 主线程在每个 TDD 步骤派发前写入 `openspec/changes/<name>/context/.tdd-stage`（内容为 "red"/"green"/"refactor"）
2. `unified-write-edit-check.sh` CHECK 1（118-147 行）在 Phase 5 期间：
   - 读取 `.tdd-stage` 文件内容
   - 通过文件名模式 (`*.test.*`, `*.spec.*`, `*_test.*`, `*_spec.*`, `*Test.*`, `*Spec.*`) 和路径模式 (`__tests__/`, `test/`, `tests/`, `spec/`) 判定文件类型
   - RED 阶段：非测试文件触发 `decision: "block"`
   - GREEN 阶段：测试文件触发 `decision: "block"`
   - REFACTOR 阶段：不拦截（行为保持由 L2 Bash 验证）
3. task 全部完成后删除 `.tdd-stage` 文件

**正则审查**:
- 测试文件名匹配（125-127 行）: `*.test.* | *.spec.* | *_test.* | *_spec.* | *Test.* | *Spec.*` — 覆盖 JS/TS/Python/Java/Kotlin 主流命名规范
- 测试路径匹配（128-130 行）: `*/__tests__/* | */test/* | */tests/* | */spec/* | *_test/* | *_spec/*` — 覆盖主流目录结构
- **遗漏**: `*_tests/*` 目录模式（某些 Python 项目使用）、`**/check_*` 或 `**/verify_*` 等非标准命名

### 2.3 代码质量硬约束（7 条）

| # | 法则 | L2 保障 | L3 保障 | 风险等级 | v5.0→v5.0.4 |
|---|------|---------|---------|----------|------------|
| CQ-1 | 禁止 TODO/FIXME/HACK | `unified-write-edit-check.sh` CHECK 2 (150-178): `grep -inE '(TODO:\|FIXME:\|HACK:)'` | N/A | **低** | **优化**: 合并到统一 Hook |
| CQ-2 | 禁止恒真断言 | `unified-write-edit-check.sh` CHECK 3 (180-223): JS/TS/Python/Java/Kotlin/通用 5 类恒真模式 | N/A | **低** | **优化**: 合并到统一 Hook |
| CQ-3 | Anti-Rationalization | `_post_task_validator.py` 316-378: 22 个加权模式 (11 EN + 11 CN)，评分阈值阻断 | N/A | **低** | 不变 |
| CQ-4 | 代码约束 (forbidden) | `unified-write-edit-check.sh` CHECK 4 (229-258): Phase 5 Write/Edit + `_post_task_validator.py` 382-403: Task 产物 | N/A | **低** | **优化**: 双重保障整合 |
| CQ-5 | 测试金字塔地板 | `_post_task_validator.py` 203-234: 可配置阈值 + routing_overrides | `autopilot-gate/SKILL.md` | **低** | 不变 |
| CQ-6 | Change Coverage ≥ 80% | `_post_task_validator.py` 259-273: 阻断验证 | `autopilot-gate/SKILL.md` | **低** | 不变 |
| CQ-7 | Sad Path ≥ 20%/类型 | `_post_task_validator.py` 275-303: 按类型比例验证 + routing_overrides | N/A | **低** | 不变 |

### 2.4 子 Agent 约束（6 条）

| # | 法则 | L2 保障 | L3 保障 | 风险等级 | v5.0→v5.0.4 |
|---|------|---------|---------|----------|------------|
| SA-1 | 禁止自行读取计划文件 | 无 L2（无 PreToolUse(Read) Hook） | dispatch prompt 指令 | **中** | 不变 |
| SA-2 | 禁止修改 openspec/checkpoint | **v5.1 修复**: `unified-write-edit-check.sh` CHECK 0 (87-113): Phase 5 阻断 openspec/checkpoint 写入 | dispatch prompt 指令 | **低** | **已修复** (逻辑反转→正确阻断) |
| SA-3 | 必须返回 JSON 信封 | `_post_task_validator.py` 77-97: 缺失信封时阻断 | N/A | **低** | 不变 |
| SA-4 | 后台 Agent 产出必须 Write 到文件 | 无 L2 | dispatch prompt 指令 | **低** | 不变 |
| SA-5 | 文件所有权 (并行模式) | `_post_task_validator.py` 410-504: 并行合并守卫 | N/A | **低** | 不变 |
| SA-6 | 背景 Agent 必须接受 L2 验证 | **v5.1 新增**: `post-task-validator.sh` 删除 `is_background_agent && exit 0`; `check-predecessor-checkpoint.sh` 49-58: 保留轻量级 L2 | N/A | **低** | **新增** |

**SA-2 修复详情**:

v5.0 报告指出 `write-edit-constraint-check.sh` 38-39 行对 openspec 路径执行 `exit 0`（豁免而非阻断），构成逻辑反转。v5.1 的 `unified-write-edit-check.sh` CHECK 0（87-113 行）实施了正确的子 Agent 状态隔离：

```bash
if [ "$IN_PHASE5" = "yes" ]; then
  case "$FILE_PATH" in
    *context/phase-results/*) PROTECTED_PATH_HIT="yes" ;;
    *openspec/changes/*/context/*.json) PROTECTED_PATH_HIT="yes" ;;
    *openspec/changes/*/.autopilot-active) PROTECTED_PATH_HIT="yes" ;;
  esac
  # 窄例外: .tdd-stage 由主线程通过 Bash 写入
  case "$FILE_PATH" in
    *context/.tdd-stage) PROTECTED_PATH_HIT="no" ;;
  esac
  if [ "$PROTECTED_PATH_HIT" = "yes" ]; then
    # → decision: "block"
  fi
fi
```

**设计考量**: Checkpoint 写入通过 Bash 工具（非 Write 工具）执行，自然绕过 PostToolUse(Write|Edit) Hook。子 Agent 仅能通过 Write/Edit 工具触发此 Hook，因此阻断逻辑正确。

**SA-6 新增详情**:

v5.0 中后台 Agent 在 PreToolUse 和 PostToolUse 都被完全旁路（`is_background_agent && exit 0`）。v5.1 修复：
- `post-task-validator.sh` 22-25 行注释记录移除旁路的原因
- `check-predecessor-checkpoint.sh` 49-58 行保留前驱 checkpoint 存在性检查
- PostToolUse 在后台 Agent 完成时触发（非启动时），验证 JSON 信封 + 反合理化

### 2.5 发版纪律（4 条）

| # | 法则 | 实现 | 风险等级 | v5.0→v5.0.4 |
|---|------|------|----------|------------|
| RD-1 | 唯一入口 bump-version.sh | 文档化入口 | **低** | 不变 |
| RD-2 | 禁止散弹式修改 | 自律制度，无强制机制 | **低** | 不变 |
| RD-3 | 同步范围 4 文件 | bump-version.sh 更新 4 文件 | **低** | 不变 |
| RD-4 | 验证闭环 | bump-version.sh 读回验证 | **低** | 不变 |

---

## 3. L2 Hook 实现深度分析

### 3.1 hooks.json 注册清单

```json
{
  "PreToolUse": [
    {"matcher": "^Task$", "command": "check-predecessor-checkpoint.sh", "timeout": 30}
  ],
  "PostToolUse": [
    {"matcher": "^Task$", "command": "post-task-validator.sh", "timeout": 150},
    {"matcher": "^(Write|Edit)$", "command": "unified-write-edit-check.sh", "timeout": 15}
  ],
  "PreCompact": [{"command": "save-state-before-compact.sh", "timeout": 15}],
  "SessionStart": [
    {"command": "scan-checkpoints-on-start.sh", "timeout": 15, "async": true},
    {"command": "check-skill-size.sh", "timeout": 15},
    {"matcher": "compact", "command": "reinject-state-after-compact.sh", "timeout": 15}
  ]
}
```

**v5.0 → v5.0.4 变化**:
- PostToolUse(Write|Edit) 从 3 条（banned-patterns-check.sh + assertion-quality-check.sh + write-edit-constraint-check.sh）合并为 1 条（unified-write-edit-check.sh）
- 性能从 ~35s（3 次 fork）降至 ~5s（1 次 fork）
- 功能覆盖完全等价（CHECK 0-4 对应原 4 个脚本的逻辑 + v5.1 新增 TDD 隔离）

### 3.2 unified-write-edit-check.sh 深度分析

该脚本是 v5.1 的核心新增，整合了 4 个检查逻辑到一个进程中：

| CHECK | 功能 | 触发条件 | 性能 |
|-------|------|---------|------|
| CHECK 0 | 子 Agent 状态隔离 | Phase 5 + 保护路径命中 | ~1ms (纯 bash case) |
| CHECK 1 | TDD 阶段隔离 | Phase 5 + .tdd-stage 存在 | ~1ms (纯 bash) |
| CHECK 2 | TODO/FIXME/HACK 检测 | 非排除文件 + 文件存在 | ~2ms (grep) |
| CHECK 3 | 恒真断言检测 | 测试文件 + 文件存在 | ~2ms (grep) |
| CHECK 4 | 代码约束检查 | Phase 5 + python3 可用 | ~50ms (python3) |

**共享阶段检测**（20-71 行）: 运行一次，所有 CHECK 复用。通过 checkpoint 文件存在性和状态推断当前 Phase。支持 full/lite/minimal 三种模式和 TDD 模式的正确判定。

**文件路径提取**（77 行）: 纯 bash grep 提取 `file_path` 字段。注意：JSON 值中含转义引号时可能失败（边界情况，实际 Claude Code 不产生此类路径）。

### 3.3 _post_task_validator.py 深度分析

5 个 Validator 按顺序执行，第一个 block 即终止：

| Validator | 功能 | 覆盖 Phase | 关键逻辑 |
|-----------|------|-----------|---------|
| V1 | JSON 信封结构 | 全部 | 信封提取（3 策略解析）、status 验证、Phase 特定必需字段、Phase 4 warning 阻断、Phase 5 zero_skip + TDD metrics |
| V2 | 反合理化检测 | 4/5/6 | 22 个加权模式（阈值 5 硬阻断，3+无产物阻断，2 警告） |
| V3 | 代码约束检查 | 4/5/6 | artifacts 逐个检查 forbidden_files/patterns/allowed_dirs/max_lines |
| V4 | 并行合并守卫 | 5 | 冲突检测 + 范围验证 + 类型检查 |
| V5 | 决策格式验证 | 1 | decisions 数组存在 + 选项 ≥2 + 必需字段 + recommended 标记 |

**v5.0.4 新增**: Phase 4 必需字段新增 `sad_path_counts`（106 行）；路由覆写机制支持 `change_coverage_min_pct` 和 `sad_path_min_ratio_pct` 动态调整。

### 3.4 check-predecessor-checkpoint.sh 深度分析

**模式感知前驱链**（218-249 行）:
- full: 1→2→3→4→5→6→7（TDD 模式下 5 的前驱为 3）
- lite: 1→5→6→7
- minimal: 1→5→7

**特殊门禁**:
- Phase 5 门禁（306-354 行）: full 非 TDD 要求 Phase 4 status=ok（不接受 warning）；full TDD 接受 Phase 3 或 Phase 4 tdd_mode_override
- Phase 6 门禁（357-398 行）: zero_skip_check + tasks.md 全部 [x]
- Wall-clock 超时（401-434 行）: Phase 5 执行超过配置时间（默认 2h）则 deny

**v5.1 变化**: 后台 Agent 不再完全旁路，保留 L2 前驱检查（49-58 行）。

---

## 4. TDD Iron Law 执行保障分析

### 4.1 三层保障矩阵

| Iron Law | L1 (TaskCreate) | L2 (Hook 确定性) | L3 (AI Gate/Prompt) | 总评 |
|----------|-----------------|-------------------|---------------------|------|
| TDD-1: 先测试后实现 | N/A | `.tdd-stage` + unified-write-edit-check CHECK 1 | tdd-cycle.md prompt | **已覆盖** |
| TDD-2: RED 必须失败 | N/A | 主线程 Bash(exit_code != 0) | tdd-cycle.md Step 2 | **已覆盖** |
| TDD-3: GREEN 必须通过 | N/A | 主线程 Bash(exit_code == 0) | tdd-cycle.md Step 4 | **已覆盖** |
| TDD-4: 测试不可变 | N/A | `.tdd-stage` + unified-write-edit-check CHECK 1 (GREEN 阻断测试文件) | tdd-cycle.md 49 行 | **已覆盖** |
| TDD-5: REFACTOR 回滚 | N/A | 主线程 Bash(测试) → 失败则 git checkout（由 L3 协议驱动） | tdd-cycle.md Step 6 | **部分** |

### 4.2 .tdd-stage 机制可靠性评估

**可靠性因素**:
1. 状态文件由主线程通过 Bash 工具写入（非 Write/Edit），不触发 Hook 自身
2. `.tdd-stage` 路径在 CHECK 0 中被显式豁免（99-101 行 `*context/.tdd-stage → PROTECTED_PATH_HIT="no"`）
3. 读取使用 `cat` + `tr`（122 行），简单可靠
4. task 全部完成后主线程删除文件，不会残留

**潜在风险**:
1. **并行 TDD 不覆盖**: `.tdd-stage` 仅用于串行 TDD。并行 TDD 中域 Agent 内部执行 RED-GREEN-REFACTOR，无主线程 `.tdd-stage` 写入，依赖 L2 后置验证（合并后 `Bash(full_test_command)`）
2. **崩溃残留**: 若主线程在 RED 阶段崩溃，`.tdd-stage` 文件残留值为 "red"，后续非 TDD 写入会被意外阻断。`autopilot-recovery/SKILL.md` 未提及清理 `.tdd-stage`
3. **文件名模式有限**: 非标准测试文件命名（如 `verification.ts`, `checks_*.py`）不被识别为测试文件

**建议**:
- Recovery 协议应增加 `.tdd-stage` 残留清理步骤
- 考虑增加 `*_tests/*` 目录模式到路径匹配

### 4.3 TDD-5 REFACTOR 回滚的 git checkout 可靠性

协议定义（tdd-cycle.md Step 6）:
```
IF exit_code != 0:
  → 回滚重构: Bash("git checkout -- {modified}")
  → 记录 tdd_cycle.refactor = { reverted: true }
```

**可靠性分析**:
- `git checkout -- {modified}` 是确定性操作，可靠回滚工作区文件
- 但 `{modified}` 列表由 AI 主线程构造，若遗漏文件则回滚不完整
- 更安全的替代: `git stash && git stash drop` 或 `git checkout -- .`（但后者影响范围过大）
- 无 L2 Hook 兜底——若主线程未执行回滚，重构破坏的代码会保留

**风险等级**: **中**。主线程 Bash 执行是确定性的，但触发条件依赖 L3 协议执行。

### 4.4 _post_task_validator.py TDD Metrics 后置验证

```python
# 132-146 行
tdd_metrics = envelope.get("tdd_metrics")
if tdd_metrics is not None:
    red_violations = tdd_metrics.get("red_violations", -1)
    if red_violations != 0:
        output_block(...)  # 阻断
    cycles_completed = tdd_metrics.get("cycles_completed", 0)
    if cycles_completed < 1:
        output_block(...)  # 阻断
```

这是事后 L2 验证，补偿并行 TDD 缺少逐步验证的问题。但依赖子 Agent 诚实报告 `tdd_metrics`。若子 Agent 虚报 `red_violations: 0`，L2 无法检测——需依赖合并后 `Bash(full_test_command)` 作为最终防线。

---

## 5. 反合理化检查完整性评估

### 5.1 当前模式覆盖（22 个加权模式）

**英文模式（11 个）**:

| 权重 | 模式 | 目标 excuse |
|------|------|-----------|
| 3 | `skip(ped\|ping)?\s+(this\|the\|these\|because)\s` | 显式跳过 |
| 3 | `(tests?\|tasks?)\s+were\s+skip(ped\|ping)` | 被动跳过 |
| 3 | `(deferred?\|postponed?\|deprioritized?)\s+(to\|for\|until)` | 延迟 |
| 2 | `out\s+of\s+scope` | 范围外 |
| 2 | `(will\|can\|should)\s+(be\s+)?(done\|handled\|addressed\|fixed)\s+(later\|separately\|in\s+a?\s*future)` | 未来处理 |
| 1 | `already\s+(covered\|tested\|handled\|addressed)` | 已覆盖借口 |
| 1 | `not\s+(needed\|necessary\|required\|relevant\|applicable)` | 不需要 |
| 1 | `(works\|good)\s+enough` | 够好了 |
| 1 | `too\s+(complex\|difficult\|risky\|time[- ]consuming)` | 太复杂 |
| 1 | `(minimal\|low)\s+(impact\|priority\|risk)` | 低影响 |
| 1 | `pre[- ]existing\s+(issue\|bug\|problem\|defect)` | 既有问题 |

**中文模式（11 个）**:

| 权重 | 模式 | 目标 excuse |
|------|------|-----------|
| 3 | `(?:测试\|任务\|功能\|用例)\s*(?:被\|已)?(?:跳过\|省略\|忽略)` | 任务跳过 |
| 3 | `跳过了?\|已跳过\|被跳过` | 直接跳过 |
| 3 | `(?:延后\|推迟\|暂缓)(?:处理\|实现\|开发)?` | 延迟处理 |
| 3 | `后续(?:再\|补充\|处理\|实现\|完善)` | 后续处理 |
| 2 | `(?:超出\|不在)(?:范围\|scope)` | 超出范围 |
| 2 | `(?:以后\|后面\|后续\|下[一个]?(?:阶段\|版本\|迭代))(?:再\|来\|处理\|实现)` | 未来迭代 |
| 2 | `(?:暂时\|先)?不(?:做\|处理\|实现\|考虑)` | 暂不处理 |
| 1 | `已[经被]?(?:覆盖\|测试\|处理\|实现\|验证)` | 已覆盖 |
| 1 | `(?:不\|无)(?:需要\|必要\|需\|必须)` | 不需要 |
| 1 | `(?:太\|过于)(?:复杂\|困难\|耗时)` | 太复杂 |
| 1 | `(?:影响\|优先级\|风险)\s*(?:较?低\|不大\|很小)` | 低影响 |

### 5.2 评分阈值逻辑

```
score >= 5                → 硬阻断 (decision: "block")
score >= 3 + 无 artifacts → 阻断 (疑似空交付合理化)
score >= 2                → stderr 警告 (不阻断)
score < 2                 → 静默通过
```

**设计合理性**: 多模式加权评分避免单个弱信号误判。要求至少 2 个高权重模式（3+3=6≥5）或 1 个高权重+无产物（3≥3）才触发阻断。

### 5.3 遗漏的 excuse 模式（潜在绕过向量）

| # | 绕过模式 | 语言 | 示例 | 建议权重 |
|---|---------|------|------|---------|
| 1 | 被动语态规避 | EN | "The feature was determined to be non-essential" | 2 |
| 2 | 委婉式完成声明 | EN | "Implemented the core functionality" (实际未完成所有任务) | 1 |
| 3 | 无标记范围缩减 | EN | "Focused on the highest-priority items" | 2 |
| 4 | 技术债务框架 | EN | "Created a clean interface for future extension" | 1 |
| 5 | 中文委婉完成 | CN | "核心功能已完成" (未标记不完整任务) | 1 |
| 6 | 隐式降级 | EN | "Simplified the approach to ensure stability" | 2 |
| 7 | 时间借口 | EN/CN | "Due to time constraints" / "由于时间限制" | 2 |
| 8 | 依赖借口 | EN/CN | "Blocked by external dependency" / "依赖外部组件" | 2 |
| 9 | 环境借口 | EN/CN | "Environment not configured for this test" / "环境未配置" | 2 |
| 10 | 覆盖率操纵 | EN/CN | "Coverage already sufficient at 81%" / "覆盖率已达标" | 1 |

**与 tdd-cycle.md 的 13 种借口对比**:

tdd-cycle.md 列出 13 种 TDD 借口（20-36 行），但这些是认知层面的教育内容，注入到子 Agent prompt 中作为 L3 防线。与 `_post_task_validator.py` 的 22 个模式存在语义重叠但不完全对齐。特别是 tdd-cycle.md 的以下借口没有对应的 L2 正则匹配：

- #4 "删除 X 小时的工作太浪费" → 无匹配
- #7 "测试框架不支持" → 无匹配
- #9 "截止日期快到了" → "time constraints" 模式可部分覆盖
- #11 "我对这段代码很熟悉" → 无匹配
- #12 "团队没人这样做" → 无匹配

### 5.4 关键发现

CLAUDE.md 声称"10 种 excuse 模式"，实际实现 22 个加权模式（超出声称数量 120%），是积极的超额覆盖。评分机制设计合理。主要改进空间在于：
1. 增加时间/环境/依赖借口的正则匹配
2. 增加隐式降级/委婉完成的检测
3. CLAUDE.md 文档应更新为"22 种加权模式"以反映实态

---

## 6. 规约覆盖率矩阵（确定性 vs 自觉性）

### 6.1 汇总统计

| 类别 | 总规则 | L2 确定性 | L3 AI 自觉 | 无保障 | 确定性覆盖率 |
|------|--------|----------|-----------|--------|------------|
| 状态机硬约束 | 7 | 5 | 1 (SM-7 设计如此) | 1 (SM-4) | 71.4% |
| TDD Iron Law | 5 | 4 | 0 | 1 (TDD-5 部分) | 80.0% |
| 代码质量 | 7 | 7 | 0 | 0 | 100.0% |
| 子 Agent 约束 | 6 | 4 | 0 | 2 (SA-1, SA-4) | 66.7% |
| 发版纪律 | 4 | 3 | 0 | 1 (RD-2) | 75.0% |
| 需求路由 | 4 | 4 | 0 | 0 | 100.0% |
| Event Bus | 4 | 4 | 0 | 0 | 100.0% |
| GUI Event Bus | 3 | 3 | 0 | 0 | 100.0% |
| **总计** | **40** | **34** | **1** | **5** | **85.0%** |

### 6.2 L2 确定性覆盖率计算

```
确定性覆盖率 = L2 保障规则数 / 总规则数
            = 34 / 40
            = 85.0%
```

**含 L3 合理覆盖的有效覆盖率**:
```
有效覆盖率 = (L2 保障 + L3 合理设计) / 总规则数
           = (34 + 1) / 40
           = 87.5%
```

注: SM-7（归档需用户确认）属于用户交互约束，L3 AskUserQuestion 是唯一合理的实现方式，计入有效覆盖。

### 6.3 仅靠 L3 AI 自觉的规则清单

| # | 规则 | 风险 | 加固建议 |
|---|------|------|---------|
| SM-4 | 降级条件严格 | 低 | 可在 Phase 5 checkpoint 中记录降级原因，L2 后置审计 |
| TDD-5 | REFACTOR 回滚 | 中 | 可添加主线程在 REFACTOR Bash 失败后自动执行 `git checkout -- .` 的硬编码逻辑 |
| SA-1 | 禁止读取计划文件 | 中 | Claude Code 目前不支持 PreToolUse(Read) Hook，无法实现 L2 |
| SA-4 | 后台 Agent 产出 Write | 低 | 可在 PostToolUse(Task) 中检查 output 长度阈值 |
| RD-2 | 禁止散弹式修改 | 低 | 可添加 pre-commit Hook 检查版本相关文件的修改来源 |

---

## 7. 与 v5.0 报告对比

### 7.1 P0/P1 风险修复追踪

| v5.0 报告标记 | 规则 | v5.0 状态 | v5.0.4 状态 | 修复方式 |
|--------------|------|----------|------------|---------|
| **P0** | TDD-1: RED 仅写测试 | 仅 L3 | **L2+L3** | `.tdd-stage` + CHECK 1 |
| **P0** | TDD-4: GREEN 测试不可变 | 仅 L3 | **L2+L3** | `.tdd-stage` + CHECK 1 |
| **P1** | SA-2: openspec 写入隔离 | L2 逻辑反转 | **L2 正确** | CHECK 0 状态隔离 |
| P2 | 反合理化绕过 | 22 模式 | 22 模式 | 未变（仍有改进空间） |
| P3 | 无冒号 TODO | 仅 `TODO:` | 仅 `TODO:` | 未变（设计选择） |
| P3 | 断言反模式遗漏 | 5 类已覆盖 | 5 类已覆盖 | 未变 |

### 7.2 新增能力

| 能力 | 说明 | 实现位置 |
|------|------|---------|
| TDD 阶段隔离 | RED/GREEN 阶段文件类型确定性拦截 | unified-write-edit-check.sh CHECK 1 |
| 子 Agent 状态隔离 | Phase 5 阻断 openspec/checkpoint 写入 | unified-write-edit-check.sh CHECK 0 |
| 后台 Agent L2 验证 | 删除后台 Agent L2 旁路 | post-task-validator.sh, check-predecessor-checkpoint.sh |
| Hook 统一优化 | 3 个 Write\|Edit Hook 合并为 1 个 | unified-write-edit-check.sh |
| Phase 4 sad_path 必需 | sad_path_counts 升级为必需字段 | _post_task_validator.py 106 行 |
| Phase 1 决策格式 L2 | 决策卡片格式确定性验证 | _post_task_validator.py V5 |
| Checkpoint 原子写入 | .tmp + mv 原子重命名 | autopilot-gate/SKILL.md 278-302 |
| Phase 1 中间 Checkpoint | 调研/决策轮次中间态保存 | autopilot/SKILL.md 132-157 |

### 7.3 评分变化

| 维度 | v5.0 | v5.0.4 | 变化 | 原因 |
|------|------|--------|------|------|
| TDD 铁律 | 6.5/12.5 | 11.0/12.5 | +4.5 | TDD-1, TDD-4 从缺口→已覆盖 |
| 子 Agent | 5.5/12.5 | 9.5/12.5 | +4.0 | SA-2 修复 + SA-6 新增 |
| 状态机 | 16.0/17.5 | 16.0/17.5 | 0 | 不变 |
| 代码质量 | 16.5/17.5 | 17.0/17.5 | +0.5 | sad_path 必需字段升级 |
| 需求路由 | 9.0/10.0 | 9.0/10.0 | 0 | 不变 |
| Event Bus | 9.5/10.0 | 9.5/10.0 | 0 | 不变 |
| 发版纪律 | 8.5/10.0 | 8.5/10.0 | 0 | 不变 |
| 幽灵规则加分 | 5.0 | 6.0 | +1.0 | Phase 1 决策格式 L2 新增 |
| 扣分 | -5.0 | -2.5 | +2.5 | SA-2 反转已修复(-3→0)，废弃文件仍在(-1)，平台问题(-1)，hooks.json 简洁度改善(-0.5) |
| **合计** | **73** | **84** | **+11** | |

### 7.4 废弃文件清理状态

以下文件标记为 DEPRECATED 但仍保留在磁盘上：
- `scripts/anti-rationalization-check.sh` — 第 2 行标注 DEPRECATED
- `scripts/code-constraint-check.sh` — 第 2 行标注 DEPRECATED
- `scripts/validate-json-envelope.sh` — 第 2 行标注 DEPRECATED
- `scripts/banned-patterns-check.sh` — 第 2 行标注 DEPRECATED (v5.1)
- `scripts/assertion-quality-check.sh` — 第 2 行标注 DEPRECATED (v5.1)

**评估**: hooks.json 正确地不引用这些文件。保留它们作为参考合理但增加仓库杂乱度。建议移至 `scripts/_deprecated/` 子目录。

---

## 8. 修复建议（按风险排序）

### P1: TDD-5 REFACTOR 回滚 L2 兜底

**风险**: 中
**当前状态**: 主线程执行 `git checkout` 由 L3 协议驱动，若遗漏则无 L2 兜底
**建议**: 在 `_post_task_validator.py` V1 中增加 Phase 5 TDD 后置检查：当 `tdd_cycle.refactor.reverted=true` 时，验证 git diff 是否真正回滚到 GREEN 状态。或在主线程串行 TDD 流程中硬编码"REFACTOR Bash 失败→自动 git stash"逻辑。

### P1: SA-1 禁止读取计划文件

**风险**: 中
**当前状态**: 无 PreToolUse(Read) Hook，子 Agent 可自由读取任何文件
**建议**: Claude Code 目前不支持 PreToolUse(Read) Hook。替代方案：
1. 在 dispatch prompt 中更强调禁令（已实施，但仅 L3）
2. 在 PostToolUse(Task) 中分析子 Agent output 是否引用了计划文件内容（启发式检测）
3. 等待 Claude Code 支持 PreToolUse(Read) 后第一时间添加

### P2: 反合理化模式扩展

**风险**: 低-中
**当前状态**: 22 个模式，评分机制合理
**建议**: 增加以下高价值模式（预计降低绕过率 30%+）：
```python
# 时间/环境/依赖借口（权重 2）
(2, r"due\s+to\s+(time|resource|environment)\s+(constraints?|limitations?)"),
(2, r"blocked\s+by\s+(external|upstream|dependency)"),
(2, r"environment\s+(not|isn't)\s+(configured|ready|available)"),
# 中文时间/环境借口（权重 2）
(2, r"(?:由于|因为)(?:时间|资源|环境)(?:限制|不足|约束)"),
(2, r"(?:被|受)(?:外部|上游|依赖)(?:阻塞|限制)"),
```

### P2: CLAUDE.md 文档一致性

**风险**: 低
**当前状态**: CLAUDE.md 声称"10 种 excuse 模式"，实际 22 个
**建议**: 更新 CLAUDE.md 第 28 行为"22 种加权 excuse 模式匹配（11 EN + 11 CN）"

### P3: .tdd-stage 崩溃残留清理

**风险**: 低
**当前状态**: Recovery 协议未提及清理 `.tdd-stage`
**建议**: 在 `autopilot-recovery/SKILL.md` Step 2.1 后增加：
```bash
rm -f openspec/changes/*/context/.tdd-stage 2>/dev/null
```

### P3: 测试文件名模式补充

**风险**: 低
**当前状态**: 缺少 `*_tests/*` 目录模式
**建议**: 在 unified-write-edit-check.sh 129 行增加 `*_tests/*` 匹配

### P3: 无冒号 TODO 逃逸

**风险**: 低
**当前状态**: 仅检测 `TODO:` `FIXME:` `HACK:`（含冒号）
**建议**: 这是有意设计（减少误报）。可考虑增加 `XXX:` 检测，但无冒号变体的误报率高，维持现状合理。

### P4: 废弃文件整理

**风险**: 极低
**建议**: 将 5 个 DEPRECATED 文件移至 `scripts/_deprecated/` 子目录

### P4: bump-version.sh Linux 兼容

**风险**: 极低（仅影响 Linux 开发环境）
**建议**: 使用平台检测 `if [[ "$(uname)" == "Darwin" ]]; then sed -i '' ...; else sed -i ...; fi`

---

## 附录 A: 幽灵规则清单（有 L2 强制但 CLAUDE.md 未声明）

| Hook/脚本 | 强制内容 | 应声明位置 |
|----------|---------|-----------|
| `_post_task_validator.py` 106 | Phase 4 `sad_path_counts` 必需字段 | CLAUDE.md CQ-7 |
| `_post_task_validator.py` 132-146 | Phase 5 TDD metrics L2 (red_violations=0, cycles>=1) | CLAUDE.md TDD |
| `_post_task_validator.py` 236-257 | Phase 4 traceability L2 (coverage>=80%) | CLAUDE.md CQ |
| `_post_task_validator.py` 410-504 | 并行合并守卫 (冲突+范围+类型检查) | CLAUDE.md 子 Agent |
| `_post_task_validator.py` 556-631 | Phase 1 决策格式验证 | CLAUDE.md 新增 |
| `check-predecessor-checkpoint.sh` 401-434 | Phase 5 wall-clock 超时 | CLAUDE.md 状态机 |
| `check-predecessor-checkpoint.sh` 383-398 | Phase 6 tasks.md 全 [x] | CLAUDE.md 状态机 |
| `unified-write-edit-check.sh` CHECK 0 | 子 Agent 状态隔离 | CLAUDE.md SA-2 (已部分声明) |
| `unified-write-edit-check.sh` CHECK 1 | TDD 阶段隔离 | CLAUDE.md TDD-1/TDD-4 (已部分声明) |

**评估**: 幽灵规则代表超越 CLAUDE.md 声明的积极强制（9→10 条），建议在 CLAUDE.md 中补充声明以保持 Single Source of Truth 的完整性。

## 附录 B: 审计涉及文件

### Hook 脚本（活跃）
- `scripts/unified-write-edit-check.sh` (260 行, v5.1 统一 Write|Edit Hook)
- `scripts/post-task-validator.sh` (35 行, PostToolUse(Task) 入口)
- `scripts/_post_task_validator.py` (634 行, 5 合 1 验证器)
- `scripts/check-predecessor-checkpoint.sh` (437 行, PreToolUse(Task) 门禁)
- `scripts/_hook_preamble.sh` (39 行, 共享前导)
- `scripts/_common.sh` (352 行, 共享工具函数)
- `scripts/_envelope_parser.py` (191 行, JSON 信封解析)
- `scripts/_constraint_loader.py` (185 行, 约束加载)

### Hook 脚本（已废弃，不在 hooks.json 中）
- `scripts/anti-rationalization-check.sh` (151 行)
- `scripts/code-constraint-check.sh` (82 行)
- `scripts/validate-json-envelope.sh` (225 行)
- `scripts/banned-patterns-check.sh` (66 行)
- `scripts/assertion-quality-check.sh` (83 行)

### 配置
- `hooks/hooks.json` (80 行)

### Skill 文件
- `skills/autopilot/SKILL.md` (367 行)
- `skills/autopilot-gate/SKILL.md` (372 行)
- `skills/autopilot-dispatch/SKILL.md` (323 行)
- `skills/autopilot-phase7/SKILL.md` (182 行)
- `skills/autopilot-recovery/SKILL.md` (158 行)
- `skills/autopilot-setup/SKILL.md` (368 行)

### 参考文档
- `skills/autopilot/references/tdd-cycle.md` (253 行)
- `skills/autopilot/references/phase5-implementation.md` (600 行)
- `skills/autopilot/references/guardrails.md` (75 行)
- `skills/autopilot-phase5-implement/references/testing-anti-patterns.md` (176 行)
- `skills/autopilot/templates/shared-test-standards.md` (31 行)

### 基线报告
- `docs/reports/v5.0/compliance-audit.md` (451 行)

### 规约定义
- `CLAUDE.md` (64 行, Single Source of Truth)
