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
| `context_management` | 上下文保护配置（每 Phase 自动 git commit、autocompact 阈值） |
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

> **Checkpoint 范围**: Phase 1-6 产生 checkpoint 文件。Phase 0、7 在主线程执行，不写 checkpoint。

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
   {"change":"<change_name>","pid":"<当前进程PID>","started":"<ISO-8601时间戳>","session_cwd":"<项目根目录>"}
   ```
   - 此文件供 Hook 脚本确定性识别当前活跃 change，避免多 change 并发时的误判
   - 启动时检查：如果 lock 文件已存在，读取 `pid` 字段，检查该进程是否存活（`kill -0 <pid>`）
     - 进程存活 → AskUserQuestion：「检测到另一个 autopilot 正在运行（PID: {pid}，启动于 {started}），是否覆盖？」
     - 进程不存在 → 视为崩溃残留，自动清理并覆盖

## Phase 1: 需求理解与多轮决策（主线程）

**核心原则**: 绝不假设，始终列出选项由用户决策。

### 1.1 获取需求来源

- `$ARGUMENTS` 为文件路径 → 读取文件内容
- `$ARGUMENTS` 为文本 → 直接作为需求描述
- `$ARGUMENTS` 为空 → AskUserQuestion 要求输入

### 1.2 需求分析

调用 Task(subagent_type = config.phases.requirements.agent) 分析需求，产出:
- 功能清单
- 疑问点列表（每个疑问必须转化为决策点）
- 技术可行性初判

> **返回值校验**: 主线程必须检查 business-analyst 子 Agent 返回非空，且包含功能清单和疑问点。如果返回为空或格式异常，应重新 dispatch 并在 prompt 中明确要求结构化输出。此 Task 不含 autopilot-phase 标记（设计预期），因此不受 Hook 门禁校验。

### 1.3 多轮决策循环（LOOP）

**循环条件**: 存在任何未澄清的决策点

每轮循环:
1. 梳理当前所有未决策点
2. 将每个决策点转化为 AskUserQuestion（2-4 个选项，推荐方案标 Recommended）
3. 收集用户决策结果
4. 检查是否产生新的决策点
5. 重复直到**所有点全部澄清**

### 1.4 生成结构化提示词

整理所有决策结果，包含: 背景与目标、功能清单、决策结论、技术约束、验收标准。

### 1.5 最终确认

展示完整提示词，AskUserQuestion:
"以上需求理解是否准确？如有遗漏请补充。"
选项: "确认，开始实施 (Recommended)" / "需要补充修改"
- 选"补充" → 回到 1.3 循环

### 1.6 写入 Phase 1 Checkpoint

需求确认后，调用 Skill(`spec-autopilot:autopilot-checkpoint`) 写入 `phase-1-requirements.json`：

```json
{
  "status": "ok",
  "summary": "需求分析完成，共 N 个功能点，M 个决策已确认",
  "artifacts": ["openspec/changes/<name>/context/prd.md", "openspec/changes/<name>/context/discussion.md"],
  "requirements_summary": "功能概要...",
  "decisions": [{"point": "决策点描述", "choice": "用户选择"}],
  "change_name": "<推导出的 kebab-case 名称>"
}
```

> 此 checkpoint 使崩溃恢复能跳过 Phase 1，直接从 Phase 2 继续。

### 1.7 可配置用户确认点

如果 `config.gates.user_confirmation.after_phase_1 === true`（默认 true）：
- AskUserQuestion：「需求分析已完成，是否确认进入 OpenSpec 创建阶段？」
- 选项: "继续 (Recommended)" / "暂停，我需要再想想"
- 选"暂停" → 结束当前流水线，用户可后续通过崩溃恢复继续

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
Step 7: 上下文保护 — 自动 Git Commit（当 config.context_management.git_commit_per_phase = true）
        → git add openspec/changes/<name>/context/phase-results/
        → git commit -m "autopilot: Phase N complete — <phase_summary>"
        → 此 commit 是崩溃恢复的额外安全网，确保 checkpoint 持久化到 git 历史
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

**Phase 5 启动前安全准备**：
1. **Git 安全检查点**：在实施任何代码变更前，创建 git tag `autopilot-phase5-start` 标记当前状态
   ```
   git tag -f autopilot-phase5-start HEAD
   ```
   如果 Phase 5 实施失败需要回退，可通过 `git diff autopilot-phase5-start..HEAD` 查看所有变更，或通过 `git stash` 暂存后 `git checkout autopilot-phase5-start` 回退。
2. **记录启动时间戳**：在 `openspec/changes/<name>/context/phase-results/phase5-start-time.txt` 写入 ISO-8601 时间戳，供 wall-clock 超时检查使用。

**Wall-clock 超时机制**：
- 每次迭代开始时检查已用时间 = 当前时间 - phase5-start-time
- 超过 **2 小时** → 强制暂停，AskUserQuestion：「Phase 5 已运行 {elapsed} 分钟，是否继续？」
- 选项："继续执行" / "保存进度并暂停" / "回退到 Phase 5 起始点"

**实施流程**：
1. 检查 `.claude/settings.json` 中 `enabledPlugins` 是否包含 `ralph-loop`
2. **检查 worktree 隔离模式**：读取 `config.phases.implementation.worktree.enabled`
   - **启用** → Phase 5 按 task 粒度派发，每个 task 通过 `Task(isolation: "worktree")` 在独立 worktree 中执行
     - 每个 task 完成后，worktree 变更自动合并回主分支
     - 如有合并冲突 → AskUserQuestion 展示冲突文件，让用户选择处理方式
     - 主线程上下文不被实现代码膨胀
   - **禁用**（默认） → 使用下方 ralph-loop / fallback 策略
3. **ralph-loop 可用** → 通过 Skill 调用 `ralph-loop:ralph-loop`，读取 config.phases.implementation
4. **不可用但 config.phases.implementation.ralph_loop.fallback_enabled** → 进入手动循环模式
   - 每次迭代执行 Skill(`openspec-apply-change`) 实施一个任务
   - 每任务后运行 quick_check，每 3 任务运行 full_test
   - 遵循 3 次失败暂停策略
   - 最大迭代次数从 config.phases.implementation.ralph_loop.max_iterations 读取
4. **不可用且 fallback 禁用** → AskUserQuestion：
   ```
   "ralph-loop 插件不可用，手动 fallback 也已禁用。请选择处理方式："
   选项:
   - "启用 fallback 模式 (Recommended)" → 修改 config 中 fallback_enabled 为 true，进入手动循环
   - "暂停流水线，手动安装 ralph-loop" → 展示安装命令，暂停等待
   - "跳过实施阶段（仅测试已有代码）" → 标记 Phase 5 为 warning，继续 Phase 6
   ```

### Phase 5→6 特殊门禁

autopilot-gate 额外验证：
- `test-results.json` 存在
- `zero_skip_check.passed === true`
- `tasks.md` 中所有任务标记为 `[x]`

---

## Phase 6→7 过渡: 并行质量扫描（主线程派发，不阻塞）

Phase 6 完成后、Phase 7 之前，主线程**同时**派发多个后台质量扫描 Agent。这些 Agent 与 Phase 7 的汇总准备并行执行。

### 派发流程

读取 `config.async_quality_scans`，对每个扫描项：

1. **检查工具是否已安装**（通过 `command -v` 或 `npx --version` 验证）
2. **未安装 → 自动安装**（使用项目包管理器：pnpm add -D / pip install / Gradle plugin）
3. **安装失败 → 联网搜索安装方式，重试一次**
4. **仍失败 → 标记该扫描为 "install_failed"，继续其他扫描**

使用 `Task(run_in_background: true)` 并行派发所有扫描：

```
scan_agents = []
for scan in config.async_quality_scans:
  agent = Task(
    subagent_type: "general-purpose",
    run_in_background: true,
    prompt: "<!-- autopilot-quality-scan:{scan.name} -->
      1. 检查工具: {scan.check_command}
      2. 未安装则执行: {scan.install_command}
      3. 运行扫描: {scan.command}
      4. 阈值: {scan.threshold}
      返回 JSON: {status, summary, score, details, installed}"
  )
  scan_agents.append(agent)
