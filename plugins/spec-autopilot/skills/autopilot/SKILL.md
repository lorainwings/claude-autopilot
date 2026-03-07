---
name: autopilot
description: "Full autopilot orchestrator: requirements → OpenSpec → implementation → testing → reporting → archive. Triggers: '全自动开发流程', '一键从需求到交付', '启动autopilot'. NOT for single-phase tasks like /opsx:apply or /opsx:ff."
argument-hint: "[mode] [需求描述或 PRD 文件路径] — mode: full(default)|lite|minimal"
---

# Autopilot — 主线程编排器

在主线程中直接执行全自动交付流水线。Phase 2-6 通过 Task 工具派发**单层**子 Agent。

> **架构约束**: 子 Agent 内部没有 Task 工具，所有 Task 派发必须在主线程中执行，禁止嵌套。

## 执行模式

支持 3 种执行模式，按任务规模选择：

| 模式 | 阶段 | 跳过内容 | 适用场景 |
|------|------|---------|---------|
| **full** | 0→1→2→3→4→5→6→7 | 无 | 中大型功能，需要完整规范 |
| **lite** | 0→1→5→6→7 | OpenSpec（Phase 2/3/4） | 小功能，需求明确，跳过规范文档 |
| **minimal** | 0→1→5→7 | OpenSpec + 测试（Phase 2/3/4/6） | 极简需求，跳过规范和测试报告 |

### 核心约束：模式只控制阶段跳过，不影响阶段质量

**Phase 1（需求讨论）和 Phase 5（实施）在所有模式下执行完全相同的流程，无任何简化或跳过。**

### 模式解析优先级

```
1. $ARGUMENTS 关键词匹配: "lite"/"minimal"/"full" → 直接使用
2. config.default_mode → 配置默认值
3. 未指定 → "full"

解析: $ARGUMENTS = "[mode_keyword] [actual_requirement]"
  - 首个 token 匹配 full|lite|minimal → 提取为 mode，剩余为需求
  - 不匹配 → mode 从 config 读取，整体为需求
```

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
| `async_quality_scans` | Phase 6→7 并行质量扫描配置（契约/性能/视觉/变异/安全测试） |
| `code_constraints` | 可选：代码生成约束（Phase 5 Hook 自动验证） |
| `context_management` | 上下文保护配置（每 Phase 自动 git commit、autocompact 阈值、squash_on_archive） |
| `test_suites` | 各测试套件命令和类型 |
| `default_mode` | 执行模式默认值：full(默认)/lite/minimal |

如果配置文件不存在 → 自动调用 Skill(`spec-autopilot:autopilot-init`) 扫描项目生成配置。

## 协议技能

| 技能 | 用途 |
|------|------|
| `spec-autopilot:autopilot-recovery` | 崩溃恢复协议 |
| `spec-autopilot:autopilot-gate` | 阶段门禁验证 |
| `spec-autopilot:autopilot-dispatch` | 子 Agent 调度构造 |
| `spec-autopilot:autopilot-checkpoint` | 检查点读写管理 |

**参考文档**:
| 文档 | 用途 |
|------|------|
| `references/parallel-dispatch.md` | 跨阶段通用并行编排协议（Phase 1/4/5/6） |

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
   - **存在** → 直接读取并解析所有配置节，然后调用 `bash scripts/validate-config.sh` 验证 schema 完整性（valid=false 时展示 missing_keys 并提示修复）
2. **解析执行模式**：
   - 从 $ARGUMENTS 首个 token 提取 mode（full/lite/minimal）
   - 未匹配 → 读取 `config.default_mode`（默认 "full"）
   - 展示当前模式：「执行模式: {mode}（阶段: {phase_list}）」
3. 读取 `.claude/settings.json` 的 `enabledPlugins` → 检查 ralph-loop 插件是否启用
4. **调用 Skill(`spec-autopilot:autopilot-recovery`)**：扫描 checkpoint，决定起始阶段
5. 使用 TaskCreate 创建阶段任务 + blockedBy 依赖链
   - **full 模式**: 创建 Phase 1-7（7 个任务）
   - **lite 模式**: 创建 Phase 1, 5, 6, 7（4 个任务），Phase 5 blockedBy Phase 1，Phase 6 blockedBy Phase 5
   - **minimal 模式**: 创建 Phase 1, 5, 7（3 个任务），Phase 5 blockedBy Phase 1
   - 崩溃恢复时：已完成阶段直接标记 completed
