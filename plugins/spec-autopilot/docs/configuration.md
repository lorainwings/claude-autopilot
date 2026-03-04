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
| `ralph_loop.enabled` | boolean | Yes | — | Whether ralph-loop plugin is used |
| `ralph_loop.max_iterations` | number | Yes | — | Maximum implementation iterations |
| `ralph_loop.fallback_enabled` | boolean | Yes | — | Enable manual fallback when ralph-loop unavailable |
| `worktree.enabled` | boolean | No | `false` | Enable git worktree isolation per task |

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

## `test_pyramid`

Layer 2 (Hook) enforces lenient floors; Layer 3 (AI gate) enforces strict config values.

| Field | Type | Default | Hook Floor | Description |
|-------|------|---------|------------|-------------|
| `min_unit_pct` | number | `50` | `30` | Minimum unit test percentage |
| `max_e2e_pct` | number | `20` | `40` | Maximum E2E test percentage |
| `min_total_cases` | number | `20` | `10` | Minimum total test cases |

```yaml
test_pyramid:
  min_unit_pct: 50     # Layer 3 strict (config)
  max_e2e_pct: 20      # Layer 3 strict (config)
  min_total_cases: 20   # Layer 3 strict (config)
  # Hook Layer 2 uses lenient floors: 30/40/10
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

Output: `{"valid": true/false, "missing_keys": [...], "warnings": [...]}`

Required keys checked:
- Top-level: `version`, `services`, `phases`, `test_suites`
- Nested: `phases.requirements.agent`, `phases.testing.agent`, `phases.testing.gate.*`, `phases.implementation.ralph_loop.*`, `phases.reporting.coverage_target`, `phases.reporting.zero_skip_required`
