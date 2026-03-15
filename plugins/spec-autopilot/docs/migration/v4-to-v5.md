> **[中文版](v4-to-v5.zh.md)** | English (default)

# v4 → v5 Migration Guide

> This document covers all breaking changes and migration steps for upgrading spec-autopilot from v4.x to v5.x.

## 1. Config Schema Changes

### 1.1 New Required Fields

The following fields became required in v5.0+. Missing them causes `_config_validator.py` to report `valid: false`:

| Field | Type | Description | Suggested Default |
|-------|------|-------------|-------------------|
| `phases.reporting.coverage_target` | int | Code coverage threshold | `80` |
| `phases.reporting.zero_skip_required` | bool | Zero-skip enforcement | `true` |
| `phases.implementation.serial_task.max_retries_per_task` | int | Max retries per task | `3` |

### 1.2 New Recommended Fields

| Field | Type | Description |
|-------|------|-------------|
| `test_pyramid.hook_floors.*` | int | L2 Hook gate floor values (min_unit_pct/max_e2e_pct/min_total_cases/min_change_coverage_pct) |
| `context_management.git_commit_per_phase` | bool | Auto git fixup commit per phase |
| `default_mode` | str | Default execution mode (full/lite/minimal) |
| `background_agent_timeout_minutes` | int | Background agent timeout (minutes) |

### 1.3 Enum Value Changes

| Field | v4 Allowed Values | v5 Allowed Values |
|-------|-------------------|-------------------|
| `default_mode` | N/A (field did not exist) | `full`, `lite`, `minimal` |
| `phases.reporting.format` | N/A (field did not exist) | `allure`, `custom` |

### 1.4 Migration Steps

```yaml
# Add the following to autopilot.config.yaml (if missing):
phases:
  reporting:
    coverage_target: 80
    zero_skip_required: true
  implementation:
    serial_task:
      max_retries_per_task: 3

# Recommended additions:
default_mode: "full"
test_pyramid:
  hook_floors:
    min_unit_pct: 30
    max_e2e_pct: 40
    min_total_cases: 10
    min_change_coverage_pct: 80
```

## 2. Hook Protocol Changes

### 2.1 Unified Hook Architecture (v5.1)

v4 used 5 independent PostToolUse(Task) hook scripts (serial execution ~420ms). v5.1 merges them into a single Python validator:

| v4 (Deprecated) | v5.1+ (Unified) |
|-----------------|-----------------|
| `json-envelope-check.sh` | `_post_task_validator.py` Validator 1 |
| `anti-rationalization-check.sh` (Task) | `_post_task_validator.py` Validator 2 |
| `code-constraint-check.sh` (Task) | `_post_task_validator.py` Validator 3 |
| `parallel-merge-guard.sh` | `_post_task_validator.py` Validator 4 |
| `decision-format-check.sh` | `_post_task_validator.py` Validator 5 |

**Migration**: Update `hooks.json` to replace the 5 individual hooks with `_post_task_validator.py` as a single entry point.

### 2.2 Unified Write/Edit Hook (v5.1)

| v4 | v5.1+ |
|----|-------|
| `banned-patterns-check.sh` + `assertion-quality-check.sh` | `unified-write-edit-check.sh` (merged) |

### 2.3 Hook Protocol Convention

All hooks follow a unified protocol:

```
PostToolUse Hook:
  Block: stdout → {"decision": "block", "reason": "..."}
  Pass:  stdout is empty or non-JSON
  Exit code: always exit 0 (non-zero indicates hook crash)

PreToolUse Hook:
  Deny:  stdout → {"hookSpecificOutput": {"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"..."}}
  Allow: stdout is empty
  Exit code: always exit 0
```

### 2.4 Shared Preamble Script

v5.0+ introduces `_hook_preamble.sh`, used uniformly by all PostToolUse hooks:

```bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_hook_preamble.sh"
# Provides: STDIN_DATA, SCRIPT_DIR, PROJECT_ROOT_QUICK
# Auto-skips: non-autopilot sessions (Layer 0 bypass, ~1ms)
```

## 3. Event Bus (New in v4.2)

### 3.1 Event Types

v5.0+ introduces the Event Bus mechanism, writing events to `logs/events.jsonl`:

| Event Type | Script | Trigger |
|------------|--------|---------|
| `phase_start` / `phase_end` | `emit-phase-event.sh` | Phase lifecycle |
| `gate_pass` / `gate_block` | `emit-gate-event.sh` | Gate decisions |
| `task_progress` | `emit-task-progress.sh` | Phase 5 task completion (v5.2) |
| `agent_dispatch` / `agent_complete` | `emit-agent-event.sh` | Agent lifecycle (v5.3) |
| `tool_use` | `emit-tool-event.sh` | Full tool call logging (v5.3) |
| `decision_ack` | WebSocket-only | GUI decision acknowledgment (v5.2) |

### 3.2 Event Format

```json
{
  "type": "phase_start",
  "sequence": 1,
  "timestamp": "2026-03-15T10:00:00.000Z",
  "phase": 1,
  "mode": "full",
  "payload": { ... }
}
```

### 3.3 Migration Steps

Event Bus is a new feature — no migration needed. It becomes available automatically after upgrading from v4. For GUI visualization, start `autopilot-server.ts`.

## 4. Other Important Changes

### 4.1 Atomic Checkpoint Writes (v5.1)

v5.1 changes all checkpoint writes to atomic mode: write to `.tmp` first → validate → `mv` rename. Crash recovery automatically cleans up `.tmp` residuals.

### 4.2 TDD Stage State File (v5.1)

TDD mode introduces a `.tdd-stage` file (`context/.tdd-stage`) with values `red`/`green`/`refactor`. The L2 Write/Edit Hook reads this file for deterministic interception.

### 4.3 Test Discipline (v5.0.7)

New CLAUDE.md Test Discipline Iron Law:

- No reverse adaptation (modifying hook logic to make failing tests pass)
- No weakening assertions
- No deleting/skipping existing tests

### 4.4 Build Discipline (v5.0.7)

New `build-dist.sh` whitelist build:

- Runtime files are copied to `dist/` via whitelist
- CLAUDE.md DEV-ONLY sections are automatically stripped
- `tests/`, `docs/`, `gui/` are excluded from dist

## 5. Version Compatibility Matrix

| Feature | v4.0 | v4.2 | v5.0 | v5.1 | v5.2 | v5.3 |
|---------|------|------|------|------|------|------|
| Core Orchestration | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Event Bus | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Unified Hooks | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ |
| Atomic Checkpoints | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ |
| GUI Console | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ |
| Agent Lifecycle Events | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ |
| Sub-step Progress Recovery | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ |
