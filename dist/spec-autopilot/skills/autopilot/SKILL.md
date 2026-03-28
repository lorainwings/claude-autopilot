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
| `phases.implementation` | instruction_files、serial_task 配置、worktree 隔离配置 |
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
| `spec-autopilot:autopilot-phase0` | Phase 0 初始化（环境检查 + 崩溃恢复 + 锁文件管理） |
| `spec-autopilot:autopilot-phase7` | Phase 7 汇总 + 归档 |
| `spec-autopilot:autopilot-recovery` | 崩溃恢复协议 |
| `spec-autopilot:autopilot-gate` | 阶段门禁验证 + 检查点读写管理 |
| `spec-autopilot:autopilot-dispatch` | 子 Agent 调度构造 |

**参考文档**:
| 文档 | 用途 |
|------|------|
| `references/mode-routing-table.md` | 三种模式的阶段序列、跳过规则、路径选择（声明式表格） |
| `references/parallel-dispatch.md` | 跨阶段通用并行编排协议（核心协议） |
| `references/parallel-phase{1,4,5,6}.md` | 各 Phase 按需加载的并行配置与 dispatch 模板（v5.2 拆分） |
| `references/log-format.md` | 统一日志格式规范 |

## 阶段总览

| Phase | 执行位置 | Description |
|-------|----------|-------------|
| 0 | Skill(`autopilot-phase0`) | 环境检查 + 崩溃恢复 + 锁文件初始化 |
| 1 | 主线程 | 需求理解与多轮决策（LOOP 直到全部澄清） |
| 2 | Task 子 Agent | 创建 OpenSpec 并保存上下文 |
| 3 | Task 子 Agent | OpenSpec 快进生成制品 |
| 4 | Task 子 Agent | 测试用例设计（full 模式强制；TDD 模式下由 Phase 5 吸收，标记 `skipped_tdd`） |
| 5 | Task 子 Agent | 串行/并行 循环实施 |
| 6 | Task 子 Agent | 测试报告生成（强制，不可跳过） |
| 7 | Skill(`autopilot-phase7`) | 汇总展示 + **Archive Readiness 自动**归档 |

> **Checkpoint 范围**: Phase 1-7 产生 checkpoint 文件。Phase 0 在主线程执行，不写 checkpoint。

---

## Phase 0: 环境检查 + 崩溃恢复

调用 Skill(`spec-autopilot:autopilot-phase0`)，传入 $ARGUMENTS 和 plugin_dir。

Phase 0 完成后获得：version、mode、session_id、ANCHOR_SHA、config、recovery_phase、auto_continue_eligible。

> **v5.4 自动继续**: 当 `recovery-decision.sh` 输出 `auto_continue_eligible: true` 时（单候选 + 无危险 git 状态 + continue 路径存在），Phase 0 可跳过用户恢复交互，直接设定 `recovery_phase` 并继续。`auto_continue_eligible` 为 false 时仍走用户交互恢复流程。

## Phase 1: 需求理解与多轮决策（主线程）

**核心原则**: 绝不假设，始终列出选项由用户决策。

**v5.5 跳过规则**: 当 `recovery_phase > 1` 时，Phase 1 已完成，跳过整个 Phase 1 流程。直接从 `recovery_phase` 对应的阶段继续。跳过时不发射 Phase 1 事件。

**执行前读取**: `references/phase1-requirements.md`（完整的 10 步流程）

**Step 0: 发射 Phase 1 开始事件（v5.2 Event Bus 补全）**

```
Bash('bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/emit-phase-event.sh phase_start 1 {mode}')
```

概要流程:
1. 获取需求来源（$ARGUMENTS 解析）
2. **前置决策：Requirement Lint + 复杂度路由**（v5.1.51 策略统一）
   - 执行 requirement lint（参见 `references/phase1-requirements.md` Step 1.1.7）
   - 如 `flags >= 2` → 先进入澄清预检（Step 1.1.7），完成后再派发调研
   - 按 `references/parallel-phase1.md:85-93` 复杂度分级路由决定调研 agent 数量：
     - 低复杂度（纯 bugfix/chore）→ 单路调研（Auto-Scan only）
     - 中复杂度 → 双路调研（Auto-Scan + 技术调研）
     - 高复杂度 → 三路调研（Auto-Scan + 技术调研 + 联网搜索）
