# spec-autopilot

Generic autopilot orchestration framework for spec-driven delivery pipelines.

## Architecture

Two-layer design:

- **Layer 1 (this plugin)**: Reusable orchestration framework — Agent, Skills, Hooks, Scripts
- **Layer 2 (project-side)**: Project-specific config + phase instruction files

## Components

### Agent

| File | Lines | Purpose |
|------|-------|---------|
| `agents/autopilot.md` | ~120 | Top-level orchestrator with 8-phase pipeline |

### Skills

| Skill | Lines | Purpose |
|-------|-------|---------|
| `autopilot-dispatch` | ~80 | Sub-Agent dispatch protocol with JSON envelope contract |
| `autopilot-gate` | ~70 | Gate verification: 8-step checklist + special gates + cognitive immunity |
| `autopilot-checkpoint` | ~50 | Checkpoint read/write for phase-results |
| `autopilot-recovery` | ~60 | Crash recovery: scan checkpoints, determine resume point |

### Hooks

| Script | Event | Purpose | Exit |
|--------|-------|---------|------|
| `check-predecessor-checkpoint.sh` | PreToolUse(Task) | Verify predecessor checkpoint before dispatch | 0=allow, 2=block |
| `validate-json-envelope.sh` | SubagentStop | Validate sub-Agent output has valid JSON envelope | 0=pass, 1=warn |
| `scan-checkpoints-on-start.sh` | SessionStart | Scan and report existing checkpoints | 0 (info only) |

## Project Integration

### 1. Enable the plugin

In `.claude/settings.json`:

```json
{
  "enabledPlugins": {
    "spec-autopilot": true
  }
}
```

### 2. Create project config

Create `.claude/autopilot.config.yaml` with:

- `services`: Health check URLs for project services
- `phases`: Per-phase agent, instruction files, reference files, gate thresholds
- `test_suites`: Test commands with type classification

### 3. Create phase instruction files

Place phase-specific instructions in `.claude/skills/autopilot/phases/` and reference them from the config.

## Gate Enforcement

Three-layer defense against phase skipping:

| Layer | Mechanism | Executor |
|-------|-----------|----------|
| 1 | TaskCreate + blockedBy | Task system (automatic) |
| 2 | Disk checkpoint validation | Hook scripts (deterministic) |
| 3 | 8-step checklist + special gates | autopilot-gate Skill (AI) |

## Crash Recovery

1. **SessionStart Hook**: Automatically scans checkpoints on new session
2. **autopilot-recovery Skill**: Interactive resume decision via AskUserQuestion
3. **Task system rebuild**: Creates full task chain, marks completed phases

## Ralph-Loop Fallback

When `ralph-loop` plugin is unavailable and `fallback_enabled: true` in config:

1. Falls back to manual `/opsx:apply` loop
2. Runs quick checks after each task, full tests every 3 tasks
3. Respects same 3-failure pause strategy
4. Max iterations from config
