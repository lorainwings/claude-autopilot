# Changelog

## [5.1.40] - 2026-03-20

### Fixed

- **TS2430 类型错误**: `ModelRoutingEvidence` 添加 `[key: string]: unknown` 索引签名，修复与 `AutopilotEvent.payload` (`Record<string, unknown>`) 的类型兼容性
- **Regex fallback phases 嵌套重建**: 无 PyYAML 时 `model_routing.phases.*` dotted keys 被正确重建为嵌套 dict，修复 macOS CI 下 C4/D1 测试失败

### Changed

- **Phase 5 默认路由升级为 deep/opus**: 代码实施阶段默认使用最强推理能力，同步更新升级链测试、多 phase 差异化测试、dispatch 技能说明、中英文配置文档

### Fixed

- **pre-commit hook 链路收敛**: `core.hooksPath` 指向 `.githooks`，消除 `.git/hooks/pre-commit` 旧实现的执行链路分裂
- **marketplace.json 版本同步改用 jq 确定性更新**: 按 `name == "spec-autopilot"` 精确匹配，取代脆弱的 sed 文本替换
- **jq 缺失 fail-closed**: pre-commit 缺少 jq 时硬阻断提交，不再静默跳过版本同步
- **README badge 兼容 shields.io pre-release 双横线**: sed 替换匹配 `version-X.Y.Z--beta.1-blue` 格式，grep 读取同步兼容，版本一致性校验不再漏检。`bump-version.sh` 同步对齐同一套正则
- **pre-release auto-bump fail-closed**: 版本号含 pre-release 后缀时先 strip 再 patch+1，PATCH 非整数时 exit 1 阻断；jq 更新失败时显式 exit 1
- **版本漂移回归测试加强**: 6a/6b 验证 stable 漂移同步，7a/7b/7c/7d 验证 pre-release auto-bump 含 README badge；jq 缺失时 FAIL 不 SKIP
- **E2E 测试仓库完整性**: Part 3/4/5 E2E 仓库均包含 marketplace.json + README badge + stub build-dist.sh

## [5.1.39] - 2026-03-20

### Fixed

- **hooks.json PostCompact 无效 key**: 移除不在 Claude Code 合法事件集合中的 `PostCompact` 顶级 key，将事件捕获迁移至 `SessionStart(compact)` handler 中 `reinject-state-after-compact.sh` 之前，保持 GUI 可观测性不变

### Added

- **hook key 白名单测试** (`test_hooks_json.sh` 6d): 断言所有顶级 hook key 必须属于 Claude 支持的 21 种事件类型，防止未来回归

## [5.1.38] - 2026-03-19

### Fixed

- **CI/Makefile 路径适配**: Makefile 和 `.github/workflows/test.yml` 中 `scripts/` → `runtime/scripts/`、`server/` → `runtime/server/`
- **测试相对路径修复**: 10 个测试文件中 `$SCRIPT_DIR/../skills` → `$SCRIPT_DIR/../../skills`（runtime/scripts/ 上两级到插件根目录）

## [5.1.37] - 2026-03-19

### Changed

- **架构重构 — 目录收敛**: `scripts/` → `runtime/scripts/`，`server/` → `runtime/server/`，dist 产物 `gui-dist/` → `assets/gui/`
- **Server 模块化**: 1181 行 `autopilot-server.ts` 拆分为 7 层 19 个 TS 模块 (`runtime/server/src/`)
- **增量快照引擎**: 字节偏移游标替代全量 size+mtime 缓存；journal 追加写入；session 切换时 cursor/journal 重置
- **构建脚本**: `build-dist.sh` 完整重写为 `runtime/` + `assets/gui` 目标结构，移除旧单文件回填
- **hooks.json**: 21 处路径更新至 `runtime/scripts/`
- **Skills**: 8 个 SKILL/reference 文件 35 处路径更新
- **Tests**: 74 个测试文件路径更新
- **文档同步**: 12 个用户面向文档中 22 处旧路径 + 6 处无效 CLI 参数 (`--ws-port`/`--http-port`) 修正

### Added

- **健壮性测试** (`test_server_robustness.sh`): 32 项覆盖多 session 切换、损坏 JSON 容错、raw-tail 增量游标、snapshot/journal 一致性、超长单行 JSONL

### Fixed

