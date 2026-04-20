#!/usr/bin/env bash
# TEST_LAYER: integration
# test_phase1_e2e_v2.sh — Phase 1 端到端集成测试
#
# 验证 Phase 1 双路并行（scan + research）→ 串行汇总（synthesizer）
# → PackagerAgent 合成 requirement-packet 的完整契约链路：
#
#   (a) 派发顺序契约 = scan ‖ research → synthesizer（先并行 scan+research，
#       后串行 synthesizer），由 parallel-phase1.md / phase1-requirements.md
#       的文档契约校验。
#   (b) verdict.json 存在且通过 synthesizer-verdict.schema.json 必填字段校验。
#   (c) requirement-packet.json 存在且 sha256 hex 校验通过 validate-requirement-packet.sh。
#   (d) 中间无独立 web-search Agent 被派发（v5.x deprecated；websearch
#       已合并为 ResearchAgent depth=deep 子任务）。
#
# Fixture 策略：
#   采用「文档契约 + fixture 回放」(无独立 mock subagent runner)：
#   - 构造 fixture 双路 envelope（scan + research）+ verdict.json + packet.json
#   - 直接调用 validator 脚本与 schema required-field 字段校验
#   - 通过 grep 文档契约验证派发顺序与无 websearch 派发
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGIN_ROOT="$(cd "$TEST_DIR/.." && pwd)"
# shellcheck disable=SC1091
source "$TEST_DIR/_test_helpers.sh"

PARALLEL_DOC="$PLUGIN_ROOT/skills/autopilot/references/parallel-phase1.md"
PHASE1_DOC="$PLUGIN_ROOT/skills/autopilot/references/phase1-requirements.md"
SKILL_DOC="$PLUGIN_ROOT/skills/autopilot-phase1-requirements/SKILL.md"
DISPATCH_DOC="$PLUGIN_ROOT/skills/autopilot/references/dispatch-phase-prompts.md"
VERDICT_SCHEMA="$PLUGIN_ROOT/runtime/schemas/synthesizer-verdict.schema.json"
RESEARCH_SCHEMA="$PLUGIN_ROOT/runtime/schemas/research-envelope.schema.json"
PACKET_SCHEMA="$PLUGIN_ROOT/runtime/schemas/requirement-packet.schema.json"
VALIDATOR_SCRIPT="$PLUGIN_ROOT/runtime/scripts/validate-requirement-packet.sh"

echo "=== Phase 1 v2 E2E (Task 8): scan ‖ research → synthesizer → packet ==="

# Pre-flight ---------------------------------------------------------------
assert_file_exists "parallel-phase1.md present"               "$PARALLEL_DOC"
assert_file_exists "phase1-requirements.md present"           "$PHASE1_DOC"
assert_file_exists "autopilot-phase1-requirements SKILL present" "$SKILL_DOC"
assert_file_exists "dispatch-phase-prompts.md present"        "$DISPATCH_DOC"
assert_file_exists "synthesizer-verdict.schema.json present"  "$VERDICT_SCHEMA"
assert_file_exists "research-envelope.schema.json present"    "$RESEARCH_SCHEMA"
assert_file_exists "requirement-packet.schema.json present"   "$PACKET_SCHEMA"
assert_file_exists "validate-requirement-packet.sh present"   "$VALIDATOR_SCRIPT"

PARALLEL_BODY="$(cat "$PARALLEL_DOC")"
PHASE1_BODY="$(cat "$PHASE1_DOC")"
SKILL_BODY="$(cat "$SKILL_DOC")"
DISPATCH_BODY="$(cat "$DISPATCH_DOC")"

# Fixture：partial 复杂度需求（"添加用户登录限流"）
FIXTURE_DIR="$(mktemp -d)"
trap 'rm -rf "$FIXTURE_DIR"' EXIT
mkdir -p "$FIXTURE_DIR/openspec/changes/login-rate-limit/context"
CONTEXT_DIR="$FIXTURE_DIR/openspec/changes/login-rate-limit/context"
RAW_REQUIREMENT="添加用户登录限流：限制同一账号 5 分钟内登录失败 ≥ 5 次后锁定 15 分钟，记录审计日志。"
echo "$RAW_REQUIREMENT" > "$FIXTURE_DIR/raw-requirement.txt"

