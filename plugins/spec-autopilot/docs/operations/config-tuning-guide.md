> **[中文版](config-tuning-guide.zh.md)** | English (default)

# Configuration Tuning Guide

> Optimize `.claude/autopilot.config.yaml` based on project type and team needs.

## Configuration Layering Concept

The 60+ configuration fields in spec-autopilot are organized into three layers. Most scenarios only require Level 1:

| Layer | Fields | Use Case |
|-------|--------|----------|
| **Level 1 — Core** | ~5 | First-time setup, quick start |
| **Level 2 — Team** | ~15 | Team-level customization, workflow tuning |
| **Level 3 — Expert** | ~40 | Deep customization, Hook threshold fine-tuning |

## Level 1: Core Configuration (Required)

```yaml
version: "1.0"
default_mode: "full"        # full | lite | minimal

services:
  backend:
    name: "Backend service"
    health_url: "http://localhost:3000/health"

test_suites:
  unit:
    command: "npm test"
    type: "unit"
```

## Recommended Configuration by Project Type

### Scenario A: Large Enterprise Project (Strict)

```yaml
default_mode: "full"
phases:
  requirements:
    min_qa_rounds: 3
    mode: "socratic"
  testing:
    gate:
      min_test_count_per_type: 5
  implementation:
    tdd_mode: true
    parallel:
      enabled: true
      max_agents: 4
    wall_clock_timeout_hours: 4
test_pyramid:
  min_unit_pct: 60
  max_e2e_pct: 15
  traceability_floor: 90
brownfield_validation:
  enabled: true
  strict_mode: true
```

### Scenario B: Medium Team Project (Moderate, Recommended)

```yaml
default_mode: "full"
phases:
  requirements:
    min_qa_rounds: 1
  testing:
    gate:
      min_test_count_per_type: 3
  implementation:
    tdd_mode: false
    parallel:
      enabled: false
    wall_clock_timeout_hours: 2
test_pyramid:
  min_unit_pct: 50
  max_e2e_pct: 20
  traceability_floor: 80
brownfield_validation:
  enabled: true
  strict_mode: false
```

### Scenario C: Rapid Prototype / Small Project (Relaxed)

```yaml
default_mode: "lite"
phases:
  requirements:
    min_qa_rounds: 1
  testing:
    gate:
      min_test_count_per_type: 1
  implementation:
    tdd_mode: false
    parallel:
      enabled: false           # No parallelism needed for rapid prototypes
test_pyramid:
  min_unit_pct: 30
  max_e2e_pct: 40
  traceability_floor: 50
  hook_floors:
    min_unit_pct: 20
    min_total_cases: 5
brownfield_validation:
  enabled: false
```

### Scenario D: TDD-Driven Development

```yaml
default_mode: "full"
phases:
  implementation:
    tdd_mode: true
    tdd_refactor: true
    tdd_test_command: "npm test -- --bail"
test_pyramid:
  min_unit_pct: 70
  traceability_floor: 90
```

In TDD mode, Phase 4 is automatically skipped (tests are created per-task in Phase 5), and Phase 5 executes the RED-GREEN-REFACTOR cycle.

## Common Tuning Scenarios

### Tuning 1: Reduce Unnecessary User Confirmations

```yaml
gates:
  user_confirmation:
    after_phase_1: false   # Skip requirements confirmation (for well-defined requirements)
    after_phase_3: false
    after_phase_4: false
```

### Tuning 2: Increase Timeouts for Large Projects

```yaml
phases:
  implementation:
    wall_clock_timeout_hours: 6
background_agent_timeout_minutes: 60
async_quality_scans:
  timeout_minutes: 20
```

### Tuning 3: Integrate Real Static Analysis Tools (v4.0)

```yaml
quality_scans:
  tools:
    - name: typecheck
      command: "npx tsc --noEmit"
      blocking: true
    - name: lint
      command: "npx eslint . --max-warnings 0"
      blocking: false
    - name: security
      command: "npm audit --audit-level=moderate"
      blocking: true
```

### Tuning 4: Relax Hook Floor Thresholds

When Hooks block frequently and the blocks are confirmed to be false positives:

```yaml
test_pyramid:
  hook_floors:
    min_unit_pct: 20       # Lowered from 30 to 20
    max_e2e_pct: 50        # Raised from 40 to 50
    min_total_cases: 5     # Lowered from 10 to 5
    min_change_coverage_pct: 60  # Lowered from 80 to 60
```

> Note: `hook_floors` is the Layer 2 relaxed floor and should not be stricter than the top-level `test_pyramid` thresholds. The configuration validator automatically checks cross-consistency.

### Tuning 5: Disable Web Search

```yaml
phases:
  requirements:
    research:
      web_search:
        enabled: false
```

### Tuning 6: Parallel Execution Optimization

```yaml
phases:
  implementation:
    parallel:
      enabled: true
      max_agents: 3           # Recommended: set to number of domains (backend + frontend + node)
      dependency_analysis: true  # Automatically analyze inter-task dependencies

# Domain mapping — ensure directory assignments are accurate
project_context:
  project_structure:
    backend_dir: "backend"        # Backend source root directory
    frontend_dir: "frontend/app"  # Frontend source root directory
    node_dir: "services/node"     # Node service directory
```

Tuning tips:
- Set `max_agents` to the actual number of project domains (e.g., 3 domains = 3 agents)
- Ensure `project_structure` directory mappings are accurate; otherwise file ownership assignment may be incorrect
- If merge conflicts are frequent, reduce `max_agents` or switch back to serial mode

### Tuning 7: TDD Mode Fine-Tuning

```yaml
phases:
  implementation:
    tdd_mode: true
    tdd_refactor: true            # Include REFACTOR step
    tdd_test_command: "npm test -- --bail"  # Override default test_suites command

test_pyramid:
  min_unit_pct: 70                # Recommended: raise unit test percentage in TDD mode
```

TDD behavior details:
- **RED**: Write tests only; execution must fail (`exit_code != 0`). L2 Bash deterministic verification
- **GREEN**: Write implementation only; execution must pass (`exit_code = 0`). L2 Bash deterministic verification
- **REFACTOR**: Tests must remain passing after refactoring. Failure triggers automatic `git checkout` rollback

> Set `tdd_refactor: false` to skip the REFACTOR step, suitable for rapid iteration scenarios.

### Tuning 8: Event Bus & GUI Tuning

```bash
# Start the GUI dual-mode server
bun run plugins/spec-autopilot/server/autopilot-server.ts

# Custom ports
bun run plugins/spec-autopilot/server/autopilot-server.ts --http-port 3000 --ws-port 9000
```

Tuning tips:
- Event files are written to `logs/events.jsonl` by default; consider adding `logs/` to `.gitignore`
- Use `--ws-port` to change the port if there is a WebSocket port conflict
- For large projects with high event volume, periodically clean up `events.jsonl` (each autopilot session appends; no automatic cleanup)
- If not using the GUI, there is no need to start the server; events are still written to the file and can be consumed via `tail -f`

## Configuration Validation

Run validation after modifying the configuration:

```bash
bash plugins/spec-autopilot/scripts/validate-config.sh
```

The output JSON includes:
- `valid`: Whether validation passed
- `missing_keys`: Missing required fields
- `type_errors`: Type errors
- `range_errors`: Range errors
- `cross_ref_warnings`: Cross-reference warnings (e.g., hook_floors stricter than gate thresholds)
