#!/usr/bin/env bash
# TEST_LAYER: contract
# test_phase1_config_schema_v2.sh — Phase 1 redesign config schema v2 contract
#   覆盖 docs/superpowers/plans/2026-04-20-phase1-redesign.md Task 1
#   - 新增 phases.requirements.synthesizer.agent
#   - 标记 phases.requirements.research.web_search.agent 为 deprecated
#   - 引入 research.web_search_subtask 块
#   - autopilot-agents install Step 4 写入 synthesizer
#   - Phase → config key 映射表新增 requirements.synthesizer
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCHEMA_FILE="$(cd "$TEST_DIR/../skills/autopilot/references" && pwd)/config-schema.md"
AGENTS_SKILL="$(cd "$TEST_DIR/../skills/autopilot-agents" && pwd)/SKILL.md"
source "$TEST_DIR/_test_helpers.sh"

echo "--- Phase 1 redesign: config schema v2 contract ---"

# 1. config-schema.md must declare phases.requirements.synthesizer.agent
if grep -nF 'synthesizer:' "$SCHEMA_FILE" >/dev/null \
  && awk '/^[[:space:]]*synthesizer:/{flag=1; next} flag && /agent:/{print; exit} flag && /^[^[:space:]]/{exit}' \
       "$SCHEMA_FILE" | grep -qF 'agent:'; then
  green "  PASS: 1: config-schema declares synthesizer.agent under phases.requirements"
  PASS=$((PASS + 1))
else
  red "  FAIL: 1: config-schema missing phases.requirements.synthesizer.agent"
  FAIL=$((FAIL + 1))
fi

# 2. config-schema.md must mark research.web_search block as deprecated
if awk '
    /^[[:space:]]*web_search:/{flag=1; next}
    flag && /^[[:space:]]+deprecated:[[:space:]]*true/{found=1; exit}
    flag && /^[[:space:]]{0,6}[a-z_]+:/ && !/^[[:space:]]{8,}/{flag=0}
    END{exit found?0:1}
  ' "$SCHEMA_FILE"; then
  green "  PASS: 2: web_search block marked deprecated"
  PASS=$((PASS + 1))
else
  red "  FAIL: 2: web_search block marked deprecated"
  FAIL=$((FAIL + 1))
fi

# 2b. config-schema.md must introduce web_search_subtask block (research-internal)
if grep -nF 'web_search_subtask:' "$SCHEMA_FILE" >/dev/null; then
  green "  PASS: 2b: config-schema introduces research.web_search_subtask block"
  PASS=$((PASS + 1))
else
  red "  FAIL: 2b: config-schema missing research.web_search_subtask block"
  FAIL=$((FAIL + 1))
fi

# 3. autopilot-agents/SKILL.md install Step 4 must write phases.requirements.synthesizer.agent
if grep -nF 'phases.requirements.synthesizer.agent' "$AGENTS_SKILL" >/dev/null; then
  green "  PASS: 3: autopilot-agents install writes phases.requirements.synthesizer.agent"
  PASS=$((PASS + 1))
else
  red "  FAIL: 3: autopilot-agents install missing phases.requirements.synthesizer.agent"
  FAIL=$((FAIL + 1))
fi

# 4. autopilot-agents/SKILL.md Phase → config key mapping table must include requirements.synthesizer
if grep -nE 'requirements\.synthesizer|phase1-synthesizer' "$AGENTS_SKILL" >/dev/null; then
  green "  PASS: 4: Phase → config key mapping includes requirements.synthesizer"
  PASS=$((PASS + 1))
else
  red "  FAIL: 4: Phase → config key mapping missing requirements.synthesizer"
  FAIL=$((FAIL + 1))
fi

echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1
exit 0