# ---------------------------------------------------------------------------
# (a) 派发顺序契约：scan ‖ research → synthesizer
# ---------------------------------------------------------------------------
echo "--- (a) 派发顺序契约 scan ‖ research → synthesizer ---"

# parallel-phase1.md 必须声明双路并行 + synthesizer triggers_after 串行依赖
assert_contains "parallel-phase1 declares parallel auto-scan task"  "$PARALLEL_BODY" "auto-scan"
assert_contains "parallel-phase1 declares parallel tech-research task" "$PARALLEL_BODY" "tech-research"
assert_contains "parallel-phase1 declares synthesizer_agent block"  "$PARALLEL_BODY" "synthesizer_agent:"
if grep -F -q "triggers_after: [scan_agent, research_agent]" "$PARALLEL_DOC"; then
  green "  PASS: synthesizer triggers_after scan_agent + research_agent"
  PASS=$((PASS + 1))
else
  red "  FAIL: synthesizer missing triggers_after: [scan_agent, research_agent]"
  FAIL=$((FAIL + 1))
fi

# 顺序约束：synthesizer_agent: 块必须出现在 research_agent: 块之后
SCAN_LINE=$(grep -n "^research_agent:" "$PARALLEL_DOC" | head -1 | cut -d: -f1 || echo 0)
SYN_LINE=$(grep -n "^synthesizer_agent:" "$PARALLEL_DOC" | head -1 | cut -d: -f1 || echo 0)
if [ "$SCAN_LINE" -gt 0 ] && [ "$SYN_LINE" -gt "$SCAN_LINE" ]; then
  green "  PASS: synthesizer_agent block declared AFTER research_agent (line $SYN_LINE > $SCAN_LINE)"
  PASS=$((PASS + 1))
else
  red "  FAIL: synthesizer_agent block must follow research_agent (research=$SCAN_LINE syn=$SYN_LINE)"
  FAIL=$((FAIL + 1))
fi

# phase1-requirements.md partial 路由必须包含 standard depth（Task 18: 2D 矩阵）
assert_contains "phase1-requirements partial maturity dispatches scan + tech_research" \
  "$PHASE1_BODY" "partial | brownfield | true | true | standard"

# ---------------------------------------------------------------------------
# (b) verdict.json 存在且 schema 通过
# ---------------------------------------------------------------------------
echo "--- (b) verdict.json schema 校验 ---"

VERDICT_FILE="$CONTEXT_DIR/phase1-verdict.json"
cat > "$VERDICT_FILE" <<'EOF'
{
  "coverage_ok": true,
  "conflicts": [],
  "confidence": 0.85,
  "requires_human": false,
  "ambiguities": [
    "[NEEDS CLARIFICATION: 锁定 15 分钟是否需要支持管理员手动解锁？]"
  ],
  "rationale": "scan 与 research 一致认为基于 Redis sliding window 实现，无冲突；锁定解除策略需澄清。",
  "merged_decision_points": [
    {
      "topic": "限流算法",
      "options": ["sliding window", "token bucket"],
      "recommendation": "sliding window",
      "evidence_refs": ["scan:existing-patterns.md#auth", "research:research-findings.md#rate-limit"]
    }
  ]
}
EOF
assert_file_exists "verdict.json fixture exists" "$VERDICT_FILE"

# verdict 必填字段校验（基于 schema required）
SCHEMA_REQUIRED=$(jq -r '.required | join(" ")' "$VERDICT_SCHEMA")
verdict_ok=1
for key in $SCHEMA_REQUIRED; do
  if ! jq -e --arg k "$key" 'has($k)' "$VERDICT_FILE" >/dev/null; then
    red "  FAIL: verdict.json missing required key: $key"
    FAIL=$((FAIL + 1))
    verdict_ok=0
  fi
done
if [ "$verdict_ok" -eq 1 ]; then
  green "  PASS: verdict.json contains all schema-required keys ($SCHEMA_REQUIRED)"
  PASS=$((PASS + 1))
fi

