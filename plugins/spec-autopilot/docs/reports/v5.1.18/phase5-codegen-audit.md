# Phase 5 代码生成质量与规约遵从度审计报告

> **版本**: v5.1.18
> **审计日期**: 2026-03-17
> **审计范围**: `plugins/spec-autopilot/` — Phase 5 (Implementation) 全链路
> **审计员**: Agent 3 — Phase 5 代码生成质量与规约遵从度审计员

---

## 执行摘要

| 维度 | 评分 | 等级 |
|------|------|------|
| 全局记忆与规约服从度 | 93/100 | A |
| 上下文感知与防重复 | 88/100 | A- |
| 反偷懒检测机制 | 95/100 | A+ |
| 安全性与健壮性 | 82/100 | B+ |
| 并行模式审计 | 91/100 | A |
| 测试覆盖度 | 87/100 | A- |
| **综合评分** | **89/100** | **A-** |

**核心结论**: Phase 5 实现了工业级的代码生成质量管控体系。三层门禁 (L1/L2/L3) + 反偷懒检测 + TDD 隔离构成了纵深防御。主要风险集中在：(1) 安全性约束为软性引导而非硬性拦截；(2) brownfield 验证为配置可关闭状态；(3) 并行模式下的 L2 Hook 覆盖存在已知间隙。

---

## 1. 全局记忆与规约服从度评分 (93/100)

### 1.1 CLAUDE.md 架构约定引用情况

**结论: 强制引用, 闭环执行**

| 检查项 | 状态 | 证据 |
|--------|------|------|
| Phase 5 模板引用 CLAUDE.md 约束 | PASS | `autopilot-dispatch/SKILL.md` 优先级 2.5 — `rules-scanner.sh` 自动扫描 `.claude/rules/` + `CLAUDE.md` 并注入子 Agent prompt |
| 强制读取项目 CLAUDE.md | PASS | `rules-scanner.sh` 第 97-114 行明确扫描 `CLAUDE.md` 中的禁止项和必须项 |
| Phase 5 注入完整规则 | PASS | `autopilot-dispatch/SKILL.md` 阶段差异化注入表: Phase 5 = "完整规则 + 实时 Hook 强制执行" |
| code_constraints 配置强制执行 | PASS | `unified-write-edit-check.sh` CHECK 4 (第 252-281 行) 在 delivery phases (4/5/6) 自动加载 `_constraint_loader.py` 检查约束 |

**证据链**:
1. `rules-scanner.sh` 扫描 `.claude/rules/*.md` 和 `CLAUDE.md`，提取 forbidden/required/naming 约束
2. dispatch 模板注入 `{rules_scan_result}` 到 Phase 5 子 Agent prompt
3. `unified-write-edit-check.sh` CHECK 4 在文件写入时实时验证 `forbidden_files`、`forbidden_patterns`、`allowed_dirs`、`max_file_lines`
4. `_constraint_loader.py` 支持 `autopilot.config.yaml` 的 `code_constraints` 节和 `CLAUDE.md` 双重来源

### 1.2 code_constraints 强制执行链路

```
配置来源: autopilot.config.yaml → code_constraints
         CLAUDE.md → regex 提取 (fallback)
                 ↓
注入: rules-scanner.sh → JSON → dispatch prompt 注入
                 ↓
拦截: unified-write-edit-check.sh → _constraint_loader.py
      → forbidden_files / forbidden_patterns / allowed_dirs / max_file_lines
                 ↓
输出: {"decision": "block", "reason": "..."} → 阻断写入
```

### 1.3 L2 Hook 拦截机制

`unified-write-edit-check.sh` 实现了 5 层检查 (按优先级):

| CHECK | 目标 | 实现方式 | 耗时 |
|-------|------|----------|------|
| CHECK 0 | 子 Agent 状态隔离 | 纯 bash case 匹配 | ~1ms |
| CHECK 1 | TDD 阶段隔离 | `.tdd-stage` 文件驱动 | ~1ms |
| CHECK 2 | 禁止 TODO/FIXME/HACK | `grep -inE` | ~2ms |
| CHECK 3 | 恒真断言检测 | 多语言 regex (JS/Python/Java) | ~2ms |
| CHECK 4 | 代码约束验证 | python3 + `_constraint_loader.py` | ~50ms |

