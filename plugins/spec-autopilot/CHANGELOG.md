# Changelog


## [5.1.7] - 2026-03-15

### Fixed

- **P0-1 REFACTOR 文件级回滚**: unified-write-edit-check.sh 新增 refactor case 追踪写入文件至 `.tdd-refactor-files`；tdd-refactor-rollback.sh 替换 `git stash/checkout --./pop` 为逐文件 `git checkout`/`rm`，避免误回滚无关文件
- **P0-4 WebSocket 5s 连接超时**: ws-bridge.ts 新增 connectTimeout 定时器，CONNECTING 状态超时自动 close 触发重连
- **P1-5 TODO 检测全局化**: Phase 4/5/6 交付阶段 `.md` 文件启用 TODO/FIXME/HACK 检测（非交付阶段仍跳过）
- **P1-6 关键事件防截断**: store addEvents 分区保留 phase_start/phase_end/gate_block/gate_pass 事件，常规事件填充剩余 1000 配额

### Added

- **v5.1.6 评测报告**: v1/v2/v3 全维度评测报告 + 修复路线图
- **新增测试**: REFACTOR 文件追踪、交付阶段 .md TODO 阻断、文件级回滚验证

## [5.1.5] - 2026-03-14

### Fixed

- **_config_validator.py fallback parser**: 无 PyYAML 时数值/布尔值类型转换 + get_value() flat key fallback，修复 CI range validation 跳过问题

### Changed

