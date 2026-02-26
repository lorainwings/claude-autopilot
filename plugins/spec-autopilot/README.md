# spec-autopilot

Spec-driven autopilot orchestration for delivery pipelines.

## Architecture

Two-layer design:

- **Layer 1 (this plugin)**: Reusable orchestration — Agent, Skills, Hooks, Scripts
- **Layer 2 (project-side)**: Project-specific config + phase instruction files

## Components

### Agent

| File | Purpose |
|------|---------|
| `agents/autopilot.md` | Top-level orchestrator with 8-phase pipeline |

### Skills

| Skill | Purpose |
|-------|---------|
| `autopilot-dispatch` | Sub-Agent dispatch protocol with JSON envelope contract |
| `autopilot-gate` | Gate verification: 8-step checklist + special gates + cognitive immunity |
| `autopilot-checkpoint` | Checkpoint read/write for phase-results |
| `autopilot-recovery` | Crash recovery: scan checkpoints, determine resume point |

### Hooks

| Script | Event | Purpose | Exit |
|--------|-------|---------|------|
| `check-predecessor-checkpoint.sh` | PreToolUse(Task) | Verify predecessor checkpoint before dispatch | 0=allow, 2=block |
| `validate-json-envelope.sh` | PostToolUse(Task) | Validate sub-Agent output has valid JSON envelope | 0=pass, 1=warn |
| `scan-checkpoints-on-start.sh` | SessionStart | Scan and report existing checkpoints | 0 (info only) |

## Installation

### Option 1: Direct install from GitHub

```bash
claude plugin install --from github:lorainwings/claude-autopilot --scope project
```

### Option 2: Local development

```bash
claude --plugin-dir ./spec-autopilot
```

### Option 3: Via marketplace

Add to your marketplace's `marketplace.json`:

```json
{
  "plugins": [
    {
      "name": "spec-autopilot",
      "source": { "source": "github", "repo": "lorainwings/claude-autopilot" },
      "description": "Spec-driven autopilot orchestration",
      "version": "1.0.0"
    }
  ]
}
```

Then install:

```bash
claude plugin install spec-autopilot@your-marketplace --scope project
```

## Project Setup

### 1. Create project config

Create `.claude/autopilot.config.yaml`:

```yaml
version: "1.0"

services:
  backend:
    health_url: "http://localhost:8080/actuator/health"

phases:
  requirements:
    agent: "business-analyst"
  testing:
    agent: "qa-expert"
    instruction_files:
      - ".claude/skills/autopilot/phases/testing-requirements.md"
    gate:
      min_test_count_per_type: 5
      required_test_types: [unit, api, e2e, ui]
  implementation:
    ralph_loop:
      enabled: true
      max_iterations: 30
      fallback_enabled: true

test_suites:
  backend_unit:
    command: "cd backend && ./gradlew test"
    type: unit
```

### 2. Create project-side skill entry

Create `.claude/skills/autopilot/SKILL.md` as a thin wrapper that delegates to this plugin's Agent.

### 3. Add phase instruction files

Place project-specific instructions in `.claude/skills/autopilot/phases/` and reference them from the config.

## Gate Enforcement

Three-layer defense against phase skipping:

| Layer | Mechanism | Executor |
|-------|-----------|----------|
| 1 | TaskCreate + blockedBy | Task system (automatic) |
| 2 | Disk checkpoint validation | Hook scripts (deterministic) |
| 3 | 8-step checklist + special gates | autopilot-gate Skill (AI) |

## Crash Recovery

1. **SessionStart Hook**: Automatically scans checkpoints on new session
2. **autopilot-recovery Skill**: Interactive resume decision
3. **Task system rebuild**: Creates full task chain, marks completed phases

## Ralph-Loop Fallback

When `ralph-loop` plugin is unavailable and `fallback_enabled: true`:

1. Falls back to manual `/opsx:apply` loop
2. Runs quick checks after each task, full tests every 3 tasks
3. Respects same 3-failure pause strategy
4. Max iterations from config
