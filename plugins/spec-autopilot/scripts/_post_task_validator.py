#!/usr/bin/env python3
"""_post_task_validator.py
Unified PostToolUse(Task) validator for autopilot hooks.
Combines 5 validators into one python3 process (~100ms vs ~420ms).

Validators (run in order, first block wins):
  1. JSON envelope validation (structure, required fields, phase-specific)
  2. Anti-rationalization detection (Phase 4/5/6)
  3. Code constraint check (Phase 4/5/6)
  4. Parallel merge guard (Phase 5 worktree merges)
  5. Decision format validation (Phase 1)

Input: stdin JSON from Claude Code PostToolUse hook
Output: JSON {"decision": "block", "reason": "..."} on failure, nothing on success
"""

import importlib.util
import json
import os
import re
import subprocess
import sys

# --- Import shared modules ---
_script_dir = os.environ.get("SCRIPT_DIR", os.path.dirname(os.path.abspath(__file__)))

_spec = importlib.util.spec_from_file_location(
    "_ep", os.path.join(_script_dir, "_envelope_parser.py")
)
_ep = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_ep)

_spec2 = importlib.util.spec_from_file_location(
    "_cl", os.path.join(_script_dir, "_constraint_loader.py")
)
_cl = importlib.util.module_from_spec(_spec2)
_spec2.loader.exec_module(_cl)


def output_block(reason, fix_suggestion=None):
    """Output a block decision and exit. Optionally includes fix_suggestion."""
    result = {"decision": "block", "reason": reason}
    if fix_suggestion:
        result["fix_suggestion"] = fix_suggestion
    print(json.dumps(result))
    sys.exit(0)


# --- Parse input ---
try:
    data = json.load(sys.stdin)
except (json.JSONDecodeError, ValueError) as e:
    print(f"WARNING: Hook received malformed JSON from Claude Code: {e}", file=sys.stderr)
    sys.exit(0)

prompt = data.get("tool_input", {}).get("prompt", "")
phase_match = re.search(r"<!--\s*autopilot-phase:(\d+)\s*-->", prompt)
if not phase_match:
    sys.exit(0)

phase_num = int(phase_match.group(1))
output = _ep.normalize_tool_response(data)

if not output.strip():
    output_block(
        "Autopilot sub-agent returned empty output. The orchestrator should re-dispatch this phase."
    )

# --- Extract envelope (shared across all validators) ---
envelope = _ep.extract_envelope(output)


# ============================================================
# VALIDATOR 1: JSON Envelope Structure
# ============================================================

if not envelope:
    output_block(
        'No valid JSON envelope found in autopilot sub-agent output. '
        'The sub-agent must return a JSON object with at least {"status": "ok|warning|blocked|failed"}. '
        "Re-dispatch this phase with clearer instructions."
    )

if "status" not in envelope:
    output_block(
        'Autopilot JSON envelope missing required field: status. '
        'The sub-agent must return {"status": "ok|warning|blocked|failed", ...}.'
    )

if "summary" not in envelope:
    print("WARNING: JSON envelope missing recommended field: summary", file=sys.stderr)

valid_statuses = ["ok", "warning", "blocked", "failed"]
if envelope["status"] not in valid_statuses:
    output_block(
        f'Invalid autopilot status "{envelope["status"]}". Must be one of: {valid_statuses}'
    )

if "artifacts" not in envelope:
    print("INFO: JSON envelope missing optional field: artifacts", file=sys.stderr)
if "next_ready" not in envelope:
    print("INFO: JSON envelope missing optional field: next_ready", file=sys.stderr)

# Phase-specific required fields
phase_required = {
    4: ["test_counts", "dry_run_results", "test_pyramid", "change_coverage"],
    5: ["test_results_path", "tasks_completed", "zero_skip_check"],
    6: ["pass_rate", "report_path", "report_format"],
}
phase_recommended = {
    4: ["test_traceability"],
    6: ["suite_results", "anomaly_alerts"],
}

