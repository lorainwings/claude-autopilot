# slim-task Plugin CLAUDE.md

> 此文件为 slim-task 插件的工程法则。
> 所有 AI Agent 在执行期间必须遵守。
> 版本: 0.1.0 <!-- x-release-please-version -->

## 插件定位

纯 Skill 型插件，无 TypeScript runtime、无 hooks。
提供 6 阶段结构化 SOP，采用主检子执模式 + DAG 最大化并行，解决 AI 任务执行的 7 个常见问题。

## 核心约束

1. **主检子执**: 主 Agent 只做检查/决策/派发/验证，子 Agent 做实际编码
2. **影响范围即合约**: 禁止修改 Phase 2 审批的影响范围表之外的文件
3. **DAG 无上限并行**: 同层无依赖任务全部并行派发，不限数量
4. **阶段门控**: 每个阶段转换必须有用户检查点
5. **提交须授权**: commit/push 必须通过 AskUserQuestion 获得用户明确确认

## 触发方式

- Skill 触发词: `/slim-task`
- 自然语言: "结构化任务"、"SOP 执行"、"拆分任务并行执行"

## 完全独立

本插件不依赖 spec-autopilot、parallel-harness 或任何其他插件的基础设施。

<!-- DEV-ONLY-BEGIN -->

## 开发规范

### 发版纪律

1. **release-please 主要方式**: PR 合入 `main` → release-please 自动创建 Release PR → 合并即发版
2. **Conventional Commits 驱动**: commit message 遵循 `feat(slim-task):` / `fix(slim-task):` 前缀
3. **禁止散弹式修改版本号**: 不得人工修改 `.claude-plugin/plugin.json`、README、CLAUDE.md 中的版本号
4. **推送前必须通过 CI**: `make st-ci`（`st-lint` → `st-build`）全部通过后才允许 `git push`
5. **post-release 自动回写**: CI 发版后自动同步 `dist/slim-task/`、文档、marketplace.json

### 目录结构

```
plugins/slim-task/
├── .claude-plugin/plugin.json    # 插件元数据
├── CLAUDE.md                     # 本文件
├── skills/slim-task/
│   └── SKILL.md                  # 核心 SOP 指令
├── tools/build-dist.sh           # 构建脚本
├── version.txt                   # 版本号
└── CHANGELOG.md                  # 变更日志
```

### 构建纪律

- `tools/build-dist.sh` 负责生成 `dist/slim-task/`
- 纯文件复制，无编译步骤
- dist 产物仅包含: `.claude-plugin/`、`skills/`、`CLAUDE.md`
- 禁止将 `tools/`、`version.txt`、`CHANGELOG.md` 复制到 dist

### SKILL.md 编写约束

- 控制在 2000 words 以内
- 只写原则和工作流，不写代码模板
- 引用文档放在 `references/` 目录

<!-- DEV-ONLY-END -->
