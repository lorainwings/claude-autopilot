# Configuration Reference

> Complete YAML field reference for `.claude/autopilot.config.yaml`.

## Top-Level Fields

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `version` | string | Yes | — | Config schema version (currently `"1.0"`) |
| `services` | object | Yes | — | Service definitions for health checks |
| `phases` | object | Yes | — | Phase-specific configuration |
| `test_suites` | object | Yes | — | Test suite definitions |
| `test_pyramid` | object | Recommended | See below | Test distribution thresholds |
| `gates` | object | Recommended | See below | User confirmation gates |
| `context_management` | object | Recommended | See below | Git and context protection settings |
| `async_quality_scans` | object | Optional | See below | Phase 6→7 quality scan configuration |
| `brownfield_validation` | object | Optional | See below | Brownfield drift detection (opt-in) |
| `default_mode` | string | No | `"full"` | Default execution mode: `"full"`, `"lite"`, or `"minimal"` |
| `background_agent_timeout_minutes` | number | No | `30` | Hard timeout (minutes) for all background agents (Phase 2/3/6.5/7 knowledge extraction) |
| `project_context` | object | Recommended | See below | Project-specific context for sub-agent dispatch (auto-detected by init) |

## `services`

Each service entry:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `health_url` | string | Yes | URL for health check (must start with `http://` or `https://`) |
| `name` | string | No | Display name for the service |

```yaml
services:
  backend:
    health_url: "http://localhost:8080/actuator/health"
    name: "Backend Service"
  frontend:
    health_url: "http://localhost:5173/"
    name: "Frontend Dev Server"
```

## `phases`

### `phases.requirements`

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `agent` | string | Yes | — | Sub-agent type for requirements analysis |
| `min_qa_rounds` | number | No | `1` | Minimum Q&A rounds before confirmation |
| `mode` | string | No | `"structured"` | `"structured"` or `"socratic"` — socratic mode uses 6-step challenging questions |
| `auto_scan.enabled` | boolean | No | `true` | Enable auto-scan of project structure to generate Steering Documents |
| `auto_scan.max_depth` | number | No | `2` | Directory tree scan depth for module layout |
| `research.enabled` | boolean | No | `true` | Enable research agent for technical feasibility analysis before discussion |
| `research.agent` | string | No | `"Explore"` | Sub-agent type for research (Explore is fast and read-only) |
| `complexity_routing.enabled` | boolean | No | `true` | Enable automatic complexity assessment and discussion depth routing |
| `complexity_routing.thresholds.small` | number | No | `2` | Max files for "small" complexity (quick-confirm mode) |
| `complexity_routing.thresholds.medium` | number | No | `5` | Max files for "medium" complexity (standard discussion) |

### `phases.testing`

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `agent` | string | Yes | — | Sub-agent type for test design |
| `instruction_files` | array | No | `[]` | Paths to test design instruction files |
| `reference_files` | array | No | `[]` | Paths to reference files for test design |
| `gate.min_test_count_per_type` | number | Yes | — | Minimum tests per type (Layer 3 threshold) |
| `gate.required_test_types` | array | Yes | — | Required test types (e.g., `[unit, api, e2e, ui]`) |

### `phases.implementation`

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `instruction_files` | array | No | `[]` | Paths to implementation instruction files |
| `serial_task.max_retries_per_task` | number | Yes | 3 | Max retry attempts per task on failure |
| `wall_clock_timeout_hours` | number | No | `2` | Phase 5 wall-clock timeout in hours (supports decimals, e.g. `0.5`) |
| `tdd_mode` | boolean | No | `false` | Enable TDD RED-GREEN-REFACTOR cycle (full mode only) |
| `tdd_refactor` | boolean | No | `true` | Include REFACTOR step in TDD cycle |
| `tdd_test_command` | string | No | `""` | Override test command for TDD (uses test_suites if empty) |
| `worktree.enabled` | boolean | No | `false` | Enable git worktree isolation per task |
| `parallel.enabled` | boolean | No | `false` | 启用 Phase 5 并行 Agent Team 执行 |
| `parallel.max_agents` | number | No | `8` | 最大并行 Agent 数量（建议 2-4） |
| `parallel.dependency_analysis` | boolean | No | `true` | 是否自动分析 task 依赖关系 |

### `phases.reporting`

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `instruction_files` | array | No | `[]` | Paths to reporting instruction files |
| `format` | string | No | `"allure"` | Report format: `"allure"` or `"custom"` |
| `report_commands.html` | string | No | — | HTML report generation command |
| `report_commands.markdown` | string | No | — | Markdown report generation command |
| `report_commands.allure_generate` | string | No | — | Allure report generation command |
| `coverage_target` | number | Yes | — | Target test coverage percentage (0-100) |
| `zero_skip_required` | boolean | Yes | — | Whether zero skipped tests is required |