if phase_num in phase_required:
    missing_phase = [f for f in phase_required[phase_num] if f not in envelope]
    if missing_phase:
        output_block(
            f"Phase {phase_num} JSON envelope missing required phase-specific fields: {missing_phase}. "
            "The sub-agent must include these fields for gate verification."
        )

# Phase 5: zero_skip_check.passed must be true when status is ok
if phase_num == 5 and envelope.get("status") == "ok":
    zsc = envelope.get("zero_skip_check", {})
    if isinstance(zsc, dict) and zsc.get("passed") is not True:
        output_block(
            f'Phase 5 status is "ok" but zero_skip_check.passed is not true '
            f'(got: {zsc.get("passed", "missing")}). All tests must pass with zero skips before proceeding.'
        )

if phase_num in phase_recommended:
    missing_rec = [f for f in phase_recommended[phase_num] if f not in envelope]
    if missing_rec:
        print(
            f"INFO: Phase {phase_num} envelope missing recommended fields (non-blocking): {missing_rec}",
            file=sys.stderr,
        )

# Phase 4: warning not acceptable
if phase_num == 4 and envelope["status"] == "warning":
    output_block(
        'Phase 4 returned "warning" but only "ok" or "blocked" are accepted. Re-dispatch Phase 4.'
    )

# Phase 4 and 6: artifacts must be non-empty
if phase_num in (4, 6):
    artifacts = envelope.get("artifacts", [])
    if not isinstance(artifacts, list) or len(artifacts) == 0:
        output_block(
            f'Phase {phase_num} "artifacts" is empty or missing. '
            f"Phase {phase_num} must produce actual output files."
        )

# Phase 4: test_pyramid floor validation
if phase_num == 4:
    _root = _ep.find_project_root(data)

    def read_hook_floor(key, default):
        val = _ep.read_config_value(_root, f"test_pyramid.hook_floors.{key}", default)
        try:
            return int(val) if val is not None else default
        except (ValueError, TypeError):
            return default

    FLOOR_MIN_UNIT_PCT = read_hook_floor("min_unit_pct", 30)
    FLOOR_MAX_E2E_PCT = read_hook_floor("max_e2e_pct", 40)
    FLOOR_MIN_TOTAL_CASES = read_hook_floor("min_total_cases", 10)
    FLOOR_MIN_CHANGE_COV = read_hook_floor("min_change_coverage_pct", 80)

    pyramid = envelope.get("test_pyramid", {})
    unit_pct = pyramid.get("unit_pct", 0)
    e2e_pct = pyramid.get("e2e_pct", 0)
    total = envelope.get("test_counts", {})
    total_sum = sum(v for v in total.values() if isinstance(v, (int, float)))

    violations = []
    if isinstance(unit_pct, (int, float)) and unit_pct < FLOOR_MIN_UNIT_PCT:
        violations.append(f"unit_pct={unit_pct}% < {FLOOR_MIN_UNIT_PCT}% floor")
    if isinstance(e2e_pct, (int, float)) and e2e_pct > FLOOR_MAX_E2E_PCT:
        violations.append(f"e2e_pct={e2e_pct}% > {FLOOR_MAX_E2E_PCT}% ceiling")
    if total_sum < FLOOR_MIN_TOTAL_CASES:
        violations.append(f"total_cases={total_sum} < {FLOOR_MIN_TOTAL_CASES} minimum")

    if violations:
        output_block(
            f'Phase 4 test_pyramid floor violation (Layer 2): {";".join(violations)}. '
            "Adjust test distribution before proceeding.",
            fix_suggestion="增加单元测试数量或减少 E2E 测试占比。阈值可在 config.test_pyramid.hook_floors 中调整。参考: docs/config-tuning-guide.md"
        )

    # Phase 4 test_traceability L2 blocking (v4.0 upgrade from recommended to required)
    TRACEABILITY_FLOOR = read_hook_floor("traceability_floor", 80)
    # Read from top-level test_pyramid.traceability_floor as override
    traceability_floor_cfg = _ep.read_config_value(
        _root, "test_pyramid.traceability_floor", TRACEABILITY_FLOOR
    )
    try:
        traceability_floor_val = int(traceability_floor_cfg)
    except (ValueError, TypeError):
        traceability_floor_val = 80

    traceability = envelope.get("test_traceability", {})
    if isinstance(traceability, dict):
        trace_coverage = traceability.get("coverage_pct", None)
        if trace_coverage is not None and isinstance(trace_coverage, (int, float)):
            if trace_coverage < traceability_floor_val:
                output_block(
                    f"Phase 4 test_traceability coverage {trace_coverage}% < {traceability_floor_val}% floor. "
                    "Each test case must trace to a Phase 1 requirement. "
                    "Add traceability mappings to increase coverage.",
                    fix_suggestion="为每个测试用例添加 requirement 追溯映射。阈值可在 config.test_pyramid.traceability_floor 中调整。参考: docs/troubleshooting-faq.md#10"
                )

    # Phase 4 change_coverage validation
    cc = envelope.get("change_coverage", {})
    if not isinstance(cc, dict) or not cc or "change_points" not in cc:
        output_block(
            "Phase 4 change_coverage is empty or malformed. "
            "Must include change_points, tested_points, coverage_pct, untested_points."
        )
    cov_pct = cc.get("coverage_pct", 0)
    if isinstance(cov_pct, (int, float)) and cov_pct < FLOOR_MIN_CHANGE_COV:
        untested = cc.get("untested_points", [])
        shown = untested[:3] if isinstance(untested, list) else []
        output_block(
            f"Phase 4 change_coverage insufficient: {cov_pct}% < {FLOOR_MIN_CHANGE_COV}% threshold. "
            f"Untested: {', '.join(str(p) for p in shown)}. Add targeted tests for each change point."
        )

