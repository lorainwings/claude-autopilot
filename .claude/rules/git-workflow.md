<!-- 此文件由根 CLAUDE.md 通过 @import 加载 -->

# 分支策略

| 分支模式 | 用途 | 示例 |
|---------|------|------|
| `main` | 默认分支，稳定基线 | — |
| `feature/*` | 功能开发 | `feature/cost-aware-routing` |
| `fix/*` | Bug 修复 | `fix/worktree-default-enabled` |
| `release/*` | 独立开发分支（用于 worktree） | `release/parallel-harness` |
| `release-please--*` | release-please 自动管理，禁止手动干预 | `release-please--branches--main` |

# Git Hooks 规范

## 基础设施

- 使用 `.githooks/` 目录（非 Husky），通过 `core.hooksPath` 配置
- 初始化: `make setup` 或 `bash scripts/setup-hooks.sh`
- **pre-commit**: 测试 + lint + 版本校验 + dist 自动重建
- **pre-push**: 全插件 dist freshness 最终防线
- pre-commit hook 包含 hooksPath 自保护机制（检测到 `/dev/null` 自动恢复）

## 严禁 hooksPath 破坏

- **严禁 `git config core.hooksPath /dev/null`**: 任何脚本不得对主仓库执行此操作
- 临时仓库需跳过 hook 时使用 `git commit --no-verify`，且必须以 `git -C $TMPDIR` 隔离

## Pre-commit 执行流程

1. hooksPath 自保护检查
2. release-please 分支 bypass
3. spec-autopilot 变更时: 全量测试 → 测试覆盖检查 → staged lint → 版本一致性校验 → 自动重建 dist
4. parallel-harness 变更时: 自动重建 dist
5. daily-report 变更时: 自动重建 dist
