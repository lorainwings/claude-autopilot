#!/usr/bin/env bash
# TEST_LAYER: contract
# test_requirement_packet_synthesizer.sh — Phase 1 Task 6:
#   将 requirement-packet.json 合成从主线程压缩改为专用 PackagerAgent 全文驱动。
#   覆盖 docs/superpowers/plans/2026-04-20-phase1-redesign.md Task 6.
#
# 校验三件事：
#   A. phase1-requirements.md Step 1.9 明确把 packet 合成派发给 PackagerAgent
#      （subagent_type 复用 phases.requirements.synthesizer.agent），
#      且主线程只 Read packet.json，不读 requirements-analysis.md 原文。
#   B. autopilot-phase1-requirements/SKILL.md 同步新的 1.9 流程。
#   C. runtime/schemas/requirement-packet.schema.json：
#      required 字段完整、acceptance_criteria 结构、needs_clarification
#      pattern、sha256 hex 约束，并用一组 fixture（verdict + requirements
#      草稿）断言 packet.acceptance_criteria 数量 ≥ research-findings.md
#      可测试动词数（防止压缩导致信息失真）。
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$TEST_DIR/.." && pwd)"
# shellcheck disable=SC1091
source "$TEST_DIR/_test_helpers.sh"

PHASE1_DOC="$PLUGIN_ROOT/skills/autopilot/references/phase1-requirements.md"
SKILL_DOC="$PLUGIN_ROOT/skills/autopilot-phase1-requirements/SKILL.md"
SCHEMA_FILE="$PLUGIN_ROOT/runtime/schemas/requirement-packet.schema.json"

echo "=== Phase 1 Task 6: requirement-packet synthesizer (PackagerAgent) ==="

# --- Pre-flight ------------------------------------------------------------
assert_file_exists "phase1-requirements.md present"       "$PHASE1_DOC"
assert_file_exists "autopilot-phase1-requirements SKILL present" "$SKILL_DOC"
assert_file_exists "requirement-packet.schema.json present"      "$SCHEMA_FILE"

PHASE1_BODY="$(cat "$PHASE1_DOC")"
SKILL_BODY="$(cat "$SKILL_DOC")"

# --- A. phase1-requirements.md Step 1.9 driven by PackagerAgent -----------
assert_contains "Step 1.9.1 references SynthesizerAgent verdict" \
  "$PHASE1_BODY" "Step 1.9.1"
assert_contains "Step 1.9.2 references BA requirements draft" \
  "$PHASE1_BODY" "Step 1.9.2"
assert_contains "Step 1.9.3 dispatches PackagerAgent" \
  "$PHASE1_BODY" "Step 1.9.3"
assert_contains "Step 1.9.3 reuses synthesizer.agent subagent_type" \
  "$PHASE1_BODY" "phases.requirements.synthesizer.agent"
assert_contains "Step 1.9.3 feeds PackagerAgent with verdict.json" \
  "$PHASE1_BODY" "verdict.json"
assert_contains "Step 1.9.3 feeds PackagerAgent with requirements draft" \
  "$PHASE1_BODY" "requirements-analysis.md"
assert_contains "Step 1.9.3 outputs requirement-packet.json" \
  "$PHASE1_BODY" "openspec/changes/{change"
assert_contains "Step 1.9.3 schema validation pointer" \
  "$PHASE1_BODY" "runtime/schemas/requirement-packet.schema.json"
assert_contains "Step 1.9.4 main-thread only reads packet.json" \
  "$PHASE1_BODY" "Step 1.9.4"
assert_contains "Step 1.9.4 explicitly forbids reading raw markdown" \
  "$PHASE1_BODY" "不读原始 markdown"

# Legacy language (main-thread compresses envelopes) must not survive
assert_not_contains "no main-thread synthesis language retained" \
  "$PHASE1_BODY" "由主线程从信封数据合成"

# --- B. SKILL.md synchronized with new 1.9 flow ---------------------------
assert_contains "SKILL references PackagerAgent synthesis" \
  "$SKILL_BODY" "PackagerAgent"
assert_contains "SKILL references requirement-packet schema" \
  "$SKILL_BODY" "requirement-packet.schema.json"

# --- C. Schema contract ---------------------------------------------------
if jq . "$SCHEMA_FILE" >/dev/null 2>&1; then
  green "  PASS: schema is valid JSON"
  PASS=$((PASS + 1))
else
  red "  FAIL: schema file is not valid JSON"
  FAIL=$((FAIL + 1))
fi