print(
    f'OK: Valid autopilot JSON envelope with status="{envelope["status"]}"',
    file=sys.stderr,
)


# ============================================================
# VALIDATOR 2: Anti-Rationalization Check (Phase 4/5/6 only)
# ============================================================

if phase_num in (4, 5, 6) and envelope.get("status") in ("ok", "warning"):
    WEIGHTED_PATTERNS = [
        (3, r"skip(ped|ping)?\s+(this|the|these|because)\s"),
        (3, r"(tests?|tasks?)\s+were\s+skip(ped|ping)"),
        (3, r"(deferred?|postponed?|deprioritized?)\s+(to|for|until)"),
        (2, r"out\s+of\s+scope"),
        (2, r"(will|can|should)\s+(be\s+)?(done|handled|addressed|fixed)\s+(later|separately|in\s+a?\s*future)"),
        (1, r"already\s+(covered|tested|handled|addressed)"),
        (1, r"not\s+(needed|necessary|required|relevant|applicable)"),
        (1, r"(works|good)\s+enough"),
        (1, r"too\s+(complex|difficult|risky|time[- ]consuming)"),
        (1, r"(minimal|low)\s+(impact|priority|risk)"),
        (1, r"pre[- ]existing\s+(issue|bug|problem|defect)"),
        (3, r"(?:测试|任务|功能|用例)\s*(?:被|已)?(?:跳过|省略|忽略)"),
        (3, r"跳过了?|已跳过|被跳过"),
        (3, r"(?:延后|推迟|暂缓)(?:处理|实现|开发)?"),
        (3, r"后续(?:再|补充|处理|实现|完善)"),
        (2, r"(?:超出|不在)(?:范围|scope)"),
        (2, r"(?:以后|后面|后续|下[一个]?(?:阶段|版本|迭代))(?:再|来|处理|实现)"),
        (2, r"(?:暂时|先)?不(?:做|处理|实现|考虑)"),
        (1, r"已[经被]?(?:覆盖|测试|处理|实现|验证)"),
        (1, r"(?:不|无)(?:需要|必要|需|必须)"),
        (1, r"(?:太|过于)(?:复杂|困难|耗时)"),
        (1, r"(?:影响|优先级|风险)\s*(?:较?低|不大|很小)"),
    ]

    output_lower = output.lower()
    total_score = 0
    found_patterns = []
    for weight, pattern in WEIGHTED_PATTERNS:
        if re.search(pattern, output_lower):
            total_score += weight
            found_patterns.append((weight, pattern))

    has_artifacts = False
    arts = envelope.get("artifacts", [])
    has_artifacts = isinstance(arts, list) and len(arts) > 0

    _sep = ", "
    if total_score >= 5:
        output_block(
            f"Anti-rationalization check: Phase {phase_num} output scored {total_score} "
            f"(threshold 5). Multiple strong skip/rationalization patterns detected. "
            f"Review and re-dispatch. Patterns: {_sep.join(p for _, p in found_patterns[:3])}"
        )

    if total_score >= 3 and not has_artifacts:
        output_block(
            f"Anti-rationalization check: Phase {phase_num} output scored {total_score} "
            f"with no artifacts produced. Suspected rationalization without deliverables. "
            f"Review and re-dispatch. Patterns: {_sep.join(p for _, p in found_patterns[:3])}"
        )

    if total_score >= 2:
        print(
            json.dumps(
                {
                    "decision": "warn",
                    "reason": f"Anti-rationalization advisory: Phase {phase_num} output scored "
                    f"{total_score} but has artifacts. Patterns: {_sep.join(p for _, p in found_patterns[:3])}",
                }
            ),
            file=sys.stderr,
        )