# ambiguities pattern：每条必须以 "[NEEDS CLARIFICATION:" 开头
ambig_bad=$(jq -r '.ambiguities[] | select(startswith("[NEEDS CLARIFICATION:") | not)' "$VERDICT_FILE" | wc -l | tr -d ' ')
if [ "$ambig_bad" = "0" ]; then
  green "  PASS: verdict ambiguities all carry [NEEDS CLARIFICATION: marker"
  PASS=$((PASS + 1))
else
  red "  FAIL: verdict ambiguities missing [NEEDS CLARIFICATION: prefix ($ambig_bad bad entries)"
  FAIL=$((FAIL + 1))
fi

# 同步构造一份 research envelope fixture，保证两路输入存在
RESEARCH_FILE="$CONTEXT_DIR/research-envelope.json"
cat > "$RESEARCH_FILE" <<'EOF'
{
  "status": "ok",
  "summary": "推荐基于 Redis sliding window 实现登录限流，结合审计日志中间件；无破坏性兼容问题。",
  "decision_points": [
    {
      "topic": "限流算法",
      "options": ["sliding window", "token bucket"],
      "recommendation": "sliding window",
      "rationale": "对突发友好且实现成熟",
      "evidence_refs": ["research-findings.md#rate-limit"]
    }
  ],
  "tech_constraints": ["需引入 redis 客户端"],
  "complexity": "small",
  "key_files": ["src/auth/login.ts"],
  "output_file": "context/research-findings.md"
}
EOF
RESEARCH_REQUIRED=$(jq -r '.required | join(" ")' "$RESEARCH_SCHEMA")
research_ok=1
for key in $RESEARCH_REQUIRED; do
  if ! jq -e --arg k "$key" 'has($k)' "$RESEARCH_FILE" >/dev/null; then
    red "  FAIL: research envelope missing required key: $key"
    FAIL=$((FAIL + 1))
    research_ok=0
  fi
done
if [ "$research_ok" -eq 1 ]; then
  green "  PASS: research envelope contains all schema-required keys"
  PASS=$((PASS + 1))
fi

# ---------------------------------------------------------------------------
# (c) requirement-packet.json 存在且 sha256 + AC 结构通过 validator
# ---------------------------------------------------------------------------
echo "--- (c) requirement-packet.json validator ---"

PACKET_FILE="$CONTEXT_DIR/requirement-packet.json"
# 先写入不含 sha256 的 packet，再用 validator 相同的 canonical 算法计算真实 hash 并回填
cat > "$PACKET_FILE" <<'EOF'
{
  "change_name": "login-rate-limit",
  "discussion_rounds": 2,
  "requirement_type": "feature",
  "requirement_maturity": "partial",
  "complexity": "small",
  "goal": "限制账号登录失败次数以抵御暴力破解。",
  "scope": ["登录接口", "审计日志"],
  "non_goals": ["注册接口限流", "密码重置流程"],
  "acceptance_criteria": [
    {"text": "同一账号 5 分钟内登录失败 ≥5 次后锁定 15 分钟", "testable": true},
    {"text": "锁定期间登录请求返回 HTTP 429 并写入审计日志",   "testable": true},
    {"text": "锁定窗口结束后允许正常登录",                       "testable": true}
  ],
  "risks": [
    {"category": "可用性", "severity": "medium", "mitigation": "支持运维白名单 IP 绕过"}
  ],
  "decisions": [
    {"topic": "限流算法", "choice": "sliding window", "rationale": "对突发友好且实现成熟"}
  ],
  "open_questions_closed": true,
  "needs_clarification": []
}
EOF

# 使用与 validate-requirement-packet.sh 完全一致的 canonical 算法计算 sha256，
# 然后回填到 packet.json，确保 (c) 断言真实验证 hash 匹配。
python3 - "$PACKET_FILE" <<'PYEOF'
import json, hashlib, sys
path = sys.argv[1]
with open(path, 'r', encoding='utf-8') as f:
    packet = json.load(f)
packet_for_hash = {k: v for k, v in packet.items() if k not in ('sha256', 'hash', 'packet_hash')}
canonical = json.dumps(packet_for_hash, sort_keys=True, ensure_ascii=False)
packet['sha256'] = hashlib.sha256(canonical.encode('utf-8')).hexdigest()
with open(path, 'w', encoding='utf-8') as f:
    json.dump(packet, f, ensure_ascii=False, indent=2)
