# spec-autopilot v5.1.18 全局架构演进与 Vibe Workflow 融合指南

> **版本**: v5.1.18 | **日期**: 2026-03-17
> **编写者**: Agent 7 — 全局架构演进与 Vibe Workflow 融合指南编写者
> **性质**: 全链路审计收口报告 — 综合前 6 份 Agent 审计报告的终极演进指南

---

## 一、执行摘要

### 综合评分

| 维度 | 报告来源 | 原始评分 | 权重 | 加权分 |
|------|---------|---------|------|--------|
| 稳定性与链路闭环 | Agent 1 | 91/100 | 20% | 18.2 |
| Phase 1 需求质量 | Agent 2 | 87/100 | 15% | 13.05 |
| Phase 5 代码生成 | Agent 3 | 89/100 | 20% | 17.8 |
| Phase 6 TDD 流程 | Agent 4 | 89/100 | 15% | 13.35 |
| 性能与消耗 | Agent 5 | 76/100 | 15% | 11.4 |
| 竞品对比 | Agent 6 | N/A (定性) | 15% | 12.0* |

> *竞品对比报告为定性分析，综合 spec-autopilot 在 10 维对比中 8 维领先、2 维劣势的表现，折算为 80/100 x 15% = 12.0

**综合加权总分: 85.8 / 100**

**评级: A-**

**一句话定位**: spec-autopilot 是当前 AI Coding 领域唯一实现三层确定性门禁联防 + 8 阶段全自动交付流水线的工业级系统，在确定性治理维度处于绝对领先地位；主要短板在于性能（python3 fork 链热点）、平台锁定（仅 Claude Code）、和开发者体验（学习曲线陡峭）。

---

## 二、6 份报告关键发现汇总表

### 2.1 评分总览

| # | 报告 | 评分 | 等级 | 核心亮点 | 核心风险 |
|---|------|------|------|---------|---------|
| 1 | 稳定性审计 | 91/100 | A | 三模式状态机流转完整; 崩溃恢复三选项 + gap 感知; 测试通过率 99.68% | `get_predecessor_phase()` 返回值语义不精确; 并行合并守卫跳过后台 Agent 验证 |
| 2 | Phase 1 需求质量 | 87/100 | B+ | 三层按需加载文档架构; 确定性规则引擎 + AI 补充混合策略; 中间态 checkpoint 细粒度恢复 | flags=2 模糊需求灰区直通; 复合需求路由缺测试; 单一 Research Agent 跨系统覆盖不足 |
| 3 | Phase 5 代码生成 | 89/100 | A- | 5 层 L2 Hook 检查; anti-rationalization 30 种模式; zero_skip_check 确定性门禁 | `required_patterns` 无 L2 硬拦截; 并行模式 ownership 文件依赖主线程; 无默认安全基线 |
| 4 | Phase 6 TDD 流程 | 89/100 | A- | RED/GREEN L2 确定性隔离; TDD Metrics 三层验证闭环; 零跳过门禁双层验证 | REFACTOR 阶段不区分测试/实现文件; 并行 TDD 域 Agent 自报缺独立验证; Mock 反模式仅文档指导 |
| 5 | 性能评估 | 76/100 | B | 按需加载瘦身 58.6%; 信封摘要机制 20:1 压缩; Event Bus fail-open 策略正确 | python3 fork 链延迟高; Phase 1 人工等待占 30%; SKILL.md 全量注入浪费 token |
| 6 | 竞品对比 | 定性 | -- | 10 维对比 8 维领先; 三层门禁无竞品等效; Anti-Rationalization 独有 | 单一平台锁定; 单一 LLM 依赖; 学习曲线陡峭; 无浏览器自动化; 社区生态薄弱 |

### 2.2 各报告改进建议统计

| 报告 | 高优先级建议 | 中优先级建议 | 低优先级建议 | 合计 |
|------|------------|------------|------------|------|
| 稳定性审计 | 3 | 3 | 2 | 8 |
| Phase 1 需求质量 | 2 | 4 | 3 | 9 |
| Phase 5 代码生成 | 2 | 3 | 3 | 8 |
| Phase 6 TDD 流程 | 2 | 3 | 2 | 7 |
| 性能评估 | 2 | 3 | 3 | 8 |
| 竞品对比 | 4 (Week 1) | 4 (Week 2) | 4 (Week 3-4) | 12 |
| **合计** | **15** | **20** | **17** | **52** |

---

## 三、全局风险矩阵

### 3.1 P0 — 架构级风险（立即修复）