- **start-gui-server.sh**: 统一为 `runtime/server/` 单路径，移除旧双入口兼容逻辑

## [5.1.29] - 2026-03-19

### Fixed

- **Makefile lint/format 硬门禁**: 移除所有 `|| true`，工具报错时 `make lint` / `make format` 真正失败
- **CI lint 硬门禁**: 移除 `continue-on-error: true`，lint job 失败将阻断 CI
- **typecheck 开箱即用**: `make typecheck` 在 gui/server 缺 `node_modules` 时自动执行 `bun install`
- **setup 闭环**: `make setup` 同时安装 gui + server 依赖，新贡献者一键到位
- **shellcheck 警告**: 移除 case 模式冗余 (`*__tests__*` 已被 `*test*` 覆盖)，内嵌 Python 加 SC2140 disable
- **ruff lint**: 修复 E501 超长行 + F401 未使用导入，Python 文件统一 ruff format
- **pyproject.toml**: `select` 迁移至 `[tool.ruff.lint]` 消除 deprecated 警告
- **mypy 配置**: python_version 升至 3.9，disable `import-untyped`，修复 `spec_from_file_location` Optional 断言
- **shfmt 格式化**: 全量 shell 脚本统一 `shfmt -i 2 -ci` 格式（case/esac 缩进、`>>` 间距等）

### Changed

- **pre-commit staged lint**: 从 `|| true` 改为追踪失败状态 + 明确警告输出（非阻断快检，硬门禁在 `make lint` / CI）
- **server/package.json**: 移除冗余 `bun-types`，统一以 `@types/bun` 为准

## [5.1.28] - 2026-03-19

### Added

- **工程化配置**: 新增 `.editorconfig`（统一缩进/编码）、`.shellcheckrc`（bash lint 配置）、`pyproject.toml`（ruff + mypy）
- **Makefile 扩展**: 新增 `lint` / `format` / `typecheck` / `ci` 目标，工具缺失时优雅 `[skip]`
- **pre-commit 快检**: Part 1.7 staged 文件快速 shellcheck + shfmt + ruff 检查（警告模式）
- **CI 独立 job**: 新增 lint（shellcheck + shfmt + ruff + mypy）、typecheck、build-dist 三个独立 CI job

### Changed

- **GUI Server 分层**: `autopilot-server.ts` 及其 `package.json`/`tsconfig.json`/`bun.lock` 从 `scripts/` 迁移至新建 `server/` 目录
- **启动脚本双路径**: `start-gui-server.sh` 支持 dist 态（`scripts/`）和源码态（`server/`）双路径解析
- **构建回填**: `build-dist.sh` 自动将 `server/autopilot-server.ts` 回填到 `dist/scripts/`
- **Live docs 收口**: README、getting-started、operations 文档中 `scripts/autopilot-server.ts` 引用全部更新为 `server/autopilot-server.ts`

### Deprecated

- **兼容淘汰期**: 5 个 deprecated 脚本加完整 tombstone block，live docs 引用迁移到替代方案
  - `anti-rationalization-check.sh` / `code-constraint-check.sh` → `post-task-validator.sh` (v4.0)
  - `assertion-quality-check.sh` / `banned-patterns-check.sh` / `write-edit-constraint-check.sh` → `unified-write-edit-check.sh` (v5.1)
- `.dist-include` manifest 重组: deprecated 条目移至独立 "兼容窗口" 区块

## [5.1.27] - 2026-03-18

### Changed

- **Phase 1 — dev-only 工具迁出**: 将 `build-dist.sh`、`bump-version.sh`、`mock-event-emitter.js` 从 `scripts/` 迁移至新建 `tools/` 目录，使 `scripts/` 专注于运行时契约面
- **级联路径同步**: Makefile、pre-commit、测试、CLAUDE.md、CONTRIBUTING、README、架构文档中的所有引用路径已更新
- **构建纪律更正**: CLAUDE.md 构建白名单指引从已废弃的 EXCLUDE_SCRIPTS 改为 `scripts/.dist-include` manifest

## [5.1.26] - 2026-03-18

### Added

