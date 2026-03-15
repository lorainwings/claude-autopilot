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
| 4 | Task 子 Agent | 测试用例设计（强制，不可跳过） |
| 5 | Task 子 Agent | 串行/并行 循环实施 |
| 6 | Task 子 Agent | 测试报告生成（强制，不可跳过） |
| 7 | Skill(`autopilot-phase7`) | 汇总展示 + **用户确认**归档 |

> **Checkpoint 范围**: Phase 1-7 产生 checkpoint 文件。Phase 0 在主线程执行，不写 checkpoint。

---

## Phase 0: 环境检查 + 崩溃恢复

调用 Skill(`spec-autopilot:autopilot-phase0`)，传入 $ARGUMENTS 和 plugin_dir。

Phase 0 完成后获得：version、mode、session_id、ANCHOR_SHA、config、recovery_phase。

## Phase 1: 需求理解与多轮决策（主线程）

**核心原则**: 绝不假设，始终列出选项由用户决策。

**执行前读取**: `references/phase1-requirements.md`（完整的 10 步流程）

**Step 0: 发射 Phase 1 开始事件（v5.2 Event Bus 补全）**

```
Bash('bash ${PLUGIN_ROOT}/scripts/emit-phase-event.sh phase_start 1 {mode}')
```

概要流程:
1. 获取需求来源（$ARGUMENTS 解析）
2. **并行调研**（v3.2.0 增强, v3.3.7 搜索策略重构）→ 读取 `references/parallel-phase1.md` 并行配置。
   > **v5.3 Agent 事件**: Hook `auto-emit-agent-dispatch.sh` 自动为每个含 phase marker 的 Task 发射 `agent_dispatch` 事件，无需手动调用。
   **v5.3 进度写入**: Bash('bash ${PLUGIN_ROOT}/scripts/write-phase-progress.sh 1 research_dispatched in_progress')
   同时派发：
   ```
   ┌─ Auto-Scan (general-purpose agent) → Steering Documents
   ├─ 技术调研 (general-purpose agent) → research-findings.md        ← 三者并行
   └─ 联网搜索 (general-purpose) → web-research-findings.md  ← 默认搜索，规则判定跳过
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
   **v5.3 进度写入**: Bash('bash ${PLUGIN_ROOT}/scripts/write-phase-progress.sh 1 ba_dispatched in_progress')
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
8. 写入 `phase-1-requirements.json` checkpoint + git fixup（使用后台 Checkpoint Agent，同统一调度模板 Step 5+7）
   **v5.1**: 写入最终 checkpoint 后，删除中间态文件：`Bash('rm -f ${phase_results}/phase-1-interim.json')`
9. 可配置用户确认点（`config.gates.user_confirmation.after_phase_1`）
10. **发射 Phase 1 结束事件（v5.2 Event Bus 补全）**:
    `Bash('bash ${PLUGIN_ROOT}/scripts/emit-phase-event.sh phase_end 1 {mode} \'{"status":"{envelope.status}","duration_ms":{elapsed},"artifacts":["phase-1-requirements.json"]}\'')`

---

## Phases 2-6: 统一调度模板

对于每个 Phase N（2 ≤ N ≤ 6），在**主线程**中执行：

```
Step 0: 发射 Phase 开始事件（v4.2 Event Bus）
        → Bash('bash ${PLUGIN_ROOT}/scripts/emit-phase-event.sh phase_start {N} {mode}')