```

### 结果收集

Phase 7 开始时，逐一检查后台 Agent 状态：
- **已完成** → 读取结果，纳入质量汇总表
- **仍在运行** → AskUserQuestion：「{scan_name} 仍在执行，是否等待？」
  - "等待完成" → 轮询直到完成
  - "跳过，先看其他结果" → 标记该扫描为 pending

### 质量汇总表（Phase 7 展示）

```
| 扫描项 | 状态 | 得分 | 阈值 | 结果 |
|--------|------|------|------|------|
| 核心测试 | ok | 95% | 90% | PASS |
| 契约测试 | ok | 3/3 | all | PASS |
| 性能审计 | warn | 76 | 80 | WARN |
| 视觉回归 | ok | 0 diff | 0 | PASS |
| 变异测试 | ok | 68% | 60% | PASS |
```

> **注意**: 质量扫描的 prompt 不含 `<!-- autopilot-phase:N -->` 标记，因此不受 Hook 门禁校验。这些是信息性扫描，不是阶段门禁。扫描失败不阻断归档，但会在汇总表中标红警告。

---

## Phase 7: 汇总 + 用户确认归档（主线程）

1. 读取所有 phase-results checkpoint，展示状态汇总表
2. **收集并行质量扫描结果**：检查上一步派发的后台 Agent，展示质量汇总表（含得分和阈值对比）
3. **必须** AskUserQuestion 询问用户：
   ```
   "所有阶段已完成。是否归档此 change？"
   选项:
   - "立即归档 (Recommended)"
   - "暂不归档，稍后手动处理"
   - "需要修改后再归档"
   ```
3. 用户选择"立即归档" → 执行 Skill(`openspec-archive-change`)
4. 用户选择"暂不归档" → 展示手动归档命令，结束流程
5. 用户选择"需要修改" → 提示用户修改后可重新触发或手动归档
6. **清理锁定文件**：删除 `openspec/changes/.autopilot-active`（无论用户选择何种归档方式）
7. **清理 git tag**：删除 `autopilot-phase5-start` tag（如果存在）：`git tag -d autopilot-phase5-start 2>/dev/null`

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
| 上下文保护 | 每 Phase 完成后 git commit checkpoint；子 Agent 回传精简摘要，不传原始输出 |

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
