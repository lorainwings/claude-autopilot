#!/usr/bin/env bash
# select-research-plan.sh — Compute Phase 1 research plan from
# (maturity, project_type) and emit a structured JSON envelope.
#
# Replaces the hard-coded 1D mapping in phase1-requirements.md so the
# orchestrator dispatches Auto-Scan / ResearchAgent / depth=deep (web search)
# according to a single deterministic source.
#
# Usage:
#   select-research-plan.sh --maturity <clear|partial|ambiguous> \
#                           --project-type <greenfield|brownfield>
#
# Output (stdout, JSON):
#   {
#     "scan": bool,                      # always true (Auto-Scan is mandatory)
#     "research": bool,                  # dispatch ResearchAgent?
#     "research_depth": "none|standard|deep",
#     "websearch_subtask": bool,         # depth=deep WebSearch subtask?
#     "notes": "..."                     # human-readable explanation
#   }
#
# Exit codes:
#   0  success
#   2  invalid argument (unknown enum value, missing required arg)

set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: select-research-plan.sh --maturity <clear|partial|ambiguous> \
                               --project-type <greenfield|brownfield>
EOF
}

MATURITY=""
PROJECT_TYPE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --maturity)
      [ $# -lt 2 ] && {
        usage
        exit 2
      }
      MATURITY="$2"
      shift 2
      ;;
    --project-type)
      [ $# -lt 2 ] && {
        usage
        exit 2
      }
      PROJECT_TYPE="$2"
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

if [ -z "$MATURITY" ] || [ -z "$PROJECT_TYPE" ]; then
  usage
  exit 2
fi

case "$MATURITY" in
  clear | partial | ambiguous) ;;
  *)
    echo "Invalid --maturity: $MATURITY (expected clear|partial|ambiguous)" >&2
    exit 2
    ;;
esac

case "$PROJECT_TYPE" in
  greenfield | brownfield) ;;
  *)
    echo "Invalid --project-type: $PROJECT_TYPE (expected greenfield|brownfield)" >&2
    exit 2
    ;;
esac

# ── Decision matrix (4 outcomes) ─────────────────────────────────────────────
SCAN="true"
RESEARCH="false"
DEPTH="none"
WEBSEARCH="false"
NOTES=""

case "$MATURITY" in
  clear)
    if [ "$PROJECT_TYPE" = "brownfield" ]; then
      NOTES="clear+brownfield: Auto-Scan dispatches a lite-regression subtask; no ResearchAgent."
    else
      NOTES="clear+greenfield: Auto-Scan only; skip ResearchAgent."
    fi
    ;;
  partial)
    RESEARCH="true"
    DEPTH="standard"
    NOTES="partial: dispatch Auto-Scan + ResearchAgent (depth=standard)."
    ;;
  ambiguous)
    RESEARCH="true"
    DEPTH="deep"
    WEBSEARCH="true"
    NOTES="ambiguous: dispatch Auto-Scan + ResearchAgent (depth=deep, includes WebSearch subtask)."
    ;;
esac

# Emit JSON via python3 to guarantee correct escaping of notes string.
python3 - "$SCAN" "$RESEARCH" "$DEPTH" "$WEBSEARCH" "$NOTES" <<'PY'
import json, sys
scan, research, depth, websearch, notes = sys.argv[1:6]
print(json.dumps({
    "scan": scan == "true",
    "research": research == "true",
    "research_depth": depth,
    "websearch_subtask": websearch == "true",
    "notes": notes,
}, ensure_ascii=False))
PY