Step 1: 调用 Skill("spec-autopilot:autopilot-gate")
        → 执行 8 步阶段切换检查清单（验证 Phase N-1 checkpoint）
        → Gate 通过后: Bash('bash ${PLUGIN_ROOT}/scripts/emit-gate-event.sh gate_pass {N} {mode} \'{"gate_score":"8/8"}\'')
        → **v5.3 进度写入**: Bash('bash ${PLUGIN_ROOT}/scripts/write-phase-progress.sh {N} gate_passed in_progress')
        → Gate 阻断时: Bash('bash ${PLUGIN_ROOT}/scripts/emit-gate-event.sh gate_block {N} {mode} \'{"status":"blocked","error_message":"..."}\'')
          → 阻断后立即启动决策轮询（v5.1 双向反控）:
            DECISION=$(Bash('bash ${PLUGIN_ROOT}/scripts/poll-gate-decision.sh "${change_dir}/" {N} {mode} \'{"blocked_step":M,"error_message":"..."}\''))
            → override: 记录 [GATE] Override → 视为通过，继续 Step 2
            → retry: 记录 [GATE] Retry → 重新执行 Step 1 完整 8 步检查
            → fix: 记录 [GATE] Fix → 展示 fix_instructions 给用户，修复后重新 Step 1
            → timeout: 回退原有行为 → AskUserQuestion 请求用户决策
Step 1.5: 检查可配置用户确认点（仅当 config.gates.user_confirmation.after_phase_{N} === true 时）
        → AskUserQuestion 确认后继续，选暂停则保存进度退出
Step 2: 调用 Skill("spec-autopilot:autopilot-dispatch")
        → 按协议构造 Task prompt
        → 从 config.phases[当前阶段].instruction_files 注入指令文件路径
        → 从 config.phases[当前阶段].reference_files 注入参考文件路径
Step 2.5: 发射 Agent 派发事件（v5.3 Agent 生命周期）
        → Bash('bash ${PLUGIN_ROOT}/scripts/emit-agent-event.sh agent_dispatch {N} {mode} "phase{N}-{slug}" "{agent_label}" \'{"background":{is_background}}\'')
Step 3: 使用 Task 工具派发子 Agent
        → prompt 开头必须包含 <!-- autopilot-phase:N --> 标记
        → Hook 脚本自动校验前置 checkpoint 和返回 JSON
        → **v5.3 进度写入**: Bash('bash ${PLUGIN_ROOT}/scripts/write-phase-progress.sh {N} agent_dispatched in_progress \'{"agent_id":"phase{N}-{slug}"}\'')
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
        → **v5.3 进度写入**: Bash('bash ${PLUGIN_ROOT}/scripts/write-phase-progress.sh {N} agent_complete in_progress \'{"status":"{envelope.status}"}\'')
Step 4.5: 发射 Agent 完成事件（v5.3 Agent 生命周期）
        → Bash('bash ${PLUGIN_ROOT}/scripts/emit-agent-event.sh agent_complete {N} {mode} "phase{N}-{slug}" "{agent_label}" \'{"status":"{envelope.status}","summary":"{envelope.summary前120字符}","duration_ms":{agent_elapsed}}\'')
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
        → Bash('bash ${PLUGIN_ROOT}/scripts/emit-phase-event.sh phase_end {N} {mode} \'{"status":"{envelope.status}","duration_ms":{elapsed},"artifacts":{artifacts_json}}\'')
Step 6.7: 保存上下文快照（v5.3 上下文保护）
        → 用 python3 构造 JSON 参数避免 shell 引号问题:
          Bash("python3 -c \"import json,subprocess,sys; subprocess.run(['bash','${PLUGIN_ROOT}/scripts/save-phase-context.sh','{N}','{mode}',json.dumps({'summary':sys.argv[1],'decisions':[],'constraints':[],'artifacts':[],'next_phase_context':sys.argv[2]})],check=False)\" 'Phase {N} 产出摘要（由编排器填入实际内容）' '下阶段需要的关键上下文'")
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
Phase 4 标记为 `skipped_tdd`。测试在 Phase 5 per-task TDD RED step 创建。写入 `phase-4-tdd-override.json` checkpoint：
```json
{"status": "ok", "summary": "Phase 4 skipped: TDD mode active, tests created per-task in Phase 5", "tdd_mode_override": true}
```
直接跳转 Phase 5（Phase 2/3 OpenSpec 保留，Phase 4 不执行）。

**非 TDD 模式**（正常流程）：

