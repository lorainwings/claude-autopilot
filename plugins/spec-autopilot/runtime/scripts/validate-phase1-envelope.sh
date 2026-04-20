#!/usr/bin/env bash
# validate-phase1-envelope.sh
# Hook: PostToolUse(Task) — Phase 1 sub-phase envelope schema validator (L2)
#
# Purpose:
#   When a Task's prompt contains a Phase 1 sub-phase marker
#   (`<!-- autopilot-phase:1-scan -->`, `<!-- autopilot-phase:1-research -->`,
#    or `<!-- autopilot-phase:1-synthesizer -->`), this hook validates the
#   returned JSON envelope against the corresponding schema file under
#   runtime/schemas/. Invalid envelopes produce a PostToolUse `decision: block`.
#
# Design notes:
#   - Companion to post-task-validator.sh (runs under the same ^Task$ matcher).
#     post-task-validator.sh matches bare `autopilot-phase:N` markers and
#     does generic envelope validation; this hook tightens the contract for
#     the 3 Phase 1 sub-phase markers by schema-checking the structured fields.
#   - `runtime/schemas/phase1-research-envelope.schema.json` mirrors the older
#     `research-envelope.schema.json`; the new name is the single source of truth
#     for L2 hook lookups, keeping the three Phase 1 marker → schema map
#     co-located.
#   - Validation is self-contained (no `jsonschema` dependency): a minimal
#     walker covers required/type/enum/minLength/minItems which is what the
#     three schemas currently use.

# --- Common preamble: stdin read, SCRIPT_DIR, _common.sh, Layer 0 bypass ---
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_hook_preamble.sh"

# --- Phase 1 sub-marker detection (description OR prompt) ---
if ! echo "$STDIN_DATA" | grep -qE 'autopilot-phase:1-(scan|research|synthesizer)'; then
  exit 0
fi

# --- Dependency check: python3 required (Fail-Closed) ---
require_python3 || exit 0

# --- Resolve schemas dir relative to this script (works in src + dist) ---
SCHEMAS_DIR="$(cd "$SCRIPT_DIR/../schemas" 2>/dev/null && pwd)"
if [ -z "$SCHEMAS_DIR" ] || [ ! -d "$SCHEMAS_DIR" ]; then
  # Schemas not shipped in this install → skip (do not block on infra gaps).
  exit 0
fi
export AUTOPILOT_PHASE1_SCHEMAS_DIR="$SCHEMAS_DIR"

# --- Run validation ---
# Pass event payload via env var (heredoc occupies stdin).
AUTOPILOT_PHASE1_EVENT_JSON="$STDIN_DATA" \
  AUTOPILOT_PHASE1_SCHEMAS_DIR="$SCHEMAS_DIR" \
  python3 <<'PY'
import json
import os
import re
import sys


def first_json_object(s):
    for i, c in enumerate(s):
        if c != '{':
            continue
        depth = 0
        in_str = False
        esc = False
        for j in range(i, len(s)):
            ch = s[j]
            if esc:
                esc = False
                continue
            if ch == '\\':
                esc = True
                continue
            if ch == '"':
                in_str = not in_str
                continue
            if in_str:
                continue
            if ch == '{':
                depth += 1
            elif ch == '}':
                depth -= 1
                if depth == 0:
                    return s[i:j + 1]
    return None


def emit_block(reason):
    print(json.dumps({'decision': 'block', 'reason': reason}, ensure_ascii=False))
    sys.exit(0)


try:
    event = json.loads(os.environ.get('AUTOPILOT_PHASE1_EVENT_JSON', '') or '{}')
except Exception:
    sys.exit(0)

tool_input = event.get('tool_input') or {}
probe = '\n'.join(str(tool_input.get(k) or '') for k in ('description', 'prompt'))

# --- Detect sub-phase marker ---
marker_map = {
    '1-scan': 'phase1-scan-envelope.schema.json',
    '1-research': 'phase1-research-envelope.schema.json',
    '1-synthesizer': 'synthesizer-verdict.schema.json',
}
m = re.search(r'autopilot-phase:(1-(?:scan|research|synthesizer))', probe)
if not m:
    sys.exit(0)
marker = m.group(1)
schema_file = marker_map[marker]

