#!/usr/bin/env bash
# generate-test-fix-patch.sh — 将 .test-rot-candidates.json 转为 patch 或 suggestion
#
# 设计原则:
#   - 仅写入 --output-dir, 绝不触达 tests/*.sh
#   - R1 (orphan script 引用): 尝试生成确定性 sed 风格 patch 移除引用块, 复杂场景退化为 suggestion
#   - R3/R4/R5: 均生成 .suggestion.md
#   - R5 弱断言附补强模板 (assert_contains / assert_json_field)
#
# 输入:
#   --candidates-file <path>   默认 ./.test-rot-candidates.json
#   --output-dir <dir>         默认 ./.tests-fix-patches/
#
# 退出码:
#   0 成功; 1 候选文件缺失或损坏

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_common.sh
source "$SCRIPT_DIR/_common.sh"

PROJECT_ROOT=$(resolve_project_root)
CANDIDATES_FILE="$PROJECT_ROOT/.test-rot-candidates.json"
OUTPUT_DIR="$PROJECT_ROOT/.tests-fix-patches"

while [ $# -gt 0 ]; do
  case "$1" in
    --candidates-file)
      CANDIDATES_FILE="${2:-}"
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="${2:-}"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

if [ ! -f "$CANDIDATES_FILE" ]; then
  echo "ERROR: candidates file not found: $CANDIDATES_FILE" >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

python3 - "$CANDIDATES_FILE" "$OUTPUT_DIR" "$PROJECT_ROOT" <<'PY'
import json, os, sys, hashlib, re, difflib

candidates_file, output_dir, project_root = sys.argv[1], sys.argv[2], sys.argv[3]

try:
    data = json.load(open(candidates_file))
except Exception as e:
    print(f"ERROR: failed to parse {candidates_file}: {e}", file=sys.stderr)
    sys.exit(1)

if not isinstance(data, dict):
    print("ERROR: candidates JSON must be an object with a 'checks' key", file=sys.stderr)
    sys.exit(1)
checks = data.get("checks", []) or []
patches = []

def short_id(idx, rule, target):
    h = hashlib.sha1(f"{idx}-{rule}-{target}".encode()).hexdigest()[:8]
    return f"testfix-{idx:03d}-{rule.lower()}-{h}"

def write_suggestion(pid, rule, src, tgt, reason, evidence, extra_body=""):
    sug_path = os.path.join(output_dir, f"{pid}.{rule}.suggestion.md")
    with open(sug_path, "w") as f:
        f.write(f"# {rule} 测试过期修复建议\n\n")
        f.write(f"- **来源文件**: `{src}`\n")
        f.write(f"- **目标测试**: `{tgt}`\n")
        f.write(f"- **原因**: {reason}\n")
        f.write(f"- **证据**: `{evidence}`\n\n")
        if extra_body:
            f.write(extra_body)
    return sug_path

R5_TEMPLATE = """## 补强模板

请将弱断言替换为以下强断言之一:

```bash
# 方案 A: 基于内容的断言
assert_contains "case 名" "$OUTPUT" "期望子串"

# 方案 B: 基于 JSON 字段的断言
assert_json_field "case 名" "$JSON_OUT" "field_name" "期望值"

# 方案 C: 基于退出码的断言 (配合实际副作用检查)
assert_exit "case 名" 0 "$RC"
assert_file_contains "产物校验" "$ARTIFACT" "期望内容"
```

避免: `assert_exit "x" 0 0` / `[ "a" = "a" ]` / `grep -q . .` 等恒真模式。
"""

for idx, c in enumerate(checks):
    rule = c.get("rule_id", "")
    src = c.get("source_file", "")
    tgt = c.get("target_file", "")
    reason = c.get("reason", "")
    evidence = c.get("evidence", "")
    pid = short_id(idx, rule, tgt or src)

    if rule == "R1":
        # 尝试为 tests/<file> 生成确定性 patch: 删除引用 source_file basename 的行
        tgt_abs = os.path.join(project_root, tgt)
        script_basename = os.path.basename(src)
        patch_generated = False
        if os.path.isfile(tgt_abs) and script_basename:
            with open(tgt_abs) as f:
                old_lines = f.read().splitlines()
            new_lines = [ln for ln in old_lines if script_basename not in ln]
            if new_lines != old_lines:
                diff = list(difflib.unified_diff(
                    old_lines, new_lines,
                    fromfile=f"a/{tgt}", tofile=f"b/{tgt}", lineterm="",
                ))
                diff_text = "\n".join(diff) + "\n"
                patch_path = os.path.join(output_dir, f"{pid}.R1.patch")
                with open(patch_path, "w") as f:
                    f.write(diff_text)
                patches.append({"id": pid, "type": "auto", "target": tgt,
                                "apply_cmd": f"git apply {os.path.basename(patch_path)}"})
                patch_generated = True
        if not patch_generated:
            sug = write_suggestion(pid, "R1", src, tgt, reason, evidence,
                                    f"## 推荐修改\n\n`{script_basename}` 已删除, 请人工移除 `{tgt}` 中的相关 case。\n")
            patches.append({"id": pid, "type": "manual", "target": tgt,
                            "apply_cmd": f"manual-review {os.path.basename(sug)}"})
    elif rule == "R3":
        sug = write_suggestion(pid, "R3", src, tgt, reason, evidence,
                                f"## 推荐修改\n\nSymbol `{evidence}` 在 `{src}` 中已不存在, 建议删除 `{tgt}` 中对应 case 或更新引用。\n")
        patches.append({"id": pid, "type": "manual", "target": tgt,
                        "apply_cmd": f"manual-review {os.path.basename(sug)}"})
    elif rule == "R4":
        sug = write_suggestion(pid, "R4", src, tgt, reason, evidence,
                                f"## 推荐修改\n\nHook `{src}` 已修改, 请回归 `{tgt}` 中与该 hook 相关的测试。\n")
        patches.append({"id": pid, "type": "manual", "target": tgt,
                        "apply_cmd": f"manual-review {os.path.basename(sug)}"})
    elif rule == "R5":
        sug = write_suggestion(pid, "R5", src, tgt, reason, evidence, R5_TEMPLATE)
        patches.append({"id": pid, "type": "manual", "target": tgt,
                        "apply_cmd": f"manual-review {os.path.basename(sug)}"})
    else:
        sug = write_suggestion(pid, rule or "RX", src, tgt, reason, evidence,
                                "## 推荐修改\n\n请人工评审该候选。\n")
        patches.append({"id": pid, "type": "manual", "target": tgt,
                        "apply_cmd": f"manual-review {os.path.basename(sug)}"})

with open(os.path.join(output_dir, "INDEX.json"), "w") as f:
    json.dump({"patches": patches, "source": candidates_file}, f, indent=2)

auto_n = sum(1 for p in patches if p["type"] == "auto")
manual_n = sum(1 for p in patches if p["type"] == "manual")
print(f"TEST_FIX_PATCHES: total={len(patches)} auto={auto_n} manual={manual_n}")
print(f"INDEX: {os.path.join(output_dir, 'INDEX.json')}")
print("Next: review suggestions, then apply-fix-patch.sh --patch-id <id> (manual needs --force-manual)")
PY
exit $?
