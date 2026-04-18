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

## Pre-push 执行流程

1. **`origin/main` 同步闸口（最先执行）**: 分支必须包含 `origin/main` 最新 commit，否则阻断
2. dist 内容一致性 (`scripts/check-dist-freshness.sh all`)
3. dist 变更已提交 (无 unstaged / 未提交 / untracked)

## 提交流程规范化（main 同步铁律）

> 无论 commit 频率多高，**每次 push 前必须先 rebase / merge `origin/main`**，避免 PR 合入时与他人改动冲突、CI 失效。

`scripts/check-branch-synced.sh` 由 pre-push 钩子自动调用：

| 场景 | 行为 |
|------|------|
| 当前在 `main`/`master` | 放行 |
| `release-please--*` / `release/*` 分支 | 放行（自动化管理） |
| 离线 / 无 `origin/main` | 警告但放行（断网容灾） |
| 分支已包含 `origin/main` 最新 commit | 放行 |
| 分支落后 `origin/main` | **阻断**，输出落后/领先 commit 数 + 修复指引 |

**修复方式**（按推荐度排序）：

```bash
# 推荐：保持线性历史
git fetch origin main && git rebase origin/main
git push --force-with-lease   # rebase 后必须用 --force-with-lease

# 替代：保留 merge commit
git fetch origin main && git merge origin/main
git push
```

**紧急绕过**（仅在 hotfix 等极端场景，需在 commit message 中说明）：

```bash
AUTOPILOT_SKIP_MAIN_SYNC=1 git push ...
```

> **设计意图**：消除"提交时不知道 main 已经走多远"导致的合入摩擦。落后越多越难 rebase，强制每次 push 前同步，把痛感降到最小且可控。