3. **并行调研**（v3.2.0 增强, v3.3.7 搜索策略重构）→ 读取 `references/parallel-phase1.md` 并行配置。
   > **v5.3 Agent 事件**: Hook `auto-emit-agent-dispatch.sh` 自动为每个含 phase marker 的 Task 发射 `agent_dispatch` 事件，无需手动调用。
   **v5.3 进度写入**: Bash('AUTOPILOT_PROJECT_ROOT=$(pwd) bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/write-phase-progress.sh 1 research_dispatched in_progress')
   按复杂度路由结果自适应派发（不再固定三路同时）：
   ```
   ┌─ Auto-Scan (general-purpose agent) → Steering Documents         ← 始终执行
   ├─ 技术调研 (general-purpose agent) → research-findings.md        ← 中/高复杂度
   └─ 联网搜索 (general-purpose) → web-research-findings.md  ← 高复杂度 + 规则判定
   ```
   **联网搜索决策**（v3.3.7）：默认执行搜索（`search_policy.default: search`），仅当任务**同时满足所有跳过条件**时才跳过：
   - ✓ 纯内部代码变更（重构、bug 修复、样式微调）
   - ✓ 不引入新概念、新模式、新交互
   - ✓ 项目 `rules/` 或 `specs/` 已有明确规范覆盖
   - ✓ codebase 中已有同类实现可参照
   判定由规则引擎执行（非 AI 自评），详见 `references/phase1-requirements.md` 1.3.3 节。
   **强制并行约束**（v3.2.1）：主线程**必须在同一条消息中**同时发起所有调研 Task（全部设置 `run_in_background: true`），然后等待 Claude Code 自动完成通知。
   - ❌ **禁止**：逐个发起 Task，等前一个完成再发下一个
   - ❌ **禁止**：使用前台 agent 逐个扫描
   - ❌ **禁止**：使用 TaskOutput 检查后台 Agent 进度（TaskOutput 仅适用于 Bash 后台命令）
   - ✅ **正确**：在一条消息中包含 2-3 个 `Task(run_in_background: true)` 调用
   优先读取持久化上下文（`openspec/.autopilot-context/`），7 天内有效则跳过 Auto-Scan 仅做增量
3. **汇合调研结果**（v3.3.0 上下文保护增强）→ 子 Agent 自行 Write 产出文件 + 返回结构化 JSON 信封（含摘要和决策点），主线程**不读取全文**：
   > **v5.3 Agent 事件**: Hook `auto-emit-agent-complete.sh` 自动为每个完成的 autopilot Task 发射 `agent_complete` 事件，无需手动调用。
   - 验证文件存在：`Bash("test -s context/project-context.md && test -s context/research-findings.md && echo ok")`
   - 从各 Agent 返回的 JSON 信封提取：`decision_points`（决策点）、`tech_constraints`（技术约束）、`complexity`（复杂度评估）
   - 文件全文由后续子 Agent（business-analyst、Phase 2-6）直接 Read，不经过主线程
   产出文件列表（子 Agent 自行写入）：
   - `context/project-context.md` + `existing-patterns.md` + `tech-constraints.md`（Auto-Scan）
   - `context/research-findings.md`（技术调研）
   - `context/web-research-findings.md`（联网搜索，默认执行，规则判定跳过时无此文件）
   **v5.1 中间 Checkpoint — 调研完成**: 三路调研汇合后立即写入中间态 checkpoint，防止崩溃丢失调研进度：
   ```
   Agent(run_in_background: true, prompt: "<!-- checkpoint-writer -->
     Write JSON to ${phase_results}/phase-1-interim.json:
     {\"status\":\"in_progress\",\"stage\":\"research_complete\",
      \"complexity\":\"...\",\"requirement_type\":\"...\",
      \"decision_points_count\":N,\"timestamp\":\"ISO-8601\"}
     Then: git add -A && git commit --fixup=$ANCHOR_SHA -m 'fixup! autopilot: Phase 1 interim (research)'")
   ```
