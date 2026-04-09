# 全局规约与记忆遵守度审计报告

**审计日期**: 2026-03-13
**插件版本**: v5.0（基于 CLAUDE.md 上下文）
**审计方**: AI 合规审计 Agent (Opus 4.6)
**事实来源**: `plugins/spec-autopilot/CLAUDE.md`

---

## 1. 执行摘要

spec-autopilot 插件展现了成熟的多层合规架构。CLAUDE.md 中跨 7 个约束类别列举的 **39 条离散规则**中，**34 条具有确定性 (L2) 或 AI 辅助 (L3) 强制执行**，初始覆盖率 **87.2%**。5 条规则存在从部分到缺失的执行缺口。三层门禁架构 (L1 TaskCreate + L2 Hook + L3 AI Gate) 提供了纵深防御，关键发现是若干规则仅作为 L3 软执行（AI 提示指令）存在，缺少 L2 确定性兜底。

三个已弃用的独立脚本（`anti-rationalization-check.sh`、`code-constraint-check.sh`、`validate-json-envelope.sh`）已整合到 `_post_task_validator.py`（通过 `post-task-validator.sh`）——架构决策合理，但独立文件仍保留在磁盘上带有 DEPRECATED 头。hooks.json 正确地仅引用统一的 `post-task-validator.sh`。

---

## 2. 覆盖矩阵

### 2.1 状态机硬约束 (7 条规则)

| # | CLAUDE.md 规则 | L2 Hook 强制 | L3 Skill 强制 | 状态 |
|---|---------------|-------------|--------------|------|
| SM-1 | Phase N 要求 Phase N-1 checkpoint ok/warning | `check-predecessor-checkpoint.sh` 252-304 行: 模式感知前驱逻辑 + deny() | `autopilot-gate/SKILL.md`: 8 步清单步骤 6 | **已覆盖** (L2+L3) |
| SM-2 | 三层门禁联防 (L1+L2+L3) | hooks.json: PreToolUse(Task) + PostToolUse(Task) + PostToolUse(Write\|Edit) | `autopilot-gate/SKILL.md` 17-23 行: 显式 L1/L2/L3 表格 | **已覆盖** (架构) |
| SM-3 | 模式路径互斥 | `check-predecessor-checkpoint.sh` 219-249 行: get_predecessor_phase() 强制模式路径; 256-275 行: 拒绝非 Full 模式下的 Phase 2/3/4 | `autopilot/SKILL.md` 226-229 行: HARD CONSTRAINT 标注 | **已覆盖** (L2+L3) |
| SM-4 | 降级仅限合并失败>3 或连续2组失败或用户选择 | 无 L2 强制 | `autopilot/SKILL.md` 231 行: 记录但仅 L3 | **部分** (仅 L3) |
| SM-5 | Phase 4 不接受 warning | `_post_task_validator.py` 157-159 行: 确定性阻断 | `autopilot-gate/SKILL.md` 88-105 行 | **已覆盖** (L2+L3) |
| SM-6 | Phase 5 zero_skip_check passed===true | `_post_task_validator.py` 124-130 行: 阻断; `check-predecessor-checkpoint.sh` 358-381 行: Phase 6 门禁检查 | `autopilot-gate/SKILL.md` 107-114 行 | **已覆盖** (L2+L3) |
| SM-7 | 归档需用户确认 | 无 L2 强制（用户交互无法 L2 门禁化） | `autopilot-phase7/SKILL.md` 91-99 行: AskUserQuestion 强制 | **已覆盖** (L3 设计如此) |

### 2.2 TDD 铁律 (5 条规则，tdd_mode: true 时生效)

| # | CLAUDE.md 规则 | L2 Hook 强制 | L3 Skill 强制 | 状态 |
|---|---------------|-------------|--------------|------|
| TDD-1 | RED 仅写测试，GREEN 仅写实现 | 无 L2 Hook（Write\|Edit Hook 不检查 TDD 阶段） | `tdd-cycle.md` 63-78 行: prompt 注入指令 | **缺口** (仅 L3) |
| TDD-2 | RED 必须失败 (exit_code ≠ 0) | 无直接 L2 Hook; 依赖主线程 Bash() L2 验证 | `tdd-cycle.md` 69-78 行: 主线程 Bash 验证协议 | **已覆盖** (L2 通过主线程 Bash) |
| TDD-3 | GREEN 必须通过 (exit_code = 0) | 无直接 L2 Hook; 依赖主线程 Bash() L2 验证 | `tdd-cycle.md`: GREEN 验证 | **已覆盖** (L2 通过主线程 Bash) |
| TDD-4 | 测试不可变（GREEN 禁止修改测试） | 无 L2 Hook 检测 GREEN 阶段的测试文件修改 | tdd-cycle.md 49 行: 仅 prompt 指令 | **缺口** (仅 L3) |
| TDD-5 | REFACTOR 破坏测试自动回滚 | 无 L2 Hook | `tdd-cycle.md`: git checkout 协议 | **部分** (L3 协议, 无 L2 兜底) |