- **gitignore gui-dist/**: 构建产物从 git 跟踪中移除，减少二进制 diff 噪声

## [5.1.3] - 2026-03-14

### Added

- **tdd-refactor-rollback.sh**: TDD REFACTOR 阶段确定性 3 步回滚脚本 (stash → checkout → pop)
- **min_qa_rounds L2 硬阻断**: 配置校验 (1-10 范围) + Phase 1 decisions 数量 < min_qa_rounds 时 block
- **scripts/tsconfig.json + package.json**: IDE 类型支持 (bun-types)，`tsc --noEmit --strict` 零报错
- **GateBlockCard 决策失败 UI 报警**: error state + 红色 AlertTriangle banner
- **3 个新测试文件**: test_tdd_rollback.sh, test_min_qa_rounds.sh, test_fail_closed.sh 9d case

### Changed

- **autopilot-server.ts I/O 增量化**: lastLineCount → lastByteOffset，getNewEventLines 字节偏移读取
- **selectGateStats 单次遍历**: 3×filter → 1×for 循环
- **TelemetryDashboard/PhaseTimeline**: useStore selector 精细化 + gateStats useMemo
- **WebSocket 类型标注**: ServerWebSocket\<unknown\>，消除 implicit any

### Fixed

- **autopilot-server.ts JSON.parse 3 处防崩溃**: safeJsonParse + filter type predicate，损坏行 skip 不 crash
- **Python3 缺失 fail-closed**: unified-write-edit-check.sh `command -v python3 || exit 0` → `require_python3 || exit 0`

## [5.1.2] - 2026-03-14

### Added

- **Bilingual documentation (i18n)**: All 10 technical docs now have English (default) + Chinese (.zh.md) versions with language switcher links at top (20 files total)

## [5.1.0] - 2026-03-14

## [5.0.10] - 2026-03-14

### Added

- **v5.3 全量审计报告**: 7-Agent 并行全自动评估，总分 87.3/100 (Delta +2.9)
- **总控仪表盘**: `docs/reports/v5.3/v5.3-evaluation-dashboard.md`
- **7 份专项报告**: 基建/路由/遥测/竞品/规约/GUI交互/全链路仿真
- **v5.3 审计 roadmap**: `docs/roadmap/v5.3-analysis-report.md`

## [5.0.8] - 2026-03-14

### Added

- **GUI V2 视觉升维**: Tailwind CSS v4 @theme 设计系统 + motion 动画库
- **三栏布局**: 左侧 PhaseTimeline 垂直时间轴 + 中心 Kanban/Terminal + 右侧 TelemetryDashboard
- **本地字体**: JetBrains Mono / Space Grotesk / Orbitron (10 个 woff2)
- **TelemetryDashboard 组件**: SVG 环形图 + 阶段耗时条 + 门禁统计面板
- **Store derived selectors**: selectPhaseDurations / selectGateStats / selectTotalElapsedMs

### Changed

- **GateBlockCard**: 赛博朋克风格重构 + fix_instructions 输入框
- **VirtualTerminal**: xterm.js 极客外壳 + ANSI 彩色事件类型标签 + payload 详情展示
- **PhaseTimeline**: 垂直左侧栏 hex 节点 + 连接线 + 底部统计面板
- **ParallelKanban**: 水平可滚动卡片流 + TDD 步骤指示

### Fixed (GUI 完整性审计迭代)

- **G1 GateBlockCard 幽灵复现**: 对比 gate_block/gate_pass sequence，已消解的 block 不再显示
- **G2 decision_ack 竞态**: 改为事件驱动重置，新 gate_block 到达自动清除 ack 状态
- **G3 loading 状态不复位**: 发送成功后显式 setLoading(null)
- **G4 PhaseTimeline blocked 不解除**: gate_pass.sequence > gate_block.sequence 时状态恢复为 running
- **G5 硬编码 8 阶段**: 根据 mode (full/lite/minimal) 动态选择活跃阶段
- **G6 ParallelKanban 硬编码标签**: 从 events 推断并行/TDD 模式，条件渲染
- **G7 VirtualTerminal 无 payload**: 根据事件类型追加 gate_score/error_message/task_name 等关键字段
- **G8 无初始空状态**: 添加连接中 spinner + "等待事件流" 占位符
- **G9 Running 计时器不刷新**: 添加 1s setInterval 强制重渲染
- **G10 `as any` 类型不安全**: 定义 TaskProgressPayload + isTaskProgressPayload 类型守卫
- **G11 无 Error Boundary**: 新增 ErrorBoundary 组件包裹 App，显示降级 UI
- **G12 版本号硬编码**: 通过 vite define 从 plugin.json 动态注入
- **G13 SVG 颜色硬编码**: 改用 CSS 变量 var(--color-surface)/var(--color-cyan)

## [5.0.7] - 2026-03-14

### Added

- **模块化测试体系**: 2725 行单文件 `test-hooks.sh` 重构为 49 个独立 `tests/test_*.sh` 模块 (357 tests)
- **build-dist.sh**: 白名单构建 `dist/spec-autopilot/`，终端用户仅安装运行时文件 (1.1M vs 源码 2.9M)
- **CLAUDE.md 测试纪律铁律**: 禁止反向适配、弱化断言、删除测试等反模式
- **CLAUDE.md 构建纪律**: dist 构建规范 + DEV-ONLY 标记裁剪机制

### Changed

- **marketplace.json source**: `./plugins/spec-autopilot` → `./dist/spec-autopilot`，终端用户不再安装 gui 源码/测试/文档
- **pre-commit hook**: 指向 `tests/run_all.sh` + 自动 rebuild dist + 测试覆盖检查升级
- **GitHub Actions**: `test.yml` 指向新测试路径
- **dist 按插件名隔离**: `dist/plugin/` → `dist/<plugin-name>/`，支持多插件市场扩展

### Removed

- **scripts/test-hooks.sh**: 已完整迁移至 `tests/` 目录

## [5.0.6] - 2026-03-14

### Added (v5.2 卓越线冲刺 — Sprint to 90+)

- **按需加载并行协议**: `parallel-dispatch.md` 拆分为 `parallel-phase{1,4,5,6}.md`，各阶段按需加载 (63.7% Token 瘦身)
- **`emit-task-progress.sh`**: Phase 5 细粒度 `task_progress` 事件发射脚本，GUI 并发看板实时跳动
- **`decision_ack` WebSocket 事件**: server 写入决策后即时广播，前端 GateBlockCard 秒级消失
- **VirtualTerminal ANSI 着色**: 终端按事件类型上色 (gate_block=红, gate_pass=绿, task_progress=青, error=亮红)
- **复合需求路由**: `requirement_type` 支持数组 (如 `["refactor","feature"]`)，`routing_overrides` 取 max() 合并最严阈值
- **苏格拉底第 7 步**: 非功能需求质询 (SLA/性能/可靠性)，并发/分布式关键词触发
- **`min_qa_rounds` 消费**: Step 1.6 决策循环读取 `config.phases.requirements.min_qa_rounds` 作为强制最低轮数

### Changed

- **hooks.json**: `post-task-validator` timeout 150s → 60s
- **TDD-5 回滚升级**: REFACTOR 失败时 `git checkout -- .` 全文件回滚 (原为仅回滚 modified 文件)
- **反合理化扩展**: +6 模式 — 时间/Deadline 借口、环境配置借口、第三方依赖阻塞借口 (中英双语)
- **崩溃恢复增强**: `autopilot-recovery` 清理步骤新增 `rm -f .tdd-stage` 防止状态残留

## [5.0.5] - 2026-03-14

### Added

- **v5.1.1 全量审计报告** (9 份): 合规审计、稳定性审计、性能基准、GUI 交互审计、竞品分析、Phase 1 基准、热修复验证、整体仿真基准、评估仪表盘
- **v5.1.1 路线图文档**: 全量评估计划、热修复验证计划
- **v5.2 执行计划**: 冲刺至 90 分路线图

## [5.0.4] - 2026-03-14
## [4.2.0] - 2026-03-13

### Added (规约补漏 — TD-1/TD-2/TD-3)

- **`banned-patterns-check.sh`**: PostToolUse(Write|Edit) L2 Hook，确定性拦截 TODO:/FIXME:/HACK: 占位符代码 (TD-2)
- **`assertion-quality-check.sh`**: PostToolUse(Write|Edit) L2 Hook，确定性拦截恒真断言 `expect(true).toBe(true)` 等 (TD-1)
- **`sad_path_counts` 门禁**: Phase 4 JSON 信封新增必填字段，要求每种测试类型异常分支用例 ≥ 20% (TD-3)
  - 默认 20%，Bugfix 路由提升至 40%
  - `_post_task_validator.py` Validator 6 确定性验证

### Added (需求分类路由 — TD-6)

- **Step 1.1.6 需求类型分类**: 确定性规则将需求分类为 Feature/Bugfix/Refactor/Chore
- **差异化路由策略**: 不同类别动态调整 sad_path 比例、change_coverage 阈值、必须测试类型
- **`routing_overrides`**: Phase 1 checkpoint 写入路由覆盖值，L2 Hook 动态读取调整门禁

### Added (GUI Event Bus — v5.0 先导)

- **`emit-phase-event.sh`**: Phase 生命周期事件发射器 (phase_start/phase_end/error)
- **`emit-gate-event.sh`**: Gate 判定事件发射器 (gate_pass/gate_block)
- **`logs/events.jsonl`**: 结构化 JSON Lines 事件流 (PhaseEvent/GateEvent 规范)
- **`references/event-bus-api.md`**: Event Bus API 规范文档 (TypeScript 接口定义)
- **SKILL.md 事件埋点**: 统一调度模板 Step 0 (phase_start) + Step 1 (gate) + Step 6.5 (phase_end)

### Added (工程治理)

- **`CLAUDE.md`**: 项目级工程法则文档（状态机红线 + TDD Iron Law + 代码质量约束 + Event API）

### Changed (Phase 5 并行引擎 — TD-5)

- **Batch Scheduler 升级**: 串行模式后台并行从"可选优化"升级为"默认引擎"
  - 拓扑排序 + 层级分组算法，自动检测无依赖 task 并批量后台派发
  - 预期 Phase 5 串行耗时减少 40-60%（10 task → 3 batch）
  - 失败降级: batch 内 >50% 失败则回退纯串行
- **`parallel-dispatch.md`**: 新增 Batch Scheduler 协议引用

### Changed

- **`hooks.json`**: 新增 2 个 PostToolUse(Write|Edit) Hook 注册
- **`protocol.md`**: Phase 1 新增 `requirement_type` + `routing_overrides` 可选字段；Phase 4 新增 `sad_path_counts` 必填字段
- **`phase4-testing.md`**: 新增 Sad Path 门禁规则说明 + 返回格式更新
- **`_post_task_validator.py`**: 新增 Validator 6 (sad_path) + routing_overrides 动态阈值读取

## [4.1.0] - 2026-03-13

### Fixed (P0)

- **TDD Metrics L2 确定性检查**: `_post_task_validator.py` 新增 `tdd_metrics` 字段验证（`red_violations === 0`, `cycles_completed >= 1`）
- **并行 TDD 后置审计**: Phase 5 并行模式合并后逐 task 验证 TDD 循环完整性
- **需求模糊度前置检测**: Step 1.1.5 规则引擎（4 维检测 + flags 决策树），避免模糊需求浪费 Token
- **Phase 5 串行优化**: 无依赖 task 后台并行策略（预计耗时减少 30-50%）

### Fixed (P1)

- **python3 硬前置条件**: Phase 0 环境检查阻断无 python3 环境
- **anchor_sha 恢复校验**: `autopilot-recovery` Step 6 验证 anchor_sha 有效性，无效时自动重建
- **brownfield 默认值统一**: `brownfield-validation.md` 与 `autopilot-gate/SKILL.md` 一致（v4.0 起默认 true）
- **minimal zero_skip 警告**: Phase 5→7 门禁输出测试未验证警告（stderr, 非阻断）
- **`get_predecessor_phase` fallback 安全化**: 所有模式的 fallback 从 `$((target-1))` 改为 `echo 0`
- **`scan-checkpoints-on-start.sh` 模式感知**: 按 mode 计算正确的 suggested resume phase
- **Summary Box 模式说明**: lite/minimal 模式展示跳过阶段列表

### Changed

- 遗留脚本（`validate-json-envelope.sh` / `anti-rationalization-check.sh` / `code-constraint-check.sh` / `validate-decision-format.sh`）标记 DEPRECATED
- `phase1-requirements.md` 分层拆分：核心流程（~138 行常驻）+ `phase1-requirements-detail.md`（~559 行按需加载）
- `parallel-dispatch.md` + `parallel-phase-dispatch.md` 合并为单一文档
- `protocol.md` 补充 L2/L3 分层策略说明

### Removed

- 物理删除 `skills/autopilot-checkpoint/` 目录（已合入 gate，v4.0）
- 物理删除 `skills/autopilot-lockfile/` 目录（已合入 phase0，v4.0）
- 删除 `references/parallel-phase-dispatch.md`（合入 `parallel-dispatch.md`）

### Optimized

- 主线程常驻 Token 预估减少 ~16K（phase1-req 拆分 ~8K + 并行文档合并 ~4K + 冗余 Skill 清理 ~3K）

## [4.0.4] - 2026-03-13

### Added

- **全链路审计报告 (7 份)**: 稳定性/需求质量/代码生成/TDD 流程/性能评估/竞品对比/架构演进
- **重构执行计划**: `docs/plans/execution-plan.md` — v4.1 目标 20 任务 4 批次
- **Benchmark prompts**: `docs/beenchmark/prompt.md` + `validate.md` 审计与重构驱动 prompt

## [4.0.0] - 2026-03-12

### Added

- **`_hook_preamble.sh`**: 公共 Hook 前言脚本，统一 6 个 PostToolUse Hook 的 stdin 读取 + Layer 0 bypass 逻辑（消除 ~90 行重复）
- **`_config_validator.py`**: 独立 Python 配置验证模块，从 validate-config.sh 中提取（支持 IDE 高亮/linting）
- **`docs/plans/2026-03-12-v4.0-upgrade-blueprint.md`**: v4.0 升级蓝图（4 Wave 方案设计）
- **`references/guardrails.md`**: 护栏约束清单（从 SKILL.md 拆出 ~65 行，按需加载）
- **`post-task-validator.sh` + `_post_task_validator.py`**: 统一 PostToolUse(Task) 验证器，5→1 Hook 合并
  - 单次 python3 fork 替代 5 次独立调用（~420ms → ~100ms）
  - hooks.json PostToolUse(Task) 从 5 条注册简化为 1 条
- **test_traceability L2 blocking**: Phase 4 需求追溯覆盖率从 recommended 升级为 L2 blocking（`traceability_floor` 默认 80%）
- **brownfield_validation 默认开启**: 存量项目设计-实现漂移检测默认开启（greenfield 项目 Phase 0 自动关闭）
- **`quality_scans.tools` 配置**: Phase 6 路径 C 支持配置真实静态分析工具（typecheck/lint/security）
- **4 篇文档补全**: `quick-start.md`、`architecture-overview.md`、`troubleshooting-faq.md`、`config-tuning-guide.md`
- **CLAUDE.md 变更感知**: Gate Step 5.5 检测运行期间 CLAUDE.md 修改，自动重新扫描规则
- **错误信息增强**: Hook 阻断消息添加 `fix_suggestion` 字段（中文修复建议 + 文档链接）

### Changed

- **Skill 合并 (9→7)**: `autopilot-checkpoint` 合入 `autopilot-gate`，`autopilot-lockfile` 合入 `autopilot-phase0`
- **Hook 去重**: 6 个 PostToolUse Hook 脚本使用 `_hook_preamble.sh` 替代重复的前言逻辑
- **SKILL.md 瘦身**: 护栏约束 + 错误处理 + 压缩恢复协议提取为 `references/guardrails.md`（~65 行 → 3 行概要引用）
- **Hook 链合并**: 5 个 PostToolUse(Task) Hook 合并为 1 个统一入口 `post-task-validator.sh`
- **validate-config.sh**: Python 验证逻辑外置为 `_config_validator.py`，bash 仅做调用和 fallback
- 更新 16 处跨文件引用（SKILL.md / references / log-format 等）

## [3.6.1] - 2026-03-12

### Added

- `docs/self-evaluation-report-v3.6.0.md`: 插件多维度自评报告（9维度，综合 3.67/5）

### Changed

- `.gitignore`: 添加 Python 缓存文件排除规则（`__pycache__/`, `*.pyc`, `*.pyo`）

## [3.6.0] - 2026-03-12

### Added

- **TDD 确定性模式** (Batch C2): RED-GREEN-REFACTOR 循环，Iron Law 强制先测试后实现
  - `references/tdd-cycle.md`: 完整 TDD 协议（串行/并行/崩溃恢复）
  - `references/testing-anti-patterns.md`: 5 种反模式 + Gate Function 检查表
  - 并行 TDD L2 后置验证（合并后 full_test_command 验证）
  - Phase 4→5 TDD 门禁 + Phase 5→6 TDD 审计
  - TDD 崩溃恢复（per-task tdd_cycle 恢复点）
- **交互式快速启动向导** (P0): autopilot-init 3 预设模板 (strict/moderate/relaxed)
- **共享 Python 模块**: `_envelope_parser.py` (JSON 信封解析) + `_constraint_loader.py` (约束加载)
- **Bash 辅助函数**: `is_background_agent()`, `has_phase_marker()`, `require_python3()`
- **配置字段**: `tdd_mode`, `tdd_refactor`, `tdd_test_command`, `wall_clock_timeout_hours`, `hook_floors.*`, `default_mode`, `background_agent_timeout_minutes`

### Changed

- **配置外部化** (Batch B): 硬编码值提取到 config
  - Phase 5 超时: `7200` → `config.wall_clock_timeout_hours` (默认 2h)
  - 测试金字塔阈值: `30/40/10/80` → `config.hook_floors.*`
  - `validate-config.sh`: 新增 TYPE/RANGE/交叉引用验证
- **Hook 工程化重构** (Batch A): 6 个 PostToolUse Hook 使用共享模块，减少 287 行重复代码
  - importlib 路径改用 `os.environ['SCRIPT_DIR']` 安全注入
  - `validate-json-envelope.sh`: read_hook_floor 改用 `_ep.read_config_value`
- **TDD_MODE 懒加载**: lite/minimal 模式跳过 python3 fork (~50ms 优化)
- **parallel-merge-guard.sh**: 移除 stderr 静默 (2>/dev/null)，提高可调试性

### Fixed

- `configuration.md`: 补全 `default_mode` + `background_agent_timeout_minutes` 文档
- `configuration.md`: 统一 `parallel.max_agents` 默认值为 8
- `configuration.md`: 补全类型/范围验证规则表 (15 + 7 条)
- `autopilot-gate/SKILL.md`: Phase 1→5 门禁描述补 "ok 或 warning"
- `validate-decision-format.sh`: 补充 Phase 1 Task 无标记的设计意图注释
- `check-predecessor-checkpoint.sh`: Layer 1.5 补充 L2/L3 职责分工注释
- `write-edit-constraint-check.sh`: TDD 模式下 Phase 5 显式识别 (Phase 3 + tdd_mode)
