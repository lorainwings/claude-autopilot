<!-- 此文件由根 CLAUDE.md 通过 @import 加载 -->

# 版本管理与发版纪律

## release-please (主要方式)

1. **自动化流程**: PR 合入 `main` → release-please 自动创建 Release PR → 合并即发版
2. **Conventional Commits 驱动**: commit message 遵循 `feat:` / `fix:` / `refactor:` / `perf:` 等前缀，release-please 据此计算版本号和生成 CHANGELOG
3. **多包配置**: `release-please-config.json` 定义三个插件的发版规则，每个插件独立版本
4. **post-release 自动化**: CI 发版后自动更新 `dist/`、插件 README/CLAUDE、根 README 版本表和 `.claude-plugin/marketplace.json`

## 手动 fallback

- `tools/release.sh` (交互式向导) 仅在 release-please 不可用时使用
- 预览模式: `make release-dry`

## 版本一致性铁律

1. **禁止散弹式修改**: 禁止人工或 AI 单独修改以下任何文件中的版本号:
   - `plugins/<name>/.claude-plugin/plugin.json`
   - `plugins/<name>/package.json` (parallel-harness)
   - `.claude-plugin/marketplace.json`
   - `plugins/<name>/README.md` / `README.zh.md` 中的 badge/标题
   - `plugins/<name>/CHANGELOG.md`
   - 根目录 `README.md` / `README.zh.md` 的版本表格
2. **版本号由自动化工具统一管理**: release-please 或 `tools/release.sh`
3. **pre-commit 一致性校验**: hook 检查 `plugin.json` vs `README.md` vs `marketplace.json` 版本，不一致即阻断
4. **CI release-discipline 检查**: `scripts/check-release-discipline.sh` 验证版本一致性

## Conventional Commits 规范

```
feat(<scope>): 添加新功能        → 触发 minor 版本升级
fix(<scope>): 修复 bug           → 触发 patch 版本升级
refactor(<scope>): 代码重构      → 触发 patch 版本升级
perf(<scope>): 性能优化          → 记入 CHANGELOG
docs: 文档更新                   → 不触发发版
test: 测试更新                   → 不触发发版
chore: 维护任务                  → 不触发发版
ci: CI 配置变更                  → 不触发发版
```

scope 使用插件名: `feat(spec-autopilot):` 或 `fix(parallel-harness):`