| ID | 风险 | 来源 | 影响范围 | 修复优先级 |
|----|------|------|---------|-----------|
| G-P0-1 | `required_patterns` 配置无 L2 硬拦截 | Agent 3 R1 | Phase 5 全部生成代码 — 项目要求使用特定 API（如 `createWebHashHistory`）但生成代码可能不遵守 | **立即** |
| G-P0-2 | python3 fork 链是绝对性能热点 | Agent 5 #1 | 全链路 — 单次 Write/Edit 检查 250-500ms，Phase 5 累计 Hook 延迟 15-40s | **立即** |
| G-P0-3 | 并行模式 ownership 文件依赖主线程写入 | Agent 3 R2 | Phase 5 并行模式 — ownership 文件缺失时检查静默跳过 | **立即** |
| G-P0-4 | 并行 TDD tdd_cycles 为域 Agent 自报 | Agent 4 R-3 | Phase 5 TDD 并行模式 — 域 Agent 可虚报 `red_verified: true` | **立即** |

### 3.2 P1 — 流程级风险（近期修复）

| ID | 风险 | 来源 | 影响范围 | 类别 |
|----|------|------|---------|------|
| G-P1-1 | flags=2 模糊需求灰区直通调研 | Agent 2 C-1 | Phase 1 — "系统性能优化"类需求不强制澄清，调研方向可能发散 | 流程级 |
| G-P1-2 | REFACTOR 阶段 Hook 不区分测试/实现文件 | Agent 4 R-2 | Phase 5 TDD — 理论上允许同时修改测试和实现，违反"测试不可变"原则 | 流程级 |
| G-P1-3 | 生成代码无默认安全基线 | Agent 3 R3 | Phase 5 — `forbidden_patterns` 无默认安全规则（eval/exec/dangerouslySetInnerHTML），需项目显式配置 | 工具级 |
| G-P1-4 | anti-rationalization `score 3-4 + 有 artifacts` 仅警告 | Agent 3 R4 | Phase 4/5/6 — 低质量产出可能通过检测 | 流程级 |
| G-P1-5 | SKILL.md 全量注入浪费 token | Agent 5 #4 | 全链路 — 22.9K 常驻 Skill 含所有 Phase 协议，当前 Phase 无关内容冗余 | 架构级 |
| G-P1-6 | `parallel-merge-guard.sh` 跳过后台 Agent 验证 | Agent 1 M-3 | Phase 5 并行合并 — 后台并行合并的冲突残留和文件越界不被检测 | 流程级 |
| G-P1-7 | 复合需求路由缺测试覆盖 | Agent 2 R-2 | Phase 1 + Phase 4 — `requirement_type` 数组合并策略未被测试 | 文档级 |
| G-P1-8 | Phase 5 模板无安全性/健壮性硬性要求 | Agent 3 R7 | Phase 5 — 无异常捕获/输入验证/日志记录的强制要求 | 流程级 |
| G-P1-9 | Mock 反模式 Gate Function 无自动化检测 | Agent 4 R-6 | Phase 4/5 TDD — Mock 过度依赖 AI 自律 | 工具级 |

### 3.3 P2 — 工具级/文档级风险（中期优化）

| ID | 风险 | 来源 | 类别 |
|----|------|------|------|
| G-P2-1 | `get_predecessor_phase()` 对非预期 Phase 返回 `0` 而非显式错误 | Agent 1 M-1 | 工具级 |
| G-P2-2 | `next_event_sequence()` 锁竞争回退策略理论上有序号重叠风险 | Agent 1 M-2 | 工具级 |
| G-P2-3 | 事件脚本重复上下文解析（~90ms/次） | Agent 5 #5 | 工具级 |
| G-P2-4 | Phase 5 三路径全加载（serial/parallel/TDD），实际仅走一条 | Agent 5 | 架构级 |
| G-P2-5 | 恒真断言检测缺少 Go/Rust/C#/Ruby 语言覆盖 | Agent 4 R-4 | 工具级 |
| G-P2-6 | `scan-checkpoints-on-start.sh` 硬编码 Phase 1-7 扫描不感知 lite/minimal | Agent 1 L-3 | 工具级 |
| G-P2-7 | sad_path_counts 为子 Agent 自报无静态分析验证 | Agent 4 R-5 | 工具级 |
| G-P2-8 | brownfield `strict_mode` 默认 false，设计-实现不一致仅 warning | Agent 3 R9 | 文档级 |
| G-P2-9 | 单一平台锁定（仅 Claude Code） | Agent 6 | 架构级 |
| G-P2-10 | 无 IDE 深度集成（CLI 交互模式） | Agent 6 | 架构级 |
| G-P2-11 | Phase 7 强制人工确认阻断自动化 | Agent 5 | 流程级 |
| G-P2-12 | `test_agent_correlation 2d` 测试失败 | Agent 1 L-1 | 工具级 |
| G-P2-13 | 版本注释噪声（"v3.2.0 新增"等）消耗 token | Agent 5 | 文档级 |

### 3.4 风险类别分布

| 类别 | P0 | P1 | P2 | 合计 |
|------|----|----|----|----|
| 架构级 | 0 | 1 | 3 | **4** |
| 流程级 | 1 | 5 | 1 | **7** |
| 工具级 | 3 | 2 | 7 | **12** |
| 文档级 | 0 | 1 | 2 | **3** |
| **合计** | **4** | **9** | **13** | **26** |

---

