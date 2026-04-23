---
name: autopilot
description: "Use when the user requests an end-to-end spec-driven delivery pipeline (requirements → OpenSpec → implementation → testing → archive); orchestrates Phase 0-7."
argument-hint: "[mode] [需求描述或 PRD 文件路径] — mode: full(default)|lite|minimal"
user-invocable: true
---

# Autopilot — 主线程编排器

主线程**仅做编排**。Phase 1-7 全部通过 Task 工具派发**单层**子 Agent 执行（包含 Phase 1 调研/BA、Phase 5.5 Red Team、Phase 7 归档）。

> **架构约束**: 子 Agent 内部没有 Task 工具，所有 Task 派发必须在主线程中执行，禁止嵌套。

## 主线程职责边界（Hard Boundary，最高优先级）

主线程**只允许**执行以下 4 类操作，**禁止**亲自承担本应由子 Agent 完成的认知/产出工作：

| ✅ 允许（编排动作） | ❌ 禁止（应派发给子 Agent） |
|---|---|
| 调用 Skill(...) 加载协议 | 自行 Read PRD / 源码 / 测试 / 运行时脚本做"勘察"或"分析" |
| Bash 调用 `runtime/scripts/*` 确定性脚本（emit/checkpoint/gate/validate）| 自行 Web Search / Glob / Grep 做调研 |
| Task(subagent_type=...) 派发子 Agent | 自行设计测试用例 / 撰写实现代码 / 生成报告 |
| 解析子 Agent JSON 信封 → 写 checkpoint → emit 事件 → AskUserQuestion 用户决策 | 自行合成 requirement-packet / 自行做 Red Team 对抗 / 自行做归档总结 |

**Phase Owner 表（与 `autopilot-dispatch/SKILL.md` 第 240-251 行严格对齐）**：

| Phase | 实际执行者 | subagent_type |
|------|-----------|---------------|
| 0 | 主线程（仅环境/锁文件/恢复决策） | — |
| 1 | **必须 Task 派发** | `config.phases.requirements.research.agent`（调研）+ `config.phases.requirements.agent`（BA）+ `config.phases.requirements.synthesizer.agent`（Packager） |
| 2-3 | **必须 Task 派发** | `autopilot-phase2-3-openspec` |
| 4 | **必须 Task 派发** | `autopilot-phase4-testcase` |
| 5 | **必须 Task 派发** | `autopilot-phase5-implement` |
| 5.5 | **必须 Task 派发** | `autopilot-phase5-5-redteam` |
| 6 | **必须 Task 派发** | `autopilot-phase6-report` |
| 7 | **必须 Task 派发** | `autopilot-phase7-archive` |

**反模式自检**（主线程进入任意 Phase ≥ 1 后立即自检；若命中任意一项，立即停止并改走 Task 派发）：

- 在没有 Task 工具调用的情况下，主线程已经输出"已勘察 / 已分析 / 已读取 / 已扫描 / 已总结"等动词的内容
- 主线程已经使用 Read/Grep/Glob/WebFetch/WebSearch 检视业务文件（hooks/runtime/gui/src 等），但当前 Phase Owner 表显示该工作应由子 Agent 完成
- 主线程在 AskUserQuestion 之前已经"自己想好了答案"，跳过了 ScanAgent / ResearchAgent / SynthesizerAgent 的派发链路

**P0 红线引用**：派发前必须调用 `runtime/scripts/validate-agent-registry.sh` 校验 `subagent_type`；Phase 2-7 严禁使用 `Explore` 或残留 `{{...}}` 占位符；详见 `skills/autopilot-dispatch/SKILL.md` § Sub-Agent 名称硬解析协议。

## 执行模式

支持 3 种模式（`full` / `lite` / `minimal`），按任务规模选择。**模式只控制阶段跳过，不影响阶段质量**：Phase 1（需求讨论）与 Phase 5（实施）在所有模式下执行完全相同的流程。

模式解析优先级：`$ARGUMENTS 首 token` > `config.default_mode` > `full`。

详细的阶段序列、跳过规则、任务来源、路径选择逻辑见 `references/mode-routing-table.md`。

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

如果配置文件不存在 → 自动调用 Skill(`spec-autopilot:autopilot-setup`) 扫描项目生成配置。

## 协议技能与阶段总览