PYEOF

assert_file_exists "requirement-packet.json fixture exists" "$PACKET_FILE"

VAL_OUT=$(bash "$VALIDATOR_SCRIPT" "$PACKET_FILE" "$FIXTURE_DIR" 2>/dev/null || true)
assert_not_contains "validator does NOT report sha256 格式无效" "$VAL_OUT" "格式无效"
assert_not_contains "validator does NOT report blocked status"  "$VAL_OUT" "\"status\": \"blocked\""
# 真正的 hash 一致性断言（修复先前假阳性：原 fixture 硬编码 0123... 导致 validator 输出 "sha256 不匹配" warning，
# 但测试仅断言 blocked/格式无效 而 trivially 通过）
assert_not_contains "validator does NOT warn sha256 不匹配"    "$VAL_OUT" "sha256 不匹配"

# sha256 64 字符 hex 模式校验
PACKET_SHA=$(jq -r '.sha256' "$PACKET_FILE")
if [[ "$PACKET_SHA" =~ ^[0-9a-f]{64}$ ]]; then
  green "  PASS: packet sha256 matches 64-char hex pattern"
  PASS=$((PASS + 1))
else
  red "  FAIL: packet sha256 does not match ^[0-9a-f]{64}$ (got: $PACKET_SHA)"
  FAIL=$((FAIL + 1))
fi

# AC 结构必须为 {text, testable} 对象
AC_BAD=$(jq -r '.acceptance_criteria[] | select((has("text") and has("testable")) | not) | .' "$PACKET_FILE" | wc -l | tr -d ' ')
if [ "$AC_BAD" = "0" ]; then
  green "  PASS: packet acceptance_criteria all carry {text,testable}"
  PASS=$((PASS + 1))
else
  red "  FAIL: packet AC items missing text/testable ($AC_BAD bad entries)"
  FAIL=$((FAIL + 1))
fi

# ---------------------------------------------------------------------------
# (d) 中间无 web-search Agent 被派发（v5.x deprecated）
# ---------------------------------------------------------------------------
echo "--- (d) 无独立 web-search Agent 派发 ---"

# parallel-phase1.md 不应在 parallel_tasks 顶层声明 web_search/websearch 路径
if grep -E -q "^[[:space:]]*-[[:space:]]+name:[[:space:]]*\"?(web[_-]?search|websearch)" "$PARALLEL_DOC"; then
  red "  FAIL: parallel-phase1.md still declares a separate web-search parallel task"
  FAIL=$((FAIL + 1))
else
  green "  PASS: parallel-phase1.md has no top-level web-search parallel task"
  PASS=$((PASS + 1))
fi

# phase1-requirements.md 不应该指示主线程 dispatch web_search.agent 作为独立 Task
if grep -E -q "subagent_type:[[:space:]]*config\.phases\.requirements\.web_search\.agent|subagent_type:[[:space:]]*config\.phases\.requirements\.research\.web_search\.agent" "$PHASE1_DOC"; then
  red "  FAIL: phase1-requirements.md still dispatches web_search.agent as standalone Task"
  FAIL=$((FAIL + 1))
else
  green "  PASS: phase1-requirements.md does not dispatch standalone web_search.agent"
  PASS=$((PASS + 1))
fi

# SKILL.md 不应残留旧 web-research-findings.md 引用（消费侧）
if grep -q "web-research-findings.md" "$SKILL_DOC"; then
  red "  FAIL: SKILL.md still references legacy web-research-findings.md"
  FAIL=$((FAIL + 1))
else
  green "  PASS: SKILL.md no longer references legacy web-research-findings.md"
  PASS=$((PASS + 1))
fi

# parallel-phase1.md 必须声明 v5.x 第三路 web-search 已合并到 ResearchAgent
assert_contains "parallel-phase1 declares web-search subtask absorbed into ResearchAgent" \
  "$PARALLEL_BODY" "已合并至 ResearchAgent"