## 四、架构重构方案（代码级建议）

### 4.1 针对规约遗漏：加固 CLAUDE.md 约束传递

**问题**: `required_patterns` 配置在 `_constraint_loader.py` 的 `check_file_violations()` 中缺失正向校验逻辑，仅靠 prompt 软性注入。

**修改方案**:

| 文件 | 修改内容 |
|------|---------|
| `scripts/_constraint_loader.py` | 在 `check_file_violations()` 函数中新增 `required_patterns` 正向校验：当 `context` glob 匹配当前文件路径时，验证文件内容 `re.search(pattern)` 通过，缺失时输出 violation |
| `scripts/unified-write-edit-check.sh` | CHECK 4 调用 `_constraint_loader.py` 时传入 `--check-required` 标志启用正向校验 |
| `CLAUDE.md` | 在"代码约束"条目中增加: "required_patterns: 配置的必需模式 -> L2 正向校验硬阻断" |
| `tests/test_code_constraint.sh` | 新增 3 个 case: required_patterns 匹配通过 / 匹配失败 block / context 不匹配跳过 |

**新增默认安全基线**:

| 文件 | 修改内容 |
|------|---------|
| `skills/autopilot-setup/SKILL.md` | 生成的默认 `autopilot.config.yaml` 中 `code_constraints.forbidden_patterns` 预置常见安全反模式: `eval(` / `exec(` / `Function(` / `dangerouslySetInnerHTML` / `os.system(` / `subprocess.call(.*shell=True` |
| `references/config-schema.md` | 文档说明默认安全基线及覆盖方式 |

### 4.2 针对 TDD 穿透：防止 TDD 流程被绕过

**问题 1**: REFACTOR 阶段 Hook 不区分测试/实现文件，允许修改测试文件。

**修改方案**:

| 文件 | 修改内容 |
|------|---------|
| `scripts/unified-write-edit-check.sh` | CHECK 1 REFACTOR 分支增加测试文件检测: `if [ "$IS_TEST_FILE" = "yes" ]; then` 输出 `{"decision":"block","reason":"REFACTOR stage: test files are immutable per TDD Iron Law"}` |
| `tests/test_tdd_isolation.sh` | 新增 case: REFACTOR + 测试文件 -> block |

**问题 2**: 并行 TDD `tdd_cycles` 为域 Agent 自报，缺少独立 L2 验证。

**修改方案**:

| 文件 | 修改内容 |
|------|---------|
| `skills/autopilot/references/parallel-phase5.md` | 在合并后验证段增加 "RED 验证回溯" 步骤: 随机抽取 N 个 task，checkout 仅测试文件到 RED 阶段，重新运行测试验证确实失败 |
| `scripts/_post_task_validator.py` | VALIDATOR 4（并行合并守卫）增加 `tdd_spot_check` 逻辑: 从 `phase5-tasks/task-N.json` 抽样验证 `tdd_cycle.red.exit_code != 0` 的记录与 git log 一致 |

**问题 3**: anti-rationalization `score 3-4 + 有 artifacts` 仅 stderr 警告。

**修改方案**:

| 文件 | 修改内容 |
|------|---------|
| `scripts/_post_task_validator.py` | VALIDATOR 2 将 `score >= 3 + has_artifacts` 从 stderr warn 升级为 `{"decision":"block"}`，同时在 block reason 中注明"产出可能为低质量占位" |

### 4.3 针对状态跳变：加固三层门禁

**问题 1**: `get_predecessor_phase()` 对非预期 Phase 返回 `0` 语义不精确。

**修改方案**:

| 文件 | 修改内容 |
|------|---------|
| `scripts/_common.sh` | `get_predecessor_phase()` 函数: 对 lite 模式下 Phase 2/3/4 和 minimal 模式下 Phase 2/3/4/6 返回 `-1`（错误标记）而非 `0` |
| `scripts/check-predecessor-checkpoint.sh` | 检测 `get_predecessor_phase` 返回 `-1` 时直接 `deny("Phase $N is not in mode $MODE phase sequence")` |
| `tests/test_check_predecessor_checkpoint.sh` | 新增 2 个 case: lite 模式 Phase 3 -> deny / minimal 模式 Phase 6 -> deny |

**问题 2**: `parallel-merge-guard.sh` 跳过后台 Agent 验证。

**修改方案**:

| 文件 | 修改内容 |
|------|---------|
| `scripts/parallel-merge-guard.sh` | 移除 `is_background_agent && exit 0` 跳过逻辑，允许后台 Agent 也执行合并验证（冲突检测 + 文件范围 + typecheck） |
| `tests/test_parallel_merge.sh` | 新增 case: 后台 Agent 合并 -> 执行完整验证 |

**问题 3**: 并行模式 ownership 文件缺失时静默跳过。

**修改方案**:

| 文件 | 修改内容 |
|------|---------|
| `skills/autopilot/references/parallel-phase5.md` | Step 3 域 Agent 派发前增加验证: `test -f phase5-ownership/{domain}.json` 失败时降级为串行而非继续并行 |
| `scripts/unified-write-edit-check.sh` | ownership 文件缺失时输出 `{"decision":"block","reason":"ownership file missing, parallel mode requires explicit file ownership"}` 而非静默跳过 |

### 4.4 针对性能瓶颈：优化 token 消耗

**瓶颈 1**: python3 fork 链（P0 优先级）

| 文件 | 修改内容 |
|------|---------|
| `scripts/unified-write-edit-check.sh` | 将 `parse_lock_file` + `read_checkpoint_status` x N + `read_config_value` + `_constraint_loader.py` 合并为单次 python3 批处理调用。新增 `_batch_hook_context.py` 脚本，一次 fork 返回所有需要的上下文 JSON |
| 预期收益 | Hook 延迟从 ~250-500ms 降至 ~80-150ms（-60%） |

**瓶颈 2**: 事件脚本重复上下文解析

| 文件 | 修改内容 |
|------|---------|
| `scripts/emit-phase-event.sh` / `emit-gate-event.sh` / `emit-task-progress.sh` / `emit-tool-event.sh` / `emit-agent-event.sh` | 首次解析后 `export AUTOPILOT_CHANGE_NAME` / `AUTOPILOT_SESSION_ID` / `AUTOPILOT_MODE` 环境变量，后续脚本直接读取 |
| 预期收益 | 事件发射延迟从 ~124ms 降至 ~40ms（-68%） |

**瓶颈 3**: SKILL.md 全量注入

| 文件 | 修改内容 |
|------|---------|
| `skills/autopilot/SKILL.md` | 按 Phase 拆分为: `SKILL.md`（核心调度，~100 行）+ `references/phase{0-7}-protocol.md`（各 Phase 专属协议）。主 SKILL.md 仅保留模式解析、配置加载、阶段总览表，具体 Phase 协议按需 `Read()` |
| 预期收益 | 单 Phase 窗口内 Skill Token 减少 ~30-50%（~3,000-5,000 tokens/Phase） |

**瓶颈 4**: Phase 5 三路径全加载

| 文件 | 修改内容 |
|------|---------|
| `skills/autopilot/references/phase5-implementation.md` | 拆分为 `phase5-core.md`（公共流程）+ `phase5-serial.md` / `phase5-parallel.md` / `phase5-tdd.md`（按 `tdd_mode` + `parallel.enabled` 条件加载） |
| 预期收益 | Phase 5 Token 减少 ~15%（~5,000 tokens） |

---

## 五、Vibe Workflow 融合指南

### 5.1 当前 GUI V2 的能力边界

spec-autopilot GUI V2 Dashboard（v5.0.8）已实现:

| 能力 | 实现状态 | 技术栈 |
|------|---------|--------|
| 三栏实时 Dashboard | 已实现 | React + Zustand + Tailwind CSS v4 |
| Phase 时间轴可视化 | 已实现 | PhaseTimeline 组件 + SVG |
| 事件流终端 | 已实现 | VirtualTerminal + ANSI 着色 |
| Gate 决策交互 | 已实现 | GateBlockCard + decision_ack WebSocket |
| 并行 Kanban 看板 | 已实现 | ParallelKanban + Agent 卡片 |
| 遥测仪表盘 | 已实现 | TelemetryDashboard + SVG 环形图 |
| Error Boundary | 已实现 | 降级 UI |

**能力边界（当前不具备）**:

| 缺失能力 | 竞品参照 | 影响 |
|---------|---------|------|
| 代码 Diff 预览 | Cline VS Code 集成 | 用户无法在 GUI 中审查生成代码 |
| 需求编辑与再提交 | 无竞品 | Phase 1 需求修改必须回到 CLI |
| 配置可视化编辑 | 无竞品 | `autopilot.config.yaml` 必须手动编辑 |
| 测试结果可视化 | Allure Dashboard | Phase 6 测试报告必须外部查看 |
| 多会话管理 | Cline 多 Tab | 无法同时查看多个 autopilot 会话 |
| 浏览器自动化预览 | Cline Computer Use | E2E 测试结果无视觉反馈 |

### 5.2 底层编排能力向上解耦方案

当前 spec-autopilot 的编排逻辑深度耦合于 Claude Code Skill 系统。要实现 Vibe Workflow 融合，需要三层解耦:

```
Layer 3: Workflow UI (GUI Dashboard / VS Code Extension / Web IDE)
    ↕ Workflow API (REST/WebSocket)
Layer 2: Orchestration Engine (Phase 状态机 + Gate 引擎 + Recovery 引擎)
    ↕ Agent API (抽象 Agent 接口)
Layer 1: Agent Runtime (Claude Code / Cursor / Cline / Aider / 自定义)
```

**解耦步骤**:

**Step 1 — 状态机引擎提取**:
- 将 `SKILL.md` 中的 Phase 状态转移逻辑提取为可独立运行的状态机模块
- 输入: 当前 Phase + checkpoint 状态 + 模式
- 输出: 下一个 Phase + 门禁条件
- 实现: TypeScript 模块（复用 GUI 已有的 Bun 运行时）