### 2.3 代码质量硬约束 (7 条规则)

| # | CLAUDE.md 规则 | L2 Hook 强制 | L3 Skill 强制 | 状态 |
|---|---------------|-------------|--------------|------|
| CQ-1 | 禁止 TODO/FIXME/HACK | `banned-patterns-check.sh` 47-51 行: grep 扫描 Write\|Edit | N/A | **已覆盖** (L2) |
| CQ-2 | 禁止恒真断言 | `assertion-quality-check.sh` 43-66 行: 多语言模式匹配 | N/A | **已覆盖** (L2) |
| CQ-3 | 反合理化 (声称10模式) | `_post_task_validator.py` 316-378 行: 22 个加权模式 (11 EN + 11 CN)，评分阻断 | N/A | **已覆盖** (L2，实际超出 CLAUDE.md 声称的"10 模式"——实为 22 个) |
| CQ-4 | 代码约束 (forbidden_files/patterns) | `write-edit-constraint-check.sh`: PostToolUse(Write\|Edit); `_post_task_validator.py` 382-403 行: PostToolUse(Task) 产物检查 | N/A | **已覆盖** (L2, 双重强制) |
| CQ-5 | 测试金字塔地板 (unit≥30%, e2e≤40%, total≥10) | `_post_task_validator.py` 203-234 行: 可配置地板验证 | `autopilot-gate/SKILL.md` 88-105 行 | **已覆盖** (L2+L3) |
| CQ-6 | 变更覆盖率 ≥ 80% | `_post_task_validator.py` 259-273 行: 阻断验证，支持 routing_overrides | `autopilot-gate/SKILL.md` | **已覆盖** (L2+L3) |
| CQ-7 | Sad path 比例 ≥ 20%/类型 | `_post_task_validator.py` 275-303 行: 按类型比例验证，支持路由覆写 | N/A | **已覆盖** (L2) |

### 2.4 需求路由 (4 组规则)

| # | CLAUDE.md 规则 | L2 Hook 强制 | L3 Skill 强制 | 状态 |
|---|---------------|-------------|--------------|------|
| RR-1 | 自动分类 (Feature/Bugfix/Refactor/Chore) | 无 L2 对分类正确性的强制 | `autopilot-dispatch/SKILL.md`: Phase 1 信封 `requirement_type` | **部分** (L3 分类, L2 验证下游阈值) |
| RR-2 | Bugfix: sad_path≥40%, coverage=100%, 复现测试 | `_post_task_validator.py` 207-213 行: routing_overrides 动态调整阈值 | N/A | **已覆盖** (L2 动态阈值) |
| RR-3 | Refactor: coverage=100%, 行为保持测试 | 同 RR-2 机制 | N/A | **已覆盖** (L2 动态阈值) |
| RR-4 | Chore: coverage≥60%, typecheck 即可 | 同机制; chore 设置更低的 routing_overrides | N/A | **已覆盖** (L2 动态阈值) |

### 2.5 GUI Event Bus API

| # | CLAUDE.md 规则 | 实现 | 状态 |
|---|---------------|------|------|
| EB-1 | phase_start/phase_end 事件 | `emit-phase-event.sh`: 验证 event_type ∈ {phase_start, phase_end, error} | **已覆盖** |
| EB-2 | gate_pass/gate_block 事件 | `emit-gate-event.sh`: 验证 event_type ∈ {gate_pass, gate_block} | **已覆盖** |
| EB-3 | ISO-8601 时间戳 + phase + mode + payload | 两个脚本 43 行通过 python3 生成 ISO-8601; 事件 JSON 包含 phase, mode, payload | **已覆盖** |
| EB-4 | 输出到 logs/events.jsonl | 两个脚本 106-110 行追加到 events.jsonl | **已覆盖** |

### 2.6 子 Agent 约束 (5 条规则)