4. **复杂度评估与分路** → 基于信封中的 `complexity` 字段 + `decision_points` 数量自动分类为 small/medium/large，决定讨论深度
5. Task 调度 business-analyst 分析需求（`run_in_background: true`）：
   > **v5.3 Agent 事件**: Hook 自动发射 agent_dispatch/complete，无需手动调用。
   **v5.3 进度写入**: Bash('AUTOPILOT_PROJECT_ROOT=$(pwd) bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/write-phase-progress.sh 1 ba_dispatched in_progress')
   - 子 Agent 自行 Read context/ 全部文件，将完整分析 Write 到 `context/requirements-analysis.md`
   - 等待 Claude Code 自动完成通知
   - 从 JSON 信封提取：`decision_points`、`requirements_summary`、`open_questions`
   - 主线程**不读取** `requirements-analysis.md` 全文
5.5. **主动讨论协议** — 基于信封中的 `decision_points` + business-analyst 产出，构造决策卡片（方案/优劣/推荐），通过 AskUserQuestion 由用户决策
6. **多轮决策 LOOP** — AskUserQuestion 逐个澄清决策点，直到全部确认（复杂度分路影响循环深度）。**v5.2: `config.phases.requirements.min_qa_rounds` 作为强制最低轮数下限。**
   **v5.1 中间 Checkpoint — 每轮决策后**: 每轮决策 LOOP 完成后，覆盖写入中间态 checkpoint，防止崩溃丢失用户决策：
   ```
   Agent(run_in_background: true, prompt: "<!-- checkpoint-writer -->
     Write JSON to ${phase_results}/phase-1-interim.json:
     {\"status\":\"in_progress\",\"stage\":\"decision_round_N\",
      \"round\":N,\"decisions_resolved\":[...],\"decisions_pending\":[...],
      \"timestamp\":\"ISO-8601\"}
     Then: git add -A && git commit --fixup=$ANCHOR_SHA -m 'fixup! autopilot: Phase 1 interim (decision round N)'")
   ```
7. 生成结构化提示词 → 用户最终确认
8. 写入 `phase-1-requirements.json` checkpoint + `requirement-packet.json`（Phase 1 唯一结构化产出，含 sha256 hash）+ git fixup（使用后台 Checkpoint Agent，同统一调度模板 Step 5+7）
   **v5.1**: 写入最终 checkpoint 后，删除中间态文件：`Bash('rm -f ${phase_results}/phase-1-interim.json')`
9. 可配置用户确认点（`config.gates.user_confirmation.after_phase_1`，**v6.0 默认 false**——需求评审完成后默认自动推进）
10. **发射 Phase 1 结束事件（v5.2 Event Bus 补全）**:
    `Bash('bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/emit-phase-event.sh phase_end 1 {mode} \'{"status":"{envelope.status}","duration_ms":{elapsed},"artifacts":["phase-1-requirements.json"]}\'')`

---

## Phases 2-6: 统一调度模板

对于每个 Phase N（2 ≤ N ≤ 6），在**主线程**中执行：