**Step 2 — Agent 接口抽象**:
- 定义 `AgentRuntime` 接口:
  ```typescript
  interface AgentRuntime {
    dispatch(task: TaskSpec): Promise<AgentResult>;
    cancel(taskId: string): Promise<void>;
    getStatus(taskId: string): Promise<AgentStatus>;
  }
  ```
- 实现 `ClaudeCodeRuntime`（当前 Task 工具）、`CursorRuntime`、`AiderRuntime` 适配器

**Step 3 — Workflow API 服务化**:
- 将 `autopilot-server.ts` 从纯事件推送升级为完整的 Workflow API 服务
- 新增 REST 端点: `/api/start`、`/api/pause`、`/api/resume`、`/api/gate-decision`
- WebSocket 保持实时事件推送

### 5.3 现代化 Vibe Workflow 工具链设计

**目标架构**: 从 "CLI 驱动的自动化流水线" 进化为 "可视化驱动的 Vibe Workflow 平台"

```
┌─────────────────────────────────────────────────────┐
│                  Vibe Workflow Studio                 │
│  ┌──────────┐  ┌──────────┐  ┌──────────────────┐  │
│  │ 需求画布  │  │ 流程编排  │  │ 实时监控 + 干预   │  │
│  │ (Phase 1) │  │ (DAG)    │  │ (Phase 2-7)      │  │
│  └──────────┘  └──────────┘  └──────────────────┘  │
│                                                      │
│  ┌──────────┐  ┌──────────┐  ┌──────────────────┐  │
│  │ Diff 审查 │  │ 测试报告  │  │ 配置中心         │  │
│  │ (Code)   │  │ (Visual) │  │ (YAML Editor)    │  │
│  └──────────┘  └──────────┘  └──────────────────┘  │
└─────────────────────────────────────────────────────┘
          ↕ Workflow API (REST + WebSocket)
┌─────────────────────────────────────────────────────┐
│              Orchestration Engine                     │
│  State Machine + Gate Engine + Recovery Engine        │
│  + Event Bus + Metrics Collector                     │
└─────────────────────────────────────────────────────┘
          ↕ Agent API (Abstract Runtime)
┌─────────────────────────────────────────────────────┐
│  Claude Code │ Cursor │ Cline │ Aider │ Custom      │
└─────────────────────────────────────────────────────┘
```

**核心组件**:

| 组件 | 功能 | 技术选型 |
|------|------|---------|
| 需求画布 | 可视化需求编辑、决策卡片交互、苏格拉底对话 | React + Tiptap 富文本 |
| 流程编排器 | 可视化 DAG 编辑、模式切换、条件分支 | React Flow / XState |
| 实时监控 | Phase 进度、Agent 状态、Gate 干预 | 当前 GUI V2 升级 |
| Diff 审查器 | 生成代码 Diff 预览、批注、拒绝 | Monaco Editor + Diff View |
| 测试报告可视化 | 测试金字塔图、覆盖率热力图、失败追踪 | Allure 嵌入 / 自研 |
| 配置中心 | YAML 可视化编辑、预设模板切换、实时验证 | JSON Schema Form |

### 5.4 与竞品的 UX 差距及弥合路径

基于 Agent 6 竞品对比报告，spec-autopilot 的 UX 差距和弥合方案:

| 差距 | 竞品标杆 | 弥合路径 | 难度 | 优先级 |
|------|---------|---------|------|--------|
| **入门门槛高** | Aider `pip install` 即用 | `autopilot quick-start [path]` 一键初始化 + 三档预设 (strict/moderate/relaxed) | 低 | P0 |
| **无 IDE 集成** | Cline VS Code 原生 | VS Code Extension: WebView Panel 承载 GUI Dashboard | 中 | P1 |
| **CLI 输出简陋** | Aider 彩色终端 | Phase 进度条 + 彩色状态 + 预估耗时 + Gate 阻断修复路径 | 低 | P0 |
| **Git 历史侵入** | Cline Shadow Git | 可选 Shadow Git 模式: `.autopilot-shadow/` 隔离分支 | 中 | P1 |
| **无浏览器自动化** | Cline Computer Use | 集成 Playwright MCP Server 用于 E2E 视觉测试 | 高 | P2 |
| **单 LLM 锁定** | BMAD 多模型编排 | Agent API 抽象层支持多 Runtime，Phase 1 用搜索增强型 LLM | 高 | P3 |
| **无 Watch Mode** | Aider Watch Mode | 文件系统监听 `.autopilot-trigger` 变更自动启动 | 低 | P2 |
| **社区生态薄弱** | Aider 42k stars | 开放 Phase Hook Extension API + 公开 Benchmark | 中 | P2 |

**弥合优先序**: 入门门槛 > CLI 美化 > IDE 集成 > Shadow Git > Watch Mode > 浏览器自动化 > 多 LLM