### `phases.code_review`

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `enabled` | boolean | No | `true` | 是否启用 Phase 6.5 代码审查 |
| `auto_fix_minor` | boolean | No | `false` | 是否自动修复 minor findings |
| `block_on_critical` | boolean | No | `true` | critical findings 是否阻断流水线 |
| `skip_patterns` | array | No | `["*.md", "*.json", "openspec/**"]` | 跳过审查的文件模式 |

## `test_pyramid`

Layer 2 (Hook) enforces lenient floors; Layer 3 (AI gate) enforces strict config values. Hook floors are configurable via `test_pyramid.hook_floors`.

| Field | Type | Default | Hook Floor Default | Description |
|-------|------|---------|------------|-------------|
| `min_unit_pct` | number | `50` | `30` | Minimum unit test percentage |
| `max_e2e_pct` | number | `20` | `40` | Maximum E2E test percentage |
| `min_total_cases` | number | `20` | `10` | Minimum total test cases |

### `test_pyramid.hook_floors`

Optional overrides for Layer 2 Hook floor thresholds. These are the lenient minimums enforced by `validate-json-envelope.sh`. The Hook floor must not be stricter than the Layer 3 strict threshold (cross-validated by `validate-config.sh`).

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `min_unit_pct` | number | `30` | Hook floor: minimum unit test percentage |
| `max_e2e_pct` | number | `40` | Hook floor: maximum E2E test percentage |
| `min_total_cases` | number | `10` | Hook floor: minimum total test cases |
| `min_change_coverage_pct` | number | `80` | Hook floor: minimum change coverage percentage |

```yaml
test_pyramid:
  min_unit_pct: 50     # Layer 3 strict (config)
  max_e2e_pct: 20      # Layer 3 strict (config)
  min_total_cases: 20   # Layer 3 strict (config)
  hook_floors:          # Layer 2 lenient (configurable)
    min_unit_pct: 30
    max_e2e_pct: 40
    min_total_cases: 10
    min_change_coverage_pct: 80
```

## `gates`

### `gates.user_confirmation`

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `after_phase_1` | boolean | `true` | Pause for user review after requirements |
| `after_phase_3` | boolean | `false` | Pause after design generation |
| `after_phase_4` | boolean | `false` | Pause after test design |

## `context_management`

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `git_commit_per_phase` | boolean | `true` | Auto git fixup commit after each phase |
| `autocompact_pct` | number | `80` | Recommended `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` value |
| `squash_on_archive` | boolean | `true` | Autosquash fixup commits on Phase 7 archive |

## `brownfield_validation`

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `enabled` | boolean | `false` | Enable drift detection (opt-in for existing codebases) |
| `strict_mode` | boolean | `false` | `true`: block on drift; `false`: warning only |
| `ignore_patterns` | array | `["*.test.*", "*.spec.*", "__mocks__/**"]` | File patterns to ignore |

## `project_context`

Project-specific context auto-detected by `autopilot-init`. Dispatch dynamically injects these values into sub-agent prompts, **eliminating the need for separate instruction files in most cases**.

### `project_context.project_structure`

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `backend_dir` | string | `""` | Backend source directory (e.g., `"backend"`) |
| `frontend_dir` | string | `""` | Frontend source directory (e.g., `"frontend/web-app"`) |
| `node_dir` | string | `""` | Node service directory (e.g., `"node"`) |
| `test_dirs.unit` | string | `""` | Unit test directory path |
| `test_dirs.api` | string | `""` | API test directory path |
| `test_dirs.e2e` | string | `""` | E2E test directory path |
| `test_dirs.ui` | string | `""` | UI test directory path |

### `project_context.test_credentials`

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `username` | string | `""` | Test account username. Empty → Phase 1 Auto-Scan discovers |
| `password` | string | `""` | Test account password. Empty → Phase 1 Auto-Scan discovers |
| `login_endpoint` | string | `""` | Login API endpoint (e.g., `"POST /api/auth/login"`) |

> **Security note**: These are test/dev credentials only. Do not use production credentials.

### `project_context.playwright_login`

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `steps` | string | `""` | Multi-line login flow description (auto-detected from Login component) |
| `known_testids` | array | `[]` | data-testid attributes found in Login component |

> All `project_context` fields are **optional**. Empty fields are supplemented by Phase 1 Auto-Scan + Research Agent at runtime.

