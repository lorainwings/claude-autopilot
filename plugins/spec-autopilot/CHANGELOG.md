# Changelog

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