| # | CLAUDE.md 规则 | L2 Hook 强制 | L3 Skill 强制 | 状态 |
|---|---------------|-------------|--------------|------|
| SA-1 | 禁止自行读取计划文件 | 无 L2 强制（无法阻断特定路径的 Read） | `parallel-dispatch.md` 25 行; `autopilot-dispatch/SKILL.md` | **缺口** (仅 L3, 无 L2) |
| SA-2 | 禁止修改 openspec/checkpoint | `write-edit-constraint-check.sh` 38-39 行: **豁免**（exit 0）openspec 路径，而非阻断 | dispatch prompt 指令 | **缺口** (L2 实际上豁免了这些路径, 未阻断) |
| SA-3 | 必须返回 JSON 信封 | `_post_task_validator.py` 77-97 行: 缺失/无效信封时阻断 | N/A | **已覆盖** (L2) |
| SA-4 | 后台 Agent 产出必须 Write 到文件 | 无 L2 强制 | dispatch prompt 指令 | **缺口** (仅 L3) |
| SA-5 | 文件所有权 (并行模式) | `_post_task_validator.py` 410-504 行: 并行合并守卫检查范围 | N/A | **已覆盖** (L2) |

### 2.7 发版纪律 (4 条规则)

| # | CLAUDE.md 规则 | 实现 | 状态 |
|---|---------------|------|------|
| RD-1 | 唯一入口 bump-version.sh | `bump-version.sh` 存在且为文档化入口 | **已覆盖** (流程纪律) |
| RD-2 | 禁止散弹式修改 | 无强制机制阻止直接文件编辑 | **部分** (自律制度) |
| RD-3 | 同步范围: 4 个文件 | `bump-version.sh` 78-113 行: 更新 plugin.json, marketplace.json, README.md, CHANGELOG.md | **已覆盖** |
| RD-4 | 验证闭环 | `bump-version.sh` 119-144 行: 读回全部 4 个文件验证一致性，不匹配则 exit 1 | **已覆盖** |

---

## 3. TDD 合规深度分析

### 3.1 tdd-cycle.md vs CLAUDE.md 铁律

| 铁律 | tdd-cycle.md 覆盖 | 缺口 |
|------|------------------|------|
| "RED 仅写测试" | 63-78 行: prompt 指令"子 Agent 仅写测试文件，禁止写实现" | 无 L2 Hook 阻止 RED 阶段子 Agent 写入实现文件。完全依赖 prompt 遵从 |
| "RED 必须失败" | 69-78 行: 主线程 `Bash("{test_command}")` 验证 exit_code ≠ 0 | 通过主线程 Bash L2 正确实现。检查区分断言失败和语法错误 |
| "GREEN 必须通过" | GREEN 章节记录 | 通过主线程 Bash L2 正确实现 |
| "GREEN 测试不可变" | 49 行: "GREEN 阶段修改测试 → 禁止，修复实现" | 无 L2 机制。GREEN 阶段子 Agent 可修改测试文件，无 Hook 阻断。`write-edit-constraint-check.sh` 仅检查 code_constraints，不感知 TDD 阶段 |
| "REFACTOR 自动回滚" | 记录为测试失败时 `git checkout` | 仅 L3。主线程必须执行此操作，但若 AI 未执行则无 L2 兜底 |

### 3.2 TDD 指标 L2 验证

`_post_task_validator.py` 132-146 行在 Phase 5 信封中存在 tdd_metrics 时提供 L2 验证:
- `red_violations` 必须等于 0
- `cycles_completed` 必须 ≥ 1

这是一个积极发现——提供了事后 L2 验证 TDD 协议是否被遵循，部分补偿了缺少逐步 L2 强制的问题。

### 3.3 关键 TDD 缺口

**TDD-1 和 TDD-4 完全没有 L2 强制。** RED 阶段期间，没有机制阻止子 Agent 在测试旁写入实现代码。GREEN 阶段期间，没有机制阻止修改测试文件。完全依赖 prompt 遵从。`write-edit-constraint-check.sh` Hook 不知道当前 TDD 阶段，无法强制阶段特定的文件限制。

**建议**: 添加感知 TDD 阶段的 Write/Edit Hook，从状态文件（如 `phase5-tasks/task-N-tdd-phase.txt`）读取当前 TDD 阶段，阻断超出允许范围的文件修改。

---

## 4. 反幻觉分析

### 4.1 反合理化模式覆盖

CLAUDE.md 声称"10 种 excuse 模式"。实际实现 `_post_task_validator.py` 316-339 行包含 **22 个加权模式**（11 英文 + 11 中文），按置信权重组织 (1-3)。超出声称数量。

**模式分类覆盖:**
- 跳过/遗漏信号（权重 3）: 6 个模式
- 范围/延迟信号（权重 2）: 5 个模式
- 弱合理化信号（权重 1）: 11 个模式

