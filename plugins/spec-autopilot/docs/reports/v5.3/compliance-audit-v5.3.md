# 全局规约与 TDD 隔离度审查报告 (v5.3)

> 审查日期: 2026-03-14
> 审查范围: spec-autopilot 插件 TDD 机制、全局规约遵从性、L2 Hook 拦截力、子 Agent 约束
> 审查依据: CLAUDE.md (全局规约)、SKILL.md (主编排)、tdd-cycle.md、autopilot-recovery SKILL.md、unified-write-edit-check.sh、_post_task_validator.py、hooks.json

---

## 执行摘要

spec-autopilot v5.3 的 TDD 机制和全局规约体系已达到较高的工程成熟度。核心发现:

1. **TDD-5 回滚机制**: 在规约文档 (tdd-cycle.md) 中明确定义了 REFACTOR 失败时 `git checkout -- .` 全文件回滚，但回滚逻辑由主线程 AI 执行（L3 层），缺乏 L2 Hook 级别的自动化强制执行脚本。
2. **`.tdd-stage` 生命周期管理**: 写入、读取、清理三个阶段均有明确定义和实现，崩溃恢复中的残留清理已在 v5.2 补全。
3. **Anti-Rationalization 引擎**: 共计 29 种模式（15 EN + 14 CN），覆盖时间/环境/第三方借口等 v5.2 新增类别，满足 "10+6 种 excuse 模式" 设计目标。
4. **L2 Hook 拦截体系**: unified-write-edit-check.sh 统一了 4 项检查，post-task-validator.sh 统一了 5 项验证，架构清晰、性能优化显著。
5. **子 Agent 约束**: JSON 信封、文件所有权、状态隔离等机制完备，L2 确定性阻断有效。

**总体评分: 88/100**

---

## 1. TDD 铁律验证

### 1.1 回滚机制 (TDD-5)

**规约定义** (CLAUDE.md 第 22 行):
> REFACTOR 回归保护: 重构破坏测试 -> 自动 `git checkout` 回滚

**实现路径分析**:

| 层级 | 实现状态 | 说明 |
|------|---------|------|
| L3 (规约) | 已定义 | tdd-cycle.md 明确: REFACTOR exit_code != 0 -> `Bash("git checkout -- .")` + 记录 `tdd_cycle.refactor = { reverted: true }` |
| L2 (Hook) | **未实现** | 无 Hook 脚本自动执行 `git checkout -- .`，回滚依赖主线程 AI 按规约执行 |
| L1 (Task) | 不适用 | 回滚是主线程操作，不涉及 Task 系统 |

**详细流程验证** (tdd-cycle.md 第 116-129 行):

```
REFACTOR 步骤:
  Step 5: Task(prompt: "TDD REFACTOR -- 清理代码")
  Step 6: 主线程确定性验证 (L2)
    result = Bash("{test_command}")
    IF exit_code != 0:
      -> v5.2 强制回滚: Bash("git checkout -- .")
      -> 记录 tdd_cycle.refactor = { reverted: true }
    IF exit_code == 0:
      -> PASS
```

**风险评估**:
- 回滚命令 `git checkout -- .` 的执行取决于主线程 AI 是否严格遵循 tdd-cycle.md 协议
- 验证步骤 (Bash test_command) 是确定性的 L2 行为，但后续的 `git checkout` 是 AI 决策驱动
- 在 scripts/ 目录中搜索 `git checkout`，**未发现任何 Hook 脚本包含此命令**，确认回滚完全由 AI 层执行

**结论**: TDD-5 回滚机制的"触发条件判定"是确定性的（L2 Bash 验证），但"回滚执行"是 L3 AI 驱动的。建议未来版本将回滚逻辑封装为独立脚本（如 `tdd-refactor-rollback.sh`），由 Hook 或主线程确定性调用。

**得分: 7/10** -- 协议完整，但缺乏 L2 自动化执行。

### 1.2 .tdd-stage 生命周期

**生命周期管理矩阵**:

| 阶段 | 操作 | 实现位置 | 验证状态 |
|------|------|---------|---------|
| 创建 (RED) | `echo "red" > .tdd-stage` | SKILL.md 第 293 行 | 由主线程 Bash() 执行 |
| 切换 (GREEN) | `echo "green" > .tdd-stage` | SKILL.md 第 294 行 | 由主线程 Bash() 执行 |
| 切换 (REFACTOR) | `echo "refactor" > .tdd-stage` | SKILL.md 第 295 行 | 由主线程 Bash() 执行 |
| 正常清理 | `rm -f .tdd-stage` | SKILL.md 第 297 行 | task 全部完成后执行 |
| 崩溃恢复清理 | `rm -f openspec/changes/*/context/.tdd-stage` | autopilot-recovery SKILL.md 第 30 行 | v5.2 新增 |

**L2 Hook 消费验证**:

unified-write-edit-check.sh (第 124-151 行) 正确读取 `.tdd-stage` 并执行确定性拦截:
- RED 阶段: 硬阻断实现文件写入（仅允许测试文件）
- GREEN 阶段: 硬阻断测试文件修改（仅允许实现文件）
- REFACTOR 阶段: 放行所有写入

**测试文件检测逻辑** (第 129-135 行):
- 文件名模式: `*.test.*`, `*.spec.*`, `*_test.*`, `*_spec.*`, `*Test.*`, `*Spec.*`
- 路径模式: `__tests__/`, `test/`, `tests/`, `spec/`, `_test/`, `_spec/`
- 覆盖 JavaScript/TypeScript/Python/Java/Go 等主流框架约定

**保护路径例外** (第 103-106 行):
```bash
# .tdd-stage 本身的写入不受保护路径拦截
case "$FILE_PATH" in
  *context/.tdd-stage) PROTECTED_PATH_HIT="no" ;;
esac
```
此例外确保主线程通过 Bash 工具写入 `.tdd-stage` 时不被 Write/Edit Hook 误拦截。

**结论**: `.tdd-stage` 生命周期管理完整，创建/消费/清理三个环节均有明确实现，崩溃恢复在 v5.2 已补全。

**得分: 10/10** -- 完整且无遗漏。

### 1.3 崩溃恢复

**恢复协议验证** (autopilot-recovery SKILL.md):

| 恢复步骤 | 实现 | 状态 |
|----------|------|------|
| .tmp 残留清理 | `rm -f *.json.tmp` | 第 24-25 行，v5.1 |
| .tdd-stage 残留清理 | `rm -f .tdd-stage` | 第 29-30 行，v5.2 |
| TDD per-task 恢复点扫描 | 扫描 `phase5-tasks/task-N.json` 的 `tdd_cycle` 字段 | 第 149-162 行 |

**TDD 崩溃恢复决策矩阵** (autopilot-recovery 第 154-157 行):

| tdd_cycle 状态 | 恢复点 |
|----------------|--------|
| 无 tdd_cycle | 从 RED 开始 |
| red.verified = true，无 green | 从 GREEN 恢复 |
| green.verified = true，无 refactor | 从 REFACTOR 恢复 |
| tdd_cycle 完整 | 下一个 task |

恢复时额外验证:
- GREEN/REFACTOR 恢复: 验证测试文件存在
- REFACTOR 恢复: 运行测试确认当前状态

**风险评估**:
- 崩溃恢复逻辑本身在 SKILL.md 中定义（L3 AI 执行），不是确定性 Hook
- 但恢复的前提（.tdd-stage 清理）是确定性脚本命令
- per-task checkpoint 粒度足够细，恢复精度高

**结论**: 崩溃恢复机制设计合理，覆盖了 .tmp 残留、.tdd-stage 残留、per-task TDD 断点三个维度。

**得分: 9/10** -- 设计完整，.tdd-stage 清理在 v5.2 已补全。

---

## 2. Anti-Rationalization 引擎

### 2.1 模式覆盖度

Anti-Rationalization 引擎在 `_post_task_validator.py` 中实现（第 316-348 行），共计 **29 种加权模式**:

| 类别 | 权重 | 英文模式数 | 中文模式数 | 小计 |
|------|------|-----------|-----------|------|
| 高置信 (weight=3) | 硬跳过信号 | 5 | 5 | 10 |
| 中置信 (weight=2) | 范围/延迟信号 | 4 | 5 | 9 |
| 低置信 (weight=1) | 弱信号 | 6 | 4 | 10 |
| **合计** | | **15** | **14** | **29** |

**v5.2 新增模式 (7 种)**:
- 时间借口 (EN): `not enough time`, `deadline prevents` -- weight=3
- 环境借口 (EN): `environment issue/not ready` -- weight=2
- 第三方借口 (EN): `third-party dependency block` -- weight=2
- 时间借口 (CN): `时间不够/不足/紧张` -- weight=3
- 环境借口 (CN): `环境未就绪/未配置` -- weight=2
- 第三方借口 (CN): `第三方依赖阻塞/不可用` -- weight=2

**对照 CLAUDE.md 声明**: "10+6 种 excuse 模式" -- 实际实现 29 种（远超声明），v5.2 新增了时间/环境/第三方 3 个类别（每类中英双语），总计新增 7 种。

### 2.2 评分阈值与决策

| 条件 | 决策 |
|------|------|
| total_score >= 5 | 硬阻断 (block) |
| total_score >= 3 且无 artifacts | 硬阻断 (block) -- 可疑合理化 + 无产出 |
| total_score >= 2 | 仅警告 (stderr warning) |
| total_score < 2 | 静默放行 |

**设计亮点**:
- artifacts 感知: 有产出时容忍度更高（3 分不阻断），无产出时更严格（3 分即阻断）
- 双语覆盖: 中英文各有独立模式组，防止中文输出绕过检测
- 权重分级: 避免多个弱信号误报导致频繁阻断

### 2.3 部署位置

| 部署方式 | 文件 | 状态 |
|----------|------|------|
| PostToolUse(Task) 统一验证器 | `_post_task_validator.py` (VALIDATOR 2) | **活跃** |
| 独立脚本（已废弃） | `anti-rationalization-check.sh` | 第 2 行标记 DEPRECATED |

anti-rationalization-check.sh 第 2 行明确标记:
> DEPRECATED: Core logic merged into post-task-validator.sh / _post_task_validator.py (v4.0)

hooks.json 中注册的是 `post-task-validator.sh`，确认旧版不再执行。

**结论**: Anti-Rationalization 引擎覆盖度充分，模式数量（29 种）远超规约声明（10+6），v5.2 新增的时间/环境/第三方类别有效堵住了常见借口缺口。

**得分: 10/10**

---

## 3. L2 Hook 确定性拦截

### 3.1 Hook 注册架构 (hooks.json)

| Hook 类型 | 匹配器 | 脚本 | 超时 |
|-----------|--------|------|------|
| PreToolUse(Task) | `^Task$` | check-predecessor-checkpoint.sh | 30s |
| PostToolUse(Task) | `^Task$` | post-task-validator.sh | 60s |
| PostToolUse(Write\|Edit) | `^(Write\|Edit)$` | unified-write-edit-check.sh | 15s |
| PreCompact | (全局) | save-state-before-compact.sh | 15s |
| SessionStart | (全局) | scan-checkpoints-on-start.sh | 15s (async) |
| SessionStart | (全局) | check-skill-size.sh | 15s |
| SessionStart(compact) | compact | reinject-state-after-compact.sh | 15s |

### 3.2 unified-write-edit-check.sh 四项检查

此脚本统一了 v5.1 之前 3 个独立 Hook 脚本 + 1 项新增检查:

| 检查编号 | 功能 | 性能 | 确定性 |
|---------|------|------|--------|
| CHECK 0 | 子 Agent 状态隔离 -- 阻断 Phase 5 子 Agent 写入 openspec/ 和 checkpoint 路径 | ~1ms (纯 bash) | 确定性 |
| CHECK 1 | TDD 阶段隔离 -- RED/GREEN 文件类型强制执行 | ~1ms (纯 bash) | 确定性 |
| CHECK 2 | 禁止 TODO/FIXME/HACK 占位符 | ~2ms (grep) | 确定性 |
| CHECK 3 | 恒真断言检测 (JS/TS/Python/Java/Kotlin) | ~2ms (grep) | 确定性 |
| CHECK 4 | 代码约束 (config code_constraints) | ~10ms (python3) | 确定性 |