| Phase | Skill | Description |
|-------|-------|-------------|
| 0 | `spec-autopilot:autopilot-phase0-init` | 环境检查 + 崩溃恢复 + 锁文件初始化（主线程执行，不写 checkpoint） |
| 1 | `spec-autopilot:autopilot-phase1-requirements` | 需求理解与多轮决策（LOOP 直到全部澄清） |
| 2-3 | `spec-autopilot:autopilot-phase2-3-openspec` | OpenSpec 创建 + FF 生成（联合调度快速路径） |
| 4 | `spec-autopilot:autopilot-phase4-testcase` | 测试用例设计（full 模式强制；TDD 模式下由 Phase 5 吸收） |
| 5 | `spec-autopilot:autopilot-phase5-implement` | 串行/并行循环实施 |
| 5.5 | `spec-autopilot:autopilot-phase5-5-redteam` | Red Team 对抗相位，详见该 SKILL |
| 6 | `spec-autopilot:autopilot-phase6-report` | 测试报告生成（强制，不可跳过） |
| 6.5 | — | Phase 6.5 code review advisory gate（结果在 Phase 7 汇合） |
| 7 | `spec-autopilot:autopilot-phase7-archive` | 汇总展示 + Archive Readiness 自动归档 |

支撑 Skill：`autopilot-gate`（阶段门禁 + checkpoint）、`autopilot-dispatch`（子 Agent 调度构造）、`autopilot-recovery`（崩溃恢复）、`autopilot-risk-scanner`（gate 前 Critic 风险报告）、`autopilot-learn`（Phase 7 后 episode 聚类）、`autopilot-docs-sync` / `autopilot-docs-fix` / `autopilot-test-audit` / `autopilot-test-fix` / `autopilot-test-health`（工程自动化纪律）。

## 连续执行硬约束（用户交互边界明确化）

当某个阶段满足以下条件时，主线程**必须立即继续到下一个阶段**，不得把阶段完成本身当作新的用户决策点：

- 当前阶段最终状态为 `ok` 或 `warning`
- 下一阶段未被 mode 跳过
- `config.gates.user_confirmation.after_phase_{N}` 不为 `true`
- 不存在 gate blocked、崩溃恢复歧义或 archive readiness 阻断

**用户交互边界**: Phase 1 是**唯一**需要用户主动确认的阶段（通过 AskUserQuestion 确认需求）。Phase 2-7 全部自动完成，除非显式配置了 `user_confirmation.after_phase_{N}` 或遇到 gate blocked。

允许输出简短进度信息，但输出后必须直接执行下一阶段。**禁止**额外提问例如：

- `Phase N 已完成。要继续下一阶段还是先审查当前产物？` — 禁止以"是否继续下一阶段"类问题中断流程
- `下一步是 Phase 2 还是需要先审查？是否先审查当前阶段输出？` — 禁止审查输出元问题
- 任何仅用于把控制权交还给用户、但并非协议要求的"继续/审查/暂停"问题

唯一允许的中断来源：

- Phase 1 尚有未闭合决策点或最终 requirement packet 未确认（必须使用 AskUserQuestion）
- 显式开启的 `user_confirmation.after_phase_{N}`
- gate blocked / retry / fix / override 决策
- Phase 7 archive readiness blocked 或非 autopilot fixup 风险确认

---

## Phase 0: 环境检查 + 崩溃恢复

调用 Skill(`spec-autopilot:autopilot-phase0-init`)，传入 $ARGUMENTS 和 plugin_dir。

Phase 0 完成后获得：version、mode、session_id、ANCHOR_SHA、config、recovery_phase、auto_continue_eligible。

> **自动继续**: 当 `recovery-decision.sh` 输出 `auto_continue_eligible: true` 时（单候选 + 无危险 git 状态 + continue 路径存在），Phase 0 可跳过用户恢复交互，直接设定 `recovery_phase` 并继续。`auto_continue_eligible` 为 false 时仍走用户交互恢复流程。

## Phase 1: 需求理解与多轮决策

主线程**必须**调用 Skill(`spec-autopilot:autopilot-phase1-requirements`)，并按其协议**通过 Task 工具派发** ScanAgent / ResearchAgent / SynthesizerAgent / BA / PackagerAgent。**禁止**主线程自行 Read 源码、自行 Web Search、自行设计需求包；主线程仅消费子 Agent 返回的 JSON 信封字段。

Phase 1 完成后获得：requirement_packet、change_name、complexity、decisions。

> **跳过规则**: 当 `recovery_phase > 1` 时跳过。
> Phase 1 结束时发射 `phase_end 1` 事件，payload 包含 `requirement_packet_hash`、`clarity_score`、`discussion_rounds`、`challenge_agents_activated`。

详见 Skill(spec-autopilot:autopilot-phase1-requirements)。

> **联网搜索决策（test 锚点）**：默认执行搜索（`search_policy.default: search`），由 `regex/rules-scanner.sh` 规则引擎执行跳过判定，仅当任务同时满足所有跳过条件时才跳过。