## `routing_overrides` (Phase 1 自动生成, v4.2)

Phase 1 完成后自动写入 checkpoint，供 L2 Hook 在后续阶段读取。**无需手动配置**。

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `requirement_type` | string\|array | `"feature"` | 需求分类: `"feature"`, `"bugfix"`, `"refactor"`, `"chore"`, 或数组 `["feature","bugfix"]` |
| `sad_path_min_pct` | number | `20` | Sad path 测试最低比例 (bugfix 自动提升至 40) |
| `change_coverage_min_pct` | number | `80` | 变更覆盖率最低值 (bugfix/refactor 自动提升至 100) |
| `require_reproduction_test` | boolean | `false` | 是否要求复现测试 (bugfix 自动启用) |
| `require_behavior_preservation_test` | boolean | `false` | 是否要求行为保持测试 (refactor 自动启用) |

> `routing_overrides` 存储在 Phase 1 checkpoint (`phase-1-requirements.json`) 中，不是 `autopilot.config.yaml` 的字段。记录在此是因为 L2 Hook 的验证逻辑依赖它。

## `code_constraints` (v4.2)

项目级代码约束，由 L2 Hook (`unified-write-edit-check.sh`, v5.1) 在 Write/Edit 时强制执行。

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `forbidden_files` | array | `[]` | 禁止修改的文件路径列表 (支持 glob，如 `["*.lock", "package-lock.json"]`) |
| `forbidden_patterns` | array | `[]` | 禁止出现的代码模式 (正则，如 `["TODO", "FIXME", "HACK"]`) |
| `allowed_dirs` | array | `[]` | 允许写入的目录白名单（为空则不限制） |

```yaml
code_constraints:
  forbidden_files:
    - "package-lock.json"
    - "*.lock"
  forbidden_patterns:
    - "TODO"
    - "FIXME"
    - "HACK"
    - "console\\.log"
  allowed_dirs:
    - "src/"
    - "tests/"
```

> `forbidden_patterns` 中的 `TODO/FIXME/HACK` 由 `unified-write-edit-check.sh` (v5.1) 确定性拦截，不依赖 AI 判断。

## GUI 与事件总线 (v5.0.8)

GUI 大盘通过 `autopilot-server.ts` 提供双模服务，无需在 `autopilot.config.yaml` 中配置。

### 服务器命令行参数

```bash
bun run scripts/autopilot-server.ts [options]
```

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `--http-port` | `9527` | HTTP 静态资源端口 |
| `--ws-port` | `8765` | WebSocket 实时推送端口 |
| `--events-file` | `logs/events.jsonl` | 事件文件路径 |

### 端口映射

| 协议 | 端口 | 用途 |
|------|------|------|
| HTTP | 9527 | Vite 构建产出的静态资源 (三栏布局 GUI) |
| WebSocket | 8765 | 实时事件推送 + decision_ack 回传 |

> GUI 为可选组件，不影响 CLI 模式下的功能。

## `async_quality_scans`

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `timeout_minutes` | number | `10` | Hard timeout for scan completion |

Each scan type (`contract_testing`, `performance_audit`, `visual_regression`, `mutation_testing`):

| Field | Type | Description |
|-------|------|-------------|
| `check_command` | string | Command to check if tool is installed |
| `install_command` | string | Command to install the tool |
| `command` | string | Command to run the scan |
| `threshold` | string/number | Pass threshold |

## `test_suites`

Each test suite entry:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `command` | string | Yes | Command to run the test suite |
| `type` | string | Yes | One of: `unit`, `integration`, `e2e`, `ui`, `typecheck` |
| `allure` | string | Yes | One of: `pytest`, `playwright`, `junit_xml`, `none` |
| `allure_post` | string | No | Post-processing command (only when `allure=junit_xml`) |

```yaml
test_suites:
  backend_unit:
    command: "cd backend && ./gradlew test"
    type: unit
    allure: junit_xml
    allure_post: 'cp -r backend/build/test-results/test/*.xml "$ALLURE_RESULTS_DIR/"'
  api_test:
    command: "python3 -m pytest tests/api/ -v"
    type: integration
    allure: pytest
  e2e:
    command: "npx playwright test"
    type: e2e
    allure: playwright
```

## Schema Validation

Run `validate-config.sh` to check your config:

```bash
bash plugins/spec-autopilot/scripts/validate-config.sh /path/to/project
```

Output:
```json
{
  "valid": true,
  "missing_keys": [],
  "type_errors": [],
  "range_errors": [],
  "cross_ref_warnings": [],
  "warnings": []
}
```

### 验证层级