**扣分项 (-3)**:
- `semantic_rules` (语义规则) 无法被 Hook 自动检测，仅依赖 AI 自觉遵守，Phase 6.5 代码审查作为补偿但非实时拦截
- `required_patterns` 验证仅在 CHECK 4 的 `_constraint_loader.py` 中检查 `forbidden_patterns`，但 `required_patterns` 的验证逻辑在 `parallel-phase5.md` 的 prompt 注入模板中仅作为软性提示，无 L2 硬拦截

**扣分项 (-4)**:
- `required_patterns` 配置项 (如 `createWebHashHistory` 必须使用) 在 `_constraint_loader.py` 的 `check_file_violations()` 中**缺失验证逻辑** — 只检查了 `forbidden_files`、`forbidden_patterns`、`allowed_dirs`、`max_file_lines`，未实现 `required_patterns` 的正向校验

---

## 2. 上下文感知与防重复评估 (88/100)

### 2.1 Phase 5 模板引导先调研已有代码

| 机制 | 实现位置 | 效果 |
|------|----------|------|
| Phase 1 Steering Documents 注入 | `dispatch-prompt-template.md` 第 46-52 行 | 子 Agent 读取 `project-context.md`、`existing-patterns.md`、`tech-constraints.md` |
| 控制器提取全文 | `parallel-phase5.md` Step 1 | "主线程一次性提取所有 task 的完整文本（子 Agent 禁止自行读取计划文件）" |
| 前序 task 摘要 | `phase5-implementation.md` 串行模板 | `{for each completed_task} - Task #{n}: {summary} — 已完成 {end for}` |
| 域级上下文注入 | `parallel-phase5.md` Step 3 | `{context_injection}` 包含 Steering Documents 的关键信息 |

### 2.2 防重复造轮子机制

| 机制 | 状态 | 说明 |
|------|------|------|
| `existing-patterns.md` 注入 | PASS | Phase 1 Auto-Scan 产出现有代码模式文件，Phase 5 子 Agent 可读取 |
| `tech-constraints.md` 注入 | PASS | 技术栈约束防止引入不一致的技术选型 |
| `requirements-analysis.md` 注入 | PASS | BA 分析结果避免需求偏差导致的重复实现 |
| 文件所有权约束 | PASS | 并行模式下 `owned_files` 防止多 Agent 修改同一文件 |

### 2.3 Brownfield 验证在 Phase 5 的作用

`brownfield-validation.md` 定义了三向一致性检查:

| 检查点 | 触发时机 | 内容 |
|--------|----------|------|
| 设计-测试对齐 | Phase 4→5 门禁 | design spec API 与测试用例映射 |
| 测试-实现就绪 | Phase 5 启动 | import 路径、fixture 基础设施、测试命令可执行性 |
| 实现-设计一致性 | Phase 5→6 门禁 | API 签名匹配、scope creep 检测、breaking change 检测 |

**集成方式**: 在 `autopilot-gate` 8 步检查清单中额外执行，`strict_mode` 控制行为:
- `false` (默认): warning 不阻断
- `true`: 任何不一致直接 block

**扣分项 (-5)**:
- brownfield 验证默认 `strict_mode: false`，不一致仅为 warning，不阻断
- greenfield 项目由 Phase 0 自动关闭此功能，但没有检测从 greenfield 转 brownfield 的场景

**扣分项 (-4)**:
- `existing-patterns.md` 的注入是被动的（子 Agent 可读取但不强制参照），没有 L2 Hook 验证生成代码是否与现有模式一致

**扣分项 (-3)**:
- 防重复造轮子主要依赖 AI 自觉而非确定性检测，没有 AST 级或 import 级的重复检测机制

---

## 3. 反偷懒检测机制评审 (95/100)

### 3.1 TODO/FIXME/HACK 拦截

