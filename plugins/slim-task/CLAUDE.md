# slim-task Plugin CLAUDE.md

> 此文件为 slim-task 插件的工程法则。
> 所有 AI Agent 在执行期间必须遵守。
> 版本: 0.5.0 <!-- x-release-please-version -->

## 插件定位

纯 Skill 型插件，无 TypeScript runtime、无 hooks。
提供 7 阶段结构化 SOP（Phase 0-6），采用主检子执模式 + DAG 最大化并行 + Phase 5 独立审计盲审，解决 AI 任务执行的 8 个常见问题。

## 核心约束

1. **主检子执**: 主 Agent 只做检查/决策/派发/验证，子 Agent 做实际编码与质量审计
2. **影响范围即合约**: 禁止修改 Phase 2 审批的影响范围表之外的文件
3. **DAG 无上限并行**: 同层无依赖任务全部并行派发，不限数量
4. **阶段门控**: 每个阶段转换必须有用户检查点
5. **提交须授权**: commit/push 必须通过 AskUserQuestion 获得用户明确确认
6. **语言一致性**: AI 对话、决策卡、生成文档、子 Agent prompt 按 `${LANG}` 配置输出（默认 `zh-CN`），Conventional Commits 前缀保持英文
7. **Worktree 隔离可选**: 可通过 `--worktree` 开启独立 worktree 执行，禁止 auto-merge 回 main
8. **Phase 5 盲审反作弊**: 质量检查由独立 auditor 子 Agent 在隔离 context 内执行，禁止注入实现 Agent 的过程信息

## 触发方式

- Skill 触发词: `/slim-task [task] [--lang ...] [--worktree] [--base ...]`
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
│   ├── SKILL.md                  # 核心编排器索引（≤100 行）
│   └── references/               # 详细 SOP / 协议 / 模板
│       ├── checkpoint-protocol.md
│       ├── phase-sop.md
│       ├── phase5-audit-protocol.md
│       └── subagent-prompt-template.md
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

- 主编排器 SKILL.md 控制在 100 行以内，仅保留护栏 + 阶段索引
- 详细 SOP、协议、模板下沉到 `references/` 子目录
- references 单文件超 100 行需添加 `## Contents` 目录
- references 引用只允许一层，禁止链式跳转
- 正文不出现版本号/迭代标签（时态中性）

### 工程红线（Worktree / 运行时产物）

1. **禁止 commit 仓库共享配置**：worktree 内 commit 必须排除 `release-please-config.json` / `.release-please-manifest.json` / `.claude-plugin/marketplace.json`
2. **禁止 auto-merge**：所有 worktree 分支只能由用户人工合并回 main，禁止主 Agent 自动 merge 或 push 到 origin/main
3. **禁止 bare 化 worktree**：遵循根 CLAUDE.md `git-worktree.md` 红线
4. **`.gitignore` 自检**：Phase 0 必须确认仓库 `.gitignore` 已忽略以下三项；缺失则经 `AskUserQuestion` 授权后追加，禁止静默写入
   - `.claude/slim-task.json`（语言偏好持久化配置）
   - `.claude/slim-task/`（Phase 5 审计落盘目录）
   - `.claude/worktrees/`（worktree 模式启用时必检）

### Phase 5 反作弊隔离

1. **审计 Agent 与实现 Agent 必须隔离 context**：Phase 5 派发的 scope-auditor / practice-auditor / engineering-auditor / fixer 子 Agent 的 prompt 严禁注入 Phase 4 实现 Agent 的对话历史、思考记录、自评结论
2. **审计 Agent 一律 `general-purpose` subagent_type 独立派发**：不复用 Phase 4 任何 Agent ID
3. **审计产物落盘可追溯**：`.claude/slim-task/audits/{task-slug}/{scope,practice,engineering}-audit.json`
4. **修复循环上限 3 次**：超过上限必须停下让用户人工介入，禁止无限自洗

### 用户检查点强制工具调用

1. **所有 Phase 检查点必须调用 `AskUserQuestion`**：禁止用纯文本提问（如"要不要继续 / 看起来如何 / 是否 OK"）作为检查点替代；自由文本回复不视为采纳
2. **检查点决策卡至少 3 选项**：「采纳进入下阶段」「修改后重审」「终止流程」
3. **Phase 6 双决策卡**：第一次决策卡确认 commit，commit 后立即第二次决策卡确认 push 与 PR；禁止合并为单次询问
4. **历史指令不构成本次授权**：用户在更早消息中的笼统指令（"提交推送拉 PR"、"全部弄完"）不能跳过 Phase 6 的两次 AskUserQuestion；违反即视为绕过用户授权

<!-- DEV-ONLY-END -->