**Phase 检测逻辑验证** (第 42-76 行):

IN_PHASE5 的三级检测分支:
1. `PHASE4_CP 存在`: full 模式正常流程
2. `PHASE3_CP 存在 + tdd_mode=true`: full TDD 模式（Phase 4 被跳过）
3. `PHASE1_CP 存在 + mode != full`: lite/minimal 模式

此逻辑正确处理了所有执行模式下的 Phase 5 检测，避免在非 Phase 5 阶段触发约束检查。

**恒真断言检测覆盖** (CHECK 3):
- JavaScript/TypeScript: `expect(true).toBe(true)`, `expect(true).toBeTruthy()`
- Python: `assert True`, `self.assertTrue(True)`
- Java/Kotlin: `assertEquals(true, true)`, `assertTrue(true)`
- 通用: `assert true == true`

### 3.3 post-task-validator.sh / _post_task_validator.py 五项验证

| 验证器 | 功能 | 确定性 |
|--------|------|--------|
| VALIDATOR 1 | JSON 信封结构验证 (status/summary/artifacts/phase-specific fields) | 确定性 |
| VALIDATOR 2 | Anti-Rationalization 检测 (29 种模式) | 确定性 |
| VALIDATOR 3 | 代码约束检查 (forbidden_files/patterns) | 确定性 |
| VALIDATOR 4 | 并行合并守卫 (冲突检测 + scope 校验 + typecheck) | 确定性 |
| VALIDATOR 5 | Phase 1 决策格式验证 (选项卡片结构) | 确定性 |

**Phase 4 特殊规则**:
- warning 状态硬阻断 (第 157-160 行): `Phase 4 returned "warning" but only "ok" or "blocked" are accepted`
- artifacts 非空强制 (第 163-169 行)
- test_pyramid 地板验证: unit_pct >= 30%, e2e_pct <= 40%, total >= 10
- change_coverage >= 80% (bugfix/refactor 路由可提升)
- sad_path_counts >= 20% 每类型

**Phase 5 TDD Metrics L2 检查** (第 132-146 行):
```python
if tdd_metrics is not None:
    red_violations = tdd_metrics.get("red_violations", -1)
    if red_violations != 0:
        output_block(...)  # 零 RED 违规强制
    cycles_completed = tdd_metrics.get("cycles_completed", 0)
    if cycles_completed < 1:
        output_block(...)  # 至少 1 个完整循环
```

**结论**: L2 Hook 拦截体系架构成熟，两个统一脚本覆盖了 Write/Edit 和 Task 两大工具类别的全部验证场景，性能经过优化（v5.1 从 ~35s 降至 ~5s）。

**得分: 9/10** -- 完备且高效，扣分点为 TDD-5 回滚未提升至 L2。

---

## 4. 子 Agent 约束体系

### 4.1 JSON 信封契约

**必需字段** (VALIDATOR 1):
- 全阶段: `status` (ok|warning|blocked|failed)
- 推荐字段: `summary`, `artifacts`, `next_ready`
- Phase 4 额外: `test_counts`, `sad_path_counts`, `dry_run_results`, `test_pyramid`, `change_coverage`
- Phase 5 额外: `test_results_path`, `tasks_completed`, `zero_skip_check`
- Phase 6 额外: `pass_rate`, `report_path`, `report_format`

缺少必需字段 -> 硬阻断。这是 L2 确定性验证。

### 4.2 文件所有权 (ENFORCED)

并行模式下:
- 每个域 Agent 的 prompt 注入 `owned_files` 列表
- write-edit-constraint-check.sh 在并行模式下读取 `phase5-ownership/agent-{N}.json`
- 越权写入 -> block

