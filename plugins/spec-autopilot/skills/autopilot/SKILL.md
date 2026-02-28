---
name: autopilot
description: "Full autopilot orchestrator: requirements → OpenSpec → implementation → testing → reporting → archive. Triggers: '全自动开发流程', '一键从需求到交付', '启动autopilot'. NOT for single-phase tasks like /opsx:apply or /opsx:ff."
argument-hint: "[需求描述或 PRD 文件路径]"
---

# Autopilot — 主线程编排器

在主线程中直接执行 8 阶段全自动交付流水线。Phase 2-6 通过 Task 工具派发**单层**子 Agent。

> **架构约束**: 子 Agent 内部没有 Task 工具，所有 Task 派发必须在主线程中执行，禁止嵌套。

## 配置加载

启动时**必须**读取 `.claude/autopilot.config.yaml`，从中获取：

| 配置节 | 用途 |
|--------|------|
| `services` | 服务健康检查地址 |
| `phases.requirements` | 需求分析 Agent、最少 QA 轮数 |
| `phases.testing` | 测试 Agent、instruction_files、reference_files、gate 门禁阈值 |
| `phases.implementation` | instruction_files、ralph_loop 配置、worktree 隔离配置 |
| `phases.reporting` | instruction_files、report_commands、coverage_target、zero_skip_required |
| `gates.user_confirmation` | 各阶段间可选用户确认点（after_phase_1, after_phase_3 等） |
| `async_quality_scans` | Phase 6→7 并行质量扫描配置（契约/性能/视觉/变异测试） |
| `context_management` | 上下文保护配置（每 Phase 自动 git commit、autocompact 阈值、squash_on_archive） |
| `test_suites` | 各测试套件命令和类型 |

如果配置文件不存在 → 自动调用 Skill(`spec-autopilot:autopilot-init`) 扫描项目生成配置。

## 协议技能

| 技能 | 用途 |
|------|------|
| `spec-autopilot:autopilot-recovery` | 崩溃恢复协议 |
| `spec-autopilot:autopilot-gate` | 阶段门禁验证 |
| `spec-autopilot:autopilot-dispatch` | 子 Agent 调度构造 |
| `spec-autopilot:autopilot-checkpoint` | 检查点读写管理 |

## 阶段总览

| Phase | 执行位置 | Description |
|-------|----------|-------------|
| 0 | 主线程 | 环境检查 + 崩溃恢复 |
| 1 | 主线程 | 需求理解与多轮决策（LOOP 直到全部澄清） |
| 2 | Task 子 Agent | 创建 OpenSpec 并保存上下文 |
| 3 | Task 子 Agent | OpenSpec 快进生成制品 |
| 4 | Task 子 Agent | 测试用例设计（强制，不可跳过） |
| 5 | Task 子 Agent | Ralph Loop / Fallback 循环实施 |
| 6 | Task 子 Agent | 测试报告生成（强制，不可跳过） |
| 7 | 主线程 | 汇总展示 + **用户确认**归档 |

> **Checkpoint 范围**: Phase 1-7 产生 checkpoint 文件。Phase 0 在主线程执行，不写 checkpoint。

---

## Phase 0: 环境检查 + 崩溃恢复

1. 检查 `.claude/autopilot.config.yaml` 是否存在
   - **不存在** → 调用 Skill(`spec-autopilot:autopilot-init`) 自动扫描项目并生成配置
   - **存在** → 直接读取并解析所有配置节
2. 读取 `.claude/settings.json` 的 `enabledPlugins` → 检查 ralph-loop 插件是否启用
3. **调用 Skill(`spec-autopilot:autopilot-recovery`)**：扫描 checkpoint，决定起始阶段
4. 使用 TaskCreate 创建 8 个阶段任务 + blockedBy 依赖链
   - 崩溃恢复时：已完成阶段直接标记 completed
