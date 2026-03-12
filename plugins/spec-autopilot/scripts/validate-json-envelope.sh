#!/usr/bin/env bash
# validate-json-envelope.sh
# Hook: PostToolUse(Task)
# Purpose: After a sub-Agent completes, validate its output contains a valid
#          JSON envelope with required fields (status/summary).
#
# Detection: Only processes Task calls whose prompt contains
#            <!-- autopilot-phase:N -->. All other Task calls exit 0 immediately.
#
# Output: Uses PostToolUse `decision: "block"` with `reason` to feed validation
#         errors back to Claude as actionable feedback. Exit is always 0.
#         See: https://code.claude.com/docs/en/hooks#posttooluse-decision-control

# NOTE: no `set -e` — we handle errors explicitly.
# --- Common preamble: stdin read, SCRIPT_DIR, _common.sh, Layer 0 bypass ---
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_hook_preamble.sh"

# --- Fast bypass Layer 1: prompt 首行标记检测 ---
# 仅匹配 prompt 字段以标记开头的情况，排除文本内容中的误判。
# Pattern: autopilot-phase:[0-9] (via has_phase_marker from _common.sh)
has_phase_marker || exit 0

# --- Fast bypass Layer 1.5: background agent skip ---
is_background_agent && exit 0

# --- Dependency check: python3 is required for autopilot envelope validation ---
# Fail-closed: block autopilot tasks when python3 unavailable (via require_python3 in _common.sh)
if ! require_python3; then
  exit 0
fi

# --- Single python3 call to do all processing ---
echo "$STDIN_DATA" | python3 -c "
import importlib.util
import json
import os
import re
import sys

# Import shared envelope parser
_script_dir = os.environ.get('SCRIPT_DIR', '.')
_spec = importlib.util.spec_from_file_location('_ep', os.path.join(_script_dir, '_envelope_parser.py'))
_ep = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_ep)

try:
    data = json.load(sys.stdin)
except (json.JSONDecodeError, ValueError) as e:
    print(f'WARNING: Hook received malformed JSON from Claude Code: {e}', file=sys.stderr)
    sys.exit(0)

# 1) Check for autopilot marker in tool_input.prompt
prompt = data.get('tool_input', {}).get('prompt', '')
if not re.search(r'<!--\s*autopilot-phase:\d+\s*-->', prompt):
    sys.exit(0)

# 2) Extract and normalize tool_response
output = _ep.normalize_tool_response(data)

if not output.strip():
    _ep.output_block('Autopilot sub-agent returned empty output. The orchestrator should re-dispatch this phase.')
    sys.exit(0)

# 3) Extract JSON envelope using shared 3-strategy parser
found_json = _ep.extract_envelope(output)

if not found_json:
    _ep.output_block('No valid JSON envelope found in autopilot sub-agent output. The sub-agent must return a JSON object with at least {\"status\": \"ok|warning|blocked|failed\"}. Re-dispatch this phase with clearer instructions.')
    sys.exit(0)

# 4) Validate required fields (only 'status' is hard-required)
if 'status' not in found_json:
    print(json.dumps({
        'decision': 'block',
        'reason': 'Autopilot JSON envelope missing required field: status. The sub-agent must return {\"status\": \"ok|warning|blocked|failed\", ...}.'
    }))
    sys.exit(0)

# 4.5) Warn on missing 'summary' (recommended but not blocking)
if 'summary' not in found_json:
    print('WARNING: JSON envelope missing recommended field: summary', file=sys.stderr)

# 5) Validate status value
valid_statuses = ['ok', 'warning', 'blocked', 'failed']
if found_json['status'] not in valid_statuses:
    print(json.dumps({
        'decision': 'block',
        'reason': f'Invalid autopilot status \"{found_json[\"status\"]}\". Must be one of: {valid_statuses}'
    }))
    sys.exit(0)

# 6) Info-level notices for optional fields (stderr only, not fed to Claude)
if 'artifacts' not in found_json:
    print('INFO: JSON envelope missing optional field: artifacts', file=sys.stderr)
if 'next_ready' not in found_json:
    print('INFO: JSON envelope missing optional field: next_ready', file=sys.stderr)

# 7) Phase-specific field validation (warn on stderr, block on critical missing)
phase_match = re.search(r'autopilot-phase:(\d+)', prompt)
phase_num = int(phase_match.group(1)) if phase_match else 0

# Required fields: block if missing (core gate dependencies)
phase_required = {
    4: ['test_counts', 'dry_run_results', 'test_pyramid', 'change_coverage'],
    5: ['test_results_path', 'tasks_completed', 'zero_skip_check'],
    6: ['pass_rate', 'report_path', 'report_format'],
}

# Recommended fields: warn on stderr if missing (v3.2.0 enhancements, not gate-critical)
phase_recommended = {
    4: ['test_traceability'],
    6: ['suite_results', 'anomaly_alerts'],
}

if phase_num in phase_required:
    missing_phase = [f for f in phase_required[phase_num] if f not in found_json]
    if missing_phase:
        print(json.dumps({
            'decision': 'block',
            'reason': f'Phase {phase_num} JSON envelope missing required phase-specific fields: {missing_phase}. The sub-agent must include these fields for gate verification.'
        }))
        sys.exit(0)