**评分阈值:**
- 分数 ≥ 5: 硬阻断
- 分数 ≥ 3 + 无产物: 阻断
- 分数 ≥ 2: 仅 stderr 警告
- 分数 < 2: 通过

### 4.2 潜在绕过向量

以下 excuse 模式可能绕过当前检测:

1. **被动语态规避**: "The feature was determined to be non-essential" —— 无匹配
2. **委婉式完成声明**: "Implemented the core functionality"（实际未完成所有任务）—— 无匹配
3. **无标记的范围缩减**: "Focused on the highest-priority items" —— 仅通过 "low priority" 弱匹配
4. **技术债务框架**: "Created a clean interface for future extension" —— 无匹配
5. **中文委婉模式**: "核心功能已完成"（未标记不完整任务）—— 无特定匹配

### 4.3 Skill 中的幻觉向量

| Skill 文件 | 潜在幻觉向量 | 缓解 |
|-----------|------------|------|
| `autopilot-gate/SKILL.md` | AI 执行 8 步清单时可能幻觉 checkpoint 存在 | L2 Hook (`check-predecessor-checkpoint.sh`) 提供确定性兜底 |
| `autopilot-dispatch/SKILL.md` | AI 构造 prompt 时可能遗漏必需字段 | L2 Hook 在返回时验证信封 |
| `autopilot-recovery/SKILL.md` | AI 扫描 checkpoint 时可能误读状态 | `_common.sh` `read_checkpoint_status()` 是确定性的 |
| `autopilot/SKILL.md` | 模式路径选择可能被 AI 推理覆盖 | L2 `check-predecessor-checkpoint.sh` 强制模式路径 |

---

## 5. 代码模式违规发现

### 5.1 源码中的 TODO/FIXME/HACK

在所有 `.sh`、`.md`、`.ts`、`.tsx`、`.py` 文件中搜索，发现**源码中零 TODO/FIXME/HACK 违规**（脚本、skill 或参考文档）。所有匹配均为:
- `banned-patterns-check.sh` 脚本自身（引用其检测的模式）
- 描述该功能的文档/路线图文件
- CHANGELOG.md 记录功能添加
- `test-hooks.sh` 测试夹具

**结论**: 清洁。强制范围内无违规。

### 5.2 banned-patterns-check.sh 覆盖分析

**检测到的** (`banned-patterns-check.sh` 47 行):
- `TODO:` (不区分大小写)
- `FIXME:` (不区分大小写)
- `HACK:` (不区分大小写)

**遗漏的** (无冒号的模式):
- `TODO implement`（无冒号）—— **未捕获**
- `FIXME this later`（无冒号）—— **未捕获**
- `HACK around the issue`（无冒号）—— **未捕获**
- `// todo: ...`（不区分大小写，有冒号）—— **已捕获** (grep -i)
- `XXX:` —— **未捕获**（常见替代占位符）
- `TEMP:` 或 `TEMPORARY:` —— **未捕获**

**文件排除** (33-40 行): 脚本排除 `.md`、`.json`、`.yaml`、`.yml`、`.toml`、`.ini`、`.cfg`、`.conf`、`.lock`、`.log`、CHANGELOG、LICENSE、README 及 `openspec/`、`context/`、`phase-results/` 路径。对避免文档中的误报合理。

**阶段范围** (22-26 行): 仅在 Phase 4/5/6 期间生效（Phase 1 checkpoint ok/warning 之后）。Phase 1 输出（需求文档）中的 TODO/FIXME/HACK 模式不被捕获，这是可接受的。

### 5.3 断言质量检查覆盖

**检测到的模式** (`assertion-quality-check.sh` 47-66 行):
- JavaScript/TypeScript: `expect(true).toBe(true)`, `expect(false).toBe(false)`, `expect(1).toBe(1)`, `expect("x").toBe("x")`
- `expect(true).toBeTruthy()`, `expect(false).toBeFalsy()`
- Python: `assert True`, `assert not False`, `self.assertTrue(True)`, `self.assertEqual(1, 1)`
- Java/Kotlin: `assertEquals(1, 1)`, `assertTrue(true)`, `assertFalse(false)`
- 通用: `assert|expect|check` 配合 `true == true`, `1 == 1` 等