**并行模式**（当 `config.phases.testing.parallel.enabled = true`）：按测试类型（unit/api/e2e/ui）并行派发子 Agent，每个注入 Phase 1 需求追溯 + 对应 test_suites 配置。详见 `references/parallel-phase4.md` 模板。

**Phase 4 门禁与阻断规则**（详见 `references/protocol.md`）：
- Phase 4 **只接受 ok 或 blocked**，warning 由 Hook 确定性阻断
- `test_counts` 每字段 ≥ `min_test_count_per_type`、`artifacts` 非空、`dry_run_results` 全 0
- `test_traceability` 覆盖率 ≥ 80%
- warning 且未满足门禁 → 强制覆盖为 blocked → 重新 dispatch

### Phase 5 特殊处理

> **HARD CONSTRAINT — 路径选择由配置决定，禁止 AI 自主判断**
> 1. 读取 `config.phases.implementation.parallel.enabled`
> 2. 立即确定路径（在任何代码调研之前）：`true` → 路径 A，`false` → 路径 B
> 3. 此选择不可更改。禁止以"共享文件多"、"跨层依赖"、"安全性"等任何理由自行降级
> 4. 合法降级仅限：路径 A 执行后合并失败 > 3 文件

**执行前读取**: `references/phase5-implementation.md`（安全准备、超时机制、无 tasks.md 场景）+ `references/parallel-phase5.md`（Phase 5 并行编排协议）

#### 任务来源（模式感知）

| 模式 | 任务来源 |
|------|---------|
| **full** | `openspec/changes/<name>/tasks.md`（Phase 3 生成） |
| **lite/minimal** | Phase 5 启动时从 `phase-1-requirements.json` 自动拆分 → `context/phase5-task-breakdown.md` |

#### 执行模式决策（互斥分支）

读取 `config.phases.implementation.parallel.enabled`，进入**互斥**的两条路径：

**【路径 A — 并行模式】**（`parallel.enabled = true`）：
读取 `references/phase5-implementation.md` 并行模式章节 + `references/parallel-phase5.md` 模板。
解析任务清单 → 按顶级目录分区 → 生成 owned_files → 并行派发 `Task(isolation: "worktree", run_in_background: true)` → 按编号合并 worktree → 批量 review → 全量测试。
**禁止**进入路径 B 或使用串行模式。降级条件：合并失败 > 3 文件 → 切换路径 B。

**【路径 B — 串行模式】**（`parallel.enabled = false` 或从路径 A 降级）：
主线程逐个派发前台 Task 实施每个 task，实现上下文隔离。
流程：解析任务清单 → 对每个 task 构造 prompt → `Task(subagent_type: "general-purpose", prompt: "...")` 同步等待 → 解析 JSON 信封 → 写入 task checkpoint → 继续下一个 task。
详见 `references/phase5-implementation.md` 串行模式章节。

**【路径 C — TDD 模式】**（`tdd_mode: true` 且模式为 `full`）：
主线程执行 RED-GREEN-REFACTOR 确定性循环。**优先于路径 A/B，与 parallel.enabled 配合使用。**

**执行前读取**: `references/tdd-cycle.md`（完整 TDD 协议）+ `references/testing-anti-patterns.md`（反模式指南）

- **串行 TDD**（`parallel.enabled: false` + `tdd_mode: true`）：
  每个 task 派发 3 个 sequential Task (RED → GREEN → REFACTOR)，主线程 Bash() 执行 L2 确定性验证。
  **v5.1 TDD 阶段状态文件**：每个 TDD 步骤派发前，主线程必须写入 `.tdd-stage` 文件，供 L2 Write/Edit Hook 确定性拦截：
  ```
  RED 派发前:   Bash('echo "red" > ${change_dir}/context/.tdd-stage')
  GREEN 派发前: Bash('echo "green" > ${change_dir}/context/.tdd-stage')
  REFACTOR 派发前: Bash('echo "refactor" > ${change_dir}/context/.tdd-stage')
  task 全部完成后: Bash('rm -f ${change_dir}/context/.tdd-stage')
  ```
  Hook 行为：RED 阶段硬阻断实现文件写入，GREEN 阶段硬阻断测试文件修改。
  详见 `references/tdd-cycle.md` 串行 TDD 章节。