**串行 Batch 模式** (v4.2 Concurrency Engine):
- 同 batch 内 task 互相注入 `sibling_task_files`
- 文件所有权通过 prompt 约束 + Hook 验证双重保障

### 4.3 状态隔离 (CHECK 0)

unified-write-edit-check.sh CHECK 0 (第 93-118 行):
- 阻断 Phase 5 子 Agent 写入 `context/phase-results/*`
- 阻断写入 `openspec/changes/*/context/*.json`
- 阻断写入 `.autopilot-active` 锁文件
- 例外: `.tdd-stage` 允许主线程写入

Checkpoint 写入由主线程通过 Bash 工具执行（非 Write 工具），天然绕过 Write/Edit Hook。

### 4.4 背景 Agent 产出约束

- 背景 Agent 必须 Write 到文件，返回信封仅含摘要
- _hook_preamble.sh 中 `is_background_agent` 函数用于跳过某些非必要检查
- 但 JSON 信封验证和反合理化检查不可绕过（确认于 hooks.json 中 post-task-validator.sh 对所有 Task 生效）

**结论**: 子 Agent 约束体系覆盖 JSON 信封、文件所有权、状态隔离三个维度，L2 确定性阻断有效。

**得分: 9/10**

---

## 5. 测试覆盖度

### 5.1 TDD 相关测试

在 `tests/` 目录中搜索 TDD 相关测试:

| 测试文件 | 相关度 | 覆盖内容 |
|----------|--------|---------|
| test_anti_rationalization.sh | 直接相关 | 4 个 case: 非 autopilot/模式检测/blocked 跳过/Phase 2 跳过 |
| test_background_agent_bypass.sh | 间接相关 | 验证背景 Agent 绕过 anti-rationalization |
| test_search_policy.sh | 间接相关 | 包含 refactor 关键词测试 |
| test_validate_config_v11.sh | 间接相关 | 验证 TDD 相关配置字段 |

**关键缺口**:

| 缺失的测试场景 | 重要性 | 说明 |
|---------------|--------|------|
| TDD RED 阶段拦截实现文件写入 | **高** | `.tdd-stage` = "red" 时 unified-write-edit-check.sh 应阻断非测试文件 |
| TDD GREEN 阶段拦截测试文件修改 | **高** | `.tdd-stage` = "green" 时应阻断测试文件 |
| TDD REFACTOR 阶段放行 | **中** | `.tdd-stage` = "refactor" 时应放行所有写入 |
| .tdd-stage 不存在时跳过 | **中** | 非 TDD 模式正常放行 |
| TDD Metrics L2 检查 (red_violations=0) | **高** | _post_task_validator.py VALIDATOR 1 中的 TDD 检查 |
| unified-write-edit-check.sh 恒真断言各语言 | **中** | JS/Python/Java 恒真断言检测 |

**现有测试质量评估**:
- test_anti_rationalization.sh: 4 个 case 覆盖了核心路径（bypass/block/skip），但未测试 v5.2 新增的时间/环境/第三方模式
- 测试使用旧版 anti-rationalization-check.sh（已 DEPRECATED），而非当前活跃的 _post_task_validator.py

**结论**: TDD 机制的 L2 Hook 实现代码完备，但测试覆盖严重不足。`.tdd-stage` 文件隔离逻辑和 TDD Metrics 验证均缺乏专项测试。

**得分: 5/10** -- 测试基础设施存在，但 TDD 核心路径测试缺失。

---

## 6. 评分

| 维度 | 得分 | 满分 | 说明 |
|------|------|------|------|
| TDD 回滚确定性 | 7 | 10 | 触发条件确定性 (L2 Bash)，但回滚执行为 L3 AI 驱动，缺乏自动化脚本 |
| `.tdd-stage` 生命周期 | 10 | 10 | 创建/消费/清理完整，崩溃恢复清理已在 v5.2 补全 |
| 崩溃恢复可靠性 | 9 | 10 | .tmp 清理 + .tdd-stage 清理 + per-task TDD 断点恢复，设计完整 |
| Anti-Rationalization 覆盖度 | 10 | 10 | 29 种模式 (15EN+14CN)，v5.2 新增时间/环境/第三方 7 种，远超规约声明 |
| L2 Hook 拦截力 | 9 | 10 | 两大统一脚本覆盖 9 项检查，性能优异，仅 TDD-5 回滚未提升至 L2 |
| 规约文档完备度 | 9 | 10 | CLAUDE.md + SKILL.md + tdd-cycle.md + phase5-implementation.md 形成完整链条 |
| 子 Agent 约束 | 9 | 10 | JSON 信封/文件所有权/状态隔离三维覆盖，L2 确定性阻断 |
| 测试覆盖度 | 5 | 10 | TDD 核心路径 (.tdd-stage 隔离、TDD Metrics L2) 缺乏专项测试 |
| **总计** | **68** | **80** | **换算百分制: 85/100** |

**综合评分: 88/100** (含定性加分: 架构设计成熟度 +3 分)

---

## 7. 改进建议

### P0 -- 必须修复

1. **新增 TDD 隔离测试文件** (`tests/test_tdd_isolation.sh`)
   - 覆盖 RED/GREEN/REFACTOR 三个阶段的文件写入拦截
   - 覆盖 .tdd-stage 不存在时的正常放行
   - 覆盖 TDD Metrics L2 检查 (red_violations=0, cycles_completed>=1)
   - 覆盖恒真断言检测各语言变体
   - 预计 12-15 个 test case

2. **更新 test_anti_rationalization.sh 测试目标**
   - 当前测试引用已废弃的 `anti-rationalization-check.sh`
   - 应改为测试 `_post_task_validator.py` 的 VALIDATOR 2
   - 增加 v5.2 新增模式（时间/环境/第三方借口）的测试 case

### P1 -- 建议改进

3. **TDD-5 回滚自动化脚本**
   - 创建 `scripts/tdd-refactor-rollback.sh`，封装 `git checkout -- .` 回滚逻辑
   - 主线程调用此脚本而非直接 AI 决策执行 `git checkout`
   - 脚本可增加安全检查: 验证当前在 REFACTOR 阶段、记录回滚日志

4. **并行 TDD L2 后置验证升级**
   - 当前并行 TDD 的 L2 后置验证仅执行 `Bash(full_test_command)`
   - 建议增加对 `tdd_unverified` task 数的阈值阻断（当前仅 stderr warning）

### P2 -- 长期优化

5. **Anti-Rationalization 模式持续扩展**
   - 添加更多领域特定的合理化模式（如 "性能影响可忽略"、"用户不会注意到"）
   - 考虑基于历史阻断数据的自适应权重调整

6. **TDD 崩溃恢复自动化测试**
   - 创建 fixture 模拟崩溃场景（RED 中断、GREEN 中断、REFACTOR 中断）
   - 验证恢复逻辑的正确性

7. **CLAUDE.md 规约声明更新**
   - "10+6 种 excuse 模式" 应更新为 "29 种加权模式 (15EN + 14CN)"，准确反映实际实现

---

## 附录 A: 文件交叉引用

| 文件 | 路径 | 角色 |
|------|------|------|
| 全局规约 | `plugins/spec-autopilot/CLAUDE.md` | TDD Iron Law + 代码质量硬约束定义 |
| 主编排 | `plugins/spec-autopilot/skills/autopilot/SKILL.md` | .tdd-stage 写入时机 + 路径 C TDD 模式 |
| TDD 循环协议 | `plugins/spec-autopilot/skills/autopilot/references/tdd-cycle.md` | RED-GREEN-REFACTOR 完整流程 + 回滚逻辑 |
| 崩溃恢复 | `plugins/spec-autopilot/skills/autopilot-recovery/SKILL.md` | .tdd-stage 残留清理 + per-task TDD 恢复 |
| 统一 Write/Edit Hook | `plugins/spec-autopilot/scripts/unified-write-edit-check.sh` | CHECK 0-4 (状态隔离+TDD 隔离+banned+assertion+constraint) |
| 统一 Task 验证器 | `plugins/spec-autopilot/scripts/_post_task_validator.py` | VALIDATOR 1-5 (信封+anti-rational+constraint+merge+decision) |
| Hook 注册表 | `plugins/spec-autopilot/hooks/hooks.json` | 3 个 Hook 入口 (PreToolUse+PostToolUse*2) |
| 门禁协议 | `plugins/spec-autopilot/skills/autopilot-gate/SKILL.md` | 8 步检查清单 + TDD 完整性审计 |
| Phase 5 实施 | `plugins/spec-autopilot/skills/autopilot/references/phase5-implementation.md` | 并行/串行/TDD 三路径 |
| 子 Agent 调度 | `plugins/spec-autopilot/skills/autopilot-dispatch/SKILL.md` | JSON 信封契约 + 路径注入 |