- **Runtime Manifest**: 新增 `scripts/.dist-include` 运行时发布清单，45 个文件显式声明
- **Manifest 一致性测试**: 新增 `test_runtime_manifest.sh`（9 项断言，fixture 自洽，不依赖外部 dist/ 状态）
- **负向回归测试**: `test_build_dist.sh` 补充 3 个 manifest 护栏失败路径测试
- **重构蓝图**: 新增 `docs/roadmap/2026-03-18-scripts-engineering-refactor-blueprint.md`

### Changed

- **构建逻辑 manifest 化**: `build-dist.sh` 从排除式复制改为 manifest 逐项复制，新增 hooks→manifest 交叉校验 + dist 纯净度校验
- **dist 纯净化**: 从发布包清除 6 个 dev-only 文件（mock-event-emitter.js, tsconfig.json, package.json, bun.lock, build-dist.sh, bump-version.sh）

## [5.1.25] - 2026-03-18

### Added

- **中文贡献文档**: 新增 `CONTRIBUTING.zh.md`，并为贡献文档补齐中英文切换入口
- **事件总线 API 中文参考**: 新增 `event-bus-api.zh.md` 并同步到源码与 dist

### Fixed

- **Make 工作流文档统一**: 顶层 README、插件 README、贡献指南统一改为 `make setup` / `make test` / `make build`
- **文档事实修正**: 修正测试规模、目录结构、Hook 入口和配置说明，去除过时的独立 Hook 描述
- **排障文档准确性**: 本地 Hook 调试示例改为 `post-task-validator.sh`，语法检查示例恢复为真实的 `bash -n` 循环
- **fresh clone 构建回退**: `build-dist.sh` 在 `plugins/spec-autopilot/gui-dist` 缺失时，可从 `dist/spec-autopilot/gui-dist` 恢复并继续构建
- **构建回退测试覆盖**: 新增 fresh-clone GUI 恢复用例，并补充 `guard-no-verify` 测试注释说明

## [5.1.24] - 2026-03-18

### Added

- **Makefile**: `make setup` / `make test` / `make build` 入口，降低新贡献者上手门槛

### Fixed

- **E2E 测试精度**: 验证 commit 被精确的 CHANGELOG 门禁阻断（非任意非零退出），修复假仓库 `.claude-plugin/` 目录结构

## [5.1.23] - 2026-03-18

### Added

- **`guard-no-verify.sh`**: Claude Code PreToolUse(Bash) 守卫，拦截 `--no-verify`/`-n`/`commit.noVerify`/`HUSKY=0` 四种 hook 绕过模式，仅作用于本仓库
- **`scripts/setup-hooks.sh`**: Hook 激活脚本，一键设置 `core.hooksPath=.githooks`，支持 fresh clone 可重复部署
- **`test_guard_no_verify.sh`**: 19 条回归测试，含 E2E fresh-repo 仿真验证完整门禁链

### Fixed

- **Hook 激活链断裂**: `.githooks/pre-commit` 已跟踪但 `core.hooksPath` 未设置，实际生效的是旧版 `.git/hooks/pre-commit`（仅匹配 `.sh|.json`），导致 `.ts` 等文件变更绕过测试门禁
- **跨平台 sed**: `.githooks/pre-commit` 中 5 处 `sed -i ''`（BSD only）替换为 `sedi()` 跨平台包装函数
- **CONTRIBUTING.md**: Setup 步骤新增 `bash scripts/setup-hooks.sh` 要求

## [5.1.22] - 2026-03-18

### Added

- **`/api/raw-tail` 游标增量端点**: 支持 cursor/lines 参数的增量日志拉取，替代全量 `/api/raw` 轮询
- **虚拟滚动**: TranscriptPanel 和 ToolTracePanel 使用 `@tanstack/react-virtual` 窗口化渲染
- **Store 预计算分类数组**: `transcriptEvents` / `toolEvents` 在 `addEvents` 中预过滤，避免渲染时重复 filter
- **Vite 代码分割**: `manualChunks` 分离 vendor-react (193kB) 和 vendor-virtual (16kB)，主 chunk 降至 346kB
- **跨 session journal 测试**: 新增 sess-a/sess-b 独立性、路径脱敏、raw-tail 游标验证用例

### Fixed