**遗漏的模式:**
- `expect(undefined).toBeUndefined()` —— 恒真但未检测
- `expect(null).toBeNull()` —— 未检测（尽管 48 行注释提及，正则未匹配）
- `expect([]).toEqual([])` —— 空数组比较
- `expect({}).toEqual({})` —— 空对象比较
- `assertNotNull(new Object())` —— 恒真构造器，未检测
- Vitest `expect.soft()` 变体 —— 未检测

**范围限制**: 仅扫描匹配 `*test*|*spec*|*Test*|*Spec*|*__tests__*` 模式的文件 (34-38 行)。非标准命名的测试文件（如 `verification.ts`、`checks.py`）会被遗漏。

---

## 6. 子 Agent 约束可执行性

### 6.1 逐条约束分析

| 约束 | 强制机制 | 可违反性评估 |
|------|---------|------------|
| SA-1: 禁止读取计划文件 | 仅 L3 prompt 指令 | **高风险**: 子 Agent 可自由使用 Read 工具读取任何文件。无 PreToolUse(Read) Hook 阻止读取计划文件 |
| SA-2: 禁止修改 openspec/checkpoint | `write-edit-constraint-check.sh` 38-39 行**豁免**（exit 0）openspec 路径而非阻断 | **高风险**: Hook 设计为跳过这些路径的验证，而非阻止写入。子 Agent 可自由写入 checkpoint 文件 |
| SA-3: 必须返回 JSON 信封 | `_post_task_validator.py` 验证器 1 在缺失信封时阻断 | **低风险**: L2 确定性强制。无 JSON 信封的子 Agent 被阻断 |
| SA-4: 后台 Agent 产出必须 Write 到文件 | 仅 L3 prompt 指令 | **中风险**: 无机制阻止后台 Agent 返回大量文本而不写入文件。主线程会在上下文中接收 |
| SA-5: 文件所有权 (并行模式) | `_post_task_validator.py` 验证器 4（并行合并守卫）456-504 行检查范围 | **低风险**: L2 通过 git diff 分析对比预期产物 |

### 6.2 关键缺口: SA-2 逻辑反转

`write-edit-constraint-check.sh` 38-39 行:
```bash
  *openspec/*|*context/*|*phase-results/*)
    exit 0 ;;
```

这**豁免**了 openspec 路径的约束检查，而非阻止子 Agent 写入。CLAUDE.md SA-2 的意图（"禁止修改 openspec/checkpoint: 隔离约束"）是子 Agent 不应修改这些路径，但 Hook 显式允许。这是逻辑反转执行。

**根因**: `write-edit-constraint-check.sh` Hook 设计用于检查 code_constraints（生产代码中的 forbidden patterns/files）。它豁免 openspec/checkpoint 路径是因为编排系统预期修改这些路径。然而没有独立机制区分主线程写入（合法）和子 Agent 写入（禁止）。

**建议**: 在 Write/Edit Hook 中实现子 Agent 隔离检查，检测当前执行上下文（子 Agent vs 主线程），阻止子 Agent 写入 openspec/checkpoint 路径。

---

## 7. Event Bus 规范合规性

### 7.1 event-bus-api.md vs emit-phase-event.sh

| 规范字段 | event-bus-api.md | emit-phase-event.sh | 匹配 |
|---------|-----------------|---------------------|------|
| `type` | `phase_start \| phase_end \| error` | 34-39 行: 验证相同 3 个值 | **匹配** |
| `phase` | 数字 0-7 | 82 行: `int(sys.argv[2])` | **匹配** |
| `mode` | `full \| lite \| minimal` | 83 行: 透传，无验证 | **部分**（无 mode 验证） |
| `timestamp` | ISO-8601 | 43 行: python3 datetime UTC ISO 格式 | **匹配** |
| `change_name` | 字符串 | 52-53 行: 环境变量 > 锁文件 > "unknown" | **匹配** |
| `session_id` | 字符串 | 56-58 行: 环境变量 > 锁文件 > 时间戳回退 | **匹配** |
| `phase_label` | 字符串 | 61 行: _common.sh 的 `get_phase_label()` | **匹配** |
| `total_phases` | 数字 | 64 行: _common.sh 的 `get_total_phases()` | **匹配** |
| `sequence` | 数字 | 67 行: `next_event_sequence()` 自增 | **匹配** |
| `payload` | 含 status/duration_ms/error_message/artifacts 的对象 | 87-92 行: 解析可选 JSON payload | **匹配** |

### 7.2 event-bus-api.md vs emit-gate-event.sh

