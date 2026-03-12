# Changelog

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
