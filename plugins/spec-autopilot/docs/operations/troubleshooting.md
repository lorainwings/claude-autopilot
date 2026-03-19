> **[中文版](troubleshooting.zh.md)** | English (default)

# Troubleshooting Guide

> Common error scenarios, debugging tips, and recovery procedures.

## Common Errors

### 1. Hook Block: test_pyramid floor violation

**Error Message**:
```json
{"decision": "block", "reason": "Phase 4 test_pyramid floor violation (Layer 2): unit_pct=20% < 30% floor"}
```

**Cause**: Unit test percentage is below the Hook floor threshold.

**Fix**:
1. Check the `test_pyramid` field returned by Phase 4
2. Add more unit test cases until the percentage reaches >= 30%
3. If you need to adjust the threshold, edit `.claude/autopilot.config.yaml`:
   ```yaml
   test_pyramid:
     hook_floors:
       min_unit_pct: 20  # Lower the floor
   ```

### 2. Hook Block: Anti-rationalization check

**Error Message**:
```json
{"decision": "block", "reason": "Anti-rationalization check: Phase 5 output scored 5 (threshold 5)"}
```

**Cause**: Skip/defer patterns detected in the sub-Agent output (e.g., "skipped because", "deferred to later").

**Fix**: This typically means the sub-Agent did not complete the required work. The system will automatically re-dispatch that phase. If triggered repeatedly, check whether the requirement is too complex and needs to be split.

### 3. Hook Block: zero_skip_check failed

**Error Message**:
```json
{"decision": "block", "reason": "Phase 5 zero_skip_check gate failed. All tests must pass with zero skips."}
```

**Cause**: Tests are still skipped or failing after Phase 5 implementation.

**Fix**:
1. Check the `zero_skip_check` field in `phase-5-implement.json`
2. Find the failing/skipped tests and fix them
3. Ensure all tests pass before resubmitting

### 4. Phase 4 Block: change_coverage insufficient

**Error Message**:
```json
{"decision": "block", "reason": "Phase 4 change_coverage insufficient: 33% < 80% threshold"}
```

**Fix**: The tests designed in Phase 4 do not cover enough change points. Add test cases targeting the uncovered change points.

### 5. test_traceability Block (new in v4.0)

**Error Message**:
```json
{"decision": "block", "reason": "Phase 4 test_traceability coverage 50% < 80% floor"}
```

**Cause**: Test cases do not sufficiently trace back to Phase 1 requirements.

**Fix**:
1. Check `test_traceability.coverage_pct` returned by Phase 4
2. Add requirement mappings for each test case
3. If you need to adjust the threshold:
   ```yaml
   test_pyramid:
     traceability_floor: 60  # Lower to 60%
   ```

### 6. "python3 is required for autopilot gate hooks but not found in PATH"

**Cause**: python3 is not installed or not in PATH.

**Fix**:
```bash
# macOS
brew install python3

# Ubuntu/Debian
sudo apt install python3

# Verify
python3 --version
```

### 7. "Phase N checkpoint not found. Phase N must complete before Phase N+1."

**Cause**: The prerequisite phase did not complete or the checkpoint file is missing.

**Fix**:
1. Check checkpoint files under `openspec/changes/<name>/context/phase-results/`
2. If the file exists but is corrupted, delete it and re-run the phase
3. If no checkpoint exists, the phase did not complete; re-trigger from the orchestrator

### 8. Phase 5 Timeout

**Error Message**:
```json
{"permissionDecision": "deny", "permissionDecisionReason": "Phase 5 wall-clock timeout"}
```

**Fix**:
1. Save current progress (task-level checkpoints preserve state)
2. Investigate why the implementation is taking too long
3. Delete `phase5-start-time.txt` to reset the timer
4. Re-trigger Phase 5 — it will resume from the last completed task

Or increase the timeout configuration:
```yaml
phases:
  implementation:
    wall_clock_timeout_hours: 4  # Increase from default 2h to 4h
```

### 9. Configuration Validation Failed: missing_keys

**Error Message**:
```json
{"valid": false, "missing_keys": ["phases.testing.agent"]}
```

**Fix**: Add the missing fields in `.claude/autopilot.config.yaml`. Refer to `references/config-schema.md` for the complete template.

