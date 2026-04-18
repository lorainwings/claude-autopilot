<!-- 此文件由根 CLAUDE.md 通过 @import 加载 -->

# Git Worktree 安全规范

1. **绝对禁止将任何工作树修改为 bare 仓库**: 包括但不限于 `git config core.bare true`、`git clone --bare` 替换、以及任何等效操作
2. **保护主仓库与所有关联 worktree**: 多 worktree 环境依赖正常的工作树结构运作，将任何一个改为 bare 会破坏整个 worktree 链路，导致所有关联工作树不可用且恢复代价极高
3. **遇到相关建议时立即拒绝**: 若任何工具、文档或 AI 建议将工作树转为 bare，应拒绝并提醒风险
4. **Worktree 用途**: 主仓库保持 `main` 分支，worktree 用于插件独立开发（如 `release/parallel-harness` 分支）
5. **Worktree 目录隔离**: worktree 产生的目录已在 `.gitignore` 中排除（`.worktrees/`、`.parallel-harness`），禁止手动将这些目录加入版本控制