| 规范字段 | event-bus-api.md | emit-gate-event.sh | 匹配 |
|---------|-----------------|---------------------|------|
| `type` | `gate_pass \| gate_block` | 34-39 行: 验证相同 2 个值 | **匹配** |
| `payload.gate_score` | 字符串 "8/8" | 通过 payload JSON 参数传递 | **匹配** |
| 所有 v5.0 上下文字段 | 同 PhaseEvent | 相同实现模式 | **匹配** |

### 7.3 合规偏差

1. **Mode 验证缺失**: 两个 emit 脚本均未验证 mode 是否为 `full|lite|minimal` 之一。无效 mode 值会静默透传
2. **total_phases 映射**: `_common.sh` `get_total_phases()` 返回 full=8, lite=5, minimal=4。event-bus-api.md 规范一致。**匹配**
3. **TaskProgressEvent**: event-bus-api.md 71-87 行声明为"v5.0 规划"但无对应 `emit-task-progress-event.sh` 脚本。记录为计划中，尚未实现

---

## 8. 发版纪律验证

### 8.1 bump-version.sh 分析

**语义化版本验证** (21 行): 正则 `^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?$` 正确验证 MAJOR.MINOR.PATCH 带可选预发布。

**4 文件同步**:
1. `plugin.json` (79 行): jq 更新 —— **正确**
2. `marketplace.json` (86-89 行): jq 选择器 `plugins[].name == "spec-autopilot"` —— **正确**
3. `README.md` (95 行): sed 替换 shield.io 徽章模式 —— **正确**
4. `CHANGELOG.md` (104-113 行): 在第 1 行后插入头部，已存在则跳过 —— **正确**

**验证循环** (119-136 行): 读回全部 4 个文件并比较。不匹配则 exit 1。

### 8.2 边界情况

| 边界情况 | 行为 | 评估 |
|---------|------|------|
| 幂等重跑（相同版本） | 64-72 行: 检测所有文件已在目标版本，exit 0 | **正确** |
| CHANGELOG 已有该版本 | 104 行: grep 检查，跳过插入 | **正确** |
| 文件缺失 | 38-48 行: 预检查，exit 1 并列出 | **正确** |
| 未安装 jq | 51-54 行: exit 1 并给出安装指引 | **正确** |
| macOS sed 语法 | 95 行: 使用 `sed -i ''`（macOS） | **平台 BUG**: 在 Linux 上 `sed -i` 不需参数或需 `sed -i''`，会失败 |
| CHANGELOG 插入 | 108-111 行: `sed -i '' "2a\\..."` 在第 2 行后插入 | **脆弱**: 假定第 1 行为 `# Changelog`。如果 CHANGELOG 有不同头部格式，插入位置错误 |
| 多个 README 徽章 | 95 行: `s///g` 全局替换 | **正确**: 更新所有徽章出现处 |
| marketplace.json 缺少 spec-autopilot 条目 | jq 静默无输出 | **静默失败**: V2 验证会显示 "missing" 但 exit 1。可接受 |

### 8.3 关键发现: 平台不兼容

`bump-version.sh` 95 行使用 macOS 特定的 `sed -i ''` 语法。在 Linux 上会创建空扩展名的备份文件。应使用类似 `_common.sh` 对 `stat` 的平台检测模式。

---

## 9. 缺口分析（无强制执行的规则）

### 9.1 硬缺口（任何层均无强制）

| CLAUDE.md 规则 | 类别 | 风险等级 | 描述 |
|---------------|------|---------|------|
| TDD-1: RED 仅写测试 | TDD 铁律 | **高** | 无 L2 Hook 阻止 RED 阶段子 Agent 写入实现文件。完全依赖 prompt 遵从 |
| TDD-4: GREEN 测试不可变 | TDD 铁律 | **高** | 无 L2 Hook 阻止 GREEN 阶段子 Agent 修改测试文件。完全依赖 prompt 遵从 |
| SA-1: 禁止读取计划文件 | 子 Agent | **中** | 无 PreToolUse(Read) Hook。子 Agent 可读取任何文件 |
| SA-2: 禁止修改 openspec/checkpoint | 子 Agent | **高** | L2 Hook `write-edit-constraint-check.sh` **豁免**（非阻断）openspec 路径。逻辑反转 |
| SA-4: 后台 Agent 必须 Write 到文件 | 子 Agent | **低** | 无强制机制。仅 prompt 指令 |

### 9.2 部分缺口（有强制但不完整）

