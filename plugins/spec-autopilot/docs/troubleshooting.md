# Troubleshooting

> Common errors, debugging techniques, and recovery scenarios for spec-autopilot.

## Common Errors

### "python3 is required for autopilot gate hooks but not found in PATH"

**Cause**: python3 not installed or not in PATH.

**Fix**:
```bash
# macOS
brew install python3

# Ubuntu/Debian
sudo apt install python3

# Verify
python3 --version
```

### "Phase N checkpoint not found. Phase N must complete before Phase N+1."

**Cause**: Predecessor phase didn't complete or checkpoint file is missing.

**Fix**:
1. Check `openspec/changes/<name>/context/phase-results/` for checkpoint files
2. If file exists but is corrupted → delete it and re-run the phase
3. If no checkpoint → the phase didn't complete; re-trigger from the orchestrator

### "Phase 4 returned 'warning' but only 'ok' or 'blocked' are accepted"

**Cause**: Phase 4 sub-agent returned `warning` status, which is not allowed.

**Fix**: Re-dispatch Phase 4. The sub-agent must create enough test cases to meet all thresholds, or report `blocked` if it cannot proceed.

### "Phase 4 test_pyramid floor violation"

**Cause**: Test distribution is severely inverted (too few unit tests, too many E2E tests).

**Fix**: Adjust test design to have at least 30% unit tests, no more than 40% E2E tests, and at least 10 total test cases. These are lenient Layer 2 floors — your config likely has stricter thresholds.

### "Anti-rationalization check: output contains potential skip/rationalization pattern(s)"

**Cause**: Sub-agent output contains phrases like "out of scope", "not needed", "skip this test", etc.

**Fix**: Review the sub-agent output. If the rationalization is legitimate (e.g., a genuine scope decision), re-dispatch with explicit instructions. If the sub-agent was skipping work, the block is correct.

### "Phase 5 wall-clock timeout"

**Cause**: Phase 5 has been running for more than 2 hours.

**Fix**:
1. Save current progress (task-level checkpoints preserve state)
2. Investigate why implementation is taking so long
3. Delete `phase5-start-time.txt` to reset the timer
4. Re-trigger Phase 5 — it will resume from the last completed task

### "validate-config: missing required keys"

**Cause**: `autopilot.config.yaml` is missing required fields.

**Fix**: Run `validate-config.sh` to see which keys are missing:
```bash
bash plugins/spec-autopilot/scripts/validate-config.sh /path/to/project
```
Add the missing keys to your config file.

### "Write/Edit constraint check: file locked by agent-N"

**Cause**: During Phase 5 parallel execution, this agent is trying to edit a file owned by another parallel agent.

**Fix**:
1. Check file ownership registry:
   ```bash
   cat openspec/changes/<name>/context/phase-results/phase5-ownership/file-locks.json
   ```
2. Verify task scope doesn't overlap — if it does, reduce `max_agents` or adjust task boundaries
3. The owning agent must complete and release the lock before this file can be edited

### "Write/Edit constraint check: forbidden pattern detected"

**Cause**: Code written during Phase 5 contains a pattern listed in `code_constraints.forbidden_patterns`.

**Fix**:
1. Review the violation message for the specific pattern and file
2. Fix the code to avoid the forbidden pattern
3. If the pattern is a false positive, update `code_constraints.forbidden_patterns` in config

### "Phase 4 complexity-aware gate: test counts below threshold"

**Cause**: Phase 4 test counts are below the complexity-adjusted minimums (v3.1).

**Fix**:
1. Check which complexity level was assigned in Phase 1: `cat openspec/changes/<name>/context/phase-results/phase-1-*.json | grep complexity`
2. Review the adjusted thresholds:
   - small: min = max(2, config / 2), UI tests optional
   - medium: min = config value
   - large: min = max(config, 5)
3. Add more test cases or adjust config thresholds

### "Parallel merge guard: typecheck failed after merge"

**Cause**: After merging a parallel agent's worktree, the type check command failed.

