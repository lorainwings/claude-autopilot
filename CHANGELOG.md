# Changelog

All notable changes to the spec-autopilot plugin will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.5.0] - 2026-03-05

### Added
- **并行合并守卫 Hook**: 新增 `parallel-merge-guard.sh` PostToolUse Hook，在 Phase 5 worktree 合并后自动验证：无合并冲突残留（git diff --check）、合并文件在预期 task scope 内、快速类型检查通过。超时 150s，支持从 config.test_suites 读取 typecheck 命令
- **Write/Edit 代码约束 Hook**: 新增 `write-edit-constraint-check.sh` PostToolUse Hook，拦截 Phase 5 期间所有 Write/Edit 操作，实时检测禁止文件、禁止模式、目录范围、文件行数违规。超时 15s，使用 3 层快速旁路（lock file + phase check + file_path extract）
- **决策格式强制验证 Hook**: 新增 `validate-decision-format.sh` PostToolUse Hook，Phase 1 返回时强制验证 DecisionPoint 格式完整性。medium/large 复杂度必须包含 options（>=2）/pros/cons/recommended/choice/rationale，small 复杂度允许简化格式
- **项目规则自动扫描**: 新增 `rules-scanner.sh` 工具脚本，扫描 `.claude/rules/*.md` 和 `CLAUDE.md`，提取禁止项/必需项/命名约定，输出 JSON 供 Phase 5 dispatch 注入子 Agent prompt
- **联网调研能力**: Phase 1 Research Agent 增加 WebSearch/WebFetch 支持，可搜索最佳实践、同类实现、依赖评估。支持三级深度（basic 跳过、standard 2-3 次搜索、deep 5+ 次搜索含竞品对比）。产出结构化 research-findings.md 含 Web Research Findings 章节

### New Files
- `scripts/parallel-merge-guard.sh` — Phase 5 并行合并验证 Hook（150s 超时）
- `scripts/write-edit-constraint-check.sh` — Write/Edit 实时约束检查 Hook（15s 超时）
- `scripts/validate-decision-format.sh` — Phase 1 决策格式强制验证 Hook（30s 超时）
- `scripts/rules-scanner.sh` — 项目规则自动扫描工具

### Changed
- `hooks/hooks.json` — 新增 4 个 Hook 条目：parallel-merge-guard（PostToolUse Task, 150s）、write-edit-constraint-check（PostToolUse Write|Edit, 15s）、validate-decision-format（PostToolUse Task, 30s）
- `skills/autopilot/references/phase5-implementation.md` — 新增"并行合并验证 (Hook 级保障)"章节，文档化 Hook 触发条件、3 层验证表、确定性冲突检测、早期 typecheck 拦截、block 处理流程
- `skills/autopilot-dispatch/SKILL.md` — 新增优先级 2.5"Project Rules Auto-Scan"，Phase 5 dispatch 时自动运行 rules-scanner.sh 并注入约束到子 Agent prompt。增强 Phase 1 business-analyst 模板注入联网调研结果指令
- `skills/autopilot/references/phase1-requirements.md` — 新增 1.3.3"联网调研（Web Research）"章节，文档化技术方案搜索、依赖评估、产出格式、搜索策略（按深度分级）
- `skills/autopilot/references/protocol.md` — 增强 Phase 1 web_research 字段文档，新增 dependency_evaluation 和 recommended_approach 子字段
- `skills/autopilot-init/SKILL.md` — 新增 web_search 配置块到生成的 config 模板（enabled/max_queries/focus_areas）
- `skills/autopilot/SKILL.md` — 更新护栏约束表"结构化决策"行，标注 Hook 确定性强制执行（validate-decision-format.sh）
- `.claude-plugin/plugin.json` — 版本号升级到 2.5.0，description 增加 merge guard/decision enforcement/rules injection/web research，keywords 增加 merge-guard/write-edit-guard/rules-injection/web-research/decision-enforcement

### Enhanced
- **代码约束从 Task 级扩展到 Write/Edit 级**: 原 code-constraint-check.sh 仅检查 Phase 5 Task 返回的 artifacts，新增 write-edit-constraint-check.sh 在每次 Write/Edit 操作时实时拦截，覆盖子 Agent 内部的所有文件操作
- **决策协议从 SKILL 描述升级到 Hook 强制**: 原结构化决策仅在 SKILL.md 中要求，现由 validate-decision-format.sh Hook 确定性验证，medium/large 复杂度无法绕过
- **规则注入从手动到自动**: 原需手动在 instruction_files 中编写规则，现 Phase 5 dispatch 自动扫描 `.claude/rules/` 并注入，确保子 Agent 感知所有项目约束
- **并行执行从设计到实战**: 原 phase5-implementation.md 仅描述并行流程，现增加 parallel-merge-guard.sh Hook 提供确定性合并验证，包含冲突检测、scope 检查、typecheck 验证

