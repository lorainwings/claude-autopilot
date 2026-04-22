<!-- 此文件由根 CLAUDE.md 通过 @import 加载 -->

# CI/CD 规范

## Pipeline 架构

| Workflow | 触发条件 | 职责 |
|----------|---------|------|
| `ci.yml` | push/PR to `main` | 统一入口: 检测受影响插件 → 动态生成 matrix → 按插件执行 lint/test/typecheck/build/dist 校验 → 输出稳定 summary check |
| `ci-sweep.yml` | 每周一定时 + 手动 | 延迟发现防线: 全插件全量 CI (ubuntu + macOS) |
| `release-please.yml` | push to `main` | release-please → post-release (dist 构建 + 版本同步) |

## 影响面解析 (单一真相)

`dorny/paths-filter@v3` 是 CI 中判断受影响插件的唯一机制 (配置在 `ci.yml` detect job 中):

- 命中 `plugins/<plugin>/**` 或 `dist/<plugin>/**` → 仅该插件
- 命中 `shared` filter (`scripts/`、`.github/`、`Makefile`、`.shellcheckrc` 等) → 全插件
- 新增插件时需在 `ci.yml` 的 `filters` 配置中添加对应条目

## dist 一致性校验 (统一机制)

`scripts/check-dist-freshness.sh` 被以下场景共同调用:

- **pre-commit**: 自动检测 + 重建
- **pre-push**: 全插件最终防线
- **CI**: build 后校验
- **release/post-release**: 与普通 build 使用相同约束

## CI 关键行为

1. **统一 summary check**: `CI Summary` 是 branch protection 的唯一 required check，不会因 path skip 导致 pending
2. **动态 matrix**: 仅跑受影响插件，共享基础设施变更自动升级为全插件 CI
3. **release-please 分支 bypass**: pre-commit hook 检测到 `release-please--*` 分支自动跳过
4. **bot commit bypass**: CI discipline 检查自动跳过 release-please 和 post-release bot 提交
5. **dist freshness 验证**: CI 构建后调用统一脚本对比，不一致则失败
6. **跨平台测试分层**: PR CI (`ci.yml`) 仅在 `ubuntu-latest` 上跑 test；macOS 专属风险由开发者本地 pre-push + 每周一 `ci-sweep.yml` 兜底（ubuntu + macOS 全量）。理由：macOS runner 计费 10× + 排队慢，而开发者本地即 macOS，PR 层面重复跑收益极低
7. **定时全量 sweep**: 每周一全插件扫描，防止路径过滤遗漏共享问题
