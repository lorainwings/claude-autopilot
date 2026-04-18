# claude-autopilot 全局工程法则 (CLAUDE.md)

> 此文件为 **lorainwings-plugins** monorepo 的**全局规则层**。
> 所有 AI Agent（主线程 + 子 Agent）在本仓库任何位置操作时**必须**遵守以下法则。
> 各子插件有独立的 `plugins/<name>/CLAUDE.md`，定义插件特定约束。
> 冲突时：子插件规则 > 全局规则（仅在子插件目录内生效）。

## 项目概述

- **仓库**: [lorainwings/claude-autopilot](https://github.com/lorainwings/claude-autopilot)
- **定位**: Claude Code 插件市场 monorepo，托管三个独立插件
- **许可**: MIT License

| 插件 | 定位 | 运行时 |
|------|------|--------|
| **spec-autopilot** | 规格驱动的自动化交付流水线编排器 | Bash/Python + React GUI + TypeScript WebSocket |
| **parallel-harness** | 并行 AI 工程控制平面 | TypeScript/Bun |
| **daily-report** | 基于 git + 飞书的日报自动化生成器 | 纯 Skill (Markdown 指令) |

## Monorepo 导航

```
├── .claude-plugin/              # 市场配置 (marketplace.json — 版本号由自动化维护)
├── .githooks/                   # Git pre-commit hook (非 Husky)
├── .github/workflows/           # CI: ci.yml (统一入口) / ci-sweep.yml (定时全量) / release-please.yml
├── dist/                        # 构建产物 (git tracked，供市场安装)
│   ├── spec-autopilot/          # spec-autopilot 发布产物
│   ├── parallel-harness/        # parallel-harness 发布产物
│   └── daily-report/            # daily-report 发布产物
├── docs/plans/                  # 设计文档与执行计划
├── plugins/                     # 插件源代码 (所有修改在此进行)
│   ├── spec-autopilot/          # → 有独立 CLAUDE.md
│   ├── parallel-harness/        # → 有独立 CLAUDE.md
│   └── daily-report/            # → 有独立 CLAUDE.md
├── scripts/                     # 仓库级脚本 (setup-hooks.sh, check-release-discipline.sh)
├── tools/                       # 发版工具 (release.sh)
├── Makefile                     # 统一构建入口 — 所有构建/测试/lint 操作的唯一入口
├── release-please-config.json   # release-please 多包配置
└── .release-please-manifest.json # 当前版本快照
```

**关键路径速查**:

- 修改 spec-autopilot 源码 → `plugins/spec-autopilot/`
- 修改 parallel-harness 源码 → `plugins/parallel-harness/`
- 修改 daily-report 源码 → `plugins/daily-report/`
- 查看市场配置 → `.claude-plugin/marketplace.json`
- 查看 CI 定义 → `.github/workflows/ci.yml` (统一入口, 含 `dorny/paths-filter` 配置)
- 查看 dist 一致性校验 → `scripts/check-dist-freshness.sh`
- 查看版本清单 → `.release-please-manifest.json`

## 规则索引

详细规则按主题拆分到 `.claude/rules/` 子文件，由 Claude Code 通过官方 `@` import 语法自动加载:

- @.claude/rules/git-worktree.md
- @.claude/rules/build.md
- @.claude/rules/versioning.md
- @.claude/rules/code-quality.md
- @.claude/rules/testing.md
- @.claude/rules/ci.md
- @.claude/rules/git-workflow.md
- @.claude/rules/docs.md
- @.claude/rules/cross-plugin.md
- @.claude/rules/forbidden.md