**实现**: `unified-write-edit-check.sh` CHECK 2 (第 187-201 行)

```bash
MATCHES=$(grep -inE '(TODO:|FIXME:|HACK:)' "$FILE_PATH" 2>/dev/null | head -5)
```

- 拦截范围: 所有源码文件 (排除 .json/.yaml/.yml/.txt/.csv/.toml/.ini/.cfg/.conf/.lock/.log/.svg/.png/.jpg/.gif/.ico)
- 特殊处理: `.md` 文件仅在 delivery phase (Phase 4+) 才拦截，Phase 1-3 允许 (合理设计)
- 输出: `{"decision": "block", "reason": "Banned placeholder patterns detected..."}`

**测试验证**: `test_unified_write_edit.sh` 覆盖了:
- 53a: 源码 TODO → block
- 53b: 源码 FIXME → block
- 53c: 源码 HACK → block
- 53d: `.md` 非 delivery phase → skip
- 53e: 干净源码 → pass
- 53m: `.md` delivery phase TODO → block

### 3.2 恒真断言拦截

**实现**: `unified-write-edit-check.sh` CHECK 3 (第 207-246 行)

覆盖 4 类语言:
| 语言 | 检测模式 |
|------|----------|
| JavaScript/TypeScript | `expect(true).toBe(true)`, `expect(true).toBeTruthy()` |
| Python | `assert True`, `self.assertTrue(True)` |
| Java/Kotlin | `assertEquals(true, true)`, `assertTrue(true)` |
| 通用 | `assert.*true == true` |

**测试验证**: `test_unified_write_edit.sh` 53f/53g/53h 覆盖

### 3.3 Anti-Rationalization 检测

**实现**: `_post_task_validator.py` VALIDATOR 2 (第 332-407 行)

**加权评分机制**:
| 权重 | 模式类型 | 数量 |
|------|----------|------|
| 3 (高) | 强跳过信号 (skipped/deferred/时间不够) | 12 模式 (EN+CN) |
| 2 (中) | 范围/延迟信号 (out of scope/环境问题) | 8 模式 (EN+CN) |
| 1 (低) | 弱信号 (not needed/太复杂) | 10 模式 (EN+CN) |

**v5.2 增强**: 新增 6 种高频借口模式:
- 时间/工期/deadline 不够
- 环境/配置/基础设施未就绪
- 第三方/外部依赖阻塞

**评分阈值**:
| 分数 | 行为 |
|------|------|
| >= 5 | 硬阻断 (block) |
| >= 3 + 无 artifacts | 阻断 (无产出的合理化) |
| >= 2 | 仅 stderr 警告 |
| < 2 | 静默通过 |

**作用范围**: Phase 4/5/6，仅对 status=ok/warning 的信封检测（blocked/failed 是合法停止，不检查）

### 3.4 zero_skip_check 门禁

**实现**: `_post_task_validator.py` 第 144-150 行

```python
if phase_num == 5 and envelope.get("status") == "ok":
    zsc = envelope.get("zero_skip_check", {})
    if isinstance(zsc, dict) and zsc.get("passed") is not True:
        output_block(...)
```

- Phase 5 status="ok" 时，`zero_skip_check.passed` 必须为 `true`
- CLAUDE.md 第 6 条: "Phase 5 zero_skip_check: passed === true 必须满足，否则阻断"
- 该字段也是 Phase 5 信封的 required field (第 107 行)

### 3.5 Phase 5 信封必要字段

```python
phase_required = {
    5: ["test_results_path", "tasks_completed", "zero_skip_check"],
}
```

任何缺失字段即 block，确保子 Agent 不能通过省略字段逃避质量检查。

**扣分项 (-3)**:
- anti-rationalization 的 `score >= 3 + 有 artifacts` 场景仅 stderr 警告不阻断。理论上子 Agent 可以在合理化文字的同时产出低质量 artifacts 通过检测

**扣分项 (-2)**:
- 模式匹配为正则表达式，可能存在绕过 (如措辞变体、同义替换)。但中英双语 30 种模式已覆盖主流场景

