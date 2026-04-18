<!-- 此文件由根 CLAUDE.md 通过 @import 加载 -->

# 构建纪律

## Makefile 作为唯一入口

所有构建、测试、lint 操作**必须**通过 Makefile target 执行:

| 操作 | spec-autopilot | parallel-harness | daily-report |
|------|---------------|-----------------|-------------|
| 初始化 | `make setup` | `make ph-setup` | — |
| 测试 | `make test` | `make ph-test` | — |
| 构建 dist | `make build` | `make ph-build` | `make dr-build` |
| Lint | `make lint` | `make ph-lint` | `make dr-lint` |
| 类型检查 | `make typecheck` | `make ph-typecheck` | — |
| 格式检查 | `make format` | — | — |
| 完整 CI | `make ci` | `make ph-ci` | `make dr-ci` |

## dist 目录管理

1. **dist/ 是 git tracked 的构建产物**: 供 Claude Code 插件市场直接安装使用
2. **禁止手动修改 dist/ 下任何文件**: 所有变更在 `plugins/<name>/` 源码中进行
3. **构建脚本自动生成**: 每个插件的 `tools/build-dist.sh` 负责从源码生成 dist
4. **pre-commit 自动重建**: 当 `plugins/<name>/` 有实质性变更时，pre-commit hook 自动执行构建并 `git add dist/<name>/`
5. **CI 验证 freshness**: CI 会对比 dist 目录，确保提交的 dist 与 fresh build 一致
6. **测试文件永不进入 dist**: `tests/` 目录不在构建白名单中
