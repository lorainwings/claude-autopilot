# daily-report Plugin CLAUDE.md

> 此文件为 daily-report 插件的工程法则。
> 所有 AI Agent 在执行期间必须遵守。
> 版本: 1.3.0 <!-- x-release-please-version -->

## 插件定位

纯 Skill 型插件，无 TypeScript runtime、无 hooks。
基于 git 提交 + lark-cli 聊天记录，自动生成并提交内控日报。

## 核心约束

1. **配置不入 git**: API 地址、Token、userId 等敏感信息存放于 `~/.config/daily-report/config.json`，绝不硬编码在插件中
2. **Token 有效性优先**: 每次执行前必须验证 Token 有效性，过期则立即引导用户重新获取
3. **用户确认后提交**: 日报生成后必须展示给用户审核，确认后才调用 API 提交
4. **跳过已填日期**: 提交前检查目标日期是否已有日报，已填写的自动跳过
5. **工时固定 8h**: 每天总工时固定 8 小时，按条目数量比例分配

## 数据来源优先级

1. **Git 提交记录** (必需): 从配置的仓库路径中按 author + 日期提取
2. **飞书聊天记录** (必需): 通过 lark-cli 拉取工作群消息，lark-cli 未安装时阻断流程并引导安装
3. **日报分类接口** (必需): 调用内控系统分类列表获取可用 matterId

## 触发方式

- Skill 触发词: `/daily-report`
- 自然语言: "填写日报"、"写日报"、"生成日报"

<!-- DEV-ONLY-BEGIN -->

## 开发规范

### 发版纪律

1. **release-please 主要方式**: PR 合入 `main` → release-please 自动创建 Release PR → 合并即发版
2. **Conventional Commits 驱动**: commit message 遵循 `feat(daily-report):` / `fix(daily-report):` 前缀，release-please 据此计算版本号
3. **禁止散弹式修改版本号**: 不得人工修改 `.claude-plugin/plugin.json`、`README.md`、`README.zh.md`、`CLAUDE.md` 中的版本号，由 release-please 统一管理
4. **推送前必须通过 CI**: `make dr-ci`（`dr-lint` → `dr-build`）全部通过后才允许 `git push`
5. **post-release 自动回写**: Release PR 合并后，CI 会自动同步 `dist/daily-report/`、插件文档、根 README 版本表和 `.claude-plugin/marketplace.json`
6. **插件级路径隔离**: 仅修改 `plugins/daily-report/**` 时，统一 CI (`ci.yml`) 只跑 daily-report 矩阵；若改动 `scripts/`、`Makefile` 等共享文件，自动升级为全插件 CI

### 目录结构

```
plugins/daily-report/
├── .claude-plugin/plugin.json    # 插件元数据
├── CLAUDE.md                     # 本文件
├── skills/daily-report/
│   ├── SKILL.md                  # 核心 skill 指令
│   └── references/
│       └── setup-guide.md        # 初始化引导文档
├── tools/build-dist.sh           # 构建脚本
├── version.txt                   # 版本号
└── CHANGELOG.md                  # 变更日志
```

### 构建纪律

- `tools/build-dist.sh` 负责生成 `dist/daily-report/`
- 纯文件复制，无编译步骤
- dist 产物仅包含: `.claude-plugin/`、`skills/`、`CLAUDE.md`
- 禁止将 `tools/`、`version.txt`、`CHANGELOG.md` 复制到 dist

### SKILL.md 编写约束

- 控制在 2000 words 以内
- 只写原则和工作流，不写代码模板
- 引用文档放在 `references/` 目录

<!-- DEV-ONLY-END -->
