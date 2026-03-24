"""
_constraint_loader.py
Shared Python module for autopilot constraint checking hook scripts.
Loads project constraints from config.yaml and CLAUDE.md,
and checks file violations against those constraints.

Usage from bash (inline python with importlib):
    import importlib.util
    spec = importlib.util.spec_from_file_location("_cl", "<scripts_dir>/_constraint_loader.py")
    _cl = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(_cl)
"""

import os
import re
import subprocess
import sys


def _parse_list(key, section):
    """Parse a YAML list from a section string using regex.

    Handles two formats:
    - Format 1: nested objects with pattern field (- pattern: "value")
    - Format 2: flat strings (- value)

    Returns list of strings.
    """
    m = re.search(rf"^( +){re.escape(key)}:\s*\n", section, re.MULTILINE)
    if not m:
        return []
    indent = m.group(1)
    start = m.end()
    end_m = re.search(rf"^{re.escape(indent)}[a-z_]", section[start:], re.MULTILINE)
    block = section[start : start + end_m.start()] if end_m else section[start:]

    items = []
    # Format 1: nested objects - extract pattern field value
    for obj_m in re.finditer(r'-\s+pattern:\s*["\x27]?([^"\x27}\n]+)["\x27]?', block):
        v = obj_m.group(1).strip()
        if v:
            items.append(v)
    # Format 2: flat strings (fallback only if no nested objects found)
    if not items:
        for x in re.finditer(r"-\s+(.+)", block):
            v = x.group(1).strip().strip("\x22\x27")
            if v and not v.startswith("pattern:") and not v.startswith("message:"):
                items.append(v)
    return items


def load_constraints(root):
    """Load project code constraints from config.yaml or CLAUDE.md.

    Priority 1: autopilot.config.yaml code_constraints section
    Priority 2: CLAUDE.md forbidden patterns (fallback)

    Returns dict with keys:
        forbidden_files: list[str]
        forbidden_patterns: list[str]
        allowed_dirs: list[str]
        max_lines: int
        found: bool  (True if any constraint source was found)
    """
    forbidden_files = []
    forbidden_patterns = []
    allowed_dirs = []
    max_lines = 800
    found = False

    # Priority 1: config.yaml code_constraints
    cfg = os.path.join(root, ".claude", "autopilot.config.yaml")
    if os.path.isfile(cfg):
        try:
            with open(cfg) as f:
                txt = f.read()
            cc = re.search(r"^code_constraints:\s*$", txt, re.MULTILINE)
            if cc:
                sec = txt[cc.end() :]
                nt = re.search(r"^\S", sec, re.MULTILINE)
                sec = sec[: nt.start()] if nt else sec

                forbidden_files = _parse_list("forbidden_files", sec)
                forbidden_patterns = _parse_list("forbidden_patterns", sec)
                allowed_dirs = _parse_list("allowed_dirs", sec)
                ml = re.search(r"max_file_lines:\s*(\d+)", sec)
                if ml:
                    max_lines = int(ml.group(1))
                found = True
        except Exception as e:
            print(f"WARNING: constraint-loader config parse: {e}", file=sys.stderr)

    # Priority 2: CLAUDE.md forbidden patterns (fallback)
    if not found:
        cmd = os.path.join(root, "CLAUDE.md")
        if os.path.isfile(cmd):
            try:
                with open(cmd) as f:
                    md = f.read()
                for m in re.finditer(r"[\x60|]([a-zA-Z0-9_.-]+\.[a-zA-Z]{1,5})[\x60|]\s*.*禁", md):
                    forbidden_files.append(m.group(1))
                for m in re.finditer(r"禁[^|]*[\x60|]([a-zA-Z0-9_.-]+\.[a-zA-Z]{1,5})[\x60|]", md):
                    forbidden_files.append(m.group(1))
                for m in re.finditer(r"[\x60|]([a-zA-Z][a-zA-Z0-9_() ]{2,30})[\x60|]\s*.*(?:禁止|禁)", md):
                    p = m.group(1).strip()
                    if len(p) > 2:
                        forbidden_patterns.append(p)
                found = bool(forbidden_files or forbidden_patterns)
            except Exception:
                pass

    # Deduplicate
    forbidden_files = list(dict.fromkeys(forbidden_files))
    forbidden_patterns = list(dict.fromkeys(forbidden_patterns))

    # YAML escape normalization: _parse_list extracts raw text, so YAML-style
    # double backslashes (e.g., "eval\\(") need to be reduced to single (e.g., "eval\(")
    forbidden_patterns = [p.replace("\\\\", "\\") for p in forbidden_patterns]

    return {
        "forbidden_files": forbidden_files,
        "forbidden_patterns": forbidden_patterns,
        "allowed_dirs": allowed_dirs,
        "max_lines": max_lines,
        "required_patterns": [],
        "naming_patterns": [],
        "found": found,
    }