| CLAUDE.md 规则 | 类别 | 缺口描述 |
|---------------|------|---------|
| SM-4: 降级条件 | 状态机 | L3 prompt 定义"合并失败 >3 文件"等，但无 L2 Hook 阻止 AI 以其他理由降级 |
| TDD-5: REFACTOR 自动回滚 | TDD 铁律 | tdd-cycle.md 记录协议但若主线程未执行回滚则无 L2 兜底 |
| RD-2: 禁止散弹式修改 | 发版 | 自律制度；无 pre-commit Hook 或 CI 检查阻止直接版本文件编辑 |
| CQ-1: 禁用模式（部分） | 代码质量 | 仅捕获带冒号的 `TODO:`、`FIXME:`、`HACK:`。无冒号变体和 `XXX:` 逃逸检测 |

---

## 10. 幽灵规则（有强制但无声明的规则）

以下强制存在于 L2 Hook 中但未在 CLAUDE.md 中显式声明:

| Hook/脚本 | 强制内容 | CLAUDE.md 引用 |
|----------|---------|---------------|
| `_post_task_validator.py` 104-108 行 | Phase 4 要求 `sad_path_counts` 为必需字段 | CLAUDE.md CQ-7 提及但未声明为必需信封字段 |
| `_post_task_validator.py` 132-146 行 | Phase 5 TDD 指标 L2 检查 (`red_violations=0`, `cycles_completed>=1`) | 未在 CLAUDE.md 中。仅在代码中声明 |
| `_post_task_validator.py` 410-504 行 | 并行合并守卫（冲突检测、范围验证、类型检查） | 未在 CLAUDE.md 中。并行模式完整性的架构强制 |
| `_post_task_validator.py` 556-631 行 | Phase 1 决策格式验证（选项≥2、必需字段、推荐标记） | 未在 CLAUDE.md 中。仅在 protocol.md DecisionPoint 格式中 |
| `_post_task_validator.py` 236-257 行 | Phase 4 test_traceability L2 阻断（覆盖率≥80%） | CLAUDE.md 未显式列出追溯性为硬约束 |
| `check-predecessor-checkpoint.sh` 401-435 行 | Phase 5 墙钟超时强制 | 未在 CLAUDE.md 中。记录在 phase5-implementation.md |
| `check-predecessor-checkpoint.sh` 383-398 行 | Phase 6 要求 tasks.md 所有项目 [x] 完成 | 未在 CLAUDE.md 中。记录在 SKILL.md |
| `hooks.json` SessionStart Hook | `scan-checkpoints-on-start.sh`, `check-skill-size.sh`, `reinject-state-after-compact.sh` | 未在 CLAUDE.md 中（操作性 Hook，非约束强制） |
| `hooks.json` PreCompact Hook | `save-state-before-compact.sh` | 未在 CLAUDE.md 中（操作性，记录在 guardrails.md） |

**评估**: 这些幽灵规则代表超越 CLAUDE.md 声明的积极强制。应在 CLAUDE.md 中记录以确保完整性，但其存在增强了安全性而非削弱。

---

## 11. 风险评估

### 11.1 风险矩阵

| 风险 | 可能性 | 影响 | 缓解状态 | 优先级 |
|------|--------|------|---------|--------|
| TDD 阶段隔离绕过 (TDD-1, TDD-4) | 中 | 高 | 仅 L3 | **P0** |
| 子 Agent 写入 openspec/checkpoint (SA-2 反转) | 低 | 高 | L2 逻辑反转 | **P1** |
| 反合理化通过委婉表达绕过 | 中 | 中 | 22 模式评分制 | **P2** |
| 无冒号 TODO 逃逸检测 | 中 | 低 | 冒号要求为设计选择 | **P3** |
| bump-version.sh Linux 上失败 | 低（开发工具） | 低 | macOS 特定 sed | **P3** |
| Event emit 脚本不验证 mode 参数 | 低 | 低 | 从调用方透传 | **P4** |
| 超出当前检测的断言反模式 | 中 | 低 | 5+ 未捕获模式 | **P3** |

### 11.2 系统性观察

1. **L2 vs L3 不对称**: 系统在 PostToolUse 验证（信封、测试金字塔、反合理化、代码约束）上有优秀的 L2 覆盖，但在 Write/Edit 阶段隔离上 L2 覆盖弱。Hook 架构只能在文件写入后检查；无法强制"哪些文件应在哪个 TDD 阶段被写入"。

2. **磁盘上的废弃文件**: `anti-rationalization-check.sh`、`code-constraint-check.sh` 和 `validate-json-envelope.sh` 标记为 DEPRECATED 但仍在磁盘上。虽然正确地不在 hooks.json 中，但其存在可能造成混淆。它们与 `_post_task_validator.py` 共享相同逻辑。