6. **写入活跃 change 锁定文件**：确定 change 名称后，写入 `openspec/changes/.autopilot-active`（JSON 格式）：
   ```json
   {"change":"<change_name>","pid":"<当前进程PID>","started":"<ISO-8601时间戳>","session_cwd":"<项目根目录>","anchor_sha":"<SHA>","session_id":"<毫秒级时间戳>","mode":"<full|lite|minimal>"}
   ```
   - 此文件供 Hook 脚本确定性识别当前活跃 change，避免多 change 并发时的误判
   - 启动时检查：如果 lock 文件已存在，读取 `pid` 和 `session_id` 字段，执行防 PID 回收检测：
     - PID 存活 + `session_id` 匹配 → 确认为同一进程，AskUserQuestion：「检测到另一个 autopilot 正在运行（PID: {pid}，启动于 {started}），是否覆盖？」
     - PID 存活 + `session_id` 不匹配 → PID 已被操作系统回收给其他进程，视为崩溃残留，自动清理并覆盖
     - PID 不存在 → 视为崩溃残留，自动清理并覆盖
7. **创建锚定 Commit**：为后续 fixup + autosquash 策略创建空锚定 commit：
   ```
   git commit --allow-empty -m "autopilot: start <change_name>"
   ANCHOR_SHA=$(git rev-parse HEAD)
   ```
   将 `ANCHOR_SHA` 写入锁定文件的 `anchor_sha` 字段（更新已写入的 `.autopilot-active` 文件）
   > **原子性保障**：步骤 6 初次写入锁文件时 `anchor_sha` 设为空字符串。步骤 7 创建 commit 后立即更新。如果步骤 7 之前崩溃，恢复时检测到 `anchor_sha` 为空 → 重新创建锚定 commit 并更新。Phase 7 autosquash 前**必须**验证 `anchor_sha` 非空且 `git rev-parse $ANCHOR_SHA` 有效，无效则跳过 autosquash 并警告用户。

## Phase 1: 需求理解与多轮决策（主线程）

**核心原则**: 绝不假设，始终列出选项由用户决策。

**执行前读取**: `references/phase1-requirements.md`（完整的 10 步流程）

概要流程:
1. 获取需求来源（$ARGUMENTS 解析）
2. **并行调研**（v3.2.0 增强）→ 读取 `references/parallel-dispatch.md` Phase 1 并行配置，同时派发：
   ```
   ┌─ Auto-Scan (Explore agent) → Steering Documents
   ├─ 技术调研 (Explore agent) → research-findings.md        ← 三者并行
   └─ 联网搜索 (general-purpose) → web-research-findings.md  ← 条件: web_search.enabled
   ```
   **强制并行约束**（v3.2.1）：主线程**必须在同一条消息中**同时发起所有调研 Task（全部设置 `run_in_background: true`），然后等待 Claude Code 自动完成通知。
   - ❌ **禁止**：逐个发起 Task，等前一个完成再发下一个
   - ❌ **禁止**：使用前台 Explore agent 逐个扫描
   - ❌ **禁止**：使用 TaskOutput 检查后台 Agent 进度（TaskOutput 仅适用于 Bash 后台命令）
   - ✅ **正确**：在一条消息中包含 2-3 个 `Task(run_in_background: true)` 调用
   优先读取持久化上下文（`openspec/.autopilot-context/`），7 天内有效则跳过 Auto-Scan 仅做增量
3. **汇合调研结果** → 三个 Agent 写入独立文件（无需文件级合并），主线程读取验证每个文件存在且非空：
   - `context/project-context.md` + `existing-patterns.md` + `tech-constraints.md`（Auto-Scan 产出）
   - `context/research-findings.md`（技术调研产出）
   - `context/web-research-findings.md`（联网搜索产出，可选）
   后续 dispatch 模板自动注入全部文件路径给子 Agent
