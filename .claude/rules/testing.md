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

`git push` 前必须确保:

1. 完整测试套件通过 (`make test` / `make ph-test`)
2. 类型检查通过 (`make typecheck` / `make ph-typecheck`)
3. Lint 通过 (`make lint` / `make ph-lint`)
4. dist 构建成功且已提交 (`make build` / `make ph-build`)
