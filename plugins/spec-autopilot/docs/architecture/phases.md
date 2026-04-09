> **[中文版](phases.zh.md)** | English (default)

# Phases

> Per-phase execution guide with inputs, outputs, checkpoint formats, and key behaviors.

## Phase Overview

| Phase | Executor | Key Behavior | Checkpoint |
|-------|----------|-------------|------------|
| 0 | Main thread | Environment check + crash recovery | None |
| 1 | Main thread | Multi-round decision loop + requirements routing (routing_overrides, v4.2) | `phase-1-requirements.json` |
| 2 | Sub-agent | Create OpenSpec change directory | `phase-2-openspec.json` |
| 3 | Sub-agent | FF generate all artifacts | `phase-3-ff.json` |
| 4 | Sub-agent | Test case design (mandatory) | `phase-4-testing.json` |
| 5 | Sub-agent | Implementation: Serial / Parallel / TDD | `phase-5-implement.json` |
| 6 | Sub-agent | Test report generation (mandatory) | `phase-6-report.json` |
| 7 | Main thread | Summary + archive-readiness auto | `phase-7-summary.json` |

## Phase 0: Environment Check + Crash Recovery

**Executor**: Main thread

### Steps

1. Check `autopilot.config.yaml` exists → if not, call `autopilot-setup`
2. Validate config schema via `validate-config.sh`
3. Check settings.json for enabled plugins
4. Call `autopilot-recovery` Skill to scan checkpoints
5. Create 8 phase tasks with blockedBy chain
6. Write `.autopilot-active` lock file
7. Create anchor commit: `git commit --allow-empty -m "autopilot: start <name>"`

### Outputs

- Lock file: `openspec/changes/.autopilot-active`
- 8 Tasks in task system with dependency chain

## Phase 1: Requirements Understanding

**Executor**: Main thread
**Reference**: `references/phase1-requirements.md`

### Steps

1. Parse `$ARGUMENTS` (file path, text, or empty → ask user)
2. **Auto-Scan**: Scan project structure → generate Steering Documents (project-context.md, existing-patterns.md, tech-constraints.md)
3. **Research Agent**: Dispatch Explore agent → analyze related code, dependency compatibility, technical feasibility → research-findings.md
4. **Complexity Routing**: Evaluate complexity based on research (small ≤2 files / medium 3-5 files / large 6+ files)
5. Dispatch business-analyst sub-agent for analysis (injected with Steering + Research context)
6. **Multi-round decision LOOP** until all points clarified (complexity affects loop depth)
7. Generate structured prompt
8. User final confirmation
9. Write checkpoint
10. Optional user gate (`config.gates.user_confirmation.after_phase_1`)

### Modes

| Mode | Behavior |
|------|----------|
| `structured` (default) | Standard AskUserQuestion flow |
| `socratic` | Additional challenging questions per the 6-step protocol |

#### Socratic Mode Steps (v5.0.6 Extension)

| Step | Content |
|------|---------|
| 1-6 | Standard 6-step challenge protocol |
| **7 (v5.0.6)** | Non-functional requirements challenge: performance metrics, security constraints, accessibility, internationalization requirements |

### Complexity Routing

| Complexity | Discussion Depth | Socratic Mode | Min QA Rounds |
|-----------|-----------------|---------------|---------------|
| small | Quick confirm — show research conclusions, user confirms | Disabled | 1 |
| medium | Standard — full decision loop | Follows config | 2-3 |
| large | Deep — forced socratic mode | Forced on | 3+ |

Auto-upgrade to `large` when: feasibility score is low, high-severity risks exist, or 3+ new dependencies needed.

### Steering Documents (Auto-generated)

| File | Content |
|------|---------|
| `context/project-context.md` | Tech stack, directory layout, key dependencies, coding constraints, test infrastructure |
| `context/existing-patterns.md` | API patterns, data models, component patterns, error handling |
| `context/tech-constraints.md` | Hard constraints, dependency constraints, infrastructure constraints |
| `context/research-findings.md` | Impact analysis, dependency check, feasibility assessment, risks |

### Requirements Type Routing (v4.2)

Phase 1 analysis results automatically classify requirements into the following types, dynamically adjusting subsequent phase gate thresholds:

| Requirement Type | Classification Rule | Gate Adjustment |
|---------|---------|---------|
| **Feature** | New functionality, new components, new APIs | Default thresholds |
| **Bugfix** | Defect fixes, behavior corrections | sad_path ≥ 40%, coverage = 100%, must include reproduction test |
| **Refactor** | Code refactoring, performance optimization | coverage = 100%, must include behavior preservation test |
| **Chore** | CI/CD, documentation, dependency upgrades | coverage ≥ 60%, typecheck pass is sufficient |

Classification results are written to the checkpoint's `requirement_type` field. Compound requirements (v5.0.6) use an array format and pass merged threshold overrides via `routing_overrides`.

### Checkpoint Format

```json
{
  "status": "ok",
  "summary": "Requirements complete, N features, M decisions confirmed",
  "artifacts": [
    "context/prd.md", "context/discussion.md",
    "context/project-context.md", "context/existing-patterns.md",
    "context/tech-constraints.md", "context/research-findings.md"
  ],
  "requirements_summary": "...",
  "decisions": [{"point": "...", "choice": "..."}],
  "change_name": "<kebab-case-name>",
  "complexity": "small | medium | large",
  "requirement_type": "feature | bugfix | refactor | chore",
  "routing_overrides": {
    "sad_path_min_pct": 20,
    "change_coverage_min_pct": 80,
    "require_reproduction_test": false,
    "require_behavior_preservation_test": false
  },
  "research": {
    "status": "completed | skipped",
    "impact_files": 0,
    "estimated_loc": 0,
    "feasibility_score": "high | medium | low",
    "new_deps_count": 0
  },
  "steering_artifacts": [
    "context/project-context.md",
    "context/existing-patterns.md",
    "context/tech-constraints.md"
  ],
  "_metrics": { "start_time": "...", "end_time": "...", "duration_seconds": 0, "retry_count": 0 }
}
```

## Phase 2: Create OpenSpec

**Executor**: Sub-agent

### Input

- Phase 1 checkpoint (requirements summary, decisions)
- Project structure from config

### Checkpoint Format

```json
{
  "status": "ok",
  "summary": "OpenSpec change created",
  "artifacts": ["openspec/changes/<name>/proposal.md"],
  "_metrics": { ... }
}
```

## Phase 3: FF Generate

**Executor**: Sub-agent

### Input

- OpenSpec change directory
- Phase 2 checkpoint

### Checkpoint Format

```json
{
  "status": "ok",
  "summary": "FF generated: proposal, design, specs, tasks",
  "artifacts": ["openspec/changes/<name>/design.md", "openspec/changes/<name>/tasks.md"],
  "_metrics": { ... }
}
```

## Phase 4: Test Design

**Executor**: Sub-agent (mandatory, cannot skip)

### Input

- Design and tasks from Phase 3
- `config.phases.testing.instruction_files`
- `config.phases.testing.reference_files`
- `config.phases.testing.gate` thresholds

### Special Rules

- **No warning status**: Only `ok` or `blocked` accepted
- **Test pyramid enforcement**: Layer 2 (Hook) checks floors, Layer 3 (AI) checks config thresholds
- **Artifacts required**: Must produce actual test files

### Checkpoint Format

```json
{
  "status": "ok",
  "summary": "Test cases designed: N unit, M api, P e2e, Q ui",
  "artifacts": ["tests/unit/test_feature.py", "tests/e2e/test_flow.spec.ts"],
  "test_counts": { "unit": 15, "api": 8, "e2e": 5, "ui": 3 },
  "dry_run_results": { "unit": 0, "api": 0, "e2e": 0, "ui": 0 },
  "test_pyramid": { "unit_pct": 48, "e2e_pct": 16 },
  "_metrics": { ... }
}
```

## Phase 5: Implementation

**Executor**: Sub-agent
**Reference**: `references/phase5-implementation.md`

### Safety Preparation

1. Git safety tag: `git tag -f autopilot-phase5-start HEAD`
2. Write start timestamp to `phase5-start-time.txt`

### Execution Modes

| Priority | Mode | Condition |
|----------|------|-----------|
| 1 | Parallel (worktree) | `config.phases.implementation.parallel.enabled = true` |
| 2 | Serial (foreground Task) | `config.phases.implementation.parallel.enabled = false` (default) |