5. **写入活跃 change 锁定文件**：确定 change 名称后，写入 `openspec/changes/.autopilot-active`（JSON 格式）：
   ```json
   {"change":"<change_name>","pid":"<当前进程PID>","started":"<ISO-8601时间戳>","session_cwd":"<项目根目录>","anchor_sha":"<SHA>","session_id":"<毫秒级时间戳>"}
   ```
   - 此文件供 Hook 脚本确定性识别当前活跃 change，避免多 change 并发时的误判
   - 启动时检查：如果 lock 文件已存在，读取 `pid` 和 `session_id` 字段，执行防 PID 回收检测：
     - PID 存活 + `session_id` 匹配 → 确认为同一进程，AskUserQuestion：「检测到另一个 autopilot 正在运行（PID: {pid}，启动于 {started}），是否覆盖？」
     - PID 存活 + `session_id` 不匹配 → PID 已被操作系统回收给其他进程，视为崩溃残留，自动清理并覆盖
     - PID 不存在 → 视为崩溃残留，自动清理并覆盖
6. **创建锚定 Commit**：为后续 fixup + autosquash 策略创建空锚定 commit：
   ```
   git commit --allow-empty -m "autopilot: start <change_name>"
   ANCHOR_SHA=$(git rev-parse HEAD)
   ```
   将 `ANCHOR_SHA` 写入锁定文件的 `anchor_sha` 字段（更新已写入的 `.autopilot-active` 文件）

## Phase 1: 需求理解与多轮决策（主线程）

**核心原则**: 绝不假设，始终列出选项由用户决策。

**执行前读取**: `references/phase1-requirements.md`（完整的 7 步流程）

概要流程:
1. 获取需求来源（$ARGUMENTS 解析）
2. Task 调度 business-analyst 分析需求，产出功能清单 + 疑问点
3. **多轮决策 LOOP** — AskUserQuestion 逐个澄清决策点，直到全部确认
4. 生成结构化提示词 → 用户最终确认
5. 写入 `phase-1-requirements.json` checkpoint
6. 可配置用户确认点（`config.gates.user_confirmation.after_phase_1`）

---

## Phases 2-6: 统一调度模板

对于每个 Phase N（2 ≤ N ≤ 6），在**主线程**中执行：

```
Step 1: 调用 Skill("spec-autopilot:autopilot-gate")
        → 执行 8 步阶段切换检查清单（验证 Phase N-1 checkpoint）
Step 1.5: 检查可配置用户确认点（仅当 config.gates.user_confirmation.after_phase_{N} === true 时）
        → AskUserQuestion 确认后继续，选暂停则保存进度退出
Step 2: 调用 Skill("spec-autopilot:autopilot-dispatch")
        → 按协议构造 Task prompt
        → 从 config.phases[当前阶段].instruction_files 注入指令文件路径
        → 从 config.phases[当前阶段].reference_files 注入参考文件路径
Step 3: 使用 Task 工具派发子 Agent
        → prompt 开头必须包含 <!-- autopilot-phase:N --> 标记
        → Hook 脚本自动校验前置 checkpoint 和返回 JSON
Step 4: 解析子 Agent 返回的 JSON 信封
        → ok → 继续
        → warning → **Phase 4 特殊处理**（见下方）
        → blocked/failed → 暂停展示给用户
Step 5: 调用 Skill("spec-autopilot:autopilot-checkpoint")
        → 写入 phase-results checkpoint 文件
Step 6: TaskUpdate Phase N → completed
Step 7: 上下文保护 — 自动 Git Fixup Commit（当 config.context_management.git_commit_per_phase = true）
        → 读取 `openspec/changes/.autopilot-active` 中的 `anchor_sha` 字段
        → git add openspec/changes/<name>/context/phase-results/
        → git commit --fixup=$ANCHOR_SHA
        → 此 fixup commit 将在 Phase 7 归档时通过 autosquash 合并为一个 commit
        → 同时也是崩溃恢复的额外安全网，确保 checkpoint 持久化到 git 历史
```

### Phase 4 特殊门禁

autopilot-gate 额外验证（阈值从 config.phases.testing.gate 读取）：
- `test_counts` 每个字段 ≥ config.phases.testing.gate.min_test_count_per_type
- `artifacts` 包含 config.phases.testing.gate.required_test_types 对应文件
- `dry_run_results` 全部为 0（exit code）

**Phase 4 warning 降级阻断规则**：