def load_scanner_constraints(root):
    """Load constraints from rules-scanner.sh output.

    Calls rules-scanner.sh and parses its JSON output to extract
    required patterns and naming conventions that complement
    the config-based constraints.

    Returns dict with keys:
        required_patterns: list[str]  (patterns files must contain)
        naming_patterns: list[str]    (file naming conventions)
        forbidden_patterns: list[str] (additional forbidden patterns from scanner)
        found: bool
    """
    required_patterns = []
    naming_patterns = []
    forbidden_patterns = []
    found = False

    # Locate rules-scanner.sh relative to this module
    scripts_dir = os.path.dirname(os.path.abspath(__file__))
    scanner_path = os.path.join(scripts_dir, "rules-scanner.sh")

    if not os.path.isfile(scanner_path):
        return {
            "required_patterns": required_patterns,
            "naming_patterns": naming_patterns,
            "forbidden_patterns": forbidden_patterns,
            "found": found,
        }

    try:
        result = subprocess.run(
            ["bash", scanner_path, root],
            capture_output=True,
            text=True,
            timeout=10,
        )
        if result.returncode != 0:
            return {
                "required_patterns": required_patterns,
                "naming_patterns": naming_patterns,
                "forbidden_patterns": forbidden_patterns,
                "found": found,
            }

        import json

        data = json.loads(result.stdout)
        if not data.get("rules_found"):
            return {
                "required_patterns": required_patterns,
                "naming_patterns": naming_patterns,
                "forbidden_patterns": forbidden_patterns,
                "found": found,
            }

        found = True
        for c in data.get("constraints", []):
            ctype = c.get("type", "")
            pattern = c.get("pattern", "")
            if not pattern:
                continue
            if ctype == "required":
                required_patterns.append(pattern)
            elif ctype == "naming":
                naming_patterns.append(pattern)
            elif ctype == "forbidden":
                forbidden_patterns.append(pattern)

    except Exception as e:
        print(f"WARNING: constraint-loader scanner: {e}", file=sys.stderr)

    return {
        "required_patterns": list(dict.fromkeys(required_patterns)),
        "naming_patterns": list(dict.fromkeys(naming_patterns)),
        "forbidden_patterns": list(dict.fromkeys(forbidden_patterns)),
        "found": found,
    }


def merge_constraints(base, scanner):
    """Merge base constraints (from config/CLAUDE.md) with scanner constraints.

    Returns a new dict combining both sources.
    """
    merged = dict(base)
    merged["forbidden_patterns"] = list(
        dict.fromkeys(base.get("forbidden_patterns", []) + scanner.get("forbidden_patterns", []))
    )
    merged["required_patterns"] = list(
        dict.fromkeys(base.get("required_patterns", []) + scanner.get("required_patterns", []))
    )
    merged["naming_patterns"] = list(
        dict.fromkeys(base.get("naming_patterns", []) + scanner.get("naming_patterns", []))
    )
    merged["found"] = base.get("found", False) or scanner.get("found", False)
    return merged


def check_file_violations(file_path, root, constraints):
    """Check a single file against loaded constraints.

    Args:
        file_path: relative or absolute path to the file
        root: project root directory
        constraints: dict from load_constraints() or merge_constraints()

    Returns list of violation strings (empty if compliant).
    """
    forbidden_files = constraints["forbidden_files"]
    forbidden_patterns = constraints["forbidden_patterns"]
    allowed_dirs = constraints["allowed_dirs"]
    max_lines = constraints["max_lines"]
    required_patterns = constraints.get("required_patterns", [])
    naming_patterns = constraints.get("naming_patterns", [])

    rel = os.path.relpath(file_path, root) if os.path.isabs(file_path) else file_path
    base = os.path.basename(rel)
    abs_path = os.path.join(root, rel) if not os.path.isabs(file_path) else file_path

    violations = []

    # Forbidden file name
    for ff in forbidden_files:
        if base == ff or rel.endswith(ff):
            violations.append(f'Forbidden file: {rel} (matches "{ff}")')

    # Directory scope
    if allowed_dirs and not any(rel.startswith(d) for d in allowed_dirs):
        violations.append(f"Out of scope: {rel} (allowed: {allowed_dirs})")

    # Naming convention check
    for naming in naming_patterns:
        naming_lower = naming.lower()
        if naming_lower == "kebab-case":
            # File name (without extension) should be kebab-case
            name_part = os.path.splitext(base)[0]
            if name_part and not re.match(r"^[a-z][a-z0-9]*(-[a-z0-9]+)*$", name_part):
                violations.append(f"Naming convention violation: {rel} (expected {naming})")
        elif naming_lower == "camelcase":
            name_part = os.path.splitext(base)[0]
            if name_part and not re.match(r"^[a-z][a-zA-Z0-9]*$", name_part):
                violations.append(f"Naming convention violation: {rel} (expected {naming})")
        elif naming_lower == "pascalcase":
            name_part = os.path.splitext(base)[0]
            if name_part and not re.match(r"^[A-Z][a-zA-Z0-9]*$", name_part):
                violations.append(f"Naming convention violation: {rel} (expected {naming})")
        elif naming_lower == "snake_case":
            name_part = os.path.splitext(base)[0]
            if name_part and not re.match(r"^[a-z][a-z0-9]*(_[a-z0-9]+)*$", name_part):
                violations.append(f"Naming convention violation: {rel} (expected {naming})")

    # File line count + forbidden patterns + required patterns (only for existing files)
    if os.path.isfile(abs_path):
        try:
            with open(abs_path, "r", errors="ignore") as f:
                content = f.read(100_000)
            lc = content.count("\n") + (1 if content and not content.endswith("\n") else 0)
            if lc > max_lines:
                violations.append(f"File too long: {rel} ({lc} lines > {max_lines})")
            for pat in forbidden_patterns:
                try:
                    if re.search(pat, content):
                        violations.append(f'Forbidden pattern "{pat}" in {rel}')
                except re.error:
                    # Fallback to literal match if pattern is invalid regex
                    if pat in content:
                        violations.append(f'Forbidden pattern "{pat}" in {rel}')
            # Required patterns: file content must contain these patterns
            for pat in required_patterns:
                try:
                    if not re.search(pat, content):
                        violations.append(f'Required pattern "{pat}" not found in {rel}')
                except re.error:
                    if pat not in content:
                        violations.append(f'Required pattern "{pat}" not found in {rel}')
        except Exception:
            pass

    return violations