**Fix**:
1. Check which files were merged: `git log --oneline -5`
2. Run typecheck manually: use the command from `config.test_suites[type=typecheck].command`
3. Fix type errors, then retry the merge
4. If recurring, reduce `max_agents` to lower parallelism

## Debugging Hook Scripts

### Enable verbose output

Hook scripts output diagnostic info to stderr (visible in Claude Code verbose mode, Ctrl+O):

```
OK: Valid autopilot JSON envelope with status="ok"
INFO: JSON envelope missing optional field: artifacts
```

### Test hooks locally

```bash
# Run the test suite
bash plugins/spec-autopilot/scripts/test-hooks.sh

# Test a specific hook with mock input
echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:4 -->\nTest"},"tool_response":"..."}' \
  | bash plugins/spec-autopilot/scripts/validate-json-envelope.sh
```

### Test all hooks automatically (v3.1)

```bash
# Run the comprehensive test suite (178+ test cases)
bash plugins/spec-autopilot/scripts/test-hooks.sh

# Expected output:
# === spec-autopilot Hook Test Suite ===
# ...
# Results: 178 passed, 0 failed
```

### Debug constraint loading cache

```bash
# Check if cache exists for your project
ls -lh /tmp/autopilot-constraints-*.json

# View cached constraints
cat /tmp/autopilot-constraints-*.json | python3 -m json.tool

# Clear cache to force re-scan
rm -f /tmp/autopilot-constraints-*.json
```

### Debug file-level locks

```bash
# View file ownership registry
cat openspec/changes/<name>/context/phase-results/phase5-ownership/file-locks.json

# Check which agent owns a specific file
python3 -c "
import json
with open('openspec/changes/<name>/context/phase-results/phase5-ownership/file-locks.json') as f:
    locks = json.load(f)
print(json.dumps(locks, indent=2))
"
```

### Check hook registration

```bash
# Verify hooks.json is valid
python3 -c "import json; json.load(open('plugins/spec-autopilot/hooks/hooks.json'))"

# Check all hooks have timeout
python3 -c "
import json
with open('plugins/spec-autopilot/hooks/hooks.json') as f:
    data = json.load(f)
for event, groups in data['hooks'].items():
    for group in groups:
        for hook in group['hooks']:
            assert 'timeout' in hook, f'{event} hook missing timeout'
print('All hooks have timeout configured')
"
```

### Syntax-check all scripts

```bash
for f in plugins/spec-autopilot/scripts/*.sh; do
  bash -n "$f" && echo "OK: $(basename $f)" || echo "FAIL: $(basename $f)"
done
```

## Recovery Scenarios

### Scenario 1: Claude Code session crashed mid-phase

**What happens**:
1. On next session start, `scan-checkpoints-on-start.sh` runs automatically
2. It reports all existing checkpoints
3. When autopilot is triggered again, `autopilot-recovery` Skill scans checkpoints
4. Pipeline resumes from the last completed phase + 1

**Manual recovery**:
```bash
# Check current state
ls openspec/changes/<name>/context/phase-results/

# View checkpoint status
python3 -c "
import json, glob
for f in sorted(glob.glob('openspec/changes/<name>/context/phase-results/phase-*.json')):
    with open(f) as fh:
        d = json.load(fh)
    print(f'{f}: status={d.get(\"status\")}')"
```

### Scenario 2: Context compaction during pipeline

**What happens automatically**:
1. `PreCompact` hook saves state to `autopilot-state.md`
2. After compaction, `SessionStart(compact)` hook reinjects state
3. Main thread detects `=== AUTOPILOT STATE RESTORED ===` marker
4. Reads checkpoint files and continues

**If auto-recovery fails**:
1. Read `autopilot-state.md` for the last known state
2. Check phase-results directory for checkpoints
3. Re-trigger autopilot — crash recovery handles the rest

### Scenario 3: Phase 5 implementation stalled

**Symptoms**: Phase 5 running for > 2 hours, wall-clock timeout triggered.

**Steps**:
1. Check `phase-results/phase5-tasks/` for task-level progress
2. Review the last completed task checkpoint
3. If the stall is due to a test failure:
   - Check the actual test output
   - Fix the failing test or implementation
