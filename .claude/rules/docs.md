<!-- 此文件由根 CLAUDE.md 通过 @import 加载 -->

# 文档规范

## 双语要求

1. 英文为默认版本 (`.md`)，中文为伴随版本 (`.zh.md`)
2. 两个版本顶部必须有语言切换链接
3. 共享内容（代码块、图表、表格）在两个版本中必须一致
4. 新增文档必须同时提供双语版本

## CLAUDE.md 特殊规范

- CLAUDE.md 使用中文撰写
- 子插件 CLAUDE.md 使用 `<!-- DEV-ONLY-BEGIN -->` / `<!-- DEV-ONLY-END -->` 标记区分开发者规则与发布规则
- `build-dist.sh` 在构建时剥离 DEV-ONLY 块，dist 中的 CLAUDE.md 仅含发布规则
- 根目录 CLAUDE.md 不使用 DEV-ONLY 标记（全部为全局规则，始终生效）
