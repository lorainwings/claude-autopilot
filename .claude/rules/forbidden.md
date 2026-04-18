<!-- 此文件由根 CLAUDE.md 通过 @import 加载 -->

# 绝对禁止清单

以下操作在任何情况下均被禁止，AI Agent 遇到相关建议时必须拒绝:

1. **禁止将工作树改为 bare 仓库** — 破坏整个 worktree 链路
2. **禁止手动修改 dist/ 下文件** — 由构建脚本自动生成
3. **禁止散弹式修改版本号** — 由 release-please 或 release.sh 统一管理
4. **禁止引入 ESLint / Prettier** — 项目不使用这些工具
5. **禁止 `git config core.hooksPath /dev/null`** — 破坏 hook 保护链
6. **禁止跨插件 import** — 插件间完全隔离
7. **禁止跳过测试套件直接推送** — 推送前必须完整测试通过
8. **禁止手动干预 release-please 分支** — 由自动化管理