4. **复杂度评估与分路** → 基于调研结果自动分类为 small/medium/large，决定讨论深度
5. Task 调度 business-analyst 分析需求（注入 Steering + Research + WebResearch 全部上下文），产出功能清单 + 疑问点
5.5. **主动讨论协议** — 对识别到的每个不确定点，构造决策卡片（方案/优劣/推荐），通过 AskUserQuestion 由用户决策
6. **多轮决策 LOOP** — AskUserQuestion 逐个澄清决策点，直到全部确认（复杂度分路影响循环深度）
7. 生成结构化提示词 → 用户最终确认
8. 写入 `phase-1-requirements.json` checkpoint（含 complexity、research 数据）
9. 可配置用户确认点（`config.gates.user_confirmation.after_phase_1`）

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
        → **Phase 2/3 必须使用 `run_in_background: true`**：这两个阶段为机械性操作（OpenSpec 创建和 FF 生成），
          不应占用主窗口上下文。派发后等待 Claude Code 自动完成通知，收到通知后继续 Step 4。
        → **Phase 4 非并行模式也必须使用 `run_in_background: true`**：测试用例生成不需要交互，
          主线程等待完成通知后验证 gate 即可。
        → **Phase 6 路径 A 也必须使用 `run_in_background: true`**：测试执行不需要交互，
          主线程等待完成通知后写入 checkpoint。与路径 B/C 在同一消息中全部后台派发。
        → Phase 5 按串行/并行策略决定模式（ralph-loop 为 Skill 调用在主线程，fallback 手动循环可后台化）
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

### Phase 4 特殊处理（v3.2.0 并行增强）

**并行测试用例生成**（当 config.phases.testing.parallel.enabled = true）：
读取 `references/parallel-dispatch.md` Phase 4 并行配置，按测试类型并行派发：
```
┌─ unit 测试 subagent (backend-developer)
├─ api 测试 subagent (qa-expert)          ← 按测试类型并行
├─ e2e 测试 subagent (qa-expert)
└─ ui 测试 subagent (frontend-developer)
↓ 汇合
主线程合并 test_counts + 验证 test_pyramid + 验证 dry_run_results（从子 Agent 信封提取，不重复执行）
```

每个子 Agent 的 prompt 必须注入：
- Phase 1 的 `requirements_summary` 和 `decisions[]`（需求追溯）
- 对应测试类型的 `config.test_suites` 配置
- `test_traceability` 要求：每个用例必须关联到具体需求点

**Phase 4 门禁**（阈值从 config.phases.testing.gate 读取）：
- `test_counts` 每个字段 ≥ config.phases.testing.gate.min_test_count_per_type
- `artifacts` 包含 config.phases.testing.gate.required_test_types 对应文件
- `dry_run_results` 全部为 0（exit code）
- **新增** `test_traceability` 覆盖率 ≥ 80%（每个需求点至少有 1 个测试用例）

**Phase 4 warning 降级阻断规则**：

Phase 4 返回 `status: "warning"` 时，主线程**必须**执行以下检查：
1. 检查 `test_counts` 是否所有字段 ≥ min_test_count_per_type
2. 检查 `artifacts` 是否非空
3. 检查 `dry_run_results` 是否所有字段为 0（exit code）
4. **如果 test_counts 任一字段 < min_test_count_per_type 或 artifacts 为空 或 dry_run_results 任一字段 ≠ 0**：
   - 将 status 强制覆盖为 `"blocked"`
   - 不写入 checkpoint
   - 展示给用户：「Phase 4 返回 warning 但未创建足够测试用例，视为 blocked」
   - 重新 dispatch Phase 4

Phase 4 **不允许**以 warning 状态通过门禁。要么 ok（测试全部创建），要么 blocked（需要排除障碍）。

### Phase 5 特殊处理

**执行前读取**: `references/phase5-implementation.md`（安全准备、超时机制）+ `references/parallel-dispatch.md`（并行编排协议）

#### 任务来源（模式感知）

| 模式 | 任务来源 | 说明 |
|------|---------|------|
| **full** | `openspec/changes/<name>/tasks.md` | 由 Phase 3 生成的完整任务清单 |
| **lite/minimal** | Phase 1 需求自动生成 | 从 `phase-1-requirements.json` 的功能清单自动拆分任务（见 `references/phase5-implementation.md` 的"无 tasks.md 场景"章节） |

> **关键约束**：无论任务来源如何，Phase 5 的执行流程（安全检查点、超时机制、并行/串行策略、ralph-loop 调用）完全一致。

