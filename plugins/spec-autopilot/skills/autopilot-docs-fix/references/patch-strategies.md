# Doc Fix Patch 策略说明

## 设计原则

1. **确定性优先**：能机械生成的 patch 一律用代码生成（unified diff），不依赖 LLM
2. **LLM 仅生成建议**：含语义判断的修改（README 文案、版本标识）写为 `.suggestion.md` 供人工评审
3. **绝不自动应用**：所有产物落盘到 `.docs-fix-patches/`，由 `apply-fix-patch.sh` 在 git stash 保护下应用

## 规则映射

### R2 — 新脚本未进 `.dist-include` (AUTO)

**生成器逻辑**：
1. 读取候选中 `target_file`（`.dist-include` 路径）
2. 取 `source_file` 的 basename
3. 用 `difflib.unified_diff` 在文件末尾追加 `<basename>\n`
4. 输出 `<id>.patch`，类型 `auto`

**应用方式**：`git apply <patch>` （已通过 `git apply --check`）

### R1 — SKILL.md 改动但 README 未同步 (MANUAL)

**生成器逻辑**：写出 `.suggestion.md`：
- 提示运行 `git diff -- <SKILL.md>` 复核改动
- 给出 README 推荐修改章节定位
- 不生成 patch（README 文案由人撰写）

### R3 — CLAUDE.md 改�� (MANUAL)

提示：检查 `target_file`（README）顶部版本徽章 / banner 是否仍准确。

### R4 — autopilot 总览 SKILL.md 改动 (MANUAL)

提示：检查 `docs/plans/` 流程图是否需刷新。

### R5 — 新 SKILL.md 但根 README 表格未更新 (MANUAL)

提示：在根 `README.md` / `README.zh.md` 插件表格追加条目。

## INDEX.json schema

```jsonc
{
  "patches": [
    {
      "id": "docfix-<NNN>-<rule_lower>-<sha8>",
      "type": "auto" | "manual",
      "target": "<相对仓库根的目标文件>",
      "apply_cmd": "<人类可读命令>"
    }
  ],
  "source": "<候选清单文件路径>"
}
```

## 退化路径

- R2 候选若 target 文件不存在 → 退化为 manual suggestion
- 候选 JSON 损坏 / 文件缺失 → 退出码 1，stderr 输出 clear error

## 与 apply-fix-patch.sh 协议

- 仅 `type: auto` 默认可应用；`manual` 需 `--force-manual`
- patch 文件命名约定：`<id>.patch`（R2）；suggestion 命名：`<id>.<rule>.suggestion.md`