### Fixed
- `parallel-merge-guard.sh` Python 代码中的多行 f-string 语法问题（bash heredoc 引号冲突），改用字符码 `\x22\x27` 避免转义冲突

## [2.4.0] - 2026-03-05

### Added
- **P0-1 并行执行引擎**: Phase 5 支持基于 git worktree 的并行 task 执行，通过 `config.phases.implementation.parallel.enabled` 启用。包含依赖图构建算法、Worktree 生命周期管理、并行 Checkpoint 管理、自动降级决策树
- **P0-2 结构化决策协议**: 决策点以结构化卡片呈现（选项/优劣/推荐/影响范围），medium/large 复杂度强制执行。DecisionPoint 格式增强支持 options、rationale、affected_components 字段
- **P1-1 代码约束 Hook**: 新增 PostToolUse hook `code-constraint-check.sh`，Phase 5 后自动检测项目规则违反（禁止文件/模式/目录范围/文件行数），支持从 `code_constraints` 配置或 CLAUDE.md 自动提取规则
- **P1-2 深度调研增强**: Phase 1 Research Agent 支持三级调研深度（basic/standard/deep），standard 以上包含多轮 Web 搜索，deep 包含同类实现对比和依赖深度分析（安全漏洞/许可证/维护活跃度）
- **P2-1 跨会话知识累积**: Phase 7 自动提取知识到 `openspec/.autopilot-knowledge.json`（decisions/pitfalls/patterns/optimizations），Phase 1 自动注入相关历史知识。支持 200 条上限和 FIFO 淘汰策略
- **P2-2 安全审计管道**: 新增 `check-security-tools-install.sh` 检测 npm audit/gitleaks/semgrep/trivy/OWASP DC，作为 Phase 6→7 异步质量扫描自动执行。Init 自动检测并配置安全审计

### New Files
- `scripts/code-constraint-check.sh` — Phase 5 代码约束 PostToolUse Hook
- `scripts/check-security-tools-install.sh` — 安全工具检测脚本
- `skills/autopilot/references/knowledge-accumulation.md` — 跨会话知识累积协议

### Changed
- `skills/autopilot/SKILL.md` — Phase 5 并行执行分支、Phase 7 知识提取、护栏约束增强
- `skills/autopilot-dispatch/SKILL.md` — 并行 Task Prompt 模板、决策协议注入
- `skills/autopilot/references/phase5-implementation.md` — 依赖图算法、Worktree 生命周期、降级决策树
- `skills/autopilot/references/phase1-requirements.md` — 结构化决策协议、深度调研、历史知识注入
- `skills/autopilot/references/protocol.md` — DecisionPoint 格式、web_research 格式、code_quality/parallel_metrics 字段
- `skills/autopilot/references/semantic-validation.md` — Phase 5→6 代码约束合规检查
- `skills/autopilot/references/quality-scans.md` — 安全审计扫描节
- `skills/autopilot-init/SKILL.md` — Step 2.6 安全工具检测、code_constraints 配置模板
- `hooks/hooks.json` — 新增 code-constraint-check.sh PostToolUse hook
- `scripts/collect-metrics.sh` — 知识库统计
- `.claude-plugin/plugin.json` — 版本号升级到 2.4.0

## [2.2.0] - 2026-03-04

### Added
- **Config `project_context`**: New config section for project-specific context (project_structure, test_credentials, playwright_login) auto-detected by init
- **Dynamic dispatch prompt**: Phase 4/5/6 sub-agent prompts now dynamically constructed from config + Phase 1 Steering Documents
- **Init Step 2.5**: Auto-detects test credentials, project structure, and Playwright login flow during config generation
- **Fallback chain**: Empty `project_context` fields supplemented by Phase 1 Auto-Scan at runtime

### Changed
- **`instruction_files` demoted to optional override**: No longer required for basic operation. Dispatch uses config fields + Phase 1 output as primary context
- **`autopilot-dispatch/SKILL.md`**: Rewritten dispatch template with 7-level context injection priority chain
- **`autopilot-init/SKILL.md`**: Added Step 2.5 (project context detection) and Step 4.1 (missing field prompts)
- **`integration-guide.md`**: Simplified from 8 steps to 7 steps, removed mandatory instruction file creation
- **`configuration.md`**: Added `project_context` section with project_structure, test_credentials, playwright_login
- **`validate-config.sh`**: Added type validation for project_context fields

## [2.1.0] - 2026-03-04