概要:
1. Git 安全检查点 → `git tag -f autopilot-phase5-start HEAD`
2. 记录启动时间戳 → wall-clock 超时机制（2 小时硬限）
3. **执行模式决策（互斥分支 — 必须且仅走一条路径）**：
   读取 `config.phases.implementation.parallel.enabled`，进入以下**互斥**的两条路径之一：

   **【路径 A — 并行模式】** 当 `parallel.enabled = true` 时**立即进入此路径**，执行完毕后**直接跳到步骤 4 构造 JSON 信封**。**禁止执行路径 B 的任何步骤（B1-B4），禁止检测 ralph-loop 可用性，禁止调用 Skill("ralph-loop:ralph-loop")**：

     > **强制指令**：读取 `references/phase5-implementation.md` 并行执行模式章节 + `references/parallel-dispatch.md` Worktree 隔离模板。

     **A1. 解析任务清单**：
        - full 模式 → 读取 `openspec/changes/<name>/tasks.md`
        - lite/minimal 模式 → 读取 `context/phase5-task-breakdown.md`（Phase 5 启动时自动生成）
        - 主线程一次性提取所有任务的完整文本和上下文（子 Agent 不自己读取计划文件）

     **A2. 构建依赖图 + 文件所有权分区**：
        - 按顶级目录（backend/frontend/node）分组 task
        - 跨目录 task 归入 cross_cutting 组，在所有并行组完成后串行执行
        - 为每个并行 agent 生成 owned_files 列表，写入 `phase5-ownership/agent-{N}.json`

     **A3. 并行派发**（对每个 task 组，最多 max_agents 个 agent 同时运行）：
        主线程**在同一条消息中**同时发起所有 Task（全部设置 `run_in_background: true`）：
        ```
        Task(
          subagent_type: "general-purpose",
          isolation: "worktree",
          run_in_background: true,
          prompt: "<!-- autopilot-phase:5 -->
          你是 autopilot Phase 5 的并行实施子 Agent。
          ## 你的任务
          仅实施以下单个 task（禁止实施其他 task）：
          - Task #{task_number}: {task_title}
          - Task 内容: {task_full_text}
          ## 文件所有权约束（ENFORCED）
          你被分配以下文件的独占所有权：{owned_files}
          禁止修改此列表之外的任何文件。
          ## 并发隔离
          - 你运行在独立 worktree 中
          - 禁止修改 openspec/ 目录下的 checkpoint 文件
          - 禁止修改其他 task 正在修改的文件: {concurrent_task_files}
          ## 项目规则约束
          {rules_scan_result}
          ## 返回要求
          执行完毕后返回 JSON 信封：
          {\"status\": \"ok|warning|blocked|failed\", \"summary\": \"...\", \"artifacts\": [...], \"test_result\": \"N/M passed\"}"
        )
        ```
        等待 Claude Code 自动完成通知（禁止 TaskOutput 轮询）。

     **A4. 合并 + 验证**（按 task 编号顺序合并 worktree）：
        - `git merge --no-ff autopilot-task-{N} -m "autopilot: task {N} - {title}"`
        - 合并冲突 → AskUserQuestion 展示冲突文件，选择处理方式
        - 每次合并后运行 quick_check（typecheck）验证
        - 由主线程写入每个 task 的 checkpoint（`phase5-tasks/task-N.json`）
        - 清理 worktree: `git worktree remove` + `git branch -d`

     **A5. 批量 Review**（每组完成后）：
        派发 review subagent 批量审查本组所有变更（规范符合性 + 代码质量 + 跨 task 一致性）
        review 发现问题 → resume 对应 implementer agent 修复

     **A6. 全量测试**：全部 group 完成后，运行 full_test

     **A7. 降级决策**：任何 group 合并失败超过 3 个文件 → 回退 worktree → 切换到路径 B 串行模式（仅此一种情况允许进入路径 B）

     → 跳到步骤 4

   **【路径 B — 串行模式】** 当 `parallel.enabled = false`（默认）或从路径 A 降级时执行：
     B1. 检测 ralph-loop 可用性 + worktree 隔离配置
     B2. **ralph-loop 可用** → 构造参数调用 `Skill("ralph-loop:ralph-loop")`，完成后从 test-results.json 构造 JSON 信封 → 跳到步骤 4
     B3. **不可用 + fallback 启用** → 手动循环模式（每任务 apply + 测试）→ 跳到步骤 4
     B4. **不可用 + fallback 禁用** → AskUserQuestion 让用户选择处理方式

   > **强制约束**：路径 A 和路径 B **互斥执行**。进入路径 A 后，除非降级（步骤 A7），否则**绝对禁止**执行路径 B 的任何步骤（B1-B4）。