4. Delete `phase5-start-time.txt` to reset the timer
5. Re-trigger Phase 5 — it resumes from the last completed task

### Scenario 4: Need to restart from a specific phase

**Steps**:
1. Delete checkpoint files for the phase and all subsequent phases:
   ```bash
   rm openspec/changes/<name>/context/phase-results/phase-{N..7}-*.json
   ```
2. Re-trigger autopilot
3. Crash recovery will detect Phase N-1 as the last completed phase
4. Pipeline resumes from Phase N

### Scenario 5: Lock file conflicts

**Symptoms**: "Another autopilot is running" message.

**Checks**:
1. Is another Claude Code session actually running?
   ```bash
   ps aux | grep claude
   ```
2. If no other session → stale lock file
3. The plugin checks PID + session_id to detect stale locks automatically
4. Manual cleanup: `rm openspec/changes/.autopilot-active`

### Scenario 6: Parallel execution merge conflict (v3.1)

**Symptoms**: Phase 5 parallel agent merge fails, `parallel-merge-guard.sh` blocks.

**Steps**:
1. Check conflict details:
   ```bash
   git diff --check
   ```
2. The plugin automatically reduces `max_agents` and retries
3. If 3+ consecutive failures → automatic downgrade to serial mode
4. Manual override: set `phases.implementation.parallel.enabled: false` in config

### Scenario 7: Code constraint false positive (v3.1)

**Symptoms**: `write-edit-constraint-check.sh` blocks a legitimate code change.

**Steps**:
1. Review the block message for the specific constraint violated
2. Check constraint sources:
   - `config.yaml` → `code_constraints` section
   - `CLAUDE.md` → forbidden patterns extracted
   - `.claude/rules/*.md` → table/list constraints extracted
3. Fix: Update the relevant constraint source, then clear cache: `rm /tmp/autopilot-constraints-*.json`

## FAQ

**Q: Can I run autopilot on an existing project with code?**
A: Yes. Enable `brownfield_validation` in your config for drift detection. The pipeline works with both greenfield and brownfield projects.

**Q: What if ralph-loop plugin is not available?**
A: Set `phases.implementation.ralph_loop.fallback_enabled: true` to use the manual fallback loop. Or install ralph-loop for the best experience.

**Q: Can I skip phases?**
A: No. All 8 phases are mandatory. If a phase is not applicable, the sub-agent should return `status: "ok"` with a justification in the summary, not skip the phase.

**Q: How do I adjust test thresholds?**
A: Edit `config.phases.testing.gate.min_test_count_per_type` for the Layer 3 threshold. The Layer 2 Hook uses lenient floors (30% unit, 40% e2e ceiling, 10 minimum) that cannot be changed via config.

**Q: What happens if a quality scan times out?**
A: The scan is marked as `"timeout"` in the quality summary table. It does not block Phase 7 archival.

**Q: Why is Phase 4 only requiring 3 test types instead of 4?**
A: v3.1 complexity-aware gates detect your change as "small" complexity and allow skipping UI tests. Adjust `phases.requirements.complexity_routing.thresholds` in config to change complexity classification.

**Q: How do I disable parallel execution in Phase 5?**
A: Set `phases.implementation.parallel.enabled: false` in config, or reduce `max_agents` to 1. Parallel is default-on since v3.1.

**Q: Can I control which files each parallel agent can edit?**
A: File ownership is auto-partitioned by task scope. The `file-locks.json` registry is managed by the orchestrator. You cannot manually assign files, but you can control partitioning via task boundaries in `tasks.md`.

**Q: How do I clear the constraint cache?**
A: Run `rm -f /tmp/autopilot-constraints-*.json`. The cache rebuilds automatically on the next Hook invocation (within ~50ms).

**Q: What is the difference between code_constraints and dynamic_constraints?**
A: `code_constraints` (config) defines the rules (forbidden files, patterns, allowed dirs). `dynamic_constraints` (config) enables runtime Hook enforcement (typecheck on write, lint checks). Both must be configured for full dual-layer protection.
