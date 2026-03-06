# Phases

> Per-phase execution guide with inputs, outputs, checkpoint formats, and key behaviors.

## Phase Overview

| Phase | Executor | Key Behavior | Checkpoint |
|-------|----------|-------------|------------|
| 0 | Main thread | Environment check + crash recovery | None |
| 1 | Main thread | Multi-round decision loop with user | `phase-1-requirements.json` |
| 2 | Sub-agent | Create OpenSpec change directory | `phase-2-openspec.json` |
| 3 | Sub-agent | FF generate all artifacts | `phase-3-ff.json` |
| 4 | Sub-agent | Test case design (mandatory) | `phase-4-testing.json` |
| 5 | Sub-agent | Implementation via ralph-loop/fallback | `phase-5-implement.json` |
| 6 | Sub-agent | Test report generation (mandatory) | `phase-6-report.json` |
| 7 | Main thread | Summary + user-confirmed archive | `phase-7-summary.json` |

## Phase 0: Environment Check + Crash Recovery

**Executor**: Main thread

### Steps

1. Check `autopilot.config.yaml` exists → if not, call `autopilot-init`
2. Validate config schema via `validate-config.sh`
   2.7. (v3.1) Auto-detect code_constraints via `rules-scanner.sh` → populate `code_constraints` config
3. Check `settings.json` for ralph-loop plugin
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
   3.1. **Multi-source aggregation** (v3.1): Research Agent consolidates ≥3 sources (project code, external search, dependency evaluation) with confidence scoring per recommendation
4. **Complexity Routing**: Evaluate complexity based on research (small ≤2 files / medium 3-5 files / large 6+ files)
5. Dispatch business-analyst sub-agent for analysis (injected with Steering + Research context)
6. **Multi-round decision LOOP** until all points clarified (complexity affects loop depth)
   6.1. **Decision priority sorting** (v3.1): Decisions sorted P0 (blocking) → P1 (irreversible) → P2 (high-impact) → P3 (low-impact). P3 supports "accept all recommendations" for quick confirmation
7. Generate structured prompt
8. User final confirmation
9. Write checkpoint
10. Optional user gate (`config.gates.user_confirmation.after_phase_1`)

### Modes

| Mode | Behavior |
|------|----------|
| `structured` (default) | Standard AskUserQuestion flow |
| `socratic` | Additional challenging questions per the 6-step protocol |

### Complexity Routing

| Complexity | Discussion Depth | Socratic Mode | Min QA Rounds |
|-----------|-----------------|---------------|---------------|
| small | Quick confirm — show research conclusions, user confirms (v3.1: skips Socratic mode and business-analyst Agent dispatch for ≤40% token consumption) | Disabled | 1 |
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
  "decisions": [{"point": "...", "choice": "...", "priority": "P0|P1|P2|P3"}],
  "change_name": "<kebab-case-name>",
  "complexity": "small | medium | large",
  "research": {
    "status": "completed | skipped",
    "impact_files": 0,
    "estimated_loc": 0,
    "feasibility_score": "high | medium | low",
    "new_deps_count": 0,
    "web_research": {
      "sources_count": 3,
      "confidence_scores": [{"source": "...", "confidence": "high|medium|low"}]
    }
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

### Complexity-Aware Thresholds (v3.1)

Phase 4 test gate thresholds dynamically adjust based on Phase 1 complexity assessment:

| Complexity | required_test_types | min_test_count_per_type | Notes |
|-----------|--------------------|-----------------------|-------|
| small | config value, allows missing `ui` | max(2, config_value / 2) | UI tests optional |
| medium | config value (all types) | config value | Standard thresholds |
| large | config value (all types) | max(config_value, 5) | Raised minimums |

> **v3.1 change**: Small projects no longer fail Phase 4 for missing UI tests. Test count minimums are halved for small complexity.

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
| 1 | Worktree isolation | `config.phases.implementation.worktree.enabled = true` |
| 2 | Ralph-loop | Plugin available |
| 3 | Manual fallback | `fallback_enabled = true` |
| 4 | User prompt | None of above |

### Parallel Execution (v3.1 Enhanced)

When `config.phases.implementation.parallel.enabled = true`:

1. Parse `tasks.md`, build task dependency graph
2. **File ownership partition**: Group tasks by top-level directory (backend/frontend/node)
3. **File-level lock registry** (v3.1): Write each agent's `owned_files` to `phase5-ownership/file-locks.json`
4. Dispatch parallel agents (max = `config.parallel.max_agents`, default 5)
5. `write-edit-constraint-check.sh` Hook enforces file ownership in real-time
6. After each group completes, merge worktrees in task order
7. `parallel-merge-guard.sh` Hook validates merge (no conflicts, scope check, typecheck)

#### Dynamic Parallelism Adjustment (v3.1)

```
initial_parallel = config.parallel.max_agents (default 5)

IF total_tasks <= 3 → actual = min(2, total_tasks)
IF total_tasks <= 6 → actual = min(3, initial_parallel)
IF total_tasks <= 12 → actual = min(initial_parallel, total_tasks // 2)
IF total_tasks > 12 → actual = initial_parallel

# Runtime adjustment
IF merge_conflict_count_in_session >= 2 → actual -= 1 (min 2)
IF typecheck_failure_in_session → actual -= 1 (min 2)
```

#### Downgrade Decision Tree

```
IF worktree creation fails → immediate serial fallback
IF merge conflict > 5 files per group → rollback group, run serially
IF 3+ consecutive group failures → full serial downgrade
IF user selects "switch to serial" → full serial downgrade
Downgrade reason recorded in checkpoint: _metrics.parallel_fallback_reason
```

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

### Checkpoint Format

```json
{
  "status": "ok",
  "summary": "All tasks implemented, tests passing",
  "artifacts": ["src/..."],
  "test_results_path": "testreport/test-results.json",
  "tasks_completed": 8,
  "zero_skip_check": { "passed": true },
  "parallel_metrics": {
    "mode": "parallel | serial | downgraded",
    "groups_count": 3,
    "max_agents_used": 5,
    "fallback_reason": null,
    "file_conflicts_count": 0
  },
  "code_quality": {
    "constraint_violations": 0,
    "violations": []
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
4. **AskUser**: Archive now / Later / Needs changes
5. If archive:
   a. Git autosquash fixup commits (if `squash_on_archive: true`)
   b. Execute archive skill
   c. Update Phase 7 checkpoint to `ok`
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