Or re-run `/autopilot-init` to regenerate the configuration.

### 10. Lock File Conflict: Another autopilot is running

**Scenario**: An `.autopilot-active` lock file belonging to another process is detected at startup.

**Fix**: The system will prompt you to choose:
- **Override and continue** (recommended): If the previous process is no longer running
- **Abort current run**: If another autopilot is indeed running

Manual cleanup:
```bash
# Check if another Claude Code session is running
ps aux | grep claude

# If it's a stale lock file, delete it manually
rm openspec/changes/.autopilot-active
```

### 11. GUI WebSocket Disconnected (v5.0.8)

**Symptom**: The GUI dashboard shows "Disconnected" and the event stream stops updating.

**Cause**: WebSocket connection interrupted (network fluctuation, server restart, port conflict).

**Fix**:
1. Check if autopilot-server.ts is still running: `ps aux | grep autopilot-server`
2. If it has exited, restart it: `bun run plugins/spec-autopilot/runtime/server/autopilot-server.ts --project-root .`
3. If there is a port conflict (HTTP: 9527, WS: 8765 are hardcoded source constants), kill the existing process (`lsof -ti:9527 | xargs kill`) and restart
4. The GUI will auto-reconnect (built-in 3-second retry) and backfill missed events after reconnection

### 12. GUI Shows No Events (v5.0.8)

**Symptom**: The GUI dashboard is running but the event panel is empty.

**Cause**: Autopilot has not started yet, or the events.jsonl path does not match.

**Fix**:
1. Confirm autopilot is running (events are only produced after `/autopilot` is triggered)
2. Check if `logs/events.jsonl` exists: `ls -la logs/events.jsonl`
3. If it does not exist, create the directory: `mkdir -p logs`
4. Confirm the server is watching the correct event file path (default: `logs/events.jsonl`)

### 13. Parallel Worktree Merge Conflict (v5.0)

**Error Message**:
```json
{"decision": "block", "reason": "Parallel merge conflict: 4 files conflicted, threshold 3 exceeded"}
```

**Cause**: Multiple parallel Agents modified the same files, causing merge conflicts that exceed the threshold.

**Fix**:
1. The system automatically downgrades to serial mode and notifies the user
2. Manually check conflicted files: `git diff --name-only --diff-filter=U`
3. Resolve conflicts and re-trigger Phase 5
4. If this happens frequently, consider lowering `parallel.max_agents` or improving domain partitioning

### 14. Parallel File Ownership Violation (v5.0)

**Error Message**:
```json
{"decision": "block", "reason": "File ownership violation: agent 'frontend' wrote to backend/src/..."}
```

**Cause**: In parallel mode, an Agent modified files outside its `owned_files` scope.

**Fix**:
1. Check whether the `project_context.project_structure` directory mapping is accurate
2. Confirm whether cross-domain files should be assigned to the correct domain
3. If the cross-domain modification is legitimate, adjust the domain partitioning or mark that task as a serial dependency

### 15. TDD RED Phase Test Unexpectedly Passed (v4.1)

**Error Message**:
```json
{"decision": "block", "reason": "TDD RED phase: test must fail (exit_code=0, expected non-zero)"}
```

**Cause**: The test written during the RED phase passed immediately, meaning it does not actually verify new functionality.

**Fix**:
1. Check whether the test uses the correct assertions
2. Ensure the test actually tests functionality that has not been implemented yet
3. Fix the test so it fails without the implementation
4. Avoid tautological assertions (`expect(true).toBe(true)` etc. — the L2 Hook also catches these)

### 16. TDD REFACTOR Regression Failure (v4.1)

**Error Message**: Tests fail after the REFACTOR step.

**Cause**: The refactoring introduced a regression.

**Fix**:
- The system automatically runs `git checkout` to roll back to the pre-REFACTOR state
- Check whether the refactoring changes altered behavior (behavior should remain unchanged)
- Retry with a more conservative refactoring strategy

## Debugging Hook Scripts

### Enable Verbose Output

Hook scripts output diagnostic information to stderr (visible in Claude Code verbose mode, Ctrl+O):

```
OK: Valid autopilot JSON envelope with status="ok"
INFO: JSON envelope missing optional field: artifacts
```