### Task-Level Checkpoints

Each completed task writes to `phase-results/phase5-tasks/task-N.json`:

```json
{
  "task_number": 1,
  "task_title": "Implement login API",
  "status": "ok",
  "summary": "Completed, 3 tests pass",
  "artifacts": ["src/LoginController.java"],
  "test_result": "3/3 passed",
  "_metrics": { ... }
}
```

### Wall-Clock Timeout

- 2-hour hard limit enforced by Hook (Layer 2)
- Skill-level soft limit: AskUser after 2 hours
- Options: continue / save & pause / rollback to start tag

### Event Emission (v4.2/v5.0)

After each task completes in Phase 5, a `task_progress` event is emitted via `emit-task-progress.sh`:

```bash
bash scripts/emit-task-progress.sh <phase> <task_name> <status> <task_index> <task_total> [tdd_step]
```

Events are pushed in real-time to `logs/events.jsonl` and WebSocket (`ws://localhost:8765`), enabling the GUI dashboard to render task progress live.

### TDD Deterministic Cycle (v4.1)

When `tdd_mode: true`, each task executes in a RED-GREEN-REFACTOR cycle:

| Stage | Behavior | L2 Verification |
|-------|----------|-----------------|
| **RED** | Write tests only, run must fail (`exit_code != 0`) | Bash deterministic verification |
| **GREEN** | Write implementation only, run must pass (`exit_code = 0`) | Bash deterministic verification |
| **REFACTOR** | Refactor, tests must remain passing | Failure → `git checkout` auto-rollback |

> When GREEN fails, fix implementation code; modifying test files is prohibited.

### Checkpoint Format

```json
{
  "status": "ok",
  "summary": "All tasks implemented, tests passing",
  "artifacts": ["src/..."],
  "test_results_path": "testreport/test-results.json",
  "tasks_completed": 8,
  "zero_skip_check": { "passed": true },
  "tdd_metrics": {
    "red_pass": true,
    "green_pass": true,
    "refactor_pass": true,
    "cycle_count": 8
  },
  "_metrics": { ... }
}
```

## Phase 6: Test Report

**Executor**: Sub-agent (mandatory, cannot skip)

### Input

- Test results from Phase 5
- `config.phases.reporting` settings
- `config.phases.reporting.report_commands`

### Checkpoint Format

```json
{
  "status": "ok",
  "summary": "Test report generated, 98.5% pass rate",
  "artifacts": ["reports/test-report.html"],
  "pass_rate": 98.5,
  "report_path": "reports/test-report.html",
  "report_format": "allure",
  "_metrics": { ... }
}
```

## Phase 6→7 Transition: Parallel Quality Scans

**Reference**: `references/quality-scans.md`

Between Phase 6 and 7, background quality scans are dispatched:

- Contract testing
- Performance audit (Lighthouse)
- Visual regression
- Mutation testing

Hard timeout: `config.async_quality_scans.timeout_minutes` (default 10 min). Timeout → auto-mark `"timeout"`, no user prompt.

## Phase 7: Summary + Archive

**Executor**: Main thread

### Steps

1. Read all checkpoints, display status summary table
2. Collect metrics via `collect-metrics.sh`, display timing table
3. Collect quality scan results (with hard timeout)
4. Run archive-readiness check
5. If readiness passes:
   a. Git autosquash fixup commits (if `squash_on_archive: true`)
   b. Execute archive skill
   c. Update Phase 7 checkpoint to `ok`
   If readiness is blocked:
   Show block reasons and ask whether to re-check after fixes or stop archiving
6. Cleanup: delete lock file, start-time file, git tag

### Metrics Summary Table

```
| Phase | Status | Duration | Retries |
|-------|--------|----------|---------|
| 1     | ok     | 5m 30s   | 0       |
| 2     | ok     | 2m 15s   | 0       |
| ...   | ...    | ...      | ...     |
| Total |        | 85m 00s  | 3       |
```

### Checkpoint Format

```json
{
  "status": "ok",
  "summary": "Archive complete",
  "phase": 7,
  "archived_change": "<name>",
  "_metrics": { ... }
}
```