```
Step -1: 恢复跳过前置检查（v5.5 新增）
        → 当 recovery_phase 已设定时，检查当前 Phase N 是否需要跳过：
          - N < recovery_phase → 该阶段已在之前会话完成，**跳过整个 Phase N**（不执行 Step 0-8）
          - N == recovery_phase → 从该阶段开始恢复执行（进入 Step 0）
          - N > recovery_phase → 正常执行（进入 Step 0）
        → 跳过的 Phase 不发射 phase_start/phase_end 事件
        → 跳过的 Phase 的 Task 已在 Phase 0 Step 7 中标记为 completed
Step -0.5: GUI 健康检查（v5.7 自动恢复）
        → Bash('bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/start-gui-server.sh --check-health')
        → 脚本自动处理：存活则静默返回；死掉则重启
        → 失败不阻断流程（GUI 为可选增强功能）
Step 0: 发射 Phase 开始事件（v4.2 Event Bus）
        → Bash('bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/emit-phase-event.sh phase_start {N} {mode}')
Step 1: 调用 Skill("spec-autopilot:autopilot-gate")
        → 执行 8 步阶段切换检查清单（验证 Phase N-1 checkpoint）
        → Gate 通过后: Bash('bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/emit-gate-event.sh gate_pass {N} {mode} \'{"gate_score":"8/8"}\'')
        → **v5.3 进度写入**: Bash('AUTOPILOT_PROJECT_ROOT=$(pwd) bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/write-phase-progress.sh {N} gate_passed in_progress')
        → Gate 阻断时: Bash('bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/emit-gate-event.sh gate_block {N} {mode} \'{"status":"blocked","error_message":"..."}\'')
          → 阻断后立即启动决策轮询（v5.1 双向反控）:
            DECISION=$(Bash('bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/poll-gate-decision.sh "${change_dir}/" {N} {mode} \'{"blocked_step":M,"error_message":"..."}\''))
            → override: 记录 [GATE] Override → 视为通过，继续 Step 2
            → retry: 记录 [GATE] Retry → 重新执行 Step 1 完整 8 步检查
            → fix: 记录 [GATE] Fix → 展示 fix_instructions 给用户，修复后重新 Step 1
            → timeout: 回退原有行为 → AskUserQuestion 请求用户决策
Step 1.5: 检查可配置用户确认点（仅当 config.gates.user_confirmation.after_phase_{N} === true 时，**v6.0 默认全部 false**）
        → AskUserQuestion 确认后继续，选暂停则保存进度退出
        → **v6.0 自动推进**: 默认不中断，需求评审后自动推进到 archive-ready
Step 2: 调用 Skill("spec-autopilot:autopilot-dispatch")
        → 按协议构造 Task prompt
        → 从 config.phases[当前阶段].instruction_files 注入指令文件路径
        → 从 config.phases[当前阶段].reference_files 注入参考文件路径
Step 2.5: 发射 Agent 派发事件（v5.3 Agent 生命周期）
        → Bash('bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/emit-agent-event.sh agent_dispatch {N} {mode} "phase{N}-{slug}" "{agent_label}" \'{"background":{is_background}}\'')
Step 3: 使用 Task 工具派发子 Agent
        → prompt 开头必须包含 <!-- autopilot-phase:N --> 标记
        → Hook 脚本自动校验前置 checkpoint 和返回 JSON
        → **v5.3 进度写入**: Bash('AUTOPILOT_PROJECT_ROOT=$(pwd) bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/write-phase-progress.sh {N} agent_dispatched in_progress \'{"agent_id":"phase{N}-{slug}"}\'')
        → **Phase 2/3 必须使用 `run_in_background: true`**：这两个阶段为机械性操作（OpenSpec 创建和 FF 生成），
          不应占用主窗口上下文。派发后等待 Claude Code 自动完成通知，收到通知后继续 Step 4。
        → **Phase 4 非并行模式也必须使用 `run_in_background: true`**：测试用例生成不需要交互，
          主线程等待完成通知后验证 gate 即可。
        → **Phase 6 路径 A 也必须使用 `run_in_background: true`**：测试执行不需要交互，
          主线程等待完成通知后写入 checkpoint。与路径 B/C 在同一消息中全部后台派发。
        → Phase 5 按串行/并行策略决定模式（串行为前台 Task 逐个派发，并行为 worktree 后台化）
Step 4: 解析子 Agent 返回的 JSON 信封
        → ok → 继续
        → warning → **Phase 4 特殊处理**（见下方）
        → blocked/failed → 暂停展示给用户
        → **v5.3 进度写入**: Bash('AUTOPILOT_PROJECT_ROOT=$(pwd) bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/write-phase-progress.sh {N} agent_complete in_progress \'{"status":"{envelope.status}"}\'')
Step 4.5: 发射 Agent 完成事件（v5.3 Agent 生命周期）
        → Bash('bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/emit-agent-event.sh agent_complete {N} {mode} "phase{N}-{slug}" "{agent_label}" \'{"status":"{envelope.status}","summary":"{envelope.summary前120字符}","duration_ms":{agent_elapsed}}\'')
Step 4.7: GUI 周期性健康检查（v5.7 — 长任务中途保活）
        → **仅 Phase 5 生效**: 在子 Agent dispatch prompt 中注入以下保活指令：
          ```
          ## GUI 保活（Phase 5 强制）
          每完成 3 个 task（或每 15 分钟，取先到者），执行：
          Bash('bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/start-gui-server.sh --check-health')
          失败不阻断（GUI 为可选增强功能）。
          ```
        → **非 Phase 5**: 主线程在 agent 完成后执行一次 `start-gui-server.sh --check-health`
        → 脚本自动处理：存活则静默返回；死掉则重启
        → 与 Step -0.5 互补：Step -0.5 覆盖 Phase 入口，Step 4.7 覆盖长时间运行的 Phase 中途崩溃
Step 5+7: 派发后台 Checkpoint Agent（v3.4.3 上下文保护增强, v5.1 原子写入 + 状态隔离）
        → 将 checkpoint 写入 + git fixup commit 合并为一个后台 Agent，避免 Write/Bash 输出污染主窗口上下文
        → **v5.1 重要**: Checkpoint 写入**必须使用 Bash 工具**（非 Write 工具），以绕过 Write/Edit Hook 的状态隔离检查
        → Agent(subagent_type: "general-purpose", run_in_background: true, prompt: "
            <!-- checkpoint-writer -->
            1. 确保目录存在: Bash('mkdir -p ${session_cwd}/openspec/changes/<name>/context/phase-results/')
            2. 写入临时 checkpoint（使用 Bash，非 Write 工具）:
               Bash('python3 -c \"import json; json.dump({envelope_dict}, open(\\\"${phase_results}/phase-{N}-{slug}.json.tmp\\\", \\\"w\\\"), ensure_ascii=False, indent=2)\"')
            3. 验证临时文件: Bash('python3 -c \"import json; json.load(open(\\\"phase-{N}-{slug}.json.tmp\\\"))\"')
               若验证失败 → 删除 .tmp 文件并报告错误，不覆盖正式文件
            4. 原子重命名: Bash('mv phase-{N}-{slug}.json.tmp phase-{N}-{slug}.json')
            5. 最终验证: Bash('python3 -c \"import json; d=json.load(open(\\\"phase-{N}-{slug}.json\\\")); assert \\\"status\\\" in d\"')
            6. Bash('cd ${session_cwd} && git add -A && git commit --fixup=$ANCHOR_SHA -m \"fixup! autopilot: start <name> — Phase N\"')
            7. Bash('git rev-parse --short HEAD')
            返回: {\"status\": \"ok\", \"checkpoint\": \"phase-N-slug.json\", \"commit_sha\": \"<short_sha>\"}
          ")
        → **必须使用 `git add -A`**（自动尊重 .gitignore，添加所有变更：代码文件 + checkpoint + 测试 + openspec 制品）
        → **禁止显式 `git add` 锁文件 `.autopilot-active`** — git add -A 自动尊重 .gitignore
Step 6: TaskUpdate Phase N → completed
Step 6.5: 发射 Phase 结束事件（v4.2 Event Bus）
        → Bash('bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/emit-phase-event.sh phase_end {N} {mode} \'{"status":"{envelope.status}","duration_ms":{elapsed},"artifacts":{artifacts_json}}\'')
Step 6.6: 上下文使用率提示（v5.8 上下文压缩预警）
        → 每个 Phase 完成后输出一行上下文监控提示，提前预警压缩风险：
          `[CTX] Phase {N} complete | Phases remaining: {remaining_count}`
        → 当剩余阶段 ≤ 2 时，额外输出：`[CTX] ⚠️ Nearing end — if context is large, consider manual compact before Phase {next}`
Step 6.7: 保存上下文快照（v5.3 上下文保护, v5.8 占位符修复）
        → **必须从子 Agent 的 JSON 信封中提取实际内容**填入 save-phase-context.sh 参数，禁止使用占位符文本：
          - `summary`: 从信封的 `summary` 字段提取（即 Step 4 解析的 `envelope.summary`）
          - `next_phase_context`: 从信封中提取对下阶段有价值的关键决策/约束/发现，格式化为简短文本
          - `decisions`: 如信封含 `decision_points` / `decisions` 字段，提取为数组
          - `artifacts`: 从信封的 `artifacts` 字段提取
          - `constraints`: 如信封含 `constraints` / `tech_constraints` 字段，提取为数组
        → 用 python3 构造 JSON 参数避免 shell 引号问题:
          Bash("AUTOPILOT_PROJECT_ROOT=$(pwd) python3 -c \"import json,subprocess,sys; subprocess.run(['bash','${CLAUDE_PLUGIN_ROOT}/runtime/scripts/save-phase-context.sh','{N}','{mode}',json.dumps({'summary':sys.argv[1],'decisions':json.loads(sys.argv[3]),'constraints':json.loads(sys.argv[4]),'artifacts':json.loads(sys.argv[5]),'next_phase_context':sys.argv[2]})],check=False)\" '{envelope.summary}' '{下阶段关键上下文，从信封决策/约束中提炼}' '{decisions_json_array}' '{constraints_json_array}' '{artifacts_json_array}'")
Step 8: 等待 Step 5+7 后台 Agent 完成通知
        → 从 Agent 返回的 JSON 提取 checkpoint 文件名和 commit SHA
        → 输出格式化进度行（让用户看到关键状态）：
          ```
          Phase {N} ✓ checkpoint: phase-{N}-{slug}.json | commit: {short_sha}
          ```
        → 确认 checkpoint 已持久化后，继续下一 Phase 的 gate check
```

### Phase 4 特殊处理（v3.2.0 并行增强）

**执行前读取**: `references/parallel-phase4.md` 并行配置 + `references/protocol.md` 特殊门禁

**TDD 模式跳过**（当 `config.phases.implementation.tdd_mode: true` 且模式为 `full`）：
Phase 4 标记为 `skipped_tdd`，写入 `phase-4-tdd-override.json` checkpoint（`{"status":"ok","tdd_mode_override":true}`），直接跳转 Phase 5。

**非 TDD 模式**：正常 dispatch，并行模式按测试类型分组。
**门禁规则**: Phase 4 **只接受 ok 或 blocked**（warning 由 Hook 确定性阻断）。详见 `references/protocol.md`。

### Phase 5 特殊处理

> **路径选择由配置决定，详见 `references/mode-routing-table.md` § 4。**

**Phase 5 主线程职责边界（v5.7 上下文节制化）**:

主线程在 Phase 5 中**仅执行最小编排**，禁止读取实施相关参考文档：
- ✅ 调用 `Skill("spec-autopilot:autopilot-dispatch")` 构造 dispatch prompt
- ✅ 调用 `generate-parallel-plan.sh` 生成并行计划
- ✅ 派发 Task + 等待完成 + 解析 JSON 信封 + 写 checkpoint
- ✅ 合并 worktree + 全量测试
- ❌ **禁止**主线程 Read `references/phase5-implementation.md`（由 dispatch skill 内部读取）
- ❌ **禁止**主线程 Read `references/parallel-phase5.md`（由 dispatch skill 内部读取）
- ❌ **禁止**主线程自行分析任务依赖（由 generate-parallel-plan.sh 确定性计算）

