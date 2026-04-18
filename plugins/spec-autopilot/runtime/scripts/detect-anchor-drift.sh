#!/usr/bin/env bash
# detect-anchor-drift.sh — 基于 ownership 锚点的双向漂移检测器 (R6/R7/R8)
#
# 设计原则：
#   - 调用 scan-code-ref-anchors.sh 产生 anchor 配对表
#   - 仅生成候选清单 .anchor-drift-candidates.json，不自动修复
#   - 退出码恒为 0 (warn-only)，与 detect-doc-drift.sh schema 对齐
#
# 输入：
#   --changed-files "<space-separated-relative-paths>"
#   --deleted-files "<space-separated-relative-paths>"
#
# 输出：
#   stdout: ANCHOR_DRIFT_CANDIDATES=N
#   file:   <project_root>/.anchor-drift-candidates.json
#
# 规则：
#   R6 (warn): 配对表中 code 文件指向的 doc 路径不存在
#   R7 (warn): 文档侧 CODE-OWNED-BY 指向的 code 文件不存在 (含 deleted)
#   R8 (warn): staged 含 code X 且 X→Y，但 Y 未进 staging

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_common.sh
source "$SCRIPT_DIR/_common.sh"

CHANGED_FILES=""
DELETED_FILES=""
while [ $# -gt 0 ]; do
  case "$1" in
    --changed-files)
      CHANGED_FILES="${2:-}"
      shift 2
      ;;
    --deleted-files)
      DELETED_FILES="${2:-}"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

PROJECT_ROOT=$(resolve_project_root)
CACHE_DIR="${PROJECT_ROOT}/.cache/spec-autopilot"
mkdir -p "$CACHE_DIR"
OUTPUT_FILE="$CACHE_DIR/anchor-drift-candidates.json"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
SCAN="$SCRIPT_DIR/scan-code-ref-anchors.sh"

# 1) 拉取 anchors
ANCHORS_JSON=$(AUTOPILOT_PROJECT_ROOT="$PROJECT_ROOT" "$SCAN" --format json 2>/dev/null || echo '{"anchors":[]}')

# 2) 用 python 解析 + 评估规则，输出候选 JSON
python3 - "$OUTPUT_FILE" "$TIMESTAMP" "$PROJECT_ROOT" "$CHANGED_FILES" "$DELETED_FILES" <<PY
import json, os, sys

out_file, ts, root, changed_str, deleted_str = sys.argv[1:6]
anchors_data = json.loads('''$ANCHORS_JSON''')
anchors = anchors_data.get('anchors', [])

changed = set([p for p in changed_str.split() if p])
deleted = set([p for p in deleted_str.split() if p])

checks = []

def add(rule, sev, src, tgt, reason, evidence):
    checks.append({
        'rule_id': rule,
        'severity': sev,
        'source_file': src,
        'target_file': tgt,
        'reason': reason,
        'evidence': evidence,
    })

for a in anchors:
    code = a['code']
    docs = a.get('docs', [])
    src = a.get('source', 'inline')

    code_abs = os.path.join(root, code)
    code_exists = os.path.exists(code_abs)

    for d in docs:
        doc_abs = os.path.join(root, d)
        doc_exists = os.path.exists(doc_abs)

        # R6: doc missing (anchor declared from code side, but doc 路径 missing)
        # Only fire when the code itself exists — otherwise R7 covers the case.
        if code_exists and not doc_exists:
            add('R6', 'warn', code, d,
                'Anchor target doc not found',
                'source=' + src)

        # R7: code missing (doc declared CODE-OWNED-BY but code absent)
        # Treat as R7 when the code is absent OR the code path appears in deleted-files.
        if (not code_exists) or (code in deleted):
            add('R7', 'warn', d, code,
                'Anchor target code not found (or deleted)',
                'source=' + src + (',deleted' if code in deleted else ''))

        # R8: staged code without paired doc in staging
        if code_exists and doc_exists and (code in changed) and (d not in changed):
            add('R8', 'warn', code, d,
                'Code staged but paired doc not staged',
                'source=' + src)

with open(out_file, 'w') as f:
    json.dump({'timestamp': ts, 'checks': checks}, f, indent=2)

print('ANCHOR_DRIFT_CANDIDATES={}'.format(len(checks)))
for c in checks:
    print('- {} [{}] {} → {}: {}'.format(
        c['rule_id'], c['severity'], c['source_file'], c['target_file'], c['reason']))
PY

exit 0