---

## 4. 安全性与健壮性评估 (82/100)

### 4.1 异常捕获要求

| 检查项 | 状态 | 说明 |
|--------|------|------|
| Phase 5 模板要求异常捕获 | PARTIAL | `phase5-serial-task.md` 仅要求"测试失败处理"，未明确要求生成代码包含异常捕获 |
| code_constraints 可配置异常模式 | PASS | `forbidden_patterns` 可配置禁止 bare except/eval，但非默认项 |
| 子 Agent 异常退出处理 | PASS | `guardrails.md`: "Phase 5 子 Agent 异常退出 → 保存进度到 phase-results checkpoint，从上次完成的 task 恢复" |

**扣分项 (-6)**:
- Phase 5 模板 (`phase5-serial-task.md`) 缺少对生成代码的安全性要求：
  - 无异常捕获强制要求
  - 无输入验证/边界校验要求
  - 无日志记录要求
  - 这些仅能通过 `code_constraints.semantic_rules` 配置实现，非默认强制

### 4.2 边界校验

| 检查项 | 状态 | 说明 |
|--------|------|------|
| 文件行数上限 | PASS | `_constraint_loader.py`: `max_file_lines` 默认 800，L2 硬拦截 |
| 任务粒度约束 | PASS | `phase5-serial-task.md`: "每次 <= 3 个文件" |
| Wall-clock 超时 | PASS | `phase5-implementation.md`: 2 小时超时 → AskUserQuestion |
| 连续失败处理 | PASS | 串行模式连续 3 次失败 → AskUserQuestion 决策 |

### 4.3 日志记录

| 检查项 | 状态 | 说明 |
|--------|------|------|
| Phase 5 task checkpoint | PASS | 每个 task 写入 `phase5-tasks/task-N.json`，包含 `_metrics` (start_time/end_time/duration/retry_count) |
| 事件发射 | PASS | `emit-task-progress.sh` 发射 task_progress 事件到 `logs/events.jsonl` |
| Phase 事件 | PASS | `emit-phase-event.sh` 发射 phase_start/phase_end 事件 |
| Agent 生命周期事件 | PASS | `emit-agent-event.sh` 发射 agent_dispatch/agent_complete 事件 |

**扣分项 (-5)**:
- 生成代码本身的日志记录要求缺失（Phase 5 模板未要求生成的应用代码包含结构化日志）
- 安全性要求（输入验证、SQL 注入防护、XSS 防护）完全依赖项目自身的 `code_constraints.semantic_rules` 配置

**扣分项 (-4)**:
- Hook 层面没有对生成代码进行安全扫描（如检测 `eval()`、`exec()` 之外的安全反模式）
- `forbidden_patterns` 只有配置了才生效，无默认安全基线

**扣分项 (-3)**:
- `unified-write-edit-check.sh` 的 SKIP_HEAVY_CHECKS 对 `.json`/`.yaml` 文件完全跳过所有检查，理论上可通过修改配置文件引入安全问题

---

## 5. 并行模式审计 (91/100)

### 5.1 文件所有权隔离

**实现**: `parallel-phase5.md` Step 2 三步域检测

```
Step A: 最长前缀匹配 (domain_agents 配置)
Step B: auto 发现 (祖先冲突检测)
Step C: 溢出合并 (同 Agent 域合并)
```

**强制执行**:
- 域 Agent prompt 注入 `## 文件所有权约束（ENFORCED）`
- `write-edit-constraint-check` Hook 验证 Write/Edit 目标文件在 `owned_files` 范围内
- 越权 → block
- 降级: ownership 文件不存在时跳过检查（向后兼容）

### 5.2 并行→串行降级条件

| 条件 | 行为 | 来源 |
|------|------|------|
| worktree 创建失败 | 立即降级为串行 | `parallel-phase5.md` 降级决策树 |
| 域级合并冲突 > 3 文件 | 回退该域 worktree → 串行 | 同上 |
| 连续 2 组合并失败 | 全面降级 | 同上 |
| 用户选择 "切换串行" | 全面降级 | 同上 |
| batch >50% task 失败 | 剩余 task 回退纯串行 | `phase5-implementation.md` batch 引擎 |