- **服务器绑定安全**: `Bun.serve` 双端口绑定 `127.0.0.1`，阻止外部网络访问
- **CORS 限制**: 替换 `Access-Control-Allow-Origin: *` 为 localhost 来源白名单
- **API 层路径脱敏**: 所有 API 出口对绝对路径做 `~/` 替换，机密字段 (apiKey/token/secret) 直接 redact
- **Journal 跳过条件**: 全局 `lastJournalEventCount` 改为 per-session `Map`，修复跨 session 同事件数互相跳过
- **RawInspectorPanel 全量轮询**: 改用游标增量拉取，累积最近 500 行

## [5.1.21] - 2026-03-17

### Added

- **补充 v5.1.18 评测文档集**: 新增 `architecture-and-workflow-evolution.md`、`competitive-analysis.md`、`performance-benchmark.md`、`phase1-benchmark.md`、`phase5-codegen-audit.md`、`phase6-tdd-audit.md`、`stability-audit.md`

## [5.1.19] - 2026-03-17

### Added

- **新增定向回归测试**: `test_build_dist.sh`、`test_collect_metrics.sh`、`test_poll_gate_decision.sh`、`test_run_all.sh`，覆盖分发完整性、最新 checkpoint 选择、override 安全限制和测试聚合器误报场景
- **全维度评测报告**: 新增 `docs/reports/v5.1.18/holistic-evaluation-report-v5.1.18.md`

### Fixed

- **Phase 7 运行时缺脚本**: `build-dist.sh` 现在会将 `collect-metrics.sh` 一并打包进 dist，修复运行时缺失
- **CI GUI 构建脆弱性**: `build-dist.sh` 仅在 `bun` 和 `gui/node_modules` 同时存在时才重建 GUI；无依赖环境回退到已提交的 `gui-dist`
- **测试总控假绿**: `tests/run_all.sh` 现在会识别测试脚本输出中的 `FAIL:` 行，即使退出码错误地为 0 也会判定失败
- **危险 override 通道**: `poll-gate-decision.sh` 对 full Phase 5、full/lite Phase 6 禁止 override，并在请求 JSON 中显式输出 `override_allowed`
- **GUI 门禁误导**: `GateBlockCard.tsx` 在禁止 override 的门禁场景下禁用按钮并显示警示信息
- **指标采集读取旧 checkpoint**: `collect-metrics.sh` 改为按文件修改时间选择最新 checkpoint，而非按文件名排序
- **macOS Bash 3.2 兼容性**: `clean-phase-artifacts.sh` 移除 `mapfile` 依赖，修复 preserve-path stdin 读取和 stash 输出污染问题

## [5.1.18] - 2026-03-17

### Added

- **recovery-decision.sh**: 确定性恢复扫描脚本（纯只读 JSON 输出），提供完整的 checkpoint/interim/progress/git 状态扫描
- **clean-phase-artifacts.sh**: 统一制品清理脚本（文件清理 + 事件过滤 + git 回退），支持 `--dry-run` 和 `--git-target-sha`
- **_common.sh 新增函数**: `get_phase_sequence()` / `get_next_phase_in_sequence()` / `read_phase_commit_sha()` / `get_gap_phases()`
- **三选项恢复**: autopilot-recovery SKILL 重构为（断点继续 / 指定阶段恢复 / 从头开始）
- **Phase 跳过机制**: Phase 1 跳过规则 + Phases 2-6 Step -1 前置检查
- **新增测试**: `test_clean_phase_artifacts.sh` (27 cases) + `test_recovery_decision.sh` (24 cases) + e2e 扩展 (10 cases)

### Fixed

- **Gap 感知**: `last_valid_phase` 在首个缺口处停止，`continue.phase` 指向缺口而非跳过
- **Mode 一致性**: lockfile mode 优先于 CLI 入参用于扫描序列
- **Interim/progress 驱动决策**: `has_checkpoints` 含 interim/progress，`sub_step` 注入到 recovery_options
- **Git 操作归属检查**: rebase/merge abort 仅限 autopilot 相关操作
- **Stash 安全**: `-u` 含 untracked + count 验证 + 失败跳过 reset + 自动 restore
- **Worktree 清理**: 限定 change_name 范围，不影响其他会话
- **read_phase_commit_sha Tier 2**: 加入 change_name 限制，避免多 change 场景匹配错误
- **顶层 local**: 移除函数外 local 声明
- **specify_range**: 仅含实际完成阶段（排除 gap 阶段）
- **progress-only 恢复**: 用 max(progress_phase) 而非硬编码 Phase 1

