"""
_envelope_parser.py
Shared Python module for autopilot PostToolUse hook scripts.
Extracts JSON envelopes from sub-agent output with 3-strategy parsing,
normalizes tool responses, and provides unified output helpers.

Usage from bash (inline python with importlib):
    import importlib.util
    spec = importlib.util.spec_from_file_location("_ep", "<scripts_dir>/_envelope_parser.py")
    _ep = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(_ep)
"""

import json
import os
import re
import sys


def extract_envelope(output):
    """Extract JSON envelope from sub-agent output using 3-strategy parsing.

    Strategy A: raw_decode — Two-pass search for JSON with 'status' key.
                Pass 1 prefers objects with both 'status' AND 'summary'.
                Pass 2 falls back to 'status' only.
    Strategy B: Fenced code block extraction (```json ... ```).
    Strategy C: Parse entire output as JSON.

    Returns dict or None.
    """
    if not output or not output.strip():
        return None

    # Strategy A: raw_decode
    decoder = json.JSONDecoder()
    candidates = []
    for i, ch in enumerate(output):
        if ch == '{':
            try:
                obj, end = decoder.raw_decode(output, i)
                if isinstance(obj, dict) and 'status' in obj:
                    candidates.append(obj)
            except (json.JSONDecodeError, ValueError):
                continue

    # Pass 1: prefer full envelope (status + summary)
    for c in candidates:
        if 'summary' in c:
            return c
    # Pass 2: fallback to status-only
    if candidates:
        return candidates[0]

    # Strategy B: fenced code block
    code_block_match = re.search(
        r'\x60\x60\x60(?:json)?\s*\n(.*?)\n\x60\x60\x60', output, re.DOTALL
    )
    if code_block_match:
        try:
            obj = json.loads(code_block_match.group(1))
            if isinstance(obj, dict) and 'status' in obj:
                return obj
        except (json.JSONDecodeError, ValueError):
            pass

    # Strategy C: entire output as JSON
    try:
        obj = json.loads(output.strip())
        if isinstance(obj, dict):
            return obj
    except (json.JSONDecodeError, ValueError):
        pass

    return None


def normalize_tool_response(data):
    """Normalize tool_response from hook stdin data to a string.

    Handles dict (JSON-serialize), str (pass-through), and other types.
    Returns empty string for None/falsy values.
    """
    tool_response = data.get('tool_response', '')
    if isinstance(tool_response, dict):
        return json.dumps(tool_response)
    elif isinstance(tool_response, str):
        return tool_response
    else:
        return str(tool_response) if tool_response else ''


def output_block(reason):
    """Print PostToolUse block decision JSON to stdout."""
    print(json.dumps({
        'decision': 'block',
        'reason': reason
    }))


def output_deny(reason):
    """Print PreToolUse deny decision JSON to stdout."""
    print(json.dumps({
        'hookSpecificOutput': {
            'hookEventName': 'PreToolUse',
            'permissionDecision': 'deny',
            'permissionDecisionReason': reason
        }
    }))


def find_project_root(data):
    """Extract project root from hook stdin data.

    Tries data['cwd'], then data['tool_input']['cwd'],
    then walks up from cwd to find .claude directory.
    Falls back to os.getcwd().
    """
    cwd = data.get('cwd', '') or data.get('tool_input', {}).get('cwd', '') or os.getcwd()
    root = cwd
    for _ in range(10):
        if os.path.isdir(os.path.join(root, '.claude')):
            break
        parent = os.path.dirname(root)
        if parent == root:
            break
        root = parent
    return root


def read_config_value(root, key_path, default=None):
    """Read a dotted key path from autopilot.config.yaml.

    PyYAML priority, regex fallback, default value.
    Returns the value or default.
    """
    cfg_path = os.path.join(root, '.claude', 'autopilot.config.yaml')
    if not os.path.isfile(cfg_path):
        return default

    # Strategy 1: PyYAML
    try:
        import yaml
        with open(cfg_path) as f:
            data = yaml.safe_load(f) or {}
        parts = key_path.split('.')
        current = data
        for part in parts:
            if isinstance(current, dict) and part in current:
                current = current[part]
            else:
                return default
        return current if current is not None else default
    except ImportError:
        pass
    except Exception:
        return default

    # Strategy 2: Regex fallback
    try:
        with open(cfg_path) as f:
            content = f.read()
        parts = key_path.split('.')
        search_text = content
        for i, part in enumerate(parts):
            if i < len(parts) - 1:
                pattern = rf'^(\s*){re.escape(part)}:\s*$'
                m = re.search(pattern, search_text, re.MULTILINE)
                if not m:
                    return default
                indent = m.group(1)
                block_start = m.end()
                next_key = re.search(
                    rf'^{re.escape(indent)}[a-zA-Z_]',
                    search_text[block_start:], re.MULTILINE
                )
                search_text = (
                    search_text[block_start:block_start + next_key.start()]
                    if next_key else search_text[block_start:]
                )
            else:
                pattern = rf'^\s*{re.escape(part)}:\s*(.+?)\s*$'
                m = re.search(pattern, search_text, re.MULTILINE)
                if m:
                    val = m.group(1).strip().strip('"').strip("'")
                    return val
                return default
    except Exception:
        return default

    return default
