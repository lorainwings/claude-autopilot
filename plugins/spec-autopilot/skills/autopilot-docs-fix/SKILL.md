---
name: autopilot-docs-fix
description: "Use when a user or the autopilot orchestrator needs to turn the documentation drift candidate list at .cache/spec-autopilot/drift-candidates.json into applicable fixes — producing deterministic auto patches (R2 scripts → .dist-include append) and manual .suggestion.md templates for the remaining rules. The skill never auto-applies: patches land under .cache/spec-autopilot/docs-fix-patches/ and are applied only via apply-fix-patch.sh under git stash protection on explicit human confirmation. Triggers: '/autopilot-docs-fix scan', '修复文档漂移', 'apply doc fix'."
user-invocable: true
---

# autopilot-docs-fix — 文档漂移候选修复生成器

## 用途

- 消费 `autopilot-docs-sync` 产出的 `.cache/spec-autopilot/drift-candidates.json`
- 将候选转换为两类产物：
  - **auto patch** (`<id>.patch`)：可直接 `git apply` 的 unified diff（确定性）
  - **manual suggestion** (`<id>.<rule>.suggestion.md`)：人工评审模板（含推荐修改说明）
- **绝不自动应用**：产物位于 `<project>/.cache/spec-autopilot/docs-fix-patches/`，需通过 `apply-fix-patch.sh` 在 `git stash` 保护下手动触发

## 触发入口

- `/autopilot-docs-fix scan` — 扫描候选清单并生成 patches
- `/autopilot-docs-fix apply --patch-id <id>` — 应用单个 patch
- `/autopilot-docs-fix apply --all` — 批量应用所有 auto patch

## 前置依赖

若 `.cache/spec-autopilot/drift-candidates.json` 不存在，提示先执行：

```bash
bash plugins/spec-autopilot/runtime/scripts/detect-doc-drift.sh \
  --changed-files "<space-separated-files>"
```

或等待 autopilot 主流水线 Phase 7 自动触发 docs-sync。

## 规则 → 产物映射

| Rule | 类型 | 产物 | 说明 |
|------|------|------|------|
| R1 | manual | `.suggestion.md` | SKILL.md 改动摘要 + README 建议修改位置 |
| R2 | auto | `.patch` | 追加脚本名到 `.dist-include` 末尾（git apply --check 通过） |
| R3 | manual | `.suggestion.md` | CLAUDE.md 改动提醒检查版本标识 |
| R4 | manual | `.suggestion.md` | Phase 总览改动提醒刷新 docs/plans 流程图 |
| R5 | manual | `.suggestion.md` | 新 SKILL.md 提醒更新根 README 插件表格 |

## 命令

### 扫描生成

```bash
bash plugins/spec-autopilot/runtime/scripts/generate-doc-fix-patch.sh \
  --candidates-file .cache/spec-autopilot/drift-candidates.json \
  --output-dir .cache/spec-autopilot/docs-fix-patches/
```

### 应用（人工 confirm 后）

```bash
# 单个
bash plugins/spec-autopilot/runtime/scripts/apply-fix-patch.sh \
  --index .cache/spec-autopilot/docs-fix-patches/INDEX.json \
  --patch-id <id>

# 批量 auto
bash plugins/spec-autopilot/runtime/scripts/apply-fix-patch.sh \
  --index .cache/spec-autopilot/docs-fix-patches/INDEX.json \
  --all

# 演练
bash plugins/spec-autopilot/runtime/scripts/apply-fix-patch.sh \
  --index .cache/spec-autopilot/docs-fix-patches/INDEX.json \
  --patch-id <id> --dry-run
```

## 安全保证

- 每次 apply 前 `git stash push -u` 保护 working tree
- 每个 patch 先 `git apply --check` 预校验，失败立即 `git stash pop` 回滚
- 默认拒绝 `type: manual` patch；需 `--force-manual` 显式 acknowledge
- **禁止在 CI / pre-commit 中自动调用**

## 产物索引

`.cache/spec-autopilot/docs-fix-patches/INDEX.json`：

```json
{
  "patches": [
    {"id":"docfix-001-r2-abc12345", "type":"auto",
     "target":"plugins/spec-autopilot/runtime/scripts/.dist-include",
     "apply_cmd":"git apply docfix-001-r2-abc12345.patch"}
  ],
  "source": ".cache/spec-autopilot/drift-candidates.json"
}
```

详见 `references/patch-strategies.md`。