> **设计意图**: Phase 5 实施细节全部下沉到 dispatch skill 和子 Agent，保护主线程上下文窗口。

**dispatch skill 执行时自行读取**: `references/phase5-implementation.md` + `references/parallel-phase5.md` + `references/mode-routing-table.md`

#### 任务来源（模式感知）

> 详见 `references/mode-routing-table.md` § 3。

#### 执行模式决策（互斥分支）

读取 `config.phases.implementation.parallel.enabled` + `tdd_mode`，按 `references/mode-routing-table.md` § 4 确定路径：

**【路径 A — 并行模式】**（`parallel.enabled = true`）：

> **ABSOLUTE HARD CONSTRAINT — 禁止自主降级**:
> 当 `config.phases.implementation.parallel.enabled = true` 时，主线程**严禁**以任何理由
>（包括但不限于"任务量大"、"有强依赖"、"复杂度高"、"安全起见"）自主决定切换为串行模式。
> 降级**仅允许**在以下确定性条件下触发：
> 1. `generate-parallel-plan.sh` 输出 `fallback_to_serial=true`（确定性脚本判定）
> 2. worktree 创建失败（runtime 错误）
> 3. 单组合并冲突 > 3 文件
> 4. 连续 2 组合并失败
> 5. 用户通过 AskUserQuestion 显式选择"切换串行"
>
> **违反此约束等同于违反 CLAUDE.md 状态机硬约束第 3 条。**

解析任务 → **生成 `parallel_plan.json`**（v5.4: 调用 `generate-parallel-plan.sh` 确定性调度器） → 按 batch 分区 → worktree 并行 → 按编号合并 → 全量测试。详见 `references/parallel-phase5.md`。

**【路径 B — 串行模式】**（`parallel.enabled = false` 或降级）：
逐个前台 Task → JSON 信封 → task checkpoint。**v5.4**: 串行模式也调用 `generate-parallel-plan.sh` 生成计划，Batch Scheduler 消费 `batches` 字段执行。详见 `references/phase5-implementation.md` 串行模式章节。