降级原因记录到: `_metrics.parallel_fallback_reason`

### 5.3 合并验证 (parallel-merge-guard)

`_post_task_validator.py` VALIDATOR 4 (第 439-578 行) 实现三层验证:

| 层 | 检查 | 方法 |
|----|------|------|
| 1 | 合并冲突检测 | `git diff --check` + `git diff --cached --check` |
| 2 | Task scope 校验 | `git diff --name-only anchor_sha..HEAD` vs envelope artifacts |
| 3 | 快速类型检查 | `config.test_suites` type=typecheck |

**anchor_sha 降级策略**: 无效 anchor → fallback `HEAD~1`

**测试验证**: `test_parallel_merge.sh` 覆盖:
- 39a: 有效 anchor_sha → 检测 scope 外文件
- 39b: 无效 anchor_sha → 降级 HEAD~1
- 39c: 空 anchor_sha → 降级
- 39d: 无锁文件 → bypass
- 39e: 所有文件在 scope 内 → 通过

### 5.4 Batch Scheduler (串行模式优化)

v4.2 默认启用，对串行模式中无依赖 task 自动后台并行:
- 拓扑排序 + 层级分组
- 单 task batch → 前台同步
- 多 task batch → 后台并行
- TDD 模式或显式禁用时回退纯串行

**扣分项 (-5)**:
- 并行模式下域 Agent 以 `run_in_background: true` 运行，Phase 5 的 `unified-write-edit-check.sh` 的 L2 Hook **在 worktree 内触发但 ownership 验证依赖 ownership 文件**。如果主线程未能正确写入 `phase5-ownership/agent-{N}.json`，ownership 检查将被跳过（降级为向后兼容模式）

**扣分项 (-4)**:
- 并行 TDD 后置审计 (第 226-234 行) 中 `tdd_unverified` 的 task 仅产生 stderr 警告不阻断 (v4.1 宽松策略)，可能存在未执行完整 TDD 循环的 task 混入

---

## 6. 测试覆盖度评估 (87/100)

### 6.1 Phase 5 相关测试清单

| 测试文件 | 覆盖内容 | 状态 |
|----------|----------|------|
| `test_phase5_serial.sh` | 串行 checkpoint 兼容性、PreCompact phase5-tasks 扫描 | 4 case |
| `test_unified_write_edit.sh` | CHECK 2/3 (banned patterns + tautological assertions) + TDD file tracking + delivery phase .md | 14 case |
| `test_code_constraint.sh` | CHECK 4 (forbidden_files/patterns/allowed_dirs) | 5 case |
| `test_tdd_isolation.sh` | TDD RED/GREEN/REFACTOR 文件写入隔离 | 7 case |
| `test_parallel_merge.sh` | parallel-merge-guard anchor_sha diff base | 5 case |
| `test_anti_rationalization.sh` | 反合理化模式检测 | 4 case |
| `test_serial_task_config.sh` | 串行 task 配置 | 存在 |
| `test_template_mapping.sh` | 模板路径映射 | 存在 |

### 6.2 测试覆盖盲区

**扣分项 (-5)**:
- 缺少对 `required_patterns` 正向校验的测试 (因实现本身缺失)
- 缺少对 Phase 5 并行模式完整 E2E 流程的集成测试 (ownership 写入 → 域 Agent → 合并 → scope 检查)

**扣分项 (-4)**:
- `test_anti_rationalization.sh` 仅 4 个 case，未覆盖 v5.2 新增的时间/环境/第三方借口模式
- `test_phase5_serial.sh` 仅 4 个 case，未覆盖 wall-clock 超时、连续失败降级、batch scheduler 逻辑

**扣分项 (-4)**:
- 无测试覆盖 `semantic_rules` scope 匹配逻辑
- 无测试覆盖 Phase 5 lite/minimal 模式下 `phase5-task-breakdown.md` 自动生成流程

---