3. **后台 Agent L2 绕过**: 如 `check-predecessor-checkpoint.sh` 49-59 行所述，后台 Agent 设计上绕过所有 L2 检查。注释中已确认，但意味着以后台方式派发的 Phase 2/3/4/6 在启动时跳过 L2 验证。L2 改在 PostToolUse 响应时运行。

4. **hooks.json 完整性**: hooks.json 中注册的全部 4 个 Hook 条目（PreToolUse:Task, PostToolUse:Task, PostToolUse:Write|Edit x3）均正确映射到现有脚本。无声明的 Hook 指向缺失脚本。3 个 Write|Edit Hook 为独立条目按顺序触发。

---

## 12. 综合合规评分

### 评分方法

- 39 条离散规则跨 7 个类别
- 完整 L2+L3 覆盖: 26 条 (得分: 26 × 2.5 = 65)
- 仅 L3 或部分覆盖: 8 条 (得分: 8 × 1.0 = 8)
- 无强制: 5 条 (得分: 0)
- 幽灵规则加分（积极的未声明强制）: +5
- 扣分: SA-2 逻辑反转 (-3), 平台不兼容 (-1), 废弃文件杂乱 (-1)

### 最终评分

**73 / 100**

### 评分明细

| 类别 | 满分 | 得分 | 备注 |
|------|------|------|------|
| 状态机 (7 规则) | 17.5 | 16.0 | SM-4 部分 |
| TDD 铁律 (5 规则) | 12.5 | 6.5 | TDD-1, TDD-4 硬缺口; TDD-5 部分 |
| 代码质量 (7 规则) | 17.5 | 16.5 | CQ-1 部分（仅冒号） |
| 需求路由 (4 规则) | 10.0 | 9.0 | RR-1 部分分类 |
| Event Bus (4 规则) | 10.0 | 9.5 | Mode 验证缺失 |
| 子 Agent (5 规则) | 12.5 | 5.5 | SA-1, SA-2, SA-4 缺口 |
| 发版纪律 (4 规则) | 10.0 | 8.5 | RD-2 自律制度，平台 bug |
| 幽灵规则加分 | 5.0 | 5.0 | 9 项未声明的积极强制 |
| 扣分 | -10.0 | -5.0 | SA-2 反转, 平台, 杂乱 |
| **合计** | **100** | **73** | |

### 总体评估

该插件在核心能力（信封验证、测试质量门禁、阶段排序）上达到了**强合规**，但在 TDD 阶段隔离和子 Agent 写入隔离方面存在**实质性缺口**。三层架构设计良好；缺口主要在 Hook 系统的文件级粒度无法在缺少额外状态追踪的情况下强制阶段级约束的领域。

---

## 附录 A: 审计涉及文件

### Hook 脚本 (8 注册 + 1 统一 + 3 废弃)
- `scripts/check-predecessor-checkpoint.sh` (439 行)
- `scripts/post-task-validator.sh` (33 行, 统一入口)
- `scripts/_post_task_validator.py` (634 行, 核心逻辑)
- `scripts/write-edit-constraint-check.sh` (111 行)
- `scripts/banned-patterns-check.sh` (65 行)
- `scripts/assertion-quality-check.sh` (82 行)
- `scripts/anti-rationalization-check.sh` (151 行, 已废弃)
- `scripts/code-constraint-check.sh` (82 行, 已废弃)
- `scripts/validate-json-envelope.sh` (225 行, 已废弃)
- `scripts/rules-scanner.sh` (157 行)
- `scripts/_common.sh` (352 行)
- `scripts/_hook_preamble.sh` (39 行)

### Skill 文件 (7)
- `skills/autopilot/SKILL.md` (330 行)
- `skills/autopilot-gate/SKILL.md` (311 行)
- `skills/autopilot-dispatch/SKILL.md` (323 行)
- `skills/autopilot-setup/SKILL.md` (368 行)
- `skills/autopilot-phase0/SKILL.md` (226 行)
- `skills/autopilot-phase7/SKILL.md` (182 行)
- `skills/autopilot-recovery/SKILL.md` (135 行)

### Event Bus 脚本 (2)
- `scripts/emit-phase-event.sh` (112 行)
- `scripts/emit-gate-event.sh` (112 行)

### 发版脚本 (1)
- `scripts/bump-version.sh` (145 行)

### 参考文档 (5)
- `references/protocol.md`
- `references/tdd-cycle.md`
- `references/guardrails.md`
- `references/testing-anti-patterns.md`
- `references/event-bus-api.md`

### 配置 (1)
- `hooks/hooks.json` (100 行)