---

## 六、综合评分与评级

### 6.1 加权评分模型

| 维度 | 原始分 | 权重 | 加权分 | 说明 |
|------|--------|------|--------|------|
| 核心稳定性 | 91 | 20% | 18.2 | 三模式状态机 + 崩溃恢复 + 测试通过率 |
| 需求工程质量 | 87 | 15% | 13.05 | Phase 1 三维需求分析 + 门禁有效性 |
| 代码生成治理 | 89 | 20% | 17.8 | 5 层 L2 Hook + anti-rationalization + zero_skip |
| TDD 流程纯洁度 | 89 | 15% | 13.35 | RED/GREEN L2 确定性 + TDD Metrics 三层验证 |
| 运行时性能 | 76 | 15% | 11.4 | Token 瘦身到位但 python3 fork 热点未解 |
| 生态竞争力 | 80 | 15% | 12.0 | 10 维 8 维领先但平台锁定和 DX 短板 |
| **综合** | | **100%** | **85.8** | |

### 6.2 评级标准

| 等级 | 分数区间 | 含义 |
|------|---------|------|
| **S** | 95-100 | 行业标杆，无显著短板 |
| **A** | 85-94 | 工业级优秀，有明确改进方向 |
| **B** | 75-84 | 可用但有显著瓶颈 |
| **C** | 60-74 | 需要重大重构 |
| **D** | <60 | 不可用于生产 |

### 6.3 最终评级

**spec-autopilot v5.1.18 综合评级: A- (85.8/100)**

**评级解读**:
- 在确定性治理（三层门禁、TDD Iron Law、Anti-Rationalization）维度达到 S 级水准
- 在核心稳定性（状态机、崩溃恢复、测试覆盖）维度达到 A 级水准
- 在性能优化和生态竞争力维度尚有 B 级短板需要弥补
- 距离 A 级（85 分）仅差 0.2 分，当前处于 A- 的上沿

---

## 七、8 周演进 Roadmap

### Phase 1-2 (Week 1-2): 紧急修复 — 基于风险矩阵 P0/P1

**目标**: 消除所有 P0 风险，修复高优先级 P1 风险。预期评分提升 +3-5 分。

| 周 | 任务 ID | 任务 | 对应风险 | 涉及文件 | 预期工作量 |
|----|---------|------|---------|---------|-----------|
| W1 | T-1 | 实现 `required_patterns` L2 正向校验 | G-P0-1 | `_constraint_loader.py` + `unified-write-edit-check.sh` + 测试 | 1 天 |
| W1 | T-2 | python3 fork 批处理合并 | G-P0-2 | 新增 `_batch_hook_context.py` + 修改 `unified-write-edit-check.sh` + `emit-*.sh` | 2 天 |
| W1 | T-3 | 并行 ownership 文件写入验证 | G-P0-3 | `parallel-phase5.md` + `unified-write-edit-check.sh` | 0.5 天 |
| W1 | T-4 | 并行 TDD RED 验证回溯 | G-P0-4 | `parallel-phase5.md` + `_post_task_validator.py` | 1 天 |
| W2 | T-5 | flags=2 模糊需求定向澄清 | G-P1-1 | `phase1-requirements.md` + `phase1-requirements-detail.md` | 1 天 |
| W2 | T-6 | REFACTOR 阶段测试文件保护 | G-P1-2 | `unified-write-edit-check.sh` + `test_tdd_isolation.sh` | 0.5 天 |
| W2 | T-7 | 默认安全 forbidden_patterns 基线 | G-P1-3 | `autopilot-setup/SKILL.md` + `config-schema.md` | 0.5 天 |
| W2 | T-8 | anti-rationalization score 3-4 升级为 block | G-P1-4 | `_post_task_validator.py` + 测试 | 0.5 天 |
| W2 | T-9 | 移除 parallel-merge-guard 后台 Agent 跳过 | G-P1-6 | `parallel-merge-guard.sh` + 测试 | 0.5 天 |
| W2 | T-10 | 复合需求路由测试补全 | G-P1-7 | `test_routing_overrides.sh` | 0.5 天 |

**里程碑**: P0 风险清零，P1 高优先级修复完毕。运行 `tests/run_all.sh` 全量通过。

### Phase 3-4 (Week 3-4): 核心加固 — 架构重构

**目标**: 解决架构级技术债，优化 token 消耗和性能。预期评分提升 +2-3 分。

