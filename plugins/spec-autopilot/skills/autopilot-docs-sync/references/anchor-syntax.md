# Code-Doc Ownership Anchor Syntax

> 锚点机制语法规范 — 在源码与文档中显式声明双向所有权关系，
> 由 `runtime/scripts/scan-code-ref-anchors.sh` 提取，
> `runtime/scripts/detect-anchor-drift.sh` 用于 R6/R7/R8 漂移检测。

## 1. 设计目标

- **双向显式**：源码侧声明"我被这份文档描述"，文档侧声明"我描述这个代码"
- **零侵入**：仅追加注释行，不改动既有逻辑
- **回退兼容**：当无内联锚点时，可由 `.claude/docs-ownership.yaml` 配置补足

## 2. 内联锚点语法

### 2.1 代码侧（`CODE-REF`）

源码文件内一行注释，路径相对仓库根。语法形式：

| 语言 | 示例 |
|------|------|
| Shell / Bash | `# CODE-REF: docs/plans/engineering-auto-sync/02-rollout.md` |
| Python | `# CODE-REF: docs/plans/foo.md` |
| TypeScript / JavaScript | `// CODE-REF: docs/plans/foo.md` |
| Markdown 注释 | `<!-- CODE-REF: docs/plans/foo.md -->` |

### 2.2 文档侧（`CODE-OWNED-BY`）

Markdown 文件内 HTML 注释，单条或多条逗号分隔：

```markdown
<!-- CODE-OWNED-BY: plugins/spec-autopilot/runtime/scripts/detect-doc-drift.sh -->
<!-- CODE-OWNED-BY: scripts/a.sh, scripts/b.sh -->
```

## 3. 配置 fallback (`.claude/docs-ownership.yaml`)

详见 [`ownership-config.md`](./ownership-config.md)。配置侧锚点 source 标记为 `config`，
内联锚点 source 标记为 `inline`。同一 code 来自多个来源时 docs 列表合并去重。

## 4. 扫描产物

```json
{
  "anchors": [
    {
      "code": "plugins/spec-autopilot/runtime/scripts/detect-doc-drift.sh",
      "docs": ["docs/plans/engineering-auto-sync/01-design.md"],
      "source": "inline",
      "line": 12
    }
  ]
}
```

`line` 字段在 `source=inline` 时为锚点出现的文件行号；`source=config` 时为 0。

## 5. 漂移规则（R6/R7/R8）

| 规则 | 触发 | 严重度 |
|------|------|--------|
| R6 | 配对表中某 code 文件指向的 doc 路径不存在 | warn |
| R7 | doc 中 `CODE-OWNED-BY` 指向的 code 文件不存在 | warn |
| R8 | staged-files 含 code X 且 X 锚点映射到 doc Y，但 Y 未进 staging | warn (candidate) |

## 6. 反例与边界

- 单行注释中只允许出现一次锚点关键字，多个路径以逗号分隔
- 路径必须为相对仓库根的 POSIX 风格 (`/` 分隔)，禁止 `../` 或绝对路径
- `scan-code-ref-anchors.sh` 自身位置过滤：扫描器自身文件中的示例不计入产物