### Changed

- **autopilot-phase0 Step 7**: 任务标记改为 P < recovery → completed, P == recovery → in_progress, P > recovery → pending

## [5.1.15] - 2026-03-16

### Added

- **GUI Reset 信号**: autopilot-server 检测 events.jsonl 截断（重新开始场景），广播 `reset` 消息通知 GUI 清空状态
- **WSBridge onReset**: ws-bridge 新增 `resetHandlers` + `onReset()` 方法处理 reset 消息类型
- **SKILL.md Step 6.1**: Phase 0 崩溃恢复新增事件文件清理协议（从头开始 → 清空 events.jsonl + 重发 phase_start）

### Fixed

- **崩溃恢复时间线错乱**: `selectPhaseDurations` / `selectTotalElapsedMs` 使用 `findLast` 取最新 start/end 事件，修复同一 Phase 多次 start 导致的时间计算错误
- **时间顺序校验**: end 事件必须在 start 之后才算完成，避免旧 end 覆盖新 start
- **reset 不断连**: `store.reset()` 不再重置 `connected` 状态（reset 由 WS 消息触发，连接仍然活跃）
- **autopilot-server lastByteOffset 回退**: 文件大小小于偏移量时重置为 0，避免截断后读取失败

## [5.1.14] - 2026-03-15

### Added

- **全维度工业级仿真评测报告**: 六维度并行评估 (编排架构/效能并行/TDD引擎/GUI鲁棒/DX成熟度/竞品对比)，综合评分 85/100 (A-)
- **模式路由表**: 新增 `mode-routing-table.md` 声明式配置 Full/Lite/Minimal 三种模式的阶段序列
- **迁移文档**: 新增 `docs/migration/v4-to-v5.md` 中英文迁移指南
- **新增测试**: `test_hook_preamble.sh` / `test_post_task_validator.sh` / 集成测试 (`test_e2e_checkpoint_recovery.sh`, `test_e2e_hook_chain.sh`)

### Changed

- **_common.sh 增强**: mkdir 原子锁替代 flock / date +%N fallback / 新增工具函数
- **_config_validator.py 扩展**: 交叉验证规则扩展，覆盖更多配置边界
- **SKILL.md 编排优化**: autopilot/dispatch/gate/recovery 四大 Skill 文档更新

### Fixed

- **_config_validator.py regex fallback 兼容**: 修复无 PyYAML 环境下 `required_test_types` YAML 列表解析为字符串、`domain_agents` 嵌套字典解析为 True 导致交叉验证跳过的问题
- **SKILL.md 脚本路径修复**: 将所有 `${PLUGIN_ROOT}` 统一为 `${CLAUDE_PLUGIN_ROOT}`（Claude Code 平台注入的环境变量），修复 Phase 0 validate-config.sh / start-gui-server.sh / emit-phase-event.sh 等脚本 "No such file or directory" 错误

## [5.1.13] - 2026-03-15

### Added

- **Agent 生命周期自动事件**: 新增 `auto-emit-agent-dispatch.sh` / `auto-emit-agent-complete.sh` Hook，自动为 autopilot Task 发射 agent_dispatch/complete 事件（无需手动调用 emit-agent-event.sh）
- **子步骤进度追踪**: 新增 `write-phase-progress.sh`，写入 `phase-{N}-progress.json` 实现比 checkpoint 更细粒度的崩溃恢复
- **阶段上下文快照**: 新增 `save-phase-context.sh`，每个 Phase 结束时保存关键决策/约束/产出摘要到 `phase-context-snapshots/`
- **GUI ParallelKanban 可展开 Agent 卡片**: 点击展开显示耗时、产出文件、工具调用列表（最近 20 条）
- **GUI VirtualTerminal Agent ID 筛选**: 新增"指定 Agent"过滤器，支持按 Agent ID 查看关联事件
- **tool_use ↔ Agent 关联**: `emit-tool-event.sh` 读取 `.active-agent-id` marker，为 tool_use 事件注入 agent_id 字段

### Changed

- **Recovery 子步骤恢复**: `autopilot-recovery` SKILL 新增 progress.json 扫描，支持 step 级恢复（research_dispatched、ba_complete、gate_passed 等）
- **Recovery Git 检测**: 扫描时检测 `.git/rebase-merge` 中间态和 autopilot worktree 残留
- **Compact 上下文保护**: `save-state-before-compact.sh` 包含 phase context snapshots；`reinject-state-after-compact.sh` 恢复最新快照
- **Store AgentInfo 扩展**: 新增 `output_files` 字段，`selectAgentIds` selector