| 周 | 任务 ID | 任务 | 对应风险 | 涉及文件 | 预期工作量 |
|----|---------|------|---------|---------|-----------|
| W3 | T-11 | SKILL.md 按 Phase 拆分 | G-P1-5 | `SKILL.md` -> `SKILL.md` + `references/phase{0-7}-protocol.md` | 2 天 |
| W3 | T-12 | Phase 5 三路径条件加载 | G-P2-4 | `phase5-implementation.md` -> `phase5-core.md` + `phase5-{serial,parallel,tdd}.md` | 1 天 |
| W3 | T-13 | 事件脚本环境变量缓存 | G-P2-3 | 5 个 `emit-*.sh` 脚本 | 1 天 |
| W4 | T-14 | `get_predecessor_phase()` 防御性增强 | G-P2-1 | `_common.sh` + `check-predecessor-checkpoint.sh` + 测试 | 0.5 天 |
| W4 | T-15 | `scan-checkpoints-on-start.sh` 模式感知 | G-P2-6 | `scan-checkpoints-on-start.sh` | 0.5 天 |
| W4 | T-16 | Phase 5 模板增加安全性/健壮性要求 | G-P1-8 | `phase5-serial-task.md` + `parallel-phase5.md` | 0.5 天 |
| W4 | T-17 | Mock 比例自动化检测（CHECK 5） | G-P1-9 | `unified-write-edit-check.sh` + 测试 | 1 天 |
| W4 | T-18 | 版本注释噪声清理 | G-P2-13 | 构建时 `strip-version-comments.sh` | 0.5 天 |

**里程碑**: Token 消耗降低 25-35%，Hook 链延迟降低 50-60%。性能评分预期从 76 提升至 85+。

### Phase 5-6 (Week 5-6): 差异化增强 — 竞品追赶

**目标**: 弥合关键 DX 差距，强化核心优势。

| 周 | 任务 ID | 任务 | 对标竞品 | 预期工作量 |
|----|---------|------|---------|-----------|
| W5 | T-19 | Quick Start 一键体验 | Aider `pip install` | 1 天 |
| W5 | T-20 | CLI 输出美化（进度条 + 彩色状态 + 预估耗时） | Aider 终端 UX | 1.5 天 |
| W5 | T-21 | Gate 阻断人性化提示（修复路径 + 示例命令） | Cline 用户引导 | 1 天 |
| W5 | T-22 | 恒真断言检测扩展 Go/Rust/C#/Ruby | 独有优势深化 | 0.5 天 |
| W6 | T-23 | Phase 7 `auto_archive` 配置项 | G-P2-11 | 1 天 |
| W6 | T-24 | Shadow Git 隔离模式原型 | Cline Checkpoint | 2 天 |
| W6 | T-25 | Repository Map 持久化（Auto-Scan 增强） | Aider Repository Map | 1.5 天 |

**里程碑**: 新用户 5 分钟首次运行成功率 > 90%。无人工干预成功率（含 auto_archive）从 ~13% 提升至 ~30%。

### Phase 7-8 (Week 7-8): 生态拓展 — Vibe Workflow 融合

**目标**: 完成编排引擎解耦，启动多平台支持。

| 周 | 任务 ID | 任务 | 说明 | 预期工作量 |
|----|---------|------|------|-----------|
| W7 | T-26 | 状态机引擎提取为独立 TypeScript 模块 | 从 SKILL.md 提取 Phase 转移逻辑 | 2 天 |
| W7 | T-27 | Agent API 抽象层定义 + ClaudeCodeRuntime 实现 | `AgentRuntime` 接口 + 适配器 | 2 天|
| W7 | T-28 | Workflow API 服务化 | `autopilot-server.ts` 升级为 REST + WebSocket | 1.5 天 |
| W8 | T-29 | VS Code Extension 原型 | WebView Panel 承载 GUI Dashboard | 2 天 |
| W8 | T-30 | 公开 Benchmark 体系 | 自举率测试 + 成功率基准 + 耗时基准 | 1 天 |
| W8 | T-31 | Phase Hook Extension API 文档 | 社区贡献入口 | 1 天 |
| W8 | T-32 | 多平台 Skill 适配层设计文档 | 平台无关化架构方案 | 1 天 |

**里程碑**: 编排引擎可独立于 Claude Code Skill 系统运行。VS Code Extension 可展示实时 Dashboard。Extension API 文档发布。

### Roadmap 甘特图

```
Week 1  ████████████████  紧急修复 P0（required_patterns / python3 batch / ownership / TDD 回溯）
Week 2  ████████████████  紧急修复 P1（模糊需求 / REFACTOR 保护 / 安全基线 / 后台 Agent）
Week 3  ████████████████  架构重构 A（SKILL.md 拆分 / Phase 5 条件加载 / 事件缓存）
Week 4  ████████████████  架构重构 B（predecessor 防御 / Mock 检测 / 安全模板 / 注释清理）
Week 5  ████████████████  DX 增强 A（Quick Start / CLI 美化 / Gate 提示 / 断言扩展）
Week 6  ████████████████  DX 增强 B（auto_archive / Shadow Git / Repository Map）
Week 7  ████████████████  引擎解耦（状态机提取 / Agent API / Workflow API）
Week 8  ████████████████  生态拓展（VS Code Extension / Benchmark / Extension API / 多平台设计）
```

---

## 八、战略结论

### 8.1 核心判断