4. **构造 Phase 5 JSON 信封**（路径 A 和路径 B 共同汇合点）

### Phase 6 特殊处理（v3.2.0 Allure + 并行增强）

**并行测试执行**（读取 `references/parallel-dispatch.md` Phase 6 并行配置）：
```
┌─ backend_unit (Gradle test → allure-results/)
├─ api_test (pytest --alluredir → allure-results/)     ← 按套件并行
├─ e2e_test (Playwright → allure-results/)
└─ frontend_typecheck (pnpm type-check)
↓ 汇合
allure generate allure-results/ -o allure-report/ --clean
```

**Allure 统一报告**（当 `config.phases.reporting.format === "allure"`）：
1. 检测 Allure 安装: `bash scripts/check-allure-install.sh`
2. 所有套件输出到各自子目录 `allure-results/{suite_name}/`（并行模式避免冲突）
3. 生成统一报告: `npx allure generate allure-results/ -o allure-report/ --clean`（Allure 自动合并子目录）
4. 降级: Allure 不可用 → 使用 config.phases.reporting.report_commands

**Phase 7 汇总展示增强**（v3.2.0）：
```markdown
## 测试报告汇总
| 套件 | 总数 | 通过 | 失败 | 跳过 | 通过率 |
|------|------|------|------|------|--------|
| ... |
⚠️ 异常提醒: [失败用例详情]
📊 Allure 报告: file:///path/to/allure-report/index.html
```

### Phase 5→6 特殊门禁

> **仅 full 和 lite 模式执行**。minimal 模式跳过 Phase 6，此门禁不触发。

autopilot-gate 额外验证：`test-results.json` 存在、`zero_skip_check.passed === true`、任务清单中所有任务标记为 `[x]`

---

---

## Phase 6 三路并行（v3.2.2 增强）

Phase 5→6 Gate 通过后，主线程**在同一条消息中**同时派发三路并行任务：

```
┌─ 路径 A: Phase 6 测试执行（后台 Task, run_in_background: true）
├─ 路径 B: Phase 6.5 代码审查（后台 Task, run_in_background: true）  ← 三路全后台并行
└─ 路径 C: 质量扫描（多个后台 Task, run_in_background: true）
↓ Phase 7 汇合收集所有结果
```

### 路径 A: 测试执行（后台，主流程）

按 Phases 2-6 统一调度模板的 Step 1-7 执行，但使用 `run_in_background: true` 避免输出回流消耗主窗口上下文。Phase 7 步骤 2 统一收集路径 A/B/C 结果后写入 checkpoint。测试执行的并行细节见上方「Phase 6 特殊处理」。

### 路径 B: Phase 6.5 代码审查（后台并行，可选）

当 `config.phases.code_review.enabled`（默认 true）时，**与路径 A 在同一消息中**派发后台 Agent。

**执行前读取**: `references/phase6-code-review.md`（完整审查流程）

```
Task(
  subagent_type: "general-purpose",
  run_in_background: true,
  prompt: "<!-- 代码审查，不含 autopilot-phase 标记 -->
    收集 $ANCHOR_SHA..HEAD 变更 → 执行 4 维审查 → 返回 JSON 信封"
)
```

- 代码审查仅需 `git diff`，**不依赖 Phase 6 测试结果**，可安全并行
- 审查结果在 Phase 7 步骤 2 收集，写入 `phase-6.5-code-review.json` checkpoint
- Phase 6.5 不是整数阶段，不受 Layer 2 Hook 门禁校验

### 路径 C: 质量扫描（后台并行，不阻塞）

**与路径 A、B 在同一消息中**派发所有质量扫描 Agent。

**执行前读取**: `references/quality-scans.md`（完整的派发流程、安装重试、结果收集、硬超时机制）

1. 读取 `config.async_quality_scans`，对每个扫描项 `Task(run_in_background: true)` 派发
2. prompt 不含 `autopilot-phase` 标记，不受 Hook 门禁
3. Phase 7 步骤 2 收集结果，硬超时自动标记 "timeout"

> 路径 B 和 C 失败均不阻断路径 A 的 checkpoint 写入。Phase 7 统一收集后展示。

---

## Phase 7: 汇总 + 用户确认归档（主线程）

