# Test Fix Patch 策略说明

## 设计原则

1. **禁止直接修改 `tests/*.sh`**：生成器仅写入 `--output-dir`，测试断言 (test_generate_test_fix.sh Case 5) 守护该不变式
2. **确定性优先**：R1 能机械判定的引用行删除直接生成 unified diff
3. **复杂上下文退化为 manual**：保留人工评审判断空间

## 规则映射

### R1 — 删除的 runtime 脚本仍被 tests 引用 (AUTO preferred)

**生成器逻辑**：
1. 取 `source_file` 的 basename（脚本文件名）
2. 读取 `target_file`（测试文件）全部行
3. 过滤掉包含 basename 的行
4. 若有差异，用 `difflib.unified_diff` 生成 patch (`<id>.R1.patch`)
5. 若无差异或 target 不存在，退化为 suggestion

### R3 — 源码中 symbol 删除但测试仍引用 (MANUAL)

`.suggestion.md` 提示：symbol `<evidence>` 已从 `<src>` 删除，建议删除 `<target>` 中对应 case。

### R4 — hook 文件修改 (MANUAL)

仅标记：建议回归该 hook 相关 test。不自动改动。

### R5 — 弱断言模式 (MANUAL + 模板)

`.suggestion.md` 附完整补强模板：

```bash
# 方案 A: 基于内容的断言
assert_contains "case 名" "$OUTPUT" "期望子串"

# 方案 B: 基于 JSON 字段的断言
assert_json_field "case 名" "$JSON_OUT" "field_name" "期望值"

# 方案 C: 基于退出码 + 副作用
assert_exit "case 名" 0 "$RC"
assert_file_contains "产物校验" "$ARTIFACT" "期望内容"
```

避免的反模式：`assert_exit "x" 0 0` / `[ "a" = "a" ]` / `grep -q . .`

## INDEX.json schema

```jsonc
{
  "patches": [
    {
      "id": "testfix-<NNN>-<rule_lower>-<sha8>",
      "type": "auto" | "manual",
      "target": "<相对仓库根的测试文件>",
      "apply_cmd": "<人类可读命令>"
    }
  ],
  "source": "<候选清单文件路径>"
}
```

## 与 apply-fix-patch.sh 协议

- 默认仅允许 `type: auto`；manual 需 `--force-manual`
- manual 类型应用时仅做 acknowledge，不改文件系统
- 全流程 git stash 保护