# 派发顺序辅助：调研期间不存在第 3 个独立 agent 字段（research_plan.dispatched 仅含两路）
if grep -F -q '"dispatched": ["auto_scan", "tech_research"]' "$PHASE1_DOC"; then
  green "  PASS: phase1-requirements research_plan dispatched only auto_scan + tech_research"
  PASS=$((PASS + 1))
else
  red "  FAIL: phase1-requirements research_plan missing dispatched=[auto_scan,tech_research]"
  FAIL=$((FAIL + 1))
fi

# ---------------------------------------------------------------------------
# === Phase 1 Gate hardening cases (Task 13) ===
#   覆盖 runtime/scripts/check-phase1-gate.sh 的三条硬阻断 + 通过路径:
#     A: requirements.md 含未清零 [NEEDS CLARIFICATION:] → BLOCKED
#     B: verdict.confidence < 阈值 (0.7)               → BLOCKED
#     C: verdict.conflicts 含 resolution=irreconcilable → BLOCKED
#     D: 全 clean (无标记/高置信/无 irreconcilable)     → PASSED
# ---------------------------------------------------------------------------
echo ""
echo "=== Phase 1 Gate hardening cases (Task 13) ==="

GATE_SCRIPT="$PLUGIN_ROOT/runtime/scripts/check-phase1-gate.sh"
assert_file_exists "check-phase1-gate.sh present" "$GATE_SCRIPT"

# 生成带合法 sha256 的 packet.json（复用与 (c) 相同的 canonical 算法）
make_gate_packet() {
  local target="$1"
  cat > "$target" <<'PEOF'
{
  "change_name": "gate-fixture",
  "discussion_rounds": 1,
  "requirement_type": "feature",
  "requirement_maturity": "partial",
  "complexity": "small",
  "goal": "fixture goal for gate hardening test",
  "scope": ["x"],
  "non_goals": ["y"],
  "acceptance_criteria": [
    {"text": "AC1", "testable": true}
  ],
  "risks": [],
  "decisions": [],
  "open_questions_closed": true,
  "needs_clarification": []
}
PEOF
  python3 - "$target" <<'PYEOF'
import json, hashlib, sys
path = sys.argv[1]
with open(path, 'r', encoding='utf-8') as f:
    packet = json.load(f)
packet_for_hash = {k: v for k, v in packet.items() if k not in ('sha256', 'hash', 'packet_hash')}
canonical = json.dumps(packet_for_hash, sort_keys=True, ensure_ascii=False)
packet['sha256'] = hashlib.sha256(canonical.encode('utf-8')).hexdigest()
with open(path, 'w', encoding='utf-8') as f:
    json.dump(packet, f, ensure_ascii=False, indent=2)
PYEOF
}

# --- Case A: requirements 残留 [NEEDS CLARIFICATION:] → BLOCKED ---
CASE_A_DIR="$FIXTURE_DIR/case-a"
mkdir -p "$CASE_A_DIR"
cat > "$CASE_A_DIR/requirements.md" <<'EOF'
# Requirements
- 用户登录限流
- [NEEDS CLARIFICATION: 是否支持管理员手动解锁?]
EOF
cat > "$CASE_A_DIR/verdict.json" <<'EOF'
{
  "coverage_ok": true,
  "conflicts": [],
  "confidence": 0.85,
  "requires_human": false,
  "ambiguities": [],
  "rationale": "case-a: 高置信无冲突，仅 requirements 文档残留澄清标记",
  "merged_decision_points": []
}
EOF
make_gate_packet "$CASE_A_DIR/packet.json"
A_OUT=$(bash "$GATE_SCRIPT" \
  --requirements "$CASE_A_DIR/requirements.md" \
  --verdict "$CASE_A_DIR/verdict.json" \
  --packet "$CASE_A_DIR/packet.json" 2>&1)
A_CODE=$?
assert_exit       "case A: NEEDS CLARIFICATION 残留 → exit 1" 1 "$A_CODE"
assert_contains   "case A: 报告 [NEEDS CLARIFICATION:] 残留" "$A_OUT" "NEEDS CLARIFICATION"