0. **写入 Phase 7 Checkpoint（进行中）**：调用 Skill(`spec-autopilot:autopilot-checkpoint`) 写入 `phase-7-summary.json`：
   ```json
   {"status": "in_progress", "phase": 7, "description": "Archive and cleanup"}
   ```
1. 读取所有 phase-results checkpoint，展示状态汇总表
1.5. **指标汇总**：调用 `bash scripts/collect-metrics.sh` 收集执行指标
   - 解析返回的 JSON，提取 `markdown_table` 和 `ascii_chart` 字段
   - 直接向用户展示格式化的阶段耗时表格和耗时分布图
   > 详见：`references/metrics-collection.md`
1.6. **知识提取**（后台子 Agent，v3.2.2 优化）：
   - 派发后台 Agent：`Task(subagent_type: "general-purpose", run_in_background: true)`
   - Agent 任务：读取 `references/knowledge-accumulation.md` → 遍历 phase-results → 提取知识 → 写入 `openspec/.autopilot-knowledge.json`
   - 主线程同时继续执行步骤 1.5 和步骤 2，不阻塞
   - 在步骤 3 AskUserQuestion 前等待完成，展示：「已提取 N 条知识（M 条 pitfall，K 条 decision）」
   > 详见：`references/knowledge-accumulation.md`