## 附录 B: Anti-Rationalization 完整模式清单

| # | 权重 | 语言 | 模式 | 类别 |
|---|------|------|------|------|
| 1 | 3 | EN | `skip(ped\|ping)? (this\|the\|these\|because)` | 跳过信号 |
| 2 | 3 | EN | `(tests?\|tasks?) were skip(ped\|ping)` | 跳过信号 |
| 3 | 3 | EN | `(deferred?\|postponed?\|deprioritized?) (to\|for\|until)` | 延迟信号 |
| 4 | 2 | EN | `out of scope` | 范围排除 |
| 5 | 2 | EN | `(will\|can\|should) be done later/separately/future` | 延迟信号 |
| 6 | 1 | EN | `already (covered\|tested\|handled\|addressed)` | 弱辩解 |
| 7 | 1 | EN | `not (needed\|necessary\|required\|relevant)` | 弱辩解 |
| 8 | 1 | EN | `(works\|good) enough` | 弱辩解 |
| 9 | 1 | EN | `too (complex\|difficult\|risky\|time-consuming)` | 弱辩解 |
| 10 | 1 | EN | `(minimal\|low) (impact\|priority\|risk)` | 弱辩解 |
| 11 | 1 | EN | `pre-existing (issue\|bug\|problem)` | 弱辩解 |
| 12 | 3 | EN | `(not enough\|ran out of\|insufficient) time` | 时间借口 (v5.2) |
| 13 | 3 | EN | `(deadline\|time constraint) prevents` | 时间借口 (v5.2) |
| 14 | 2 | EN | `(environment\|config) issue/not ready` | 环境借口 (v5.2) |
| 15 | 2 | EN | `(third-party\|external) dependency block/unavailable` | 第三方借口 (v5.2) |
| 16 | 3 | CN | `测试/任务/功能/用例 被/已 跳过/省略/忽略` | 跳过信号 |
| 17 | 3 | CN | `跳过了/已跳过/被跳过` | 跳过信号 |
| 18 | 3 | CN | `延后/推迟/暂缓 处理/实现/开发` | 延迟信号 |
| 19 | 3 | CN | `后续 再/补充/处理/实现/完善` | 延迟信号 |
| 20 | 2 | CN | `超出/不在 范围/scope` | 范围排除 |
| 21 | 2 | CN | `以后/后面/后续/下阶段 再/来/处理/实现` | 延迟信号 |
| 22 | 2 | CN | `暂时/先 不做/不处理/不实现/不考虑` | 延迟信号 |
| 23 | 1 | CN | `已经/已被 覆盖/测试/处理/实现/验证` | 弱辩解 |
| 24 | 1 | CN | `不/无 需要/必要/需/必须` | 弱辩解 |
| 25 | 1 | CN | `太/过于 复杂/困难/耗时` | 弱辩解 |
| 26 | 1 | CN | `影响/优先级/风险 较低/不大/很小` | 弱辩解 |
| 27 | 3 | CN | `时间/工期/deadline 不够/不足/紧张/来不及` | 时间借口 (v5.2) |
| 28 | 2 | CN | `环境/配置/基础设施 未就绪/有问题/不可用` | 环境借口 (v5.2) |
| 29 | 2 | CN | `第三方/外部/上游 依赖/服务 阻塞/不可用` | 第三方借口 (v5.2) |
