#!/usr/bin/env bash
# TEST_LAYER: contract
# test_synthesizer_verdict_schema.sh — Phase 1 SynthesizerAgent verdict JSON Schema 契约
#   覆盖 docs/superpowers/plans/2026-04-20-phase1-redesign.md Task 2
#   - schema 文件存在且可被 jq 解析
#   - required 顶层字段完整 (7 个)
#   - confidence 数值范围约束 [0, 1]
#   - ambiguities pattern 强制 [NEEDS CLARIFICATION 前缀
#   - conflicts.resolution enum 含 3 个枚举值
#
# 注: 本测试只做 schema 文件的契约层校验，不依赖外部 schema validator
#     （ajv/jsonschema 等）。运行时校验由 Task 11 (L2 Hook) 接管。
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCHEMA_FILE="$(cd "$TEST_DIR/.." && pwd)/runtime/schemas/synthesizer-verdict.schema.json"
source "$TEST_DIR/_test_helpers.sh"

echo "--- Phase 1 redesign: synthesizer verdict schema contract ---"

# 1. schema 文件存在且为合法 JSON
if [ -f "$SCHEMA_FILE" ] && jq . "$SCHEMA_FILE" >/dev/null 2>&1; then
  green "  PASS: 1: schema file exists and is parsable JSON"
  PASS=$((PASS + 1))
else
  red "  FAIL: 1: schema file missing or invalid JSON: $SCHEMA_FILE"
  FAIL=$((FAIL + 1))
fi

# 2. required 顶层字段含全部 7 个键
REQUIRED_KEYS="coverage_ok conflicts confidence requires_human ambiguities rationale merged_decision_points"
required_actual=$(jq -r '.required | join(" ")' "$SCHEMA_FILE" 2>/dev/null || echo "")
all_present=1
for key in $REQUIRED_KEYS; do
  if ! grep -qw "$key" <<<"$required_actual"; then
    all_present=0
    red "  FAIL: 2: required missing key '$key'"
    FAIL=$((FAIL + 1))
  fi
done
if [ "$all_present" -eq 1 ]; then
  green "  PASS: 2: all 7 required top-level keys present"
  PASS=$((PASS + 1))
fi

# 3. confidence 范围约束 [0, 1]
conf_min=$(jq -r '.properties.confidence.minimum' "$SCHEMA_FILE" 2>/dev/null || echo "")
conf_max=$(jq -r '.properties.confidence.maximum' "$SCHEMA_FILE" 2>/dev/null || echo "")
# 用 awk 做数值比较，避免 0 vs 0.0 字符串差异
conf_ok=$(awk -v lo="$conf_min" -v hi="$conf_max" 'BEGIN{print (lo+0==0 && hi+0==1)?"1":"0"}')
if [ "$conf_ok" = "1" ]; then
  green "  PASS: 3: confidence range constraint [0, 1]"
  PASS=$((PASS + 1))
else
  red "  FAIL: 3: confidence range expected [0,1], got [$conf_min,$conf_max]"
  FAIL=$((FAIL + 1))
fi

# 4. ambiguities pattern 含 NEEDS CLARIFICATION
amb_pattern=$(jq -r '.properties.ambiguities.items.pattern' "$SCHEMA_FILE" 2>/dev/null || echo "")
if grep -q 'NEEDS CLARIFICATION' <<<"$amb_pattern"; then
  green "  PASS: 4: ambiguities pattern enforces NEEDS CLARIFICATION prefix"
  PASS=$((PASS + 1))
else
  red "  FAIL: 4: ambiguities pattern missing NEEDS CLARIFICATION (got: '$amb_pattern')"
  FAIL=$((FAIL + 1))
fi

# 5. conflicts.resolution enum 含 3 个值
res_enum_len=$(jq -r '.properties.conflicts.items.properties.resolution.enum | length' "$SCHEMA_FILE" 2>/dev/null || echo "0")
if [ "$res_enum_len" = "3" ]; then
  green "  PASS: 5: conflicts.resolution enum has 3 values"
  PASS=$((PASS + 1))
else
  red "  FAIL: 5: conflicts.resolution enum expected 3 values, got $res_enum_len"
  FAIL=$((FAIL + 1))
fi

echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1
exit 0