spec-autopilot v5.1.18 已经建立了 AI Coding 领域最严格的确定性治理体系。三层门禁联防、TDD Iron Law、Anti-Rationalization 引擎构成了短期内竞品无法复制的护城河。综合评分 85.8（A-）证明系统已达工业级成熟度。

**但存在两个战略性风险**:

1. **性能-严格度 trade-off**: 三层门禁 + 多次 python3 fork + 全量 Skill 注入带来的性能开销，在中大型项目中可能成为采纳瓶颈。Week 1-4 的 python3 批处理 + Token 瘦身是解决此问题的关键。

2. **平台锁定-生态扩张矛盾**: 深度依赖 Claude Code Skill 系统赋予了确定性 Hook 能力，但也限制了用户基数。Week 7-8 的引擎解耦是打破此矛盾的第一步。

### 8.2 战略定位建议

> **坚持 "确定性治理" 路线，以 "降低门槛" 和 "引擎解耦" 为两翼展开。**

在 AI Coding 工具普遍追求灵活性和易用性的趋势中，spec-autopilot 应坚持工业级确定性治理的差异化定位。竞品的"灵活"意味着"不确定"，而 spec-autopilot 的"确定性"正是企业级交付场景的核心需求。

短期（8 周）:
- 消除 P0/P1 风险（评分从 85.8 提升至 88-90）
- 降低入门门槛（5 分钟首次运行）
- 优化 Token/性能（性能评分从 76 提升至 85+）

中期（3-6 月）:
- 完成编排引擎解耦
- VS Code Extension 发布
- 公开 Benchmark 建立行业标准

长期（6-12 月）:
- 多平台 / 多 LLM 支持
- 自适应门禁（基于历史数据动态调阈值）
- Phase 模板 Marketplace

### 8.3 评分提升预期

| 时间点 | 预期评分 | 评级 | 关键里程碑 |
|--------|---------|------|-----------|
| 当前 (v5.1.18) | 85.8 | A- | 全链路审计完成 |
| Week 2 结束 | 88-89 | A- | P0 清零 + P1 高优修复 |
| Week 4 结束 | 90-91 | A | 架构重构 + 性能优化 |
| Week 6 结束 | 92-93 | A | DX 增强 + Shadow Git |
| Week 8 结束 | 93-95 | A/A+ | 引擎解耦 + VS Code Extension |

---

## 附录 A: 6 份审计报告文件索引

| # | 报告 | 文件路径 |
|---|------|---------|
| 1 | 稳定性审计 | `docs/reports/v5.1.18/stability-audit.md` |
| 2 | Phase 1 需求质量 | `docs/reports/v5.1.18/phase1-benchmark.md` |
| 3 | Phase 5 代码生成 | `docs/reports/v5.1.18/phase5-codegen-audit.md` |
| 4 | Phase 6 TDD 流程 | `docs/reports/v5.1.18/phase6-tdd-audit.md` |
| 5 | 性能评估 | `docs/reports/v5.1.18/performance-benchmark.md` |
| 6 | 竞品对比 | `docs/reports/v5.1.18/competitive-analysis.md` |

## 附录 B: 关键项目文件索引

| 文件 | 用途 |
|------|------|
| `CLAUDE.md` | 插件工程法则（单点事实来源） |
| `README.md` | 插件概览与安装指南 |
| `CHANGELOG.md` | 版本演进历史 |
| `skills/autopilot/SKILL.md` | 主编排器协议 |
| `scripts/unified-write-edit-check.sh` | L2 Write/Edit 统一检查 Hook |
| `scripts/_post_task_validator.py` | L2 PostToolUse(Task) 统一验证器 |
| `scripts/_constraint_loader.py` | 代码约束加载与验证 |
| `scripts/_common.sh` | 共享工具函数库 |
| `scripts/parallel-merge-guard.sh` | 并行合并守卫 |
| `gui/src/` | GUI V2 Dashboard 源码 |

## 附录 C: 风险矩阵完整编号对照

| 全局编号 | 原始编号 | 来源报告 |
|---------|---------|---------|
| G-P0-1 | R1 | Phase 5 代码生成审计 |
| G-P0-2 | #1 | 性能评估 |
| G-P0-3 | R2 | Phase 5 代码生成审计 |
| G-P0-4 | R-3 | Phase 6 TDD 流程审计 |
| G-P1-1 | C-1 | Phase 1 需求质量评审 |
| G-P1-2 | R-2 | Phase 6 TDD 流程审计 |
| G-P1-3 | R3 | Phase 5 代码生成审计 |
| G-P1-4 | R4 | Phase 5 代码生成审计 |
| G-P1-5 | #4 | 性能评估 |
| G-P1-6 | M-3 | 稳定性审计 |
| G-P1-7 | R-2 | Phase 1 需求质量评审 |
| G-P1-8 | R7 | Phase 5 代码生成审计 |
| G-P1-9 | R-6 | Phase 6 TDD 流程审计 |

---

> 本报告由 Agent 7 于 2026-03-17 生成，综合 6 份专项审计报告，覆盖 spec-autopilot v5.1.18 全链路。
