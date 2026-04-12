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

RECOMMENDED = ["test_pyramid", "gates", "context_management", "project_context", "model_routing"]

TYPE_RULES = {
    "version": str,
    "phases.requirements.min_qa_rounds": (int, float),
    "phases.requirements.max_rounds": (int, float),
    "phases.requirements.soft_warning_rounds": (int, float),
    "phases.requirements.clarity_threshold": (int, float),
    "phases.requirements.clarity_threshold_overrides.small": (int, float),
    "phases.requirements.clarity_threshold_overrides.medium": (int, float),
    "phases.requirements.clarity_threshold_overrides.large": (int, float),
    "phases.requirements.challenge_agents.enabled": bool,
    "phases.requirements.challenge_agents.contrarian_after_round": (int, float),
    "phases.requirements.challenge_agents.simplifier_after_round": (int, float),
    "phases.requirements.challenge_agents.simplifier_scope_threshold": (int, float),
    "phases.requirements.challenge_agents.ontologist_after_round": (int, float),
    "phases.requirements.one_question_per_round": bool,
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
    "phases.requirements.max_rounds": (3, 30),
    "phases.requirements.soft_warning_rounds": (2, 20),
    "phases.requirements.clarity_threshold": (0.5, 1.0),
    "phases.requirements.clarity_threshold_overrides.small": (0.5, 1.0),
    "phases.requirements.clarity_threshold_overrides.medium": (0.5, 1.0),
    "phases.requirements.clarity_threshold_overrides.large": (0.5, 1.0),
    "phases.requirements.challenge_agents.contrarian_after_round": (2, 20),
    "phases.requirements.challenge_agents.simplifier_after_round": (3, 20),
    "phases.requirements.challenge_agents.simplifier_scope_threshold": (2, 20),
    "phases.requirements.challenge_agents.ontologist_after_round": (4, 20),
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

    # HARD BLOCK: research.agent="Explore" is deprecated and breaks runtime.
    # Explore agents are read-only and cannot Write research output files,
    # violating the v3.3.0 self-write constraint. Upgraded users with old
    # config MUST migrate before Phase 0 can complete. This is a hard error
    # (enum_errors → valid=false), NOT a warning — do not downgrade.
    research_agent = get_value(yaml_data, "phases.requirements.research.agent")
    if isinstance(research_agent, str) and research_agent.lower() == "explore":
        enum_errors.append(
            'phases.requirements.research.agent: "Explore" is forbidden '
            "(read-only agents cannot write research output files, causing "
            "Phase 1 dispatch failure). "
            'Change to "general-purpose" in .claude/autopilot.config.yaml'
        )

    # Soft warning: non-builtin agent types (e.g. "business-analyst", "qa-expert")
    # are valid if a matching .claude/agents/{name}.md exists. Since the validator
    # only reads the YAML (not the filesystem), we emit an informational warning
    # guiding the user to install the custom agent via /autopilot-agents.
    KNOWN_BUILTIN_AGENTS = {
        "general-purpose",
        "Explore",
        "Plan",
        "claude-code-guide",
        "statusline-setup",
    }
    agent_fields = [
        "phases.requirements.agent",
        "phases.requirements.research.agent",
        "phases.openspec.agent",
        "phases.testing.agent",
        "phases.reporting.agent",
    ]
    for field in agent_fields:
        agent_val = get_value(yaml_data, field)
        if isinstance(agent_val, str) and agent_val and agent_val not in KNOWN_BUILTIN_AGENTS:
            # Skip the Explore check (already handled as enum_error above)
            if field == "phases.requirements.research.agent" and agent_val.lower() == "explore":
                continue
            cross_ref_warnings.append(
                f'{field}: "{agent_val}" is not a built-in Claude Code agent type. '
                f"Ensure .claude/agents/{agent_val}.md exists, or run "
                f"/autopilot-agents to install recommended community agents."
            )

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

    # Cross-ref: Phase 1 v7.1 clarity system constraints
    soft_warn = get_value(yaml_data, "phases.requirements.soft_warning_rounds")
    max_rounds = get_value(yaml_data, "phases.requirements.max_rounds")
    if (
        soft_warn is not None
        and max_rounds is not None
        and isinstance(soft_warn, (int, float))
        and isinstance(max_rounds, (int, float))
    ):
        if soft_warn >= max_rounds:
            cross_ref_warnings.append(
                f"soft_warning_rounds ({soft_warn}) >= max_rounds ({max_rounds}), "
                "soft warning will never trigger before hard limit"
            )

    min_qa = get_value(yaml_data, "phases.requirements.min_qa_rounds")
    if (
        min_qa is not None
        and max_rounds is not None
        and isinstance(min_qa, (int, float))
        and isinstance(max_rounds, (int, float))
    ):
        if min_qa > max_rounds:
            cross_ref_warnings.append(
                f"min_qa_rounds ({min_qa}) > max_rounds ({max_rounds}), min_qa_rounds can never be satisfied"
            )

    # Cross-ref: challenge agent activation order must be contrarian < simplifier < ontologist
    ca_contrarian = get_value(yaml_data, "phases.requirements.challenge_agents.contrarian_after_round")
    ca_simplifier = get_value(yaml_data, "phases.requirements.challenge_agents.simplifier_after_round")
    ca_ontologist = get_value(yaml_data, "phases.requirements.challenge_agents.ontologist_after_round")
    ca_rounds = [
        ("contrarian", ca_contrarian),
        ("simplifier", ca_simplifier),
        ("ontologist", ca_ontologist),
    ]
    ca_valid = [(name, r) for name, r in ca_rounds if r is not None and isinstance(r, (int, float))]
    if len(ca_valid) >= 2:
        for i in range(len(ca_valid) - 1):
            name_a, round_a = ca_valid[i]
            name_b, round_b = ca_valid[i + 1]
            if round_a >= round_b:
                cross_ref_warnings.append(
                    f"challenge_agents.{name_a}_after_round ({round_a}) >= "
                    f"{name_b}_after_round ({round_b}), "
                    "agents should activate in increasing round order"
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

    # --- model_routing validation ---
    model_routing_errors = []
    mr = get_value(yaml_data, "model_routing")
    if mr is not None:
        VALID_TIERS = {"fast", "standard", "deep", "auto"}
        VALID_MODELS = {"haiku", "sonnet", "opus", "opusplan"}
        VALID_EFFORTS = {"low", "medium", "high"}
        VALID_PHASES = {f"phase_{i}" for i in range(1, 8)}

        # Regex fallback 模式：model_routing 被存为 True，子节点存为 flat dotted keys
        if mr is True:
            mr_dict = {}
            for k, v in yaml_data.items():
                if k.startswith("model_routing.") and k != "model_routing":
                    leaf = k[len("model_routing.") :]
                    mr_dict[leaf] = v
            mr = mr_dict if mr_dict else {}

        # Regex fallback 二次重建：将 phases.phase_N.* dotted keys 嵌套为 dict
        if isinstance(mr, dict) and mr.get("phases") is True:
            phases_dict = {}
            keys_to_remove = []
            for k, v in mr.items():
                if k.startswith("phases."):
                    parts = k[len("phases.") :].split(".", 1)
                    phase_key = parts[0]
                    if phase_key not in phases_dict:
                        phases_dict[phase_key] = {}
                    if len(parts) == 2 and v is not True:
                        phases_dict[phase_key][parts[1]] = v
                    keys_to_remove.append(k)
            for k in keys_to_remove:
                del mr[k]
            mr["phases"] = phases_dict if phases_dict else {}

        if isinstance(mr, str):
            # 顶层字符串 (简写): 必须是有效 tier
            if mr not in VALID_TIERS:
                model_routing_errors.append(f'model_routing: "{mr}" not in allowed values {sorted(VALID_TIERS)}')
        elif isinstance(mr, dict):
            # 新格式对象化配置
            all_phase_keys = all(k in VALID_PHASES for k in mr.keys())
            all_tier_vals = all(isinstance(v, str) and v in VALID_TIERS for v in mr.values())

            if all_phase_keys and all_tier_vals and len(mr) > 0:
                # 简写 per-phase dict (phase_1: fast) — 合法，无需进一步校验
                pass
            else:
                # 新格式对象化配置
                allowed_top_keys = {
                    "enabled",
                    "default_session_model",
                    "default_subagent_model",
                    "fallback_model",
                    "phases",
                    # 允许简写 phase_N 键混在顶层
                } | VALID_PHASES

                for key in mr.keys():
                    if key not in allowed_top_keys:
                        model_routing_errors.append(f'model_routing: unknown key "{key}"')

                # 校验顶层 phase_N 简写值（phase_1: <tier>）
                for pkey in VALID_PHASES:
                    if pkey in mr:
                        pval = mr[pkey]
                        if isinstance(pval, str) and pval not in VALID_TIERS:
                            model_routing_errors.append(
                                f'model_routing.{pkey}: "{pval}" not in allowed values {sorted(VALID_TIERS)}'
                            )

                # enabled 字段
                mr_enabled = mr.get("enabled")
                if mr_enabled is not None and not isinstance(mr_enabled, bool):
                    model_routing_errors.append(
                        f"model_routing.enabled: expected bool, got {type(mr_enabled).__name__}"
                    )

                # 模型字段校验
                for model_key in ("default_session_model", "default_subagent_model", "fallback_model"):
                    val = mr.get(model_key)
                    if val is not None:
                        if not isinstance(val, str):
                            model_routing_errors.append(
                                f"model_routing.{model_key}: expected str, got {type(val).__name__}"
                            )
                        elif val not in VALID_MODELS and val not in VALID_TIERS:
                            model_routing_errors.append(
                                f'model_routing.{model_key}: "{val}" not in allowed values '
                                f"{sorted(VALID_MODELS | VALID_TIERS)}"
                            )

                # phases 对象校验
                phases_obj = mr.get("phases")
                if phases_obj is not None:
                    if not isinstance(phases_obj, dict):
                        model_routing_errors.append(
                            f"model_routing.phases: expected dict, got {type(phases_obj).__name__}"
                        )
                    else:
                        for pkey, pval in phases_obj.items():
                            if pkey not in VALID_PHASES:
                                model_routing_errors.append(f'model_routing.phases: unknown phase key "{pkey}"')
                                continue
                            if isinstance(pval, str):
                                # 简写: phase_1: fast/standard/deep/auto
                                if pval not in VALID_TIERS:
                                    model_routing_errors.append(
                                        f'model_routing.phases.{pkey}: "{pval}" not in '
                                        f"allowed values {sorted(VALID_TIERS)}"
                                    )
                            elif isinstance(pval, dict):
                                allowed_phase_keys = {
                                    "tier",
                                    "model",
                                    "effort",
                                    "escalate_on_failure_to",
                                }
                                for pk in pval.keys():
                                    if pk not in allowed_phase_keys:
                                        model_routing_errors.append(f'model_routing.phases.{pkey}: unknown key "{pk}"')
                                tier = pval.get("tier")
                                if tier is not None and tier not in VALID_TIERS:
                                    model_routing_errors.append(
                                        f'model_routing.phases.{pkey}.tier: "{tier}" not in {sorted(VALID_TIERS)}'
                                    )
                                model = pval.get("model")
                                if model is not None and model not in VALID_MODELS:
                                    model_routing_errors.append(
                                        f'model_routing.phases.{pkey}.model: "{model}" not in {sorted(VALID_MODELS)}'
                                    )
                                effort = pval.get("effort")
                                if effort is not None and effort not in VALID_EFFORTS:
                                    model_routing_errors.append(
                                        f'model_routing.phases.{pkey}.effort: "{effort}" not in {sorted(VALID_EFFORTS)}'
                                    )
                                esc = pval.get("escalate_on_failure_to")
                                if esc is not None and esc not in VALID_TIERS and esc not in VALID_MODELS:
                                    model_routing_errors.append(
                                        f"model_routing.phases.{pkey}.escalate_on_failure_to: "
                                        f'"{esc}" not in allowed values '
                                        f"{sorted(VALID_MODELS | VALID_TIERS)}"
                                    )
                            else:
                                model_routing_errors.append(
                                    f"model_routing.phases.{pkey}: expected str or dict, got {type(pval).__name__}"
                                )
        else:
            model_routing_errors.append(f"model_routing: expected str or dict, got {type(mr).__name__}")

    valid = len(missing) == 0 and len(type_errors) == 0 and len(enum_errors) == 0 and len(model_routing_errors) == 0
    return {
        "valid": valid,
        "missing_keys": missing,
        "type_errors": type_errors,
        "range_errors": range_errors,
        "enum_errors": enum_errors,
        "model_routing_errors": model_routing_errors,
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