Phase 4 返回 `status: "warning"` 时，主线程**必须**执行以下检查：
1. 检查 `test_counts` 是否所有字段 ≥ min_test_count_per_type
2. 检查 `artifacts` 是否非空
3. **如果 test_counts 任一字段 < min_test_count_per_type 或 artifacts 为空**：
   - 将 status 强制覆盖为 `"blocked"`
   - 不写入 checkpoint
   - 展示给用户：「Phase 4 返回 warning 但未创建足够测试用例，视为 blocked」
   - 重新 dispatch Phase 4

Phase 4 **不允许**以 warning 状态通过门禁。要么 ok（测试全部创建），要么 blocked（需要排除障碍）。

### Phase 5 特殊处理

**执行前读取**: `references/phase5-implementation.md`（完整的安全准备、超时机制、实施流程）

概要:
1. Git 安全检查点 → `git tag -f autopilot-phase5-start HEAD`
2. 记录启动时间戳 → wall-clock 超时机制（2 小时硬限）
3. 检测 ralph-loop 可用性 + worktree 隔离配置
4. **ralph-loop 可用** → 构造参数调用 `Skill("ralph-loop:ralph-loop")`，完成后从 test-results.json 构造 JSON 信封
5. **不可用 + fallback 启用** → 手动循环模式（每任务 apply + 测试）
6. **不可用 + fallback 禁用** → AskUserQuestion 让用户选择处理方式

### Phase 5→6 特殊门禁

autopilot-gate 额外验证：`test-results.json` 存在、`zero_skip_check.passed === true`、`tasks.md` 全部 `[x]`

---

## Phase 6→7 过渡: 并行质量扫描（主线程派发，不阻塞）

**执行前读取**: `references/quality-scans.md`（完整的派发流程、安装重试、结果收集、硬超时机制）

概要:
1. 读取 `config.async_quality_scans`，对每个扫描项检查工具安装 → 未安装自动安装 → 仍失败标记 "install_failed"
2. 使用 `Task(run_in_background: true)` 并行派发所有扫描（prompt 不含 autopilot-phase 标记，不受 Hook 门禁）
3. Phase 7 开始时收集结果，硬超时（默认 10 分钟，`config.async_quality_scans.timeout_minutes`）自动标记 "timeout"
4. 生成质量汇总表（扫描项 / 状态 / 得分 / 阈值 / PASS|WARN|TIMEOUT）

> 扫描失败不阻断归档，但会在汇总表中标红警告。

---

## Phase 7: 汇总 + 用户确认归档（主线程）

0. **写入 Phase 7 Checkpoint（进行中）**：调用 Skill(`spec-autopilot:autopilot-checkpoint`) 写入 `phase-7-summary.json`：
   ```json
   {"status": "in_progress", "phase": 7, "description": "Archive and cleanup"}
   ```
1. 读取所有 phase-results checkpoint，展示状态汇总表
2. **收集并行质量扫描结果**：检查上一步派发的后台 Agent，展示质量汇总表（含得分和阈值对比）
   - **硬超时机制**：等待扫描结果时，最多等待 `config.async_quality_scans.timeout_minutes` 分钟（默认 10 分钟）
   - 超时后自动将该扫描标记为 `"timeout"`，**不询问用户是否继续等待**，直接继续后续步骤
   - 超时的扫描在质量汇总表中显示 `TIMEOUT` 状态
3. **必须** AskUserQuestion 询问用户：
   ```
   "所有阶段已完成。是否归档此 change？"
   选项:
   - "立即归档 (Recommended)"
   - "暂不归档，稍后手动处理"
   - "需要修改后再归档"
   ```
4. 用户选择"立即归档"：
   a. **Git 自动压缩**（当 `config.context_management.squash_on_archive` 为 true，默认 true）：
      - 读取 `openspec/changes/.autopilot-active` 中的 `anchor_sha`
      - 执行 `GIT_SEQUENCE_EDITOR=: git rebase -i --autosquash $ANCHOR_SHA~1`
      - 成功 → 修改最终 commit message 为 `feat(autopilot): <change_name> — <summary>`
      - 失败（冲突等） → 执行 `git rebase --abort`，保留原始 fixup commits，警告用户需手动处理压缩
   b. 执行 Skill(`openspec-archive-change`)
   c. **更新 Phase 7 Checkpoint（完成）**：调用 Skill(`spec-autopilot:autopilot-checkpoint`) 更新 `phase-7-summary.json`：
      ```json
      {"status": "ok", "phase": 7, "description": "Archive complete", "archived_change": "<change_name>"}
      ```