### Test Hooks Locally

```bash
# Run the full test suite
make test

# Test the unified post-task validator with mock input
echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:4 -->\nTest"},"tool_response":"..."}' \
  | bash plugins/spec-autopilot/runtime/scripts/post-task-validator.sh
```

### Check Hook Registration

```bash
# Verify hooks.json is valid
python3 -c "import json; json.load(open('plugins/spec-autopilot/hooks/hooks.json'))"

# Check all hooks have timeout configuration
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

### Syntax Check All Scripts

```bash
for f in plugins/spec-autopilot/runtime/scripts/*.sh; do
  bash -n "$f" && echo "OK: $(basename $f)" || echo "FAIL: $(basename $f)"
done
```

## Recovery Scenarios

### Scenario 1: Mid-Run Crash

**Automatic Recovery Flow**:
1. On next startup, `scan-checkpoints-on-start.sh` runs automatically
2. Reports all existing checkpoints
3. When autopilot is triggered again, the `autopilot-recovery` Skill scans checkpoints
4. The pipeline resumes from the last completed phase + 1

Simply re-run `/autopilot`. Phase 5 supports task-level recovery: even if interrupted at task 3/10, it can resume from task 3.

**Manual Recovery**:
```bash
# View current state
ls openspec/changes/<name>/context/phase-results/

# Check checkpoint status
python3 -c "
import json, glob
for f in sorted(glob.glob('openspec/changes/<name>/context/phase-results/phase-*.json')):
    with open(f) as fh:
        d = json.load(fh)
    print(f'{f}: status={d.get(\"status\")}')"
```

### Scenario 2: State Lost After Context Compaction

**Automatic Handling Flow**:
1. The `PreCompact` Hook saves state to `autopilot-state.md`
2. After compaction, the `SessionStart(compact)` Hook re-injects the state
3. The main thread detects the `=== AUTOPILOT STATE RESTORED ===` marker
4. Reads checkpoint files and continues

If you see this marker, recovery was successful. If recovery fails, manually check whether the `context/autopilot-state.md` file exists.

### Scenario 3: Restart from a Specific Phase

**Steps**:
1. Delete the checkpoint files for that phase and all subsequent phases:
   ```bash
   rm openspec/changes/<name>/context/phase-results/phase-{N..7}-*.json
   ```
2. Re-trigger autopilot
3. Crash recovery will detect Phase N-1 as the last completed phase
4. The pipeline resumes from Phase N

## FAQ

**Q: Can I run autopilot on a project with existing code?**
A: Yes. Enable `brownfield_validation` in the configuration for drift detection. The pipeline supports both greenfield and brownfield projects.

**Q: How does Phase 5 serial mode work?**
A: Phase 5 serial mode uses foreground Task dispatch — each task is sent synchronously to the sub-Agent. No external plugins are needed.

**Q: Can I skip certain phases?**
A: No. All 8 phases are required. If a phase is not applicable, the sub-Agent should return `status: "ok"` and explain the reason in the summary, rather than skipping it.

**Q: How do I adjust test thresholds?**
A: Edit `config.phases.testing.gate.min_test_count_per_type` to set Layer 3 thresholds. Layer 2 Hooks use relaxed floors (30% unit tests, 40% E2E cap, minimum 10 total) and cannot be modified through configuration.

**Q: What happens when a quality scan times out?**
A: The scan is marked as `"timeout"` in the quality summary table. It does not block Phase 7 archiving.

**Q: How do I recover after a parallel mode failure?**
A: Parallel mode supports task-level recovery. Re-trigger `/autopilot` — completed tasks are preserved and only the failed tasks are re-executed. For a full re-execution, delete `phase-5-implement.json` and re-trigger.

**Q: Do I need to start the GUI before running autopilot?**
A: No. The GUI is an optional observation tool. Events are always written to `logs/events.jsonl`, and the GUI automatically loads historical events when started. You can start the GUI at any time during an autopilot run.

**Q: Can I manually override routing_overrides thresholds?**
A: Not directly. `routing_overrides` are automatically written to the checkpoint by Phase 1. If you need adjustments, you can set global floor thresholds in `test_pyramid.hook_floors`, or adjust the requirement description so Phase 1 reclassifies it.