# Phase 5 special: zero_skip_check.passed must be true when status is ok
if phase_num == 5 and found_json.get('status') == 'ok':
    zsc = found_json.get('zero_skip_check', {})
    if isinstance(zsc, dict) and zsc.get('passed') is not True:
        print(json.dumps({
            'decision': 'block',
            'reason': f'Phase 5 status is "ok" but zero_skip_check.passed is not true (got: {zsc.get("passed", "missing")}). All tests must pass with zero skips before proceeding.'
        }))
        sys.exit(0)

if phase_num in phase_recommended:
    missing_rec = [f for f in phase_recommended[phase_num] if f not in found_json]
    if missing_rec:
        print(f'INFO: Phase {phase_num} envelope missing recommended fields (non-blocking): {missing_rec}', file=sys.stderr)

# 8) Phase 4 special: warning status not acceptable — Phase 4 protocol only allows ok/blocked
#    Layer 2 deterministic check — prevents LLM orchestrator from accidentally
#    passing Phase 4 with warning. Phase 4 must re-dispatch until ok or blocked.
if phase_num == 4 and found_json['status'] == 'warning':
    print(json.dumps({
        'decision': 'block',
        'reason': 'Phase 4 returned \"warning\" but only \"ok\" or \"blocked\" are accepted. Re-dispatch Phase 4.'
    }))
    sys.exit(0)

# 9) Phase 4 and 6: artifacts must be non-empty (test files / report files required)
if phase_num in (4, 6):
    artifacts = found_json.get('artifacts', [])
    if not isinstance(artifacts, list) or len(artifacts) == 0:
        print(json.dumps({
            'decision': 'block',
            'reason': f'Phase {phase_num} \"artifacts\" is empty or missing. Phase {phase_num} must produce actual output files.'
        }))
        sys.exit(0)

# 10) Layer 2 test_pyramid floor validation (Phase 4 only)
#     These are lenient floors — strict thresholds enforced by Layer 3 (autopilot-gate).
#     Catches severely inverted pyramids that slip through LLM self-checks.
if phase_num == 4:
    # Read floor thresholds from config using shared module (replaces inline read_hook_floor)
    _root = _ep.find_project_root(data)

    def read_hook_floor(key, default):
        val = _ep.read_config_value(_root, f'test_pyramid.hook_floors.{key}', default)
        try:
            return int(val) if val is not None else default
        except (ValueError, TypeError):
            return default

    FLOOR_MIN_UNIT_PCT = read_hook_floor('min_unit_pct', 30)
    FLOOR_MAX_E2E_PCT = read_hook_floor('max_e2e_pct', 40)
    FLOOR_MIN_TOTAL_CASES = read_hook_floor('min_total_cases', 10)
    FLOOR_MIN_CHANGE_COV = read_hook_floor('min_change_coverage_pct', 80)

    pyramid = found_json.get('test_pyramid', {})
    unit_pct = pyramid.get('unit_pct', 0)
    e2e_pct = pyramid.get('e2e_pct', 0)
    total = found_json.get('test_counts', {})
    total_sum = sum(v for v in total.values() if isinstance(v, (int, float)))

    violations = []
    if isinstance(unit_pct, (int, float)) and unit_pct < FLOOR_MIN_UNIT_PCT:
        violations.append(f'unit_pct={unit_pct}% < {FLOOR_MIN_UNIT_PCT}% floor')
    if isinstance(e2e_pct, (int, float)) and e2e_pct > FLOOR_MAX_E2E_PCT:
        violations.append(f'e2e_pct={e2e_pct}% > {FLOOR_MAX_E2E_PCT}% ceiling')
    if total_sum < FLOOR_MIN_TOTAL_CASES:
        violations.append(f'total_cases={total_sum} < {FLOOR_MIN_TOTAL_CASES} minimum')

    if violations:
        print(json.dumps({
            'decision': 'block',
            'reason': f'Phase 4 test_pyramid floor violation (Layer 2): {\";\".join(violations)}. Adjust test distribution before proceeding.'
        }))
        sys.exit(0)

    # 10.5) Phase 4 change_coverage validation
    cc = found_json.get('change_coverage', {})
    if not isinstance(cc, dict) or not cc or 'change_points' not in cc:
        print(json.dumps({
            'decision': 'block',
            'reason': 'Phase 4 change_coverage is empty or malformed. Must include change_points, tested_points, coverage_pct, untested_points.'
        }))
        sys.exit(0)
    cov_pct = cc.get('coverage_pct', 0)
    if isinstance(cov_pct, (int, float)) and cov_pct < FLOOR_MIN_CHANGE_COV:
        untested = cc.get('untested_points', [])
        shown = untested[:3] if isinstance(untested, list) else []
        print(json.dumps({
            'decision': 'block',
            'reason': f'Phase 4 change_coverage insufficient: {cov_pct}% < {FLOOR_MIN_CHANGE_COV}% threshold. Untested: {(chr(44)+chr(32)).join(str(p) for p in shown)}. Add targeted tests for each change point.'
        }))
        sys.exit(0)

# All valid → no output, let PostToolUse proceed normally
print(f'OK: Valid autopilot JSON envelope with status=\"{found_json[\"status\"]}\"', file=sys.stderr)
sys.exit(0)
"
# NOTE: python3 stderr is NOT suppressed — allows observability of INFO messages
# and uncaught exceptions in verbose mode (Ctrl+O).

exit 0
