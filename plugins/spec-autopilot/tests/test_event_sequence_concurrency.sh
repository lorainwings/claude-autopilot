#!/usr/bin/env bash
# test_event_sequence_concurrency.sh — next_event_sequence must stay unique under contention
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"

echo "--- event sequence concurrency ---"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

source "$SCRIPT_DIR/_common.sh"
mkdir -p "$TMP_DIR/logs"

SEQ_OUT="$TMP_DIR/out.txt"
for _ in $(seq 1 40); do
  bash -lc 'source "$1"; next_event_sequence "$2" >> "$3"' _ "$SCRIPT_DIR/_common.sh" "$TMP_DIR" "$SEQ_OUT" &
done
wait

RESULT=$(python3 - "$SEQ_OUT" <<'PY'
import sys
from collections import Counter
vals=[int(line.strip()) for line in open(sys.argv[1]) if line.strip()]
dups=[k for k,v in Counter(vals).items() if v>1]
contiguous = vals and sorted(vals) == list(range(min(vals), min(vals) + len(vals)))
print(len(vals))
print(len(set(vals)))
print("true" if contiguous else "false")
print(",".join(map(str, dups[:5])))
PY
)

COUNT=$(echo "$RESULT" | sed -n '1p')
UNIQUE=$(echo "$RESULT" | sed -n '2p')
CONTIGUOUS=$(echo "$RESULT" | sed -n '3p')
DUPS=$(echo "$RESULT" | sed -n '4p')

if [ "$COUNT" = "40" ] && [ "$UNIQUE" = "40" ]; then
  green "  PASS: concurrent next_event_sequence values remain unique"
  PASS=$((PASS + 1))
else
  red "  FAIL: sequence collision under contention (count=$COUNT unique=$UNIQUE dups=$DUPS)"
  FAIL=$((FAIL + 1))
fi

if [ "$CONTIGUOUS" = "true" ]; then
  green "  PASS: concurrent next_event_sequence remains gap-free"
  PASS=$((PASS + 1))
else
  red "  FAIL: sequence output contains gaps under contention"
  FAIL=$((FAIL + 1))
fi

echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1; exit 0
