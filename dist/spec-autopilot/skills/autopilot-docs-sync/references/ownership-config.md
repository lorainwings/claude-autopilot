# `.claude/docs-ownership.yaml` 配置规范

> 提供 fallback ownership 映射，用于源码或文档因历史/侵入性原因不便插入内联锚点时的兜底。

## 1. 文件位置

仓库根目录 `.claude/docs-ownership.yaml`。模板文件位于同目录 `docs-ownership.yaml.example`（不强制 Read：如需可直接复制样例到 `.claude/docs-ownership.yaml`）。

## 2. 顶层 schema

```yaml
mappings:
  - code: <relative-path>          # 单文件映射
    docs:
      - <doc-path-1>
      - <doc-path-2>
  - code_glob: <glob-pattern>      # 通配映射 (互斥)
    docs:
      - <doc-path>
```

| 字段 | 类型 | 说明 |
|------|------|------|
| `mappings` | list | 必填，至少一项 |
| `mappings[].code` | string | 单代码文件路径，相对仓库根 |
| `mappings[].code_glob` | string | shell glob，匹配多个代码文件（与 `code` 互斥） |
| `mappings[].docs` | list[string] | 对应文档路径列表，至少一项 |

## 3. Glob 行为

- 简单 `*` / `**` 匹配，由 scanner 解析
- 仅匹配仓库内已存在的真实文件
- 匹配结果去重后注入 anchors 集合

## 4. 优先级与去重

- 内联锚点（`source: inline`）与配置锚点（`source: config`）按 `code` key 合并
- `docs` 列表合并后保持稳定排序、去重
- `--only-inline` 标志位会跳过配置文件加载

## 5. 示例

```yaml
mappings:
  - code: plugins/spec-autopilot/runtime/scripts/detect-doc-drift.sh
    docs:
      - docs/plans/engineering-auto-sync/01-design.md
      - plugins/spec-autopilot/skills/autopilot-docs-sync/SKILL.md

  - code_glob: plugins/spec-autopilot/skills/autopilot-phase*/SKILL.md
    docs:
      - plugins/spec-autopilot/README.md
```

## 6. 校验

`scan-code-ref-anchors.sh` 解析失败时退出码仍为 0，但会向 stderr 打印 `WARN: invalid yaml`，
并将 `mappings` 视为空。这样不会意外阻断 pre-commit。
