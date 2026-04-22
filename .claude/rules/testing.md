<!-- 此文件由根 CLAUDE.md 通过 @import 加载 -->

# 测试纪律

## 通用规则 (跨插件)

1. **每个新功能至少 3 个测试用例**: 正常路径 + 边界条件 + 错误路径
2. **禁止弱化已有断言**: 不得将失败断言改为通过来规避问题
3. **禁止删除已有测试**: 删除必须在 commit message 中说明理由
4. **禁止跳过测试**: 不得注释或条件跳过已有测试
5. **测试失败时修复实现**: 定位具体失败断言，修复实现代码而非测试逻辑

## 插件测试命令

| 插件 | 命令 | 框架 | 基线 |
|------|------|------|------|
| spec-autopilot | `make test` | Bash 测试套件 | 104 文件, 1245+ 断言 |
| parallel-harness | `make ph-test` | `bun test` | 295 tests, 649 assertions |

## 推送前检查清单

`git push` 前必须确保（多数项由 pre-push hook 自动校验）:

1. 完整测试套件通过 (`make test` / `make ph-test`) — **pre-push 自动跑受影响 plugin 的增量测试**；仅在改动不触及 `runtime/` 或 `tests/` 时由 hook 跳过
2. 类型检查通过 (`make typecheck` / `make ph-typecheck`) — pre-push 自动校验
3. Lint 通过 (`make lint` / `make ph-lint`) — 由 CI 做全量校验；本地 pre-commit 做 staged 增量
4. dist 构建成功且已提交 (`make build` / `make ph-build`) — pre-commit 自动重建，pre-push 校验 freshness
5. 分支与 `origin/main` 已同步 — pre-push 闸口

紧急绕过：`AUTOPILOT_SKIP_TEST=1 git push ...` 跳过第 1 项本地测试（仅 hotfix 等极端场景）
