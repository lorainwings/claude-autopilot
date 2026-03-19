#!/usr/bin/env python3
"""_config_validator.py
Validates .claude/autopilot.config.yaml schema completeness, types, ranges,
and cross-references. Called from validate-config.sh.

Usage: python3 _config_validator.py <config_file_path>
Output: JSON on stdout: {"valid": bool, "missing_keys": [...], "type_errors": [...], ...}
"""

import json
import re
import sys


def get_value(data, key_path):
    """Get nested dict value by dotted key path. Returns None if not found."""
    if not isinstance(data, dict):
        return None
    # Try nested traversal first (PyYAML produces nested dicts)
    parts = key_path.split(".")
    current = data
    for part in parts:
        if isinstance(current, dict) and part in current:
            current = current[part]
        else:
            # Fallback: flat dotted key (regex fallback parser)
            return data.get(key_path)
    return current


def check_key(data, key_path):
    """Check if a key exists in nested dict or flat key dict."""
    if isinstance(data, dict):
        parts = key_path.split(".")
        current = data
        for part in parts:
            if isinstance(current, dict) and part in current:
                current = current[part]
            else:
                return key_path in data
        return True
    return False


def parse_yaml(config_path):
    """Parse YAML file. PyYAML priority, regex fallback."""
    warnings = []

    # Strategy 1: PyYAML
    try:
        import yaml

        with open(config_path) as f:
            data = yaml.safe_load(f)
        return data or {}, warnings
    except ImportError:
        warnings.append("PyYAML not installed, using basic parser")
    except Exception as e:
        return None, [f"yaml_parse_error: {e}"]

    # Strategy 2: Regex fallback
    yaml_data = {}
    try:
        with open(config_path) as f:
            content = f.read()
        for m in re.finditer(r"^(\w[\w_]*):", content, re.MULTILINE):
            yaml_data[m.group(1)] = True
        lines = content.split("\n")
        path = []
        indent_stack = [-1]
        for line in lines:
            stripped = line.lstrip()
            if not stripped or stripped.startswith("#"):
                continue
            indent = len(line) - len(stripped)
            key_match = re.match(r"([\w][\w_.]*):\s*(.*)", stripped)
            if key_match:
                key = key_match.group(1)
                while indent_stack and indent <= indent_stack[-1]:
                    indent_stack.pop()
                    if path:
                        path.pop()
                path.append(key)
                indent_stack.append(indent)
                full_key = ".".join(path)
                raw = key_match.group(2).strip()
                if not raw:
                    yaml_data[full_key] = True
                elif raw.lower() == "true":
                    yaml_data[full_key] = True
                elif raw.lower() == "false":
                    yaml_data[full_key] = False
                else:
                    try:
                        yaml_data[full_key] = int(raw)
                    except ValueError:
                        try:
                            yaml_data[full_key] = float(raw)
                        except ValueError:
                            yaml_data[full_key] = raw.strip('"').strip("'")
    except Exception as e:
        return None, [f"parse_error: {e}"]

    return yaml_data, warnings


# --- Validation rules ---

REQUIRED_TOP = ["version", "services", "phases", "test_suites"]

REQUIRED_NESTED = [
    "phases.requirements.agent",
    "phases.testing.agent",
    "phases.testing.gate.min_test_count_per_type",
    "phases.testing.gate.required_test_types",
    "phases.implementation.serial_task.max_retries_per_task",
    "phases.reporting.coverage_target",
    "phases.reporting.zero_skip_required",
]

RECOMMENDED = ["test_pyramid", "gates", "context_management", "project_context"]