| 层级 | 检查内容 | 影响 `valid` |
|------|---------|-------------|
| **必需字段** | 顶级和嵌套 key 存在性 | Yes — `valid: false` |
| **类型验证** | 字段值的数据类型（string/number/boolean） | Yes — `valid: false` |
| **范围验证** | 数值是否在合理范围内 | No — 仅 `range_errors` 非空 |
| **交叉引用** | 字段间逻辑一致性 | No — 仅 `cross_ref_warnings` 非空 |
| **推荐字段** | 可选但建议配置的字段 | No — 仅 `warnings` 非空 |

### 类型验证规则

| 字段路径 | 期望类型 |
|----------|---------|
| `version` | string |
| `phases.requirements.auto_scan.enabled` | boolean |
| `phases.requirements.auto_scan.max_depth` | number |
| `phases.requirements.research.enabled` | boolean |
| `phases.requirements.research.agent` | string |
| `phases.requirements.complexity_routing.enabled` | boolean |
| `phases.requirements.complexity_routing.thresholds.small` | number |
| `phases.requirements.complexity_routing.thresholds.medium` | number |
| `phases.implementation.serial_task.max_retries_per_task` | number |
| `phases.reporting.coverage_target` | number |
| `phases.code_review.enabled` | boolean |
| `phases.implementation.parallel.enabled` | boolean |
| `phases.implementation.parallel.max_agents` | number |
| `phases.requirements.min_qa_rounds` | number |
| `phases.reporting.zero_skip_required` | boolean |
| `test_pyramid.min_unit_pct` | number |
| `test_pyramid.max_e2e_pct` | number |
| `test_pyramid.min_total_cases` | number |
| `phases.implementation.wall_clock_timeout_hours` | number |
| `phases.implementation.tdd_mode` | boolean |
| `phases.implementation.tdd_refactor` | boolean |
| `phases.implementation.tdd_test_command` | string |
| `test_pyramid.hook_floors.min_unit_pct` | number |
| `test_pyramid.hook_floors.max_e2e_pct` | number |
| `test_pyramid.hook_floors.min_total_cases` | number |
| `test_pyramid.hook_floors.min_change_coverage_pct` | number |
| `default_mode` | string |
| `code_constraints.forbidden_files` | array |
| `code_constraints.forbidden_patterns` | array |
| `code_constraints.allowed_dirs` | array |
| `background_agent_timeout_minutes` | number |

### 范围验证规则

| 字段路径 | 范围 |
|----------|------|
| `phases.testing.gate.min_test_count_per_type` | [1, 100] |
| `phases.implementation.serial_task.max_retries_per_task` | [1, 10] |
| `phases.reporting.coverage_target` | [0, 100] |
| `test_pyramid.min_unit_pct` | [0, 100] |
| `test_pyramid.max_e2e_pct` | [0, 100] |
| `phases.implementation.parallel.max_agents` | [1, 10] |
| `async_quality_scans.timeout_minutes` | [1, 120] |
| `phases.requirements.auto_scan.max_depth` | [1, 5] |
| `phases.requirements.complexity_routing.thresholds.small` | [1, 20] |
| `phases.requirements.complexity_routing.thresholds.medium` | [2, 50] |
| `test_pyramid.min_total_cases` | [1, 1000] |
| `phases.implementation.wall_clock_timeout_hours` | [0.1, 24] |
| `test_pyramid.hook_floors.min_unit_pct` | [0, 100] |
| `test_pyramid.hook_floors.max_e2e_pct` | [0, 100] |
| `test_pyramid.hook_floors.min_total_cases` | [1, 1000] |
| `test_pyramid.hook_floors.min_change_coverage_pct` | [0, 100] |
| `background_agent_timeout_minutes` | [1, 120] |

### 交叉引用检查

| 检查项 | 描述 |
|--------|------|
| test_pyramid 总和 | `min_unit_pct + max_e2e_pct` 不超过 100% |
| serial_task 一致性 | max_retries_per_task 应 ≥ 1 |
| parallel 一致性 | `enabled=true` 时 `max_agents` 应 ≥ 2 |
| coverage 一致性 | `coverage_target=0` 且 `zero_skip_required=true` 可能为误配 |
| complexity_routing 一致性 | `thresholds.small` 必须 < `thresholds.medium` |

Required keys checked:
- Top-level: `version`, `services`, `phases`, `test_suites`
- Nested: `phases.requirements.agent`, `phases.testing.agent`, `phases.testing.gate.*`, `phases.implementation.serial_task.*`, `phases.reporting.coverage_target`, `phases.reporting.zero_skip_required`
