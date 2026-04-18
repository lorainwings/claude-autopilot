---
name: autopilot-docs-fix
description: "消费 .drift-candidates.json 生成可应用的文档漂移修复 patch。确定性优先（R2 新脚本自动 patch），其余规则生成 .suggestion.md。绝不自动应用，由 apply-fix-patch.sh 在 git stash 保护下由人工触发。触发: '/autopilot-docs-fix scan', '修复文档漂移', 'apply doc fix'。"
user-invocable: true
---

# autopilot-docs-fix — 文档漂移候选修复生成器

## 用途

- 消费 `autopilot-docs-sync` 产出的 `.drift-candidates.json`
- 将候选转换为两类产物：
  - **auto patch** (`<id>.patch`)：可直接 `git apply` 的 unified diff（确定性）
  - **manual suggestion** (`<id>.<rule>.suggestion.md`)：人工评审模板（含推荐修改说明）
- **绝不自动应用**：产物位于 `<project>/.docs-fix-patches/`，需通过 `apply-fix-patch.sh` 在 `git stash` 保护下手动触发

## 触发入口

- `/autopilot-docs-fix scan` — 扫描候选清单并生成 patches
- `/autopilot-docs-fix apply --patch-id <id>` — 应用单个 patch
- `/autopilot-docs-fix apply --all` — 批量应用所有 auto patch

## 前置依赖

若 `.drift-candidates.json` 不存在，提示先执行：

```bash
bash plugins/spec-autopilot/runtime/scripts/detect-doc-drift.sh \
  --changed-files "<space-separated-files>"
```

或直接触发 `autopilot-docs-sync` skill。

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
  --candidates-file .drift-candidates.json \
  --output-dir .docs-fix-patches/
```

### 应用（人工 confirm 后）

```bash
# 单个
bash plugins/spec-autopilot/runtime/scripts/apply-fix-patch.sh \
  --index .docs-fix-patches/INDEX.json \
  --patch-id <id>

# 批量 auto
bash plugins/spec-autopilot/runtime/scripts/apply-fix-patch.sh \
  --index .docs-fix-patches/INDEX.json \
  --all

# 演练
bash plugins/spec-autopilot/runtime/scripts/apply-fix-patch.sh \
  --index .docs-fix-patches/INDEX.json \
  --patch-id <id> --dry-run
```

## 安全保证

- 每次 apply 前 `git stash push -u` 保护 working tree
- 每个 patch 先 `git apply --check` 预校验，失败立即 `git stash pop` 回滚
- 默认拒绝 `type: manual` patch；需 `--force-manual` 显式 acknowledge
- **禁止在 CI / pre-commit 中自动调用**

## 产物索引

`.docs-fix-patches/INDEX.json`：

```json
{
  "patches": [
    {"id":"docfix-001-r2-abc12345", "type":"auto",
     "target":"plugins/spec-autopilot/runtime/scripts/.dist-include",
     "apply_cmd":"git apply docfix-001-r2-abc12345.patch"}
  ],
  "source": ".drift-candidates.json"
}
```

详见 `references/patch-strategies.md`。