- **并行 TDD**（`parallel.enabled: true` + `tdd_mode: true`）：
  域 Agent prompt 注入完整 TDD 纪律文档，Agent 内部执行 RED-GREEN-REFACTOR。
  **合并后 L2 后置验证**：所有域 Agent 完成并合并后，主线程执行 `Bash(full_test_command)` 验证所有测试通过。失败则阻断，要求修复。
  详见 `references/tdd-cycle.md` 并行 TDD + L2 后置验证章节。

TDD 护栏约束（Phase 5 专属）：

| 约束 | 规则 |
|------|------|
| TDD Iron Law | 先测试后实现，违反即删除（Superpowers 原则） |
| TDD 确定性验证 | 主线程 Bash() 运行测试验证 RED 失败/GREEN 通过 |
| TDD 测试不可变 | GREEN 阶段测试失败 → 修复实现，禁止修改测试 |
| TDD 回滚保护 | REFACTOR 破坏测试 → 强制 `git checkout -- .` 全文件回滚 (v5.2) |

> **强制约束**：路径 A/B **互斥**。Phase 5 JSON 信封构造详见 `references/protocol.md`。

### Phase 6 特殊处理（v3.2.0 Allure + 并行增强）

**执行前读取**: `references/parallel-phase6.md` 配置 + `references/phase6-code-review.md` + `references/quality-scans.md`

**并行测试执行**：按 `config.test_suites` 分套件并行派发（详见 `references/parallel-phase6.md` 模板）。

**Allure 统一报告**（当 `config.phases.reporting.format === "allure"`）：
1. 检测 Allure 安装: `bash scripts/check-allure-install.sh`
2. 所有套件输出到 `allure-results/{suite_name}/`（并行避免冲突）
3. 生成统一报告: `npx allure generate allure-results/ -o allure-report/ --clean`
4. 降级: Allure 不可用 → 使用 `config.phases.reporting.report_commands`

### Phase 5→6 特殊门禁

> **仅 full 和 lite 模式执行**。minimal 模式跳过 Phase 6。

autopilot-gate 额外验证：`test-results.json` 存在、`zero_skip_check.passed === true`、任务清单中所有任务标记为 `[x]`

---

## Phase 6 三路并行（v3.2.2 增强）

Phase 5→6 Gate 通过后，主线程**在同一条消息中**同时派发三路后台任务：

| 路径 | 内容 | 参考文档 |
|------|------|---------|
| A | Phase 6 测试执行 | `references/parallel-phase6.md` 模板 |
| B | Phase 6.5 代码审查（可选） | `references/phase6-code-review.md` |
| C | 质量扫描（多个后台 Task） | `references/quality-scans.md` |

全部使用 `run_in_background: true`。路径 B/C 不含 `autopilot-phase` 标记，不受 Hook 门禁。
路径 B/C 失败不阻断路径 A。**Phase 7 步骤 2 统一收集所有结果。**

---

## Phase 7: 汇总 + 用户确认归档（主线程）

调用 Skill(`spec-autopilot:autopilot-phase7`)。

Phase 7 执行：汇总展示（Summary Box）、三路并行结果收集、知识提取、Allure 预览、用户确认归档、git autosquash、锁文件清理。

**禁止自动归档**: 归档操作必须经过用户明确确认。

---

## 护栏约束

**执行前读取**: `references/guardrails.md`（完整护栏约束清单 + 错误处理 + 上下文压缩恢复协议）

核心约束概要：主线程编排禁嵌套 | 配置驱动禁硬编码 | 三层门禁 | 结构化标记+返回 | 测试不可变+零跳过 | 归档需用户确认 | 崩溃恢复扫描 phase5-tasks/ 细粒度恢复点