## 7. 风险发现列表

### 高风险 (P0)

| # | 风险 | 影响 | 当前缓解 |
|---|------|------|----------|
| R1 | `required_patterns` 无 L2 硬拦截 | 项目要求使用特定 API (如 `createWebHashHistory`) 但生成代码可能不遵守 | 仅 prompt 软性注入 |
| R2 | 并行模式 ownership 文件依赖主线程正确写入 | ownership 文件缺失时检查静默跳过 | 向后兼容降级 |

### 中风险 (P1)

| # | 风险 | 影响 | 当前缓解 |
|---|------|------|----------|
| R3 | 生成代码无安全基线 | `forbidden_patterns` 无默认安全规则，需项目显式配置 | `code_constraints` 可配置 |
| R4 | anti-rationalization `score 3-4 + 有 artifacts` 仅警告 | 低质量产出可能通过检测 | stderr 警告 + Phase 6 审查 |
| R5 | 并行 TDD 后置审计不阻断 | tdd_unverified task 可混入最终代码 | stderr 警告，v4.1 宽松策略 |
| R6 | `.json`/`.yaml` 文件跳过所有重检查 | 配置文件修改不受 banned patterns / constraint 检查 | CHECK 0 状态隔离仍生效 |
| R7 | Phase 5 模板无异常捕获/日志/安全性硬性要求 | 依赖项目 `semantic_rules` 配置 | Phase 6.5 代码审查补偿 |

### 低风险 (P2)

| # | 风险 | 影响 | 当前缓解 |
|---|------|------|----------|
| R8 | `semantic_rules` 无法 L2 自动检测 | 依赖 AI 自觉 + Phase 6.5 审查 | 明确文档说明 |
| R9 | brownfield `strict_mode` 默认 false | 设计-实现不一致仅 warning | 配置可切为 true |
| R10 | anti-rationalization 正则可被措辞变体绕过 | 30 种模式已覆盖主流但非全部 | 加权评分降低误判 |

---

## 8. 改进建议

### 优先级 P0 (建议立即实施)

1. **实现 `required_patterns` L2 硬拦截**
   - 在 `_constraint_loader.py` 的 `check_file_violations()` 中新增 `required_patterns` 正向校验
   - 当 `context` 字段匹配当前文件路径时，验证文件内容包含 `pattern`
   - 缺失时输出 violation

2. **并行模式 ownership 文件写入验证**
   - 在域 Agent 派发前，主线程验证 `phase5-ownership/{domain}.json` 已成功写入
   - 写入失败时降级为串行而非静默跳过 ownership 检查

### 优先级 P1 (建议下个版本)

3. **添加默认安全 `forbidden_patterns` 基线**
   - 在 `autopilot-init` 生成的默认配置中包含常见安全反模式:
     - `eval(` / `exec(` / `Function(` (JS)
     - `dangerouslySetInnerHTML` (React)
     - `os.system(` / `subprocess.call(.*shell=True` (Python)
   - 项目可在配置中覆盖

4. **Phase 5 模板增加安全性/健壮性要求段落**
   - 在 `phase5-serial-task.md` 和并行 prompt 模板中添加:
     ```markdown
     ## 代码质量要求
     - 所有外部输入必须进行类型/范围校验
     - 网络/IO 操作必须包含异常捕获和合理超时
     - 关键操作路径必须包含日志记录
     ```

5. **升级并行 TDD 后置审计为阻断策略**
   - 将 `tdd_unverified` task 从 stderr 警告升级为 block
   - 或至少在 `zero_skip_check` 中加入 `tdd_verified` 字段

### 优先级 P2 (中长期优化)

6. **扩展 anti-rationalization 测试覆盖**
   - 为 v5.2 新增的 6 种时间/环境/第三方借口模式添加专项测试
   - 覆盖中英文混合场景

7. **添加 Phase 5 并行 E2E 集成测试**
   - 模拟完整 ownership 写入 → 域 Agent → 合并 → scope 验证流程
   - 验证降级路径的正确性