---

## Phases 2-6: 统一调度模板

对于每个 Phase N（2 ≤ N ≤ 6），在**主线程**中执行以下通用步骤。各 Phase 的特殊处理通过对应 Phase Skill 加载：

- **Phase 2-3**: 调用 Skill(`spec-autopilot:autopilot-phase2-3-openspec`)，采用**联合调度快速路径**（见下方）
- **Phase 4**: 调用 Skill(`spec-autopilot:autopilot-phase4-testcase`)
- **Phase 5**: 调用 Skill(`spec-autopilot:autopilot-phase5-implement`)；串行模式逐个派发前台 Task（同步阻塞），每个 task 完成后写入 `phase5-tasks/task-N.json` checkpoint；崩溃恢复时扫描 `phase5-tasks/task-*.json` 实现细粒度恢复
- **Phase 6**: 调用 Skill(`spec-autopilot:autopilot-phase6-report`)

### Phase 2-3 联合调度快速路径（性能优化）

Phase 2 与 Phase 3 共享同一 Agent (Plan) 和 Tier (fast/haiku)，合并为单次 gate + 单次 model routing + 两个串行 background Task。

详见 `references/phase23-fast-path.md`。

### Phase 4-6 通用调度模板

对每个 Phase N (4 ≤ N ≤ 6)，主线程依次：

1. Skill(spec-autopilot:autopilot-gate)
2. Skill(spec-autopilot:autopilot-dispatch)
3. Task tool（派发并阻塞）
4. 解析 JSON 信封 → 写 checkpoint → emit 事件

详见 `references/phase4-6-loop.md`。

#### Step 1.5 / Step 5+7 关键约束（test 锚点）

- **Step 1.5**：当 `config.gates.user_confirmation.after_phase_{N} === true` 时 AskUserQuestion 确认；ELSE：**直接跳过 Step 1.5 进入 Step 2**，不得执行 AskUserQuestion
- **Step 5+7 后台 Checkpoint Agent**：Checkpoint 写入 + git fixup commit 合并为后台 Agent
  - Checkpoint 写入**必须使用 Bash 工具**（非 Write 工具）
  - **必须使用 `git add -A`**（自动尊重 .gitignore）
  - **禁止显式 `git add` 锁文件 `.autopilot-active`** — git add -A 自动尊重 .gitignore

---

## Phase 5.5: Red Team 对抗审查

主线程**必须**通过 Task 工具派发到 `autopilot-phase5-5-redteam` 子 Agent，对 Phase 5 实施成果做对抗性 critic。**禁止**主线程自行扮演 Red Team 在主对话中做对抗审查。

执行步骤：

1. Skill(`spec-autopilot:autopilot-gate`) — 校验 Phase 5 checkpoint
2. Skill(`spec-autopilot:autopilot-phase5-5-redteam`) — 加载 Red Team 协议
3. Task tool 派发 `subagent_type: autopilot-phase5-5-redteam`（阻塞）
4. 解析返回信封 → 写 checkpoint → emit `phase_end 5.5` 事件

Red Team 输出 `blocked` 时回退到 Phase 5 修复；输出 `ok|warning` 时进入 Phase 6。

---

## Phase 7: 汇总 + Archive Readiness 自动归档

主线程**必须**通过 Task 工具派发到 `autopilot-phase7-archive` 子 Agent。**禁止**主线程自行做汇总展示、知识提取、Archive Readiness 判定、git autosquash 等业务工作；主线程只负责派发、解析信封、根据 readiness 决策是否归档以及锁文件清理（确定性脚本调用）。

执行步骤：

1. Skill(`spec-autopilot:autopilot-gate`) — 校验 Phase 6 checkpoint 与三路并行结果就位
2. Skill(`spec-autopilot:autopilot-phase7-archive`) — 加载归档协议
3. Task tool 派发 `subagent_type: autopilot-phase7-archive`（阻塞）
4. 解析返回信封 → 读取 `archive-readiness.json` → 决策归档/阻断

**Archive Readiness fail-closed**: 构建 `archive-readiness.json` 统一判定。所有检查通过时自动归档，任一失败则硬阻断。

---

## 护栏约束

**执行前读取**: `references/guardrails.md`（完整护栏约束清单 + 错误处理 + 上下文压缩恢复协议）

核心约束概要：主线程编排禁嵌套 | 配置驱动禁硬编码 | 三层门禁 | 结构化标记+返回 | 测试不可变+零跳过 | 归档 fail-closed | 崩溃恢复基于 state-snapshot.json | Phase 1 上下文隔离 | Review findings blocking 硬阻断归档
