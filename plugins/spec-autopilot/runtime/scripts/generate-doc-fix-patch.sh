#!/usr/bin/env bash
# generate-doc-fix-patch.sh — 将 .drift-candidates.json 转为可应用 patch 或 suggestion
#
# 设计原则:
#   - 确定性优先: R2 (新脚本未进 .dist-include) → unified diff patch (auto)
#   - LLM 仅生成建议: R1/R3/R4/R5 → .suggestion.md (manual)
#   - 不自动应用; 由 apply-fix-patch.sh 在人工 confirm 后处理
#
# 输入:
#   --candidates-file <path>   默认 ./.drift-candidates.json
#   --output-dir <dir>         默认 ./.docs-fix-patches/
#
# 输出:
#   <output-dir>/<id>.patch                   (auto)
#   <output-dir>/<id>.<rule>.suggestion.md    (manual)
#   <output-dir>/INDEX.json                   {patches:[{id,type,target,apply_cmd}]}
#
# 退出码:
#   0 成功 (无候选也算成功)
#   1 候选文件不存在 / JSON 损坏

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_common.sh
source "$SCRIPT_DIR/_common.sh"

PROJECT_ROOT=$(resolve_project_root)
CACHE_DIR="${PROJECT_ROOT}/.cache/spec-autopilot"
mkdir -p "$CACHE_DIR"
CANDIDATES_FILE="$CACHE_DIR/drift-candidates.json"
OUTPUT_DIR="$CACHE_DIR/docs-fix-patches"

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

# 调用 python3 一次性处理所有候选, 输出 patches/suggestions + INDEX.json
python3 - "$CANDIDATES_FILE" "$OUTPUT_DIR" "$PROJECT_ROOT" <<'PY'
import json, os, sys, hashlib

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
    return f"docfix-{idx:03d}-{rule.lower()}-{h}"

def gen_r2_patch(pid, target_rel):
    """R2: 追加脚本名到 .dist-include 末尾"""
    target_abs = os.path.join(project_root, target_rel)
    if not os.path.isfile(target_abs):
        return None, None
    with open(target_abs) as f:
        content = f.read()
    # 从 source_file 提取脚本名
    return content, None  # placeholder; real diff built below

def make_unified_diff(rel_path, old_lines, new_lines):
    """构造 git apply 友好的 unified diff (a/ b/ 前缀)"""
    import difflib
    diff = difflib.unified_diff(
        old_lines, new_lines,
        fromfile=f"a/{rel_path}",
        tofile=f"b/{rel_path}",
        lineterm="",
    )
    return "\n".join(diff) + "\n"

for idx, c in enumerate(checks):
    rule = c.get("rule_id", "")
    src = c.get("source_file", "")
    tgt = c.get("target_file", "")
    reason = c.get("reason", "")
    evidence = c.get("evidence", "")
    pid = short_id(idx, rule, tgt or src)

    if rule == "R2":
        # 自动 patch: 追加脚本名到 .dist-include
        target_abs = os.path.join(project_root, tgt)
        if not os.path.isfile(target_abs):
            # 退化为 manual
            sug_path = os.path.join(output_dir, f"{pid}.{rule}.suggestion.md")
            with open(sug_path, "w") as f:
                f.write(f"# {rule} 手工建议\n\n目标文件不存在: `{tgt}`\n\n请检查路径或先创建文件。\n")
            patches.append({"id": pid, "type": "manual", "target": tgt,
                            "apply_cmd": f"manual-review {sug_path}"})
            continue
        with open(target_abs) as f:
            old_lines = f.read().splitlines(keepends=True)
        # 提取脚本名 (basename)
        script_name = os.path.basename(src)
        # 确保末尾有换行
        new_lines = list(old_lines)
        if new_lines and not new_lines[-1].endswith("\n"):
            new_lines[-1] = new_lines[-1] + "\n"
        new_lines.append(f"{script_name}\n")
        # 用 splitlines(False) 喂 difflib (保持纯行)
        old_pure = [l.rstrip("\n") for l in old_lines]
        new_pure = [l.rstrip("\n") for l in new_lines]
        import difflib
        diff_lines = list(difflib.unified_diff(
            old_pure, new_pure,
            fromfile=f"a/{tgt}",
            tofile=f"b/{tgt}",
            lineterm="",
        ))
        diff_text = "\n".join(diff_lines) + "\n"
        patch_path = os.path.join(output_dir, f"{pid}.patch")
        with open(patch_path, "w") as f:
            f.write(diff_text)
        patches.append({"id": pid, "type": "auto", "target": tgt,
                        "apply_cmd": f"git apply {os.path.basename(patch_path)}"})
    else:
        # R1/R3/R4/R5 → suggestion
        sug_path = os.path.join(output_dir, f"{pid}.{rule}.suggestion.md")
        with open(sug_path, "w") as f:
            f.write(f"# {rule} 文档漂移修复建议\n\n")
            f.write(f"- **来源文件**: `{src}`\n")
            f.write(f"- **目标文件**: `{tgt}`\n")
            f.write(f"- **原因**: {reason}\n")
            f.write(f"- **证据**: `{evidence}`\n\n")
            f.write("## 推荐修改\n\n")
            if rule == "R1":
                f.write(f"SKILL.md 已变更, 请同步更新 `{tgt}` 中对应的描述章节。\n")
                f.write(f"可参考 `git diff -- {src}` 查看具体改动后再人工写入 README。\n")
            elif rule == "R3":
                f.write(f"CLAUDE.md 改动后请确认 `{tgt}` 顶部的版本徽章 / banner 仍准确。\n")
            elif rule == "R4":
                f.write(f"autopilot 总览 SKILL.md 改动后请检查 `{tgt}` 中的流程图是否需刷新。\n")
            elif rule == "R5":
                f.write(f"新增 SKILL.md, 请在根 `README.md` / `README.zh.md` 插件表格中追加条目。\n")
            else:
                f.write("请人工评审并应用相应修改。\n")
        patches.append({"id": pid, "type": "manual", "target": tgt,
                        "apply_cmd": f"manual-review {os.path.basename(sug_path)}"})

with open(os.path.join(output_dir, "INDEX.json"), "w") as f:
    json.dump({"patches": patches, "source": candidates_file}, f, indent=2)

auto_n = sum(1 for p in patches if p["type"] == "auto")
manual_n = sum(1 for p in patches if p["type"] == "manual")
print(f"DOC_FIX_PATCHES: total={len(patches)} auto={auto_n} manual={manual_n}")
print(f"INDEX: {os.path.join(output_dir, 'INDEX.json')}")
print("Next: review individual files, then run apply-fix-patch.sh --patch-id <id>")
PY
RC=$?
exit $RC