**v5.8 串行模式 CLAUDE.md 变更检测**: 串行模式下，每个 task dispatch 前执行轻量 CLAUDE.md 变更检测：
```bash
# 在每个 task dispatch 前（与 Gate Step 5.5 相同逻辑）
CLAUDE_MD_MTIME=$(stat -f "%m" "${session_cwd}/CLAUDE.md" 2>/dev/null || echo 0)
CACHED_MTIME=$(cat "${change_dir}context/.rules-scan-mtime" 2>/dev/null || echo 0)
if [ "$CLAUDE_MD_MTIME" != "$CACHED_MTIME" ]; then
  # 重新扫描规则并更新缓存
  Bash('bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/rules-scanner.sh ${session_cwd}')
  echo "$CLAUDE_MD_MTIME" > "${change_dir}context/.rules-scan-mtime"
  # 使用新规则构造 dispatch prompt
fi
```
> 此检测仅在串行模式生效（并行模式的域 Agent 在 dispatch 时已注入完整规则，中途不可更新）。

**【路径 C — TDD 模式】**（`tdd_mode: true` 且模式为 `full`）：
**优先于路径 A/B，与 parallel.enabled 配合使用。**
**执行前读取**: `references/tdd-cycle.md` + `references/testing-anti-patterns.md`

- **串行 TDD**（`parallel.enabled: false`）：每个 task 3 个 sequential Task (RED→GREEN→REFACTOR)。主线程写入 `.tdd-stage` 文件供 L2 Hook 确定性拦截。详见 `references/tdd-cycle.md` 串行 TDD 章节。
- **并行 TDD**（`parallel.enabled: true`）：域 Agent prompt 注入完整 TDD 纪律。合并后主线程执行全量测试验证。详见 `references/tdd-cycle.md` 并行 TDD 章节。

TDD 护栏：先测试后实现 | RED 必须失败 | GREEN 必须通过 | 测试不可变 | REFACTOR 回归保护

> **强制约束**：路径 A/B **互斥**。Phase 5 JSON 信封构造详见 `references/protocol.md`。

### Phase 6 特殊处理（v3.2.0 Allure + 并行增强）

**执行前读取**: `references/parallel-phase6.md` + `references/phase6-code-review.md` + `references/quality-scans.md`

并行测试执行按 `config.test_suites` 分套件派发（详见 `references/parallel-phase6.md`）。
Allure 报告（`config.phases.reporting.format === "allure"`）：检测安装 → 统一输出 → 生成报告 → 降级兜底。

### Phase 5→6 特殊门禁

> **仅 full 和 lite 模式执行**。minimal 模式跳过 Phase 6。

autopilot-gate 额外验证：`test-results.json` 存在、`zero_skip_check.passed === true`、任务清单中所有任务标记为 `[x]`

---

## Phase 6 三路并行（v3.2.2 增强）

> 详见 `references/mode-routing-table.md` § 7。

Phase 5→6 Gate 通过后，主线程**在同一条消息中**同时派发路径 A（测试）/ B（代码审查）/ C（质量扫描），全部 `run_in_background: true`。路径 B/C 不阻断路径 A。**Phase 7 步骤 2 统一收集。**

---

## Phase 7: 汇总 + Archive Readiness 自动归档（主线程）

调用 Skill(`spec-autopilot:autopilot-phase7`)。

Phase 7 执行：汇总展示（Summary Box）、三路并行结果收集、知识提取、Allure 预览、Archive Readiness 自动判定、git autosquash、锁文件清理。

**v6.0 Archive Readiness fail-closed**: 构建 `archive-readiness.json` 统一判定。所有检查通过时自动归档，任一失败则硬阻断（fixup 不完整、anchor 无效、review blocking findings 未解决、worktree 脏等）。

---

## 护栏约束

**执行前读取**: `references/guardrails.md`（完整护栏约束清单 + 错误处理 + 上下文压缩恢复协议）

核心约束概要：主线程编排禁嵌套 | 配置驱动禁硬编码 | 三层门禁 | 结构化标记+返回 | 测试不可变+零跳过 | 归档 fail-closed（readiness 通过自动、失败硬阻断） | 崩溃恢复基于 state-snapshot.json 结构化控制态 + phase5-tasks/ 细粒度恢复点 | Phase 1 上下文隔离（主线程不读取子 agent 正文） | Review findings blocking 硬阻断归档
