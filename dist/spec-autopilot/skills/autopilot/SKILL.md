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

如果配置文件不存在 → 自动调用 Skill(`spec-autopilot:autopilot-setup`) 扫描项目生成配置。

## 协议技能

| 技能 | 用途 |
|------|------|
| `spec-autopilot:autopilot-phase0-init` | Phase 0 初始化（环境检查 + 崩溃恢复 + 锁文件管理） |
| `spec-autopilot:autopilot-phase1-requirements` | Phase 1 需求理解与多轮决策 |
| `spec-autopilot:autopilot-phase2-3-openspec` | Phase 2-3 OpenSpec 创建与 FF 生成 |
| `spec-autopilot:autopilot-phase4-testcase` | Phase 4 测试用例设计（含 TDD 跳过） |
| `spec-autopilot:autopilot-phase5-implement` | Phase 5 实施编排（路径选择 + L2 验证） |
| `spec-autopilot:autopilot-phase6-report` | Phase 6 测试报告与三路并行 |
| `spec-autopilot:autopilot-phase7-archive` | Phase 7 汇总 + 归档 |
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
| 0 | Skill(`autopilot-phase0-init`) | 环境检查 + 崩溃恢复 + 锁文件初始化 |
| 1 | Skill(`autopilot-phase1-requirements`) | 需求理解与多轮决策（LOOP 直到全部澄清） |
| 2 | Task 子 Agent | 创建 OpenSpec 并保存上下文 |
| 3 | Task 子 Agent | OpenSpec 快进生成制品 |
| 4 | Task 子 Agent | 测试用例设计（full 模式强制；TDD 模式下由 Phase 5 吸收，标记 `skipped_tdd`） |
| 5 | Task 子 Agent | 串行/并行 循环实施 |
| 6 | Task 子 Agent | 测试报告生成（强制，不可跳过） |
| 7 | Skill(`autopilot-phase7-archive`) | 汇总展示 + **Archive Readiness 自动**归档 |

> **Checkpoint 范围**: Phase 1-7 产生 checkpoint 文件。Phase 0 在主线程执行，不写 checkpoint。

## 连续执行硬约束（v6.0, v7.0.1 用户交互边界明确化）

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

> **v5.4 自动继续**: 当 `recovery-decision.sh` 输出 `auto_continue_eligible: true` 时（单候选 + 无危险 git 状态 + continue 路径存在），Phase 0 可跳过用户恢复交互，直接设定 `recovery_phase` 并继续。`auto_continue_eligible` 为 false 时仍走用户交互恢复流程。

## Phase 1: 需求理解与多轮决策（主线程）

调用 Skill(`spec-autopilot:autopilot-phase1-requirements`)。

Phase 1 完成后获得：requirement_packet、change_name、complexity、decisions。

> Phase 1 在主线程中执行，Skill 调用直接注入当前上下文。**v5.5 跳过规则**: 当 `recovery_phase > 1` 时跳过。
> Phase 1 结束时发射 `phase_end 1` 事件，payload 包含 `requirement_packet_hash`（v6.0 H-1 补全）、`clarity_score`、`discussion_rounds`、`challenge_agents_activated`（v7.1 清晰度系统）。

Phase 1 关键约束摘要（详见 autopilot-phase1 Skill）：

- **弹性收敛**（v7.1）：讨论轮数不设硬性上限，以混合清晰度评分（规则×0.6 + AI×0.4）≥ 阈值作为退出条件。安全阀: 8 轮软提醒 + 15 轮硬上限。
- **一次一问**（v7.1）：Medium/Large 每轮只问 1 个决策点，按最弱清晰度维度优先选择。Small 保持合并确认。
- **挑战代理**（v7.1）：第 4/6/8 轮自动激活反面论证/简化/本体论视角转换。停滞检测在连续 2 轮波动 ≤5% 时干预。
- **联网搜索决策**（v3.3.7）：默认执行搜索（`search_policy.default: search`），仅当同时满足所有跳过条件时才跳过。判定由规则引擎执行（非 AI 自评）。
- **并行调研**：强制在同一消息中同时发起所有调研 Task（`run_in_background: true`）

---

## Phases 2-6: 统一调度模板

对于每个 Phase N（2 ≤ N ≤ 6），在**主线程**中执行以下通用步骤。各 Phase 的特殊处理通过对应 Phase Skill 加载：