# --- Case B: confidence=0.5 < 默认 0.7 → BLOCKED ---
CASE_B_DIR="$FIXTURE_DIR/case-b"
mkdir -p "$CASE_B_DIR"
cat > "$CASE_B_DIR/requirements.md" <<'EOF'
# Requirements
- 用户登录限流（已澄清，无未决问题）
EOF
cat > "$CASE_B_DIR/verdict.json" <<'EOF'
{
  "coverage_ok": true,
  "conflicts": [],
  "confidence": 0.5,
  "requires_human": false,
  "ambiguities": [],
  "rationale": "case-b: 低置信（0.5）触发阈值阻断的 fixture",
  "merged_decision_points": []
}
EOF
make_gate_packet "$CASE_B_DIR/packet.json"
B_OUT=$(bash "$GATE_SCRIPT" \
  --requirements "$CASE_B_DIR/requirements.md" \
  --verdict "$CASE_B_DIR/verdict.json" \
  --packet "$CASE_B_DIR/packet.json" 2>&1)
B_CODE=$?
assert_exit       "case B: confidence=0.5 < 0.7 → exit 1" 1 "$B_CODE"
assert_contains   "case B: 报告 confidence 低于阈值"      "$B_OUT" "低于阈值"

# --- Case C: conflicts 含 irreconcilable → BLOCKED ---
CASE_C_DIR="$FIXTURE_DIR/case-c"
mkdir -p "$CASE_C_DIR"
cat > "$CASE_C_DIR/requirements.md" <<'EOF'
# Requirements
- 用户登录限流（已澄清）
EOF
cat > "$CASE_C_DIR/verdict.json" <<'EOF'
{
  "coverage_ok": true,
  "conflicts": [
    {
      "topic": "存储选型",
      "positions": [
        {"source": "scan", "claim": "继续使用 Redis"},
        {"source": "research", "claim": "改用 Memcached"}
      ],
      "resolution": "irreconcilable"
    }
  ],
  "confidence": 0.85,
  "requires_human": true,
  "ambiguities": [],
  "rationale": "case-c: scan 与 research 存储选型完全相反需用户裁决",
  "merged_decision_points": []
}
EOF
make_gate_packet "$CASE_C_DIR/packet.json"
C_OUT=$(bash "$GATE_SCRIPT" \
  --requirements "$CASE_C_DIR/requirements.md" \
  --verdict "$CASE_C_DIR/verdict.json" \
  --packet "$CASE_C_DIR/packet.json" 2>&1)
C_CODE=$?
assert_exit       "case C: irreconcilable conflict → exit 1" 1 "$C_CODE"
assert_contains   "case C: 报告不可调和 conflict"           "$C_OUT" "irreconcilable"

# --- Case D: 全部 clean → PASSED ---
CASE_D_DIR="$FIXTURE_DIR/case-d"
mkdir -p "$CASE_D_DIR"
cat > "$CASE_D_DIR/requirements.md" <<'EOF'
# Requirements
- 用户登录限流（已澄清，无未决问题）
- 锁定窗口与解除策略已确认
EOF
cat > "$CASE_D_DIR/verdict.json" <<'EOF'
{
  "coverage_ok": true,
  "conflicts": [
    {
      "topic": "限流算法",
      "positions": [
        {"source": "scan", "claim": "sliding window"},
        {"source": "research", "claim": "token bucket"}
      ],
      "resolution": "adopted",
      "chosen": "sliding window"
    }
  ],
  "confidence": 0.9,
  "requires_human": false,
  "ambiguities": [],
  "rationale": "case-d: 高置信，仅含已 adopted 的冲突项，requirements 已清零",
  "merged_decision_points": []
}
EOF
make_gate_packet "$CASE_D_DIR/packet.json"
D_OUT=$(bash "$GATE_SCRIPT" \
  --requirements "$CASE_D_DIR/requirements.md" \
  --verdict "$CASE_D_DIR/verdict.json" \
  --packet "$CASE_D_DIR/packet.json" 2>&1)
D_CODE=$?
assert_exit       "case D: clean fixture → exit 0" 0 "$D_CODE"
assert_contains   "case D: stdout 输出 PASSED"     "$D_OUT" "PASSED"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1
exit 0
