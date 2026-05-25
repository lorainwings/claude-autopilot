<!-- 此文件由根 CLAUDE.md 通过 @import 加载 -->

# 跨插件协作约束

## 隔离性

1. **源码隔离**: 每个插件在 `plugins/<name>/` 下完全自包含，禁止跨插件 import
2. **依赖隔离**: 每个插件有独立的 `package.json` / `bun.lock`，禁止共享 `node_modules`
3. **版本独立**: 各插件各自独立版本号，独立 CHANGELOG
4. **CI 统一**: 所有插件共用 `ci.yml` 统一入口，通过 `dorny/paths-filter` 按路径动态触发

## 共享层

以下资源属于仓库级共享，修改需考虑对所有插件的影响:

1. **`.claude-plugin/marketplace.json`**: 市场注册表，版本号由自动化维护（当前 5 插件: spec-autopilot / parallel-harness / daily-report / figma-codegen / slim-task）
2. **`.githooks/pre-commit`**: 统一 pre-commit hook，包含所有插件的检查逻辑
3. **`Makefile`**: 统一构建入口（前缀: 无 / `ph-` / `dr-` / `fc-` / `st-`）
4. **`scripts/`**: 仓库级脚本（hooks setup、release discipline 检查、dist freshness 校验）
5. **`tools/release.sh`**: 跨插件发版工具
6. **根目录 `README.md`**: 包含插件版本总表

## 新增插件清单

若需新增插件，必须完成以下步骤:

1. 在 `plugins/<new-name>/` 创建完整插件结构（含 CLAUDE.md、`.claude-plugin/plugin.json`）
2. 在 `.claude-plugin/marketplace.json` 注册
3. 在 `release-please-config.json` 和 `.release-please-manifest.json` 添加包配置
4. 在 `Makefile` 添加对应 target（沿用 2 字母前缀规范）
5. 在 `.github/workflows/ci.yml` 的 `dorny/paths-filter` filters 中添加插件条目和 CI jobs
6. 在 `.github/workflows/ci-sweep.yml` 中添加对应的 sweep job
7. 在 `scripts/check-dist-freshness.sh` 中添加对应 case 分支
8. 在 `scripts/check-release-discipline.sh` 的插件白名单三处同步添加
9. 在 `.githooks/pre-commit` 添加对应的 dist rebuild 逻辑
10. 在 `.githooks/pre-push` 的提示与扫描循环中添加该插件
11. 在根目录 `README.md` / `README.zh.md` 插件表格中添加条目
12. 在根 `CLAUDE.md` 的插件总表 + monorepo 导航树中添加条目
13. 在 `.claude/rules/build.md` / `testing.md` / `git-workflow.md` 等规则表格中追加该插件列
14. 在 `.gitignore` 确保 `!dist/<new-name>/` 被跟踪