# ============================================================
# VALIDATOR 3: Code Constraint Check (Phase 4/5/6 only)
# ============================================================

if phase_num in (4, 5, 6) and envelope.get("status") in ("ok", "warning"):
    artifacts = envelope.get("artifacts", [])
    if isinstance(artifacts, list) and artifacts:
        root = _ep.find_project_root(data)
        constraints = _cl.load_constraints(root)
        if constraints["found"] or constraints["forbidden_files"] or constraints["forbidden_patterns"]:
            violations = []
            for art in artifacts:
                if isinstance(art, str):
                    violations.extend(_cl.check_file_violations(art, root, constraints))
            if violations:
                shown = violations[:5]
                extra = f" (+{len(violations)-5} more)" if len(violations) > 5 else ""
                output_block(
                    f"Code constraint violations ({len(violations)}): "
                    + "; ".join(shown)
                    + extra
                    + ". Fix before proceeding."
                )


# ============================================================
# VALIDATOR 4: Parallel Merge Guard (Phase 5 worktree merges)
# ============================================================

if phase_num == 5:
    merge_pattern = re.compile(
        r"worktree.*merge|merge.*worktree|git\s+merge.*autopilot-task", re.IGNORECASE
    )
    if merge_pattern.search(output):
        root = _ep.find_project_root(data)
        merge_violations = []

        # Check 1: Merge conflicts
        try:
            result = subprocess.run(
                ["git", "diff", "--check"],
                cwd=root, capture_output=True, text=True, timeout=15,
            )
            if result.returncode != 0 and result.stdout.strip():
                conflict_lines = result.stdout.strip().split("\n")[:5]
                merge_violations.append("Merge conflicts detected: " + "; ".join(conflict_lines))
        except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
            pass

        try:
            result = subprocess.run(
                ["git", "diff", "--cached", "--check"],
                cwd=root, capture_output=True, text=True, timeout=15,
            )
            if result.returncode != 0 and result.stdout.strip():
                conflict_lines = result.stdout.strip().split("\n")[:5]
                merge_violations.append("Staged merge conflicts: " + "; ".join(conflict_lines))
        except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
            pass

        # Check 2: Scope validation
        expected_artifacts = []
        if envelope and isinstance(envelope.get("artifacts"), list):
            expected_artifacts = [a for a in envelope["artifacts"] if isinstance(a, str)]

        anchor_sha = None
        lock_path = os.path.join(root, "openspec", "changes", ".autopilot-active")
        if os.path.isfile(lock_path):
            try:
                with open(lock_path) as lf:
                    lock_data = json.loads(lf.read())
                    anchor_sha = lock_data.get("anchor_sha", "") or None
            except (json.JSONDecodeError, ValueError, OSError):
                pass

        if expected_artifacts:
            diff_base = None
            if anchor_sha:
                try:
                    is_ancestor = subprocess.run(
                        ["git", "merge-base", "--is-ancestor", anchor_sha, "HEAD"],
                        cwd=root, capture_output=True, text=True, timeout=5,
                    ).returncode == 0
                    if is_ancestor:
                        diff_base = anchor_sha
                except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
                    pass
            if not diff_base:
                try:
                    if subprocess.run(
                        ["git", "rev-parse", "--verify", "HEAD~1"],
                        cwd=root, capture_output=True, text=True, timeout=5,
                    ).returncode == 0:
                        diff_base = "HEAD~1"
                except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
                    pass

            if diff_base:
                try:
                    result = subprocess.run(
                        ["git", "diff", "--name-only", diff_base, "HEAD"],
                        cwd=root, capture_output=True, text=True, timeout=15,
                    )
                    if result.returncode == 0 and result.stdout.strip():
                        changed_files = [f.strip() for f in result.stdout.strip().split("\n") if f.strip()]
                        expected_rel = set()
                        for art in expected_artifacts:
                            rel = os.path.relpath(art, root) if os.path.isabs(art) else art
                            expected_rel.add(rel)
                            parts = rel.split("/")
                            for j in range(1, len(parts)):
                                expected_rel.add("/".join(parts[:j]))
                        out_of_scope = []
                        for cf in changed_files:
                            in_scope = any(
                                cf == art_rel or cf.startswith(art_rel + "/") or art_rel.startswith(cf + "/")
                                for art_rel in expected_rel
                            )
                            if not in_scope:
                                out_of_scope.append(cf)
                        if out_of_scope:
                            shown = out_of_scope[:5]
                            extra = f" (+{len(out_of_scope)-5} more)" if len(out_of_scope) > 5 else ""
                            merge_violations.append("Files outside task scope: " + ", ".join(shown) + extra)
                except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
                    pass

        # Check 3: Typecheck
        cfg_path = os.path.join(root, ".claude", "autopilot.config.yaml")
        if os.path.isfile(cfg_path):
            try:
                with open(cfg_path) as f:
                    cfg_txt = f.read()
                ts_match = re.search(r"^test_suites:\s*$", cfg_txt, re.MULTILINE)
                if ts_match:
                    section = cfg_txt[ts_match.end():]
                    next_top = re.search(r"^\S", section, re.MULTILINE)
                    section = section[: next_top.start()] if next_top else section
                    suites = re.split(r"\n  (\w[\w_-]*):\s*\n", section)
                    for idx in range(1, len(suites) - 1, 2):
                        body = suites[idx + 1]
                        type_m = re.search(r"type:\s*(\S+)", body)
                        cmd_m = re.search(r"command:\s*[\x22\x27]?(.+?)[\x22\x27]?\s*$", body, re.MULTILINE)
                        if type_m and type_m.group(1) == "typecheck" and cmd_m:
                            cmd = cmd_m.group(1).strip().strip("\x22\x27")
                            try:
                                result = subprocess.run(
                                    cmd, shell=True, cwd=root,
                                    capture_output=True, text=True, timeout=120,
                                )
                                if result.returncode != 0:
                                    stderr_tail = (result.stderr or result.stdout or "").strip()[-300:]
                                    merge_violations.append(f"Typecheck failed [{cmd}]: {stderr_tail}")
                            except subprocess.TimeoutExpired:
                                merge_violations.append(f"Typecheck timed out [{cmd}] (>120s)")
                            except (FileNotFoundError, OSError) as e:
                                merge_violations.append(f"Typecheck error [{cmd}]: {e}")
            except Exception as e:
                print(f"WARNING: parallel-merge-guard config parse: {e}", file=sys.stderr)

        if merge_violations:
            shown = merge_violations[:5]
            extra = f" (+{len(merge_violations)-5} more)" if len(merge_violations) > 5 else ""
            output_block(
                f"Parallel merge guard: {len(merge_violations)} issue(s) after worktree merge: "
                + "; ".join(shown)
                + extra
                + ". Fix conflicts or scope issues before proceeding."
            )