8. **brownfield 验证增强**
   - 添加 AST 级重复代码检测 (需语言感知)
   - 在 Phase 5→6 门禁中检测是否引入了与 `existing-patterns.md` 冲突的新模式

---

## 附录 A: 审计文件清单

| 文件 | 用途 |
|------|------|
| `skills/autopilot/SKILL.md` | 主编排器 Phase 5 规范 |
| `skills/autopilot/references/phase5-implementation.md` | Phase 5 详细流程 (串行/并行/TDD) |
| `skills/autopilot/references/parallel-phase5.md` | Phase 5 并行调度配置与模板 |
| `skills/autopilot/references/brownfield-validation.md` | Brownfield 三向一致性检查 |
| `skills/autopilot/references/guardrails.md` | 护栏约束清单 |
| `skills/autopilot/references/dispatch-prompt-template.md` | Dispatch Prompt 构造模板 |
| `skills/autopilot/templates/phase5-serial-task.md` | Phase 5 串行任务内置模板 |
| `skills/autopilot-dispatch/SKILL.md` | 子 Agent 调度协议 |
| `scripts/unified-write-edit-check.sh` | 统一 Write/Edit L2 Hook |
| `scripts/_constraint_loader.py` | 代码约束加载与验证 |
| `scripts/_post_task_validator.py` | 统一 PostToolUse(Task) 验证器 |
| `scripts/rules-scanner.sh` | 项目规则扫描器 |
| `scripts/post-task-validator.sh` | PostToolUse(Task) Hook 入口 |
| `scripts/validate-json-envelope.sh` | JSON 信封验证 (已并入 post-task-validator) |
| `scripts/anti-rationalization-check.sh` | 反合理化检测 (已并入 post-task-validator) |
| `tests/test_phase5_serial.sh` | Phase 5 串行 checkpoint 兼容性测试 |
| `tests/test_unified_write_edit.sh` | 统一 Hook banned patterns 与断言质量测试 |
| `tests/test_code_constraint.sh` | code_constraints L2 阻断测试 |
| `tests/test_tdd_isolation.sh` | TDD RED/GREEN/REFACTOR 隔离测试 |
| `tests/test_parallel_merge.sh` | 并行合并守卫测试 |
| `tests/test_anti_rationalization.sh` | 反合理化检测测试 |
| `CLAUDE.md` | 插件工程法则 (单点事实来源) |

---

## 附录 B: 三层门禁在 Phase 5 的覆盖矩阵

| 验证项 | L1 (TaskCreate) | L2 (Hook 确定性) | L3 (AI Gate 8-step) |
|--------|-----------------|-------------------|---------------------|
| Phase 4 checkpoint 存在 | blockedBy 链 | `has_phase_marker` → 前置校验 | autopilot-gate 8 步 |
| JSON 信封结构 | - | `post-task-validator.sh` VALIDATOR 1 | - |
| zero_skip_check.passed | - | `post-task-validator.sh` Phase 5 特殊检查 | autopilot-gate 额外验证 |
| TODO/FIXME/HACK | - | `unified-write-edit-check.sh` CHECK 2 | - |
| 恒真断言 | - | `unified-write-edit-check.sh` CHECK 3 | - |
| code_constraints | - | `unified-write-edit-check.sh` CHECK 4 | - |
| 反合理化 | - | `post-task-validator.sh` VALIDATOR 2 | - |
| 文件所有权 | - | `unified-write-edit-check.sh` (并行模式) | - |
| TDD 阶段隔离 | - | `unified-write-edit-check.sh` CHECK 1 | - |
| 合并冲突 | - | `post-task-validator.sh` VALIDATOR 4 | - |
| scope 校验 | - | `post-task-validator.sh` VALIDATOR 4 | - |
| tasks.md 全部完成 | - | - | autopilot-gate 额外验证 |
| brownfield 一致性 | - | - | autopilot-gate (配置启用时) |

---

*报告结束。综合评分 89/100 (A-)，Phase 5 代码生成管控体系成熟度高，主要改进空间在安全基线默认化和 required_patterns L2 硬拦截实现。*