schemas_dir = os.environ.get('AUTOPILOT_PHASE1_SCHEMAS_DIR', '')
schema_path = os.path.join(schemas_dir, schema_file)
if not os.path.isfile(schema_path):
    # Missing schema = infra problem, not an envelope problem; skip.
    sys.exit(0)

try:
    with open(schema_path, 'r', encoding='utf-8') as f:
        schema = json.load(f)
except Exception as e:
    emit_block(
        f'Phase 1 ({marker}) schema 加载失败: {schema_file} — {e}'
    )

# --- Extract envelope from tool_response ---
tool_response = event.get('tool_response')
if isinstance(tool_response, dict):
    content = json.dumps(tool_response, ensure_ascii=False)
elif isinstance(tool_response, str):
    content = tool_response
else:
    content = ''

if not content.strip():
    emit_block(
        f'Phase 1 ({marker}) Agent 必须返回 JSON 信封，但 tool_response 为空。'
    )

blob = first_json_object(content)
if not blob:
    emit_block(
        f'Phase 1 ({marker}) 响应中未发现 JSON 信封 (缺少 {{ ... }} 结构)。'
        f' 预期 schema: runtime/schemas/{schema_file}。'
    )

try:
    envelope = json.loads(blob)
except Exception as e:
    emit_block(
        f'Phase 1 ({marker}) JSON 信封解析失败: {e}。预期 schema: runtime/schemas/{schema_file}。'
    )


# --- Minimal JSON Schema validator (sufficient for Phase 1 schemas) ---
TYPE_MAP = {
    'object': dict,
    'array': list,
    'string': str,
    'integer': int,
    'number': (int, float),
    'boolean': bool,
    'null': type(None),
}


def type_ok(value, type_name):
    py = TYPE_MAP.get(type_name)
    if py is None:
        return True
    if type_name == 'integer' and isinstance(value, bool):
        return False
    if type_name == 'number' and isinstance(value, bool):
        return False
    return isinstance(value, py)


def walk(value, subschema, path, errors):
    if not isinstance(subschema, dict):
        return
    t = subschema.get('type')
    if t:
        if isinstance(t, list):
            if not any(type_ok(value, tn) for tn in t):
                errors.append(f'{path or "<root>"}: 类型不匹配，期望 {t}')
                return
        else:
            if not type_ok(value, t):
                errors.append(f'{path or "<root>"}: 类型不匹配，期望 {t}')
                return

    enum_vals = subschema.get('enum')
    if enum_vals is not None and value not in enum_vals:
        errors.append(
            f'{path or "<root>"}: 值 {value!r} 不在枚举 {enum_vals} 中'
        )

    if isinstance(value, str):
        min_len = subschema.get('minLength')
        if isinstance(min_len, int) and len(value) < min_len:
            errors.append(
                f'{path or "<root>"}: 字符串长度 {len(value)} < minLength {min_len}'
            )

    if isinstance(value, dict):
        for req in subschema.get('required', []) or []:
            if req not in value:
                errors.append(
                    f'{path or "<root>"}: 缺少必填字段 "{req}"'
                )
        props = subschema.get('properties') or {}
        for key, subval in value.items():
            if key in props:
                child_path = f'{path}.{key}' if path else key
                walk(subval, props[key], child_path, errors)

    if isinstance(value, list):
        min_items = subschema.get('minItems')
        if isinstance(min_items, int) and len(value) < min_items:
            errors.append(
                f'{path or "<root>"}: 数组长度 {len(value)} < minItems {min_items}'
            )
        items_schema = subschema.get('items')
        if isinstance(items_schema, dict):
            for idx, item in enumerate(value):
                walk(item, items_schema, f'{path}[{idx}]', errors)


errors = []
walk(envelope, schema, '', errors)

if errors:
    # Cap error list for readability
    shown = errors[:6]
    more = len(errors) - len(shown)
    detail = '; '.join(shown)
    if more > 0:
        detail += f'; ...(+{more} more)'
    emit_block(
        f'Phase 1 ({marker}) JSON 信封 schema 校验失败 '
        f'(schema: runtime/schemas/{schema_file}): {detail}'
    )

# Allow — print nothing.
PY

exit 0