# ============================================================
# VALIDATOR 5: Decision Format (Phase 1 only)
# ============================================================

if phase_num == 1 and envelope and envelope.get("status") in ("ok", "warning"):
    decisions = envelope.get("decisions")
    if not isinstance(decisions, list) or len(decisions) == 0:
        output_block(
            'Phase 1 envelope missing or empty "decisions" array. '
            "At least one DecisionPoint is required."
        )

    complexity = envelope.get("complexity", "medium")
    if complexity not in ("small", "medium", "large"):
        complexity = "medium"

    if complexity == "small":
        errors = []
        for idx, d in enumerate(decisions):
            if not isinstance(d, dict):
                errors.append(f"decisions[{idx}]: not an object")
                continue
            if not d.get("point") and not d.get("choice"):
                errors.append(f'decisions[{idx}]: missing both "point" and "choice"')
        if errors:
            output_block(
                f"Phase 1 decision format errors (small complexity): {'; '.join(errors)}"
            )
        else:
            print(
                f"OK: Phase 1 decisions validated (small complexity, {len(decisions)} decisions)",
                file=sys.stderr,
            )
    else:
        REQUIRED_OPTION_FIELDS = ["label", "description", "pros", "cons"]
        errors = []
        for idx, d in enumerate(decisions):
            prefix = f"decisions[{idx}]"
            if not isinstance(d, dict):
                errors.append(f"{prefix}: not an object")
                continue
            if not d.get("choice"):
                errors.append(f'{prefix}: missing "choice"')
            if not d.get("rationale"):
                errors.append(f'{prefix}: missing "rationale"')
            options = d.get("options")
            if not isinstance(options, list):
                errors.append(f'{prefix}: missing "options" array')
                continue
            if len(options) < 2:
                errors.append(f'{prefix}: "options" must have >= 2 entries, got {len(options)}')
                continue
            has_recommended = False
            for oi, opt in enumerate(options):
                if not isinstance(opt, dict):
                    errors.append(f"{prefix}.options[{oi}]: not an object")
                    continue
                missing = [f for f in REQUIRED_OPTION_FIELDS if not opt.get(f)]
                if missing:
                    errors.append(f"{prefix}.options[{oi}]: missing fields: {missing}")
                if opt.get("recommended") is True:
                    has_recommended = True
            if not has_recommended:
                errors.append(f'{prefix}: no option marked "recommended": true')

        if errors:
            shown = errors[:5]
            extra = f" (+{len(errors)-5} more)" if len(errors) > 5 else ""
            output_block(
                f"Phase 1 decision format violations ({len(errors)}, {complexity} complexity): "
                + "; ".join(shown)
                + extra
                + ". Each decision must have options (>=2) with label/description/pros/cons, "
                + "at least one recommended, plus choice and rationale."
            )
        else:
            print(
                f"OK: Phase 1 decisions validated ({complexity} complexity, {len(decisions)} decisions)",
                file=sys.stderr,
            )

# All validations passed
sys.exit(0)