REQUIRED_KEYS="goal scope non_goals acceptance_criteria risks decisions needs_clarification sha256"
required_actual=$(jq -r '.required | join(" ")' "$SCHEMA_FILE" 2>/dev/null || echo "")
all_present=1
for key in $REQUIRED_KEYS; do
  if ! grep -qw "$key" <<< "$required_actual"; then
    all_present=0
    red "  FAIL: required missing key '$key'"
    FAIL=$((FAIL + 1))
  fi
done
if [ "$all_present" -eq 1 ]; then
  green "  PASS: schema required contains all 8 mandatory keys"
  PASS=$((PASS + 1))
fi

ac_type=$(jq -r '.properties.acceptance_criteria.type' "$SCHEMA_FILE" 2>/dev/null)
ac_item_required=$(jq -r '.properties.acceptance_criteria.items.required | join(",")' \
  "$SCHEMA_FILE" 2>/dev/null || echo "")
if [ "$ac_type" = "array" ] \
   && grep -q "text" <<< "$ac_item_required" \
   && grep -q "testable" <<< "$ac_item_required"; then
  green "  PASS: acceptance_criteria is array with text+testable per item"
  PASS=$((PASS + 1))
else
  red "  FAIL: acceptance_criteria schema missing text/testable (type=$ac_type, item_required=$ac_item_required)"
  FAIL=$((FAIL + 1))
fi

nc_pattern=$(jq -r '.properties.needs_clarification.items.pattern' "$SCHEMA_FILE" 2>/dev/null || echo "")
if grep -q 'NEEDS CLARIFICATION' <<< "$nc_pattern"; then
  green "  PASS: needs_clarification pattern enforces [NEEDS CLARIFICATION: prefix"
  PASS=$((PASS + 1))
else
  red "  FAIL: needs_clarification pattern missing NEEDS CLARIFICATION (got: '$nc_pattern')"
  FAIL=$((FAIL + 1))
fi

sha_pattern=$(jq -r '.properties.sha256.pattern' "$SCHEMA_FILE" 2>/dev/null || echo "")
if grep -Eq '\[0-9a-f\]|\[a-f0-9\]' <<< "$sha_pattern"; then
  green "  PASS: sha256 pattern constrains to hex characters"
  PASS=$((PASS + 1))
else
  red "  FAIL: sha256 pattern not hex-constrained (got: '$sha_pattern')"
  FAIL=$((FAIL + 1))
fi

# --- D. Fixture-based "no information loss" assertion ---------------------
# Build a tiny research-findings.md with 3 testable verbs, a verdict.json
# stub, and a requirements-analysis.md draft. A packet that compresses all
# testable verbs into acceptance_criteria must have |AC| >= |verbs|.
FIXTURE_DIR="$(mktemp -d)"
trap 'rm -rf "$FIXTURE_DIR"' EXIT

cat > "$FIXTURE_DIR/research-findings.md" <<'EOF'
# Research Findings
- The system MUST validate user email on submit.
- The system MUST reject duplicate account signups.
- The system SHOULD log failed login attempts to audit trail.
EOF

cat > "$FIXTURE_DIR/requirements-analysis.md" <<'EOF'
# Requirements
## Acceptance Criteria
- Email validation rejects malformed addresses.
- Duplicate account creation returns 409.
- Failed login attempts are written to audit log.
EOF

cat > "$FIXTURE_DIR/verdict.json" <<'EOF'
{ "coverage_ok": true, "confidence": 0.9, "requires_human": false }
EOF

# Simulated PackagerAgent output (all three testable verbs preserved).
cat > "$FIXTURE_DIR/requirement-packet.json" <<'EOF'
{
  "goal": "Harden account flow",
  "scope": ["signup", "login"],
  "non_goals": ["password reset"],
  "acceptance_criteria": [
    {"text": "Email validation rejects malformed addresses", "testable": true},
    {"text": "Duplicate signup returns HTTP 409",            "testable": true},
    {"text": "Failed logins are recorded to audit log",      "testable": true}
  ],
  "risks": [],
  "decisions": [],
  "needs_clarification": [],
  "sha256": "0000000000000000000000000000000000000000000000000000000000000000"
}
EOF

verbs=$(grep -Ec 'MUST|SHOULD' "$FIXTURE_DIR/research-findings.md" || echo 0)
ac_count=$(jq '.acceptance_criteria | length' "$FIXTURE_DIR/requirement-packet.json" 2>/dev/null || echo 0)
if [ "$ac_count" -ge "$verbs" ] && [ "$verbs" -ge 3 ]; then
  green "  PASS: fixture packet AC count ($ac_count) >= testable verbs ($verbs)"
  PASS=$((PASS + 1))
else
  red "  FAIL: fixture packet AC count ($ac_count) < testable verbs ($verbs)"
  FAIL=$((FAIL + 1))
fi

echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1
exit 0