## [5.1.12] - 2026-03-15

### Added

- **全量工具调用日志**: 新增 `emit-tool-event.sh` PostToolUse catch-all hook，每次工具调用自动记录 `tool_use` 事件到 events.jsonl（纯 bash 快速路径，无 autopilot 会话时 0 开销）
- **Agent 生命周期事件**: 新增 `emit-agent-event.sh`，发射 `agent_dispatch` / `agent_complete` 事件；SKILL.md 统一调度模板新增 Step 2.5 + Step 4.5
- **VirtualTerminal 下拉过滤器**: 7 类别（全部/阶段生命周期/门禁/Agent/工具调用/任务进度/错误），替换原 `[全部]` 占位文字
- **ParallelKanban Agent 卡片**: 显示 agent_label、状态徽章（spinner/checkmark/x）、耗时、摘要
- **Store agentMap 状态管理**: 处理 agent_dispatch/agent_complete 事件，phase_end/error 自动清理残留 dispatched Agent
- **Event Bus API 文档**: 新增 `tool_use`、`agent_dispatch`、`agent_complete` 类型定义

### Fixed

- **Phase 0 耗时显示 "--ms"**: store selectPhaseDurations/selectTotalElapsedMs 新增时间戳差值 fallback；SKILL.md phase0 补充 `duration_ms` 到 phase_end payload
- **总累计耗时不动态更新**: TelemetryDashboard/PhaseTimeline 的 tick 加入 useMemo deps，使 Date.now() 基于的计算每秒重算
- **Logo 显示 &hexmark;**: `&hexmark;` 非合法 HTML entity，改为 Unicode ⬡ (U+2B21)
- **版本号缓存不更新**: autopilot-server.ts index.html Cache-Control 改 `no-store`；build-dist.sh 构建后自动 pkill 旧 server 进程

## [5.1.11] - 2026-03-15

### Fixed

- **macOS Event Bus 崩溃**: `flock` 命令 macOS 不存在导致 `next_event_sequence` 永远走 fallback，`date +%N` 在 BSD date 输出字面量 `N`（exit 0 不报错）导致 sequence 含非数字字符，Python `int()` 转换失败 → 事件发射全部崩溃
- **GUI 不可用**: Event Bus 崩溃的级联后果，修复后 GUI 可正常启动

### Changed

- **跨平台原子锁**: `flock` 替换为 `mkdir` 原子锁（POSIX 标准，Linux/macOS 均可用）
- **`date +%N` 安全回退**: 检测输出是否为纯数字，非数字时使用 `$RANDOM`

## [5.1.9] - 2026-03-15

### Fixed

- **GUI 无数据反馈**: Phase 0/1/7 补充 `emit-phase-event.sh` 调用，修复 GUI 在 Phase 2 前无任何事件数据的问题
- **GUI 版本号不同步**: `build-dist.sh` 新增 GUI 自动构建步骤，确保 `__PLUGIN_VERSION__` 与 `plugin.json` 始终一致

### Changed

- **Phase 0 Banner 合并 GUI 地址**: 启动 Banner 新增 `GUI` 行，展示 `http://localhost:9527`，不再单独输出 GUI 启动提示
- **event-bus-api.md**: 更新 `emit-phase-event.sh` 调用时机，覆盖全部 Phase 0-7

## [5.1.8] - 2026-03-15

### Fixed

- **tsconfig.json bun-types 声明错误**: 移除 `"types": ["bun-types"]`，`@types/bun` 已安装无需显式指定

### Added

- **TypeScript 配置纪律**: CLAUDE.md 新增 TypeScript 配置规范章节
- **v5.1.7 全维度评测报告**: 六维度全栈深度评测（总评 87.3/100）+ 14 条静默盲点清单

### Changed

- **pre-commit hook 全量触发**: 触发条件从 `*.sh|*.json` 扩大到所有 plugin 文件，确保 `.md/.ts/.py` 变更也执行完整构建+测试
- **发版纪律**: CLAUDE.md 新增"推送前必须完整构建+测试"条目

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