5. 用户选择"暂不归档" → 展示手动归档命令，结束流程
6. 用户选择"需要修改" → 提示用户修改后可重新触发或手动归档
7. **清理临时文件**：
   - 删除 `openspec/changes/<name>/context/phase-results/phase5-start-time.txt`（如果存在）
8. **清理锁定文件**：删除 `openspec/changes/.autopilot-active`（无论用户选择何种归档方式）
9. **清理 git tag**：删除 `autopilot-phase5-start` tag（如果存在）：`git tag -d autopilot-phase5-start 2>/dev/null`

**禁止自动归档**: 归档操作必须经过用户明确确认。

---

## 护栏约束

| 约束 | 规则 |
|------|------|
| 主线程编排 | 所有 Task 派发在主线程执行，禁止嵌套 Task |
| 配置驱动 | 所有项目路径从 autopilot.config.yaml 读取，禁止硬编码 |
| 阶段门禁 | Hook 确定性 + autopilot-gate 检查清单 |
| 阶段跳过阻断 | Hook + TaskCreate blockedBy 确定性阻断 |
| 任务系统 | Phase 0 创建 8 个阶段任务 + blockedBy 链 |
| 崩溃恢复 | autopilot-recovery Skill 扫描 checkpoint |
| 结构化标记 | 子 Agent prompt 开头包含 `<!-- autopilot-phase:N -->` |
| 结构化返回 | 子 Agent 必须返回 JSON 信封 |
| 测试不可变 | 禁止修改测试以通过；只能修改实现代码 |
| 零跳过 | Phase 6 零跳过门禁 |
| 任务拆分 | 每次 ≤3 个文件，≤800 行代码 |
| 归档确认 | Phase 7 必须经用户确认后才能归档 |
| 上下文保护 | 每 Phase 完成后 git fixup commit checkpoint；子 Agent 回传精简摘要，不传原始输出；Phase 7 归档时 autosquash 合并 |
| PID 回收防护 | 锁文件同时检查 PID 存活 + session_id 匹配，防止 PID 被系统回收导致误判 |
| 质量扫描超时 | 硬超时（默认 10 分钟），超时自动标记 timeout，不询问用户 |

## 错误处理

| 场景 | 处理方式 |
|------|----------|
| 配置文件缺失 | 调用 autopilot-init 自动生成 |
| 工具未安装 | 主动安装，失败则联网搜索 |
| ralph-loop 异常退出 | 保存进度到 phase-results，提示用户 |
| 测试全部失败 | 分析根因，不盲目修改 |
| 子 Agent 返回异常 | JSON 解析失败 → 标记 failed |
| 阶段状态文件缺失 | 视为未完成，重新执行 |
| **上下文压缩** | 见下方恢复协议 |

## 上下文压缩恢复协议

长流水线执行中 Claude Code 可能触发上下文压缩（compaction），导致对话历史被摘要化，丢失精确的阶段状态。

### 自动机制（Hook 驱动，无需主线程干预）

1. **PreCompact Hook**：压缩前自动将当前编排状态写入 `openspec/changes/<name>/context/autopilot-state.md`
2. **SessionStart(compact) Hook**：压缩后自动将状态文件内容注入回 Claude 上下文

### 主线程恢复行为

如果检测到上下文被压缩（收到 `=== AUTOPILOT STATE RESTORED ===` 标记），主线程应：

1. 读取 `autopilot-state.md` 获取当前进度（last completed phase、next phase）
2. 读取 `autopilot.config.yaml` 重新加载配置
3. 读取 `context/phase-results/` 目录下所有 checkpoint 确认状态
4. 从下一个未完成阶段继续执行，无需重建 TaskCreate 链（已有的 Task 仍然有效）
5. 调用 Skill(`spec-autopilot:autopilot-gate`) 验证前置条件后继续 dispatch