### Added
- **Phase 1 Auto-Scan**: Automatic project structure scanning generates Steering Documents (project-context.md, existing-patterns.md, tech-constraints.md) for persistent project context
- **Phase 1 Research Agent**: Dispatches Explore agent before discussion to analyze related code, dependency compatibility, technical feasibility → research-findings.md
- **Phase 1 Complexity Routing**: Auto-evaluates complexity (small/medium/large) based on research impact analysis, routes to appropriate discussion depth
- **Phase 1 enhanced business-analyst dispatch**: Injects Steering + Research context into requirements analysis agent for fact-based discussion
- **Large complexity forced socratic**: Complexity "large" forces socratic mode regardless of config setting
- **Integration guide**: New `docs/integration-guide.md` with step-by-step project onboarding, config examples for frontend/backend/monorepo scenarios
- **Config validation for Phase 1 fields**: `validate-config.sh` now validates `auto_scan`, `research`, `complexity_routing` configuration

### Changed
- `references/phase1-requirements.md`: Rewritten from 7-step to 10-step flow with auto-scan, research, and complexity routing
- `autopilot/SKILL.md`: Phase 1 summary updated to reflect 10-step enhanced flow
- `autopilot-dispatch/SKILL.md`: Added Phase 1 research and business-analyst dispatch templates
- `references/protocol.md`: Phase 1 checkpoint fields expanded with `complexity`, `research`, `steering_artifacts`
- `docs/phases.md`: Phase 1 section updated with complexity routing table, steering documents table, enhanced checkpoint format
- `docs/configuration.md`: Added `phases.requirements.auto_scan`, `research`, `complexity_routing` field references and validation rules
- `scripts/validate-config.sh`: Added type/range/cross-ref validation for new Phase 1 config fields

## [2.0.0] - 2026-03-04

### Added
- **Test pyramid floor validation** (Layer 2): Hook-level validation of unit/e2e percentage floors and minimum total test count
- **Config schema validation**: New `validate-config.sh` script validates `autopilot.config.yaml` required fields with PyYAML → regex fallback
- **Wall-clock timeout** (Hook layer): Phase 5 time limit (2h) enforced at PreToolUse hook level
- **Anti-rationalization hook**: Detects 10 rationalization patterns in Phase 4/5/6 output to prevent test/task skipping
- **Metrics collection**: `collect-metrics.sh` aggregates per-phase timing and retry data; `_metrics` field in checkpoints
- **Socratic mode** for Phase 1: Optional 6-step challenging question protocol for deep requirements analysis
- **Task-level checkpoint**: Per-task checkpoint files in `phase5-tasks/` for fine-grained Phase 5 crash recovery
- **Semantic validation protocol**: AI-level semantic checks beyond structural JSON validation
- **Brownfield validation**: Design-test-implementation drift detection for existing codebases (opt-in)
- **Professional documentation**: Complete README rewrite with Mermaid architecture diagrams
- **docs/ directory**: 5 detailed documentation files (architecture, configuration, gates, phases, troubleshooting)

### Changed
- `hooks.json`: Added PostToolUse anti-rationalization hook entry
- `plugin.json`: Enhanced metadata with new keywords and engine requirements
- `autopilot-gate/SKILL.md`: Added semantic and brownfield validation layers
- `autopilot-checkpoint/SKILL.md`: Added task-level checkpoint protocol and `_metrics` field documentation
- `autopilot/SKILL.md`: Added Phase 0 config validation and Phase 7 metrics collection

### Fixed
- N/A

## [1.9.0] - 2026-02-28

### Added
- Allure installation detection (`check-allure-install.sh`)
- Phase 7 checkpoint support
- SKILL.md refactored to reference files for better context management
- `references/` directory with protocol, phase1, phase5, quality-scans docs

### Changed
- Main `SKILL.md` reduced from ~500 lines to ~270 lines via reference extraction

## [1.8.0] - 2026-02-25

### Added
- Comprehensive plugin enhancement
- Phase 6 report format validation (allure/custom)
- `save-state-before-compact.sh` Phase 7 scan support

## [1.6.0] - 2026-02-20

### Fixed
- Comprehensive audit fixes P0-P3
- `zero_skip_check` Phase 5 validation
- Phase 5/6 test coverage improvements

## [1.5.0] - 2026-02-15

### Added
- Phase 4 gate enforcement
- Context compaction state persistence
- `PreCompact` and `SessionStart(compact)` hooks

## [1.0.0] - 2026-02-01

### Added
- Initial release
- 8-phase autopilot pipeline
- 3-layer gate system (TaskCreate blockedBy, Hook checkpoints, AI checklist)
- Crash recovery via checkpoint scanning
- Context compaction resilience