- **Phase 2-3 特殊处理**: 调用 Skill(`spec-autopilot:autopilot-phase2-3-openspec`)
- **Phase 4 特殊处理**: 调用 Skill(`spec-autopilot:autopilot-phase4-testcase`)
- **Phase 5 特殊处理**: 调用 Skill(`spec-autopilot:autopilot-phase5-implement`)
  - 路径 B 串行模式逐个派发前台 Task（同步阻塞），每个 task 完成后写入 `phase5-tasks/task-N.json` checkpoint
  - 崩溃恢复时扫描 `phase5-tasks/task-*.json` 实现细粒度恢复
- **Phase 6 特殊处理**: 调用 Skill(`spec-autopilot:autopilot-phase6-report`)

```
Step -1: 恢复跳过前置检查（v5.5 新增）
        → 当 recovery_phase 已设定时，检查当前 Phase N 是否需要跳过：
          - N < recovery_phase → 跳过整个 Phase N
          - N == recovery_phase → 从该阶段开始恢复执行
          - N > recovery_phase → 正常执行
        → 跳过的 Phase 不发射 phase_start/phase_end 事件
Step -0.5: GUI 健康检查（v5.7 自动恢复）
        → Bash('bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/start-gui-server.sh --check-health')
Step 0: 发射 Phase 开始事件（v4.2 Event Bus）
        → Bash('bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/emit-phase-event.sh phase_start {N} {mode}')
Step 1: 调用 Skill("spec-autopilot:autopilot-gate")
        → 执行 8 步阶段切换检查清单（验证 Phase N-1 checkpoint）
        → Gate 通过/阻断后发射对应事件 + 进度写入
        → 阻断时启动决策轮询（v5.1 双向反控）
Step 1.5: 检查可配置用户确认点（仅当 config.gates.user_confirmation.after_phase_{N} === true 时，v6.0 默认全部 false）
        → IF `after_phase_{N} === true`: AskUserQuestion 确认后继续
        → ELSE: **直接跳过 Step 1.5 进入 Step 2**，不得执行 AskUserQuestion
Step 2: 调用 Skill("spec-autopilot:autopilot-dispatch")
        → 按协议构造 Task prompt（注入 instruction_files、reference_files）
Step 2.5: 发射 Agent 派发事件（v5.3 Agent 生命周期）
Step 3: 使用 Task 工具派发子 Agent
        → prompt 开头必须包含 <!-- autopilot-phase:N --> 标记
        → Hook 脚本自动校验前置 checkpoint 和返回 JSON
        → 进度写入
Step 4: 解析子 Agent 返回的 JSON 信封
        → ok → 继续 | warning → 继续（Phase 4 例外）| blocked/failed → 暂停
Step 4.5: 发射 Agent 完成事件
Step 4.7: GUI 周期性健康检查（v5.7 — Phase 5 长任务保活）
Step 5+7: 派发后台 Checkpoint Agent（v3.4.3, v5.1 原子写入 + 状态隔离）
        → Checkpoint 写入 + git fixup commit 合并为后台 Agent
        → **v5.1**: Checkpoint 写入**必须使用 Bash 工具**（非 Write 工具）
        → **必须使用 `git add -A`**（自动尊重 .gitignore）
        → **禁止显式 `git add` 锁文件 `.autopilot-active`** — git add -A 自动尊重 .gitignore
Step 6: TaskUpdate Phase N → completed
Step 6.5: 发射 Phase 结束事件
Step 6.6: 上下文使用率提示（v5.8 上下文压缩预警）
Step 6.7: 保存上下文快照（v5.3, v5.8 占位符修复）
        → 从子 Agent JSON 信封提取实际内容填入 save-phase-context.sh 参数
Step 8: 等待 Step 5+7 后台 Agent 完成通知
        → 确认 checkpoint 已持久化后，**立即**继续下一 Phase
```

---

## Phase 7: 汇总 + Archive Readiness 自动归档（主线程）

调用 Skill(`spec-autopilot:autopilot-phase7-archive`)。

Phase 7 执行：汇总展示（Summary Box）、三路并行结果收集、知识提取、Allure 预览、Archive Readiness 自动判定、git autosquash、锁文件清理。

**v6.0 Archive Readiness fail-closed**: 构建 `archive-readiness.json` 统一判定。所有检查通过时自动归档，任一失败则硬阻断。

---

## 护栏约束

**执行前读取**: `references/guardrails.md`（完整护栏约束清单 + 错误处理 + 上下文压缩恢复协议）

核心约束概要：主线程编排禁嵌套 | 配置驱动禁硬编码 | 三层门禁 | 结构化标记+返回 | 测试不可变+零跳过 | 归档 fail-closed | 崩溃恢复基于 state-snapshot.json | Phase 1 上下文隔离 | Review findings blocking 硬阻断归档
