> **[中文版](configuration.zh.md)** | English (default)

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
| `research.agent` | string | No | `"general-purpose"` | Sub-agent type for research (general-purpose can read and write files) |
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
| `parallel.enabled` | boolean | No | `false` | Enable Phase 5 parallel Agent Team execution |
| `parallel.max_agents` | number | No | `8` | Maximum parallel agent count (recommended 2-4) |
| `parallel.dependency_analysis` | boolean | No | `true` | Enable automatic task dependency analysis |

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
| `enabled` | boolean | No | `true` | Enable Phase 6.5 code review |
| `auto_fix_minor` | boolean | No | `false` | Auto-fix minor findings |
| `block_on_critical` | boolean | No | `true` | Block pipeline on critical findings |
| `skip_patterns` | array | No | `["*.md", "*.json", "openspec/**"]` | File patterns to skip during review |

## `test_pyramid`

Layer 2 (Hook) enforces lenient floors; Layer 3 (AI gate) enforces strict config values. Hook floors are configurable via `test_pyramid.hook_floors`.

| Field | Type | Default | Hook Floor Default | Description |
|-------|------|---------|------------|-------------|
| `min_unit_pct` | number | `50` | `30` | Minimum unit test percentage |
| `max_e2e_pct` | number | `20` | `40` | Maximum E2E test percentage |
| `min_total_cases` | number | `20` | `10` | Minimum total test cases |

### `test_pyramid.hook_floors`

Optional overrides for Layer 2 Hook floor thresholds. These are the lenient minimums enforced by `post-task-validator.sh`. The Hook floor must not be stricter than the Layer 3 strict threshold (cross-validated by `validate-config.sh`).

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
| `after_phase_1` | boolean | `false` | Auto-continue after requirements (v6.0) |
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

## `model_routing` (v5.3)

Model routing configuration controlling AI model tier for each phase. Supports both legacy and new formats.

### Legacy Format (backward compatible)

```yaml
model_routing:
  phase_1: heavy     # heavy=deep reasoning → deep/opus
  phase_2: light     # light=mechanical ops → standard/sonnet
  phase_5: auto      # auto=inherit parent session model, no override
```

### New Format (recommended)

```yaml
model_routing:
  enabled: true
  default_subagent_model: sonnet
  fallback_model: sonnet
  phases:
    phase_1:
      tier: deep
      model: opus
      effort: high
    phase_5:
      tier: deep
      model: opus
      effort: high
      escalate_on_failure_to: deep
```

### Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `enabled` | boolean | `true` | Enable model routing |
| `default_session_model` | string | — | Default model for main thread (e.g. `opusplan`) |
| `default_subagent_model` | string | `sonnet` | Default model for sub-agents |
| `fallback_model` | string | `sonnet` | Fallback when model unavailable |
| `phases` | object | — | Per-phase model configuration |

### Per-Phase Fields

| Field | Type | Description |
|-------|------|-------------|
| `tier` | string | Model tier: `fast` / `standard` / `deep` / `auto` |
| `model` | string | Specific model: `haiku` / `sonnet` / `opus` / `opusplan` |
| `effort` | string | Reasoning depth: `low` / `medium` / `high` |
| `escalate_on_failure_to` | string | Escalation target on failure (e.g. `deep`) |

### Tier Mapping

| tier | model | effort | Use case |
|------|-------|--------|----------|
| `fast` | haiku | low | Mechanical operations (OpenSpec, FF, reports) |
| `standard` | sonnet | medium | Code implementation, routine analysis |
| `deep` | opus | high | Requirements analysis, test design, critical retries |

### Escalation Policy

- `fast` fails once → escalate to `standard`
- `standard` fails twice or critical task → escalate to `deep`
- `deep` still fails → no auto-escalation, manual decision required

## `project_context`

Project-specific context auto-detected by `autopilot-setup`. Dispatch dynamically injects these values into sub-agent prompts, **eliminating the need for separate instruction files in most cases**.

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

## `routing_overrides` (Auto-generated by Phase 1, v4.2)