2. **收集三路并行结果**（Phase 6 三路并行的汇合点，**仅 full/lite 模式**）：
   > **minimal 模式**：跳过此步骤（minimal 模式无 Phase 6，三路并行不存在，直接进入步骤 3）

   **等待机制**：阻塞等待路径 A/B/C 的后台 Agent 完成或超时（`config.background_agent_timeout_minutes`，默认 30 分钟），Claude Code 会自动发送完成通知。超时自动标记 `"timeout"`，不阻断 Phase 7 流程。

   a0. **Phase 6 测试执行**（路径 A，后台 Task）：
      - 等待后台 Agent 完成通知
      - 解析 JSON 信封，按统一调度模板 Step 4-7 处理（写入 checkpoint、TaskUpdate、git fixup）
      - ok/warning → 继续收集路径 B/C
      - blocked/failed → 展示给用户，但不阻断路径 B/C 的收集
   a. **Phase 6.5 代码审查**（路径 B，仅当 `config.phases.code_review.enabled = true`）：
      - 检查后台 Agent 完成通知
      - ok → 写入 `phase-6.5-code-review.json` checkpoint，展示审查通过
      - warning → 展示 findings 给用户，不阻断归档
      - blocked → 展示 critical findings，标记需修复（不阻断 Phase 7 汇总展示，但阻断步骤 4 归档操作）
      - **code_review 未启用** → 跳过此项，不创建 checkpoint
      - **JSON 解析失败** → 展示原始返回文本，标记为 warning
   b. **质量扫描**（路径 C）：展示质量汇总表（含得分和阈值对比）
      - **硬超时机制**：最多等待 `config.async_quality_scans.timeout_minutes` 分钟（默认 10 分钟），超时自动标记 `"timeout"`，不询问用户
      - **JSON 解析失败** → 展示原始返回文本，标记为 warning
   c. **知识提取**（步骤 1.6 后台 Agent）：等待完成，展示提取结果
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
      - **验证 anchor_sha 有效**：执行 `git rev-parse $ANCHOR_SHA` → 无效则跳过 autosquash，警告用户
      - 执行 `GIT_SEQUENCE_EDITOR=: git rebase -i --autosquash $ANCHOR_SHA~1`
      - 成功 → 修改最终 commit message 为 `feat(autopilot): <change_name> — <summary>`
      - 失败（冲突等） → 执行 `git rebase --abort`，保留原始 fixup commits，警告用户需手动处理压缩
   b. **归档**（模式感知）：
      - **full 模式**: 执行 Skill(`openspec-archive-change`)（完整 OpenSpec 归档）
      - **lite/minimal 模式**: 跳过 OpenSpec 归档（无 OpenSpec 制品），仅完成 git squash
   c. **更新 Phase 7 Checkpoint（完成）**：调用 Skill(`spec-autopilot:autopilot-checkpoint`) 更新 `phase-7-summary.json`：
      ```json
      {"status": "ok", "phase": 7, "description": "Archive complete", "archived_change": "<change_name>", "mode": "<mode>"}
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
| 任务系统 | Phase 0 创建阶段任务（full: Phase 1-7, lite: Phase 1/5/6/7, minimal: Phase 1/5/7）+ blockedBy 链 |
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
| **后台 Agent 通用超时** | 所有 `run_in_background: true` 的 Agent（Phase 2/3 后台化、Phase 1 并行调研、Phase 6.5 代码审查、Phase 7 知识提取）硬超时 30 分钟（`config.background_agent_timeout_minutes`，默认 30），超时标记 `"timeout"` 并展示警告 |
| **全面后台化** | Phase 2/3/4（非并行）/6 路径 A 全部使用 `run_in_background: true`。仅 Phase 1 主线程交互和 Phase 5 串行模式（ralph-loop Skill 调用）在前台执行。减少子 Agent 输出对主窗口上下文的消耗 |
| 代码约束 | Phase 4/5/6 PostToolUse Hook 自动检测项目规则违反（禁止文件/模式/目录范围） |
| 知识累积 | Phase 7 自动提取知识到 openspec/.autopilot-knowledge.json，Phase 1 自动注入 |
| 结构化决策 | 所有决策点以结构化卡片呈现（选项/优劣/推荐），所有复杂度级别均展示决策卡片（small 仅关键点） |
| 执行模式 | 支持 full/lite/minimal 三种模式；模式仅控制跳过哪些阶段，Phase 1 和 Phase 5 在所有模式下执行质量完全一致 |
| 并行编排 | Phase 1/4/5/6 支持阶段内并行执行；Phase 6+6.5+质量扫描三路并行；Phase 7 知识提取后台化 |
| **后台 Agent 轮询禁令** | **禁止使用 TaskOutput 检查后台 Agent 进度**。TaskOutput 仅适用于 Bash 后台命令。后台 Agent 完成时 Claude Code 自动通知，直接等待通知即可。如需提前查看进度，使用 Read 读取 output_file |
| 测试追溯 | Phase 4 测试用例必须追溯到 Phase 1 需求点（traceability matrix） |
| Allure 报告 | Phase 6 优先使用 Allure 生成统一测试报告，降级为自定义格式 |
| 需求调研并行 | Phase 1 Auto-Scan + 技术调研 + 联网搜索三者并行执行 |
| 代码约束增强 | Phase 4/5/6 注入 required_patterns + style_guide，强制合规 |

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

1. 读取 `autopilot-state.md` 获取当前进度（last completed phase、next phase、execution mode、anchor SHA）
2. 读取 `autopilot.config.yaml` 重新加载配置
3. 读取 `context/phase-results/` 目录下所有 checkpoint 确认状态
4. **确认执行模式**：从 state 文件的 `Execution mode` 字段恢复（full/lite/minimal），决定后续阶段是否需要跳过
5. **确认 Anchor SHA**：从 state 文件的 `Anchor SHA` 字段恢复，用于后续 fixup commit 的 base
6. 从下一个未完成阶段继续执行，无需重建 TaskCreate 链（已有的 Task 仍然有效）
7. 调用 Skill(`spec-autopilot:autopilot-gate`) 验证前置条件后继续 dispatch

### 恢复后检查清单（必须逐项确认）

| # | 检查项 | 来源 |
|---|--------|------|
| 1 | 当前执行模式是什么（full/lite/minimal）？ | `autopilot-state.md` → Execution mode |
| 2 | Anchor SHA 是什么？ | `autopilot-state.md` → Anchor SHA |
| 3 | 最后完成的阶段编号？ | `autopilot-state.md` → Last completed phase |
| 4 | 下一个待执行阶段？该阶段在当前模式下是否应跳过？ | `autopilot-state.md` → Next phase + 模式跳过规则 |
| 5 | tasks/breakdown 进度？ | `autopilot-state.md` → Tasks progress |
| 6 | 所有 checkpoint 文件是否与 state 一致？ | `context/phase-results/phase-*.json` |

> **禁止行为**：恢复后禁止重复执行已标记为 `ok` 或 `warning` 的阶段。如果 state 显示 Phase N 已完成，直接从 Phase N+1 继续。

### 阶段间上下文保护

每个阶段完成后自动执行 git fixup commit 保存 checkpoint，子 Agent 仅回传精简摘要（不传原始输出），减少上下文膨胀。如果上下文接近压缩阈值，可手动执行 `/compact` 触发压缩，Hook 会自动保存和恢复状态。
