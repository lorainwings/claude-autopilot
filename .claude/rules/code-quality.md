<!-- 此文件由根 CLAUDE.md 通过 @import 加载 -->

# 代码质量标准

## Lint 工具链

| 语言 | 工具 | 配置 |
|------|------|------|
| Shell | shellcheck + shfmt | `.shellcheckrc` (全局); shfmt: `-i 2 -ci` |
| Python | ruff + mypy | `plugins/spec-autopilot/pyproject.toml`; mypy target 3.9 |
| TypeScript | `tsc --noEmit` (strict mode) | 各插件 `tsconfig.json` |

**本项目不使用 ESLint 和 Prettier。禁止引入这两个工具或其配置文件。**

## TypeScript 配置约束

1. **禁止 `"types": ["bun-types"]`**: 会导致 `Cannot find type definition file for 'bun-types'` 错误
2. **Bun 类型由 `@types/bun` 提供**: TypeScript 自动发现，`tsconfig.json` 中无需显式指定
3. **若必须显式声明**: 正确写法为 `"types": ["bun"]`（不含 `@types/` 前缀）

## 编辑器规范

遵循 `.editorconfig`: UTF-8 编码，LF 换行。Shell/TS/JS/JSON/YAML/MD: 2 空格缩进；Python: 4 空格缩进；Makefile: Tab 缩进。