Automatically written to checkpoint after Phase 1 completes, read by L2 Hook in subsequent phases. **No manual configuration needed**.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `requirement_type` | string\|array | `"feature"` | Requirement classification: `"feature"`, `"bugfix"`, `"refactor"`, `"chore"`, or array `["feature","bugfix"]` |
| `sad_path_min_pct` | number | `20` | Minimum sad path test percentage (bugfix auto-raises to 40) |
| `change_coverage_min_pct` | number | `80` | Minimum change coverage (bugfix/refactor auto-raises to 100) |
| `require_reproduction_test` | boolean | `false` | Require reproduction test (auto-enabled for bugfix) |
| `require_behavior_preservation_test` | boolean | `false` | Require behavior preservation test (auto-enabled for refactor) |

> `routing_overrides` is stored in the Phase 1 checkpoint (`phase-1-requirements.json`), not as a field in `autopilot.config.yaml`. It is documented here because the L2 Hook validation logic depends on it.

## `code_constraints` (v4.2)

Project-level code constraints enforced by L2 Hook (`unified-write-edit-check.sh`, v5.1) during Write/Edit operations.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `forbidden_files` | array | `[]` | List of file paths forbidden from modification (supports glob, e.g. `["*.lock", "package-lock.json"]`) |
| `forbidden_patterns` | array | `[]` | Forbidden code patterns (regex, e.g. `["TODO", "FIXME", "HACK"]`) |
| `allowed_dirs` | array | `[]` | Directory whitelist for writes (empty means no restriction) |

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

> `TODO/FIXME/HACK` in `forbidden_patterns` are deterministically intercepted by `unified-write-edit-check.sh` (v5.1), without relying on AI judgment.

## GUI and Event Bus (v5.0.8)

The GUI dashboard is served via `autopilot-server.ts` in dual-mode, requiring no configuration in `autopilot.config.yaml`.

### Server Command-Line Arguments

```bash
bun run runtime/server/autopilot-server.ts [options]
```

| Argument | Default | Description |
|----------|---------|-------------|
| `--project-root` | `.` | Project root directory for event file discovery |
| `--no-open` | `false` | Do not auto-open browser on startup |
| `--events-file` | `logs/events.jsonl` | Event file path |

> **Note**: HTTP port (9527) and WebSocket port (8765) are hardcoded constants in the source code and are not configurable via CLI arguments. If a port conflict occurs, kill the existing process and restart.

### Port Mapping

| Protocol | Port | Purpose |
|----------|------|---------|
| HTTP | 9527 | Vite build output static assets (three-column layout GUI) |
| WebSocket | 8765 | Real-time event push + decision_ack feedback |

> The GUI is an optional component and does not affect CLI-mode functionality.

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
bash plugins/spec-autopilot/runtime/scripts/validate-config.sh /path/to/project
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

### Validation Levels

| Level | Checks | Affects `valid` |
|-------|--------|-----------------|
| **Required fields** | Top-level and nested key existence | Yes — `valid: false` |
| **Type validation** | Data type of field values (string/number/boolean) | Yes — `valid: false` |
| **Range validation** | Whether numeric values are within reasonable bounds | No — only `range_errors` non-empty |
| **Cross-reference** | Logical consistency between fields | No — only `cross_ref_warnings` non-empty |
| **Recommended fields** | Optional but suggested fields | No — only `warnings` non-empty |

### Type Validation Rules

| Field Path | Expected Type |
|------------|---------------|
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

### Range Validation Rules

| Field Path | Range |
|------------|-------|
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

### Cross-Reference Checks

| Check | Description |
|-------|-------------|
| test_pyramid sum | `min_unit_pct + max_e2e_pct` must not exceed 100% |
| serial_task consistency | max_retries_per_task should be >= 1 |
| parallel consistency | When `enabled=true`, `max_agents` should be >= 2 |
| coverage consistency | `coverage_target=0` with `zero_skip_required=true` may be misconfiguration |
| complexity_routing consistency | `thresholds.small` must be < `thresholds.medium` |

Required keys checked:
- Top-level: `version`, `services`, `phases`, `test_suites`
- Nested: `phases.requirements.agent`, `phases.testing.agent`, `phases.testing.gate.*`, `phases.implementation.serial_task.*`, `phases.reporting.coverage_target`, `phases.reporting.zero_skip_required`