TYPE_RULES = {
    "version": str,
    "phases.requirements.min_qa_rounds": (int, float),
    "phases.requirements.auto_scan.enabled": bool,
    "phases.requirements.auto_scan.max_depth": (int, float),
    "phases.requirements.research.enabled": bool,
    "phases.requirements.research.agent": str,
    "phases.requirements.complexity_routing.enabled": bool,
    "phases.requirements.complexity_routing.thresholds.small": (int, float),
    "phases.requirements.complexity_routing.thresholds.medium": (int, float),
    "project_context.test_credentials.username": str,
    "project_context.test_credentials.password": str,
    "project_context.test_credentials.login_endpoint": str,
    "project_context.project_structure.backend_dir": str,
    "project_context.project_structure.frontend_dir": str,
    "phases.testing.gate.min_test_count_per_type": (int, float),
    "phases.implementation.serial_task.max_retries_per_task": (int, float),
    "phases.reporting.coverage_target": (int, float),
    "phases.reporting.zero_skip_required": bool,
    "test_pyramid.min_unit_pct": (int, float),
    "test_pyramid.max_e2e_pct": (int, float),
    "test_pyramid.min_total_cases": (int, float),
    "test_pyramid.traceability_floor": (int, float),
    "phases.code_review.enabled": bool,
    "phases.implementation.parallel.enabled": bool,
    "phases.implementation.parallel.max_agents": (int, float),
    "phases.implementation.wall_clock_timeout_hours": (int, float),
    "phases.implementation.tdd_mode": bool,
    "phases.implementation.tdd_refactor": bool,
    "phases.implementation.tdd_test_command": str,
    "default_mode": str,
    "background_agent_timeout_minutes": (int, float),
    "test_pyramid.hook_floors.min_unit_pct": (int, float),
    "test_pyramid.hook_floors.max_e2e_pct": (int, float),
    "test_pyramid.hook_floors.min_total_cases": (int, float),
    "test_pyramid.hook_floors.min_change_coverage_pct": (int, float),
}

ENUM_RULES = {
    "phases.reporting.format": ["allure", "custom"],
    "default_mode": ["full", "lite", "minimal"],
    "phases.implementation.tdd_test_command": None,  # free-form string, no enum
}

RANGE_RULES = {
    "phases.testing.gate.min_test_count_per_type": (1, 100),
    "phases.implementation.serial_task.max_retries_per_task": (1, 10),
    "phases.reporting.coverage_target": (0, 100),
    "test_pyramid.min_unit_pct": (0, 100),
    "test_pyramid.max_e2e_pct": (0, 100),
    "test_pyramid.min_total_cases": (1, 1000),
    "test_pyramid.traceability_floor": (0, 100),
    "phases.implementation.parallel.max_agents": (1, 10),
    "phases.implementation.wall_clock_timeout_hours": (0.1, 24),
    "test_pyramid.hook_floors.min_unit_pct": (0, 100),
    "test_pyramid.hook_floors.max_e2e_pct": (0, 100),
    "test_pyramid.hook_floors.min_total_cases": (1, 1000),
    "test_pyramid.hook_floors.min_change_coverage_pct": (0, 100),
    "background_agent_timeout_minutes": (1, 120),
    "async_quality_scans.timeout_minutes": (1, 120),
    "phases.requirements.auto_scan.max_depth": (1, 5),
    "phases.requirements.complexity_routing.thresholds.small": (1, 20),
    "phases.requirements.complexity_routing.thresholds.medium": (2, 50),
    "phases.requirements.min_qa_rounds": (1, 10),
}


def validate(config_path):
    """Full validation of autopilot config file. Returns result dict."""
    yaml_data, warnings = parse_yaml(config_path)

    if yaml_data is None:
        return {
            "valid": False,
            "missing_keys": warnings,
            "type_errors": [],
            "range_errors": [],
            "cross_ref_warnings": [],
            "warnings": [],
        }

    missing = []
    type_errors = []
    range_errors = []
    cross_ref_warnings = []

    # Required keys
    for key in REQUIRED_TOP:
        if not check_key(yaml_data, key):
            missing.append(key)
    for key in REQUIRED_NESTED:
        if not check_key(yaml_data, key):
            missing.append(key)

    # Recommended keys
    for key in RECOMMENDED:
        if not check_key(yaml_data, key):
            warnings.append(f'Recommended key "{key}" not found')

    # Type validation
    for key_path, expected_type in TYPE_RULES.items():
        val = get_value(yaml_data, key_path)
        if val is None:
            continue
        if not isinstance(val, expected_type):
            if isinstance(expected_type, tuple):
                type_name = "|".join(t.__name__ for t in expected_type)
            else:
                type_name = expected_type.__name__
            type_errors.append(f"{key_path}: expected {type_name}, got {type(val).__name__}")

    # Range validation
    for key_path, (min_val, max_val) in RANGE_RULES.items():
        val = get_value(yaml_data, key_path)
        if val is not None and isinstance(val, (int, float)):
            if val < min_val or val > max_val:
                range_errors.append(f"{key_path}: value {val} out of range [{min_val}, {max_val}]")

    # Enum validation
    enum_errors = []
    for key_path, allowed_values in ENUM_RULES.items():
        if allowed_values is None:
            continue
        val = get_value(yaml_data, key_path)
        if val is not None and isinstance(val, str):
            if val not in allowed_values:
                enum_errors.append(f'{key_path}: "{val}" not in allowed values {allowed_values}')

    # Cross-reference validation
    min_unit = get_value(yaml_data, "test_pyramid.min_unit_pct")
    max_e2e = get_value(yaml_data, "test_pyramid.max_e2e_pct")
    if (
        min_unit is not None
        and max_e2e is not None
        and isinstance(min_unit, (int, float))
        and isinstance(max_e2e, (int, float))
    ):
        if min_unit + max_e2e > 100:
            cross_ref_warnings.append("test_pyramid: min_unit_pct + max_e2e_pct > 100%, impossible distribution")

    st_max = get_value(yaml_data, "phases.implementation.serial_task.max_retries_per_task")
    if isinstance(st_max, (int, float)) and st_max < 1:
        cross_ref_warnings.append("serial_task.max_retries_per_task<1, will not retry on failure")

    par_enabled = get_value(yaml_data, "phases.implementation.parallel.enabled")
    par_max = get_value(yaml_data, "phases.implementation.parallel.max_agents")
    if par_enabled and par_max is not None and isinstance(par_max, (int, float)) and par_max < 2:
        cross_ref_warnings.append("parallel.enabled=true but max_agents<2, no parallelism benefit")

    cov_target = get_value(yaml_data, "phases.reporting.coverage_target")
    zero_skip = get_value(yaml_data, "phases.reporting.zero_skip_required")
    if cov_target is not None and zero_skip is not None:
        if isinstance(cov_target, (int, float)) and cov_target == 0 and zero_skip:
            cross_ref_warnings.append("coverage_target=0 but zero_skip_required=true, may be misconfigured")

    cr_small = get_value(yaml_data, "phases.requirements.complexity_routing.thresholds.small")
    cr_medium = get_value(yaml_data, "phases.requirements.complexity_routing.thresholds.medium")
    if (
        cr_small is not None
        and cr_medium is not None
        and isinstance(cr_small, (int, float))
        and isinstance(cr_medium, (int, float))
    ):
        if cr_small >= cr_medium:
            cross_ref_warnings.append("complexity_routing: thresholds.small >= thresholds.medium, routing ineffective")

    hf_unit = get_value(yaml_data, "test_pyramid.hook_floors.min_unit_pct")
    strict_unit = get_value(yaml_data, "test_pyramid.min_unit_pct")
    if (
        hf_unit is not None
        and strict_unit is not None
        and isinstance(hf_unit, (int, float))
        and isinstance(strict_unit, (int, float))
    ):
        if hf_unit > strict_unit:
            cross_ref_warnings.append(
                f"hook_floors.min_unit_pct ({hf_unit}) > "
                f"test_pyramid.min_unit_pct ({strict_unit}), "
                "floor stricter than gate"
            )

    hf_e2e = get_value(yaml_data, "test_pyramid.hook_floors.max_e2e_pct")
    strict_e2e = get_value(yaml_data, "test_pyramid.max_e2e_pct")
    if (
        hf_e2e is not None
        and strict_e2e is not None
        and isinstance(hf_e2e, (int, float))
        and isinstance(strict_e2e, (int, float))
    ):
        if hf_e2e < strict_e2e:
            cross_ref_warnings.append(
                f"hook_floors.max_e2e_pct ({hf_e2e}) < "
                f"test_pyramid.max_e2e_pct ({strict_e2e}), "
                "floor stricter than gate"
            )

    hf_total = get_value(yaml_data, "test_pyramid.hook_floors.min_total_cases")
    strict_total = get_value(yaml_data, "test_pyramid.min_total_cases")
    if (
        hf_total is not None
        and strict_total is not None
        and isinstance(hf_total, (int, float))
        and isinstance(strict_total, (int, float))
    ):
        if hf_total > strict_total:
            cross_ref_warnings.append(
                f"hook_floors.min_total_cases ({hf_total}) > "
                f"test_pyramid.min_total_cases ({strict_total}), "
                "floor stricter than gate"
            )

    tdd_mode = get_value(yaml_data, "phases.implementation.tdd_mode")
    if tdd_mode is True:
        cross_ref_warnings.append("tdd_mode=true: TDD cycle only active in full execution mode")

    # Cross-ref: required_test_types entries must have corresponding test_suites definitions
    req_types = get_value(yaml_data, "phases.testing.gate.required_test_types")
    # Handle both PyYAML list and regex-fallback string "[unit, api, ...]"
    if isinstance(req_types, str) and req_types.startswith("["):
        req_types = [t.strip().strip("'\"") for t in req_types.strip("[]").split(",") if t.strip()]
    if isinstance(req_types, list) and req_types:
        suites = get_value(yaml_data, "test_suites")
        # Regex fallback stores nested dicts as True; collect child keys instead
        if isinstance(suites, dict):
            suite_keys = set(suites.keys())
        elif suites is True:
            suite_keys = {
                k.split(".")[-1] if k.startswith("test_suites.") and k.count(".") == 1 else k.split(".")[1]
                for k in yaml_data
                if k.startswith("test_suites.") and k != "test_suites"
            }
        else:
            suite_keys = set()
        for rt in req_types:
            if isinstance(rt, str) and rt not in suite_keys:
                cross_ref_warnings.append(
                    f'required_test_types contains "{rt}" but no matching test_suites.{rt} definition found'
                )

    # Cross-ref: domain_agents non-empty but parallel.enabled=false → warning
    domain_agents = get_value(yaml_data, "phases.implementation.parallel.domain_agents")
    # Regex fallback stores nested dicts as True (meaning children exist)
    has_domain_agents = (isinstance(domain_agents, dict) and len(domain_agents) > 0) or (
        domain_agents is True and any(k.startswith("phases.implementation.parallel.domain_agents.") for k in yaml_data)
    )
    if has_domain_agents and not par_enabled:
        cross_ref_warnings.append(
            "domain_agents configured but parallel.enabled=false, domain_agents will be ignored in serial mode"
        )

    # Cross-ref: instruction_files path format validation
    for phase_key in ("requirements", "testing", "implementation", "reporting"):
        inst_files = get_value(yaml_data, f"phases.{phase_key}.instruction_files")
        if isinstance(inst_files, list):
            for path in inst_files:
                if isinstance(path, str) and (path.startswith("/") or ".." in path or path.startswith("~")):
                    cross_ref_warnings.append(
                        f"phases.{phase_key}.instruction_files: "
                        f"path '{path}' uses absolute/relative/home "
                        "notation, should be project-relative"
                    )

    # Cross-ref: hook_floors.min_change_coverage_pct vs reporting.coverage_target
    hf_cov = get_value(yaml_data, "test_pyramid.hook_floors.min_change_coverage_pct")
    gate_cov = get_value(yaml_data, "phases.reporting.coverage_target")
    if (
        hf_cov is not None
        and gate_cov is not None
        and isinstance(hf_cov, (int, float))
        and isinstance(gate_cov, (int, float))
    ):
        if hf_cov > gate_cov:
            cross_ref_warnings.append(
                f"hook_floors.min_change_coverage_pct ({hf_cov}) > "
                f"reporting.coverage_target ({gate_cov}), "
                "floor stricter than gate"
            )

    # Cross-ref: tdd_mode=true requires non-empty test_suites
    if tdd_mode is True:
        suites_for_tdd = get_value(yaml_data, "test_suites")
        if not suites_for_tdd or (isinstance(suites_for_tdd, dict) and len(suites_for_tdd) == 0):
            cross_ref_warnings.append(
                "tdd_mode=true but test_suites is empty, TDD cycle requires at least one test suite"
            )

    # default_mode enum validation is now handled by ENUM_RULES

    valid = len(missing) == 0 and len(type_errors) == 0 and len(enum_errors) == 0
    return {
        "valid": valid,
        "missing_keys": missing,
        "type_errors": type_errors,
        "range_errors": range_errors,
        "enum_errors": enum_errors,
        "cross_ref_warnings": cross_ref_warnings,
        "warnings": warnings,
    }


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(
            json.dumps(
                {"valid": False, "missing_keys": ["usage: python3 _config_validator.py <config_path>"], "warnings": []}
            )
        )
        sys.exit(0)

    config_path = sys.argv[1]
    result = validate(config_path)
    print(json.dumps(result))
