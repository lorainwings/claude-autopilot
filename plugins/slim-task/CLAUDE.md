# slim-task Plugin CLAUDE.md

> 此文件为 slim-task 插件的工程法则。
> 所有 AI Agent 在执行期间必须遵守。
> 版本: 0.8.1 <!-- x-release-please-version -->

## 插件定位

纯 Skill 型插件，无 TypeScript runtime、无 hooks。
提供 7 阶段结构化 SOP（Phase 0-6），采用主检子执模式 + DAG 最大化并行 + Phase 5 独立审计盲审，解决 AI 任务执行的 8 个常见问题。

## 核心约束

1. **主检子执**: 主 Agent 只做检查/决策/派发/验证，子 Agent 做实际编码与质量审计
2. **影响范围即合约**: 禁止修改 Phase 2 审批的影响范围表之外的文件
3. **DAG 无上限并行**: 同层无依赖任务全部并行派发，不限数量
4. **审批点前置收敛**: 人工决策集中在 Phase 1（需求）、Phase 2（方案+DAG）、Phase 6（commit+push）三处关键 gate；Phase 3-5 执行段默认自动推进，仅异常暂停；`--interactive` 模式恢复每阶段检查点
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
│   └── SKILL.md                  # 核心 SOP 指令（自包含编排器）
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

- 编排器型 SKILL.md 采用**自包含模式**：所有 Phase 详情、检查点协议、子 Agent 模板、审计协议必须**就近写在主文件中**，禁止下沉到 `references/`
- 选择自包含的根因：references 子文件不会被 Claude 自动加载，导致执行时丢失关键约束（"就近约束失效"反模式，已在实战中观察到效果回退）
- 行数控制在 500 行以内（官方硬限）；编排器自包含场景下 250-450 行为合理区间
- 高频执行细节（每 Phase 都用的检查点协议、护栏、模板）优先就近放主文件
- 仅低频背景资料（如平台工具清单、迁移历史）可放 `references/`
- 时态中性：正文不出现版本号/迭代标签

### 工程红线（Worktree / 运行时产物）

1. **禁止 commit 仓库共享配置**：worktree 内 commit 必须排除 `release-please-config.json` / `.release-please-manifest.json` / `.claude-plugin/marketplace.json`
2. **禁止 auto-merge**：所有 worktree 分支只能由用户人工合并回 main，禁止主 Agent 自动 merge 或 push 到 origin/main
3. **禁止 bare 化 worktree**：遵循根 CLAUDE.md `git-worktree.md` 红线
4. **`.gitignore` 自检**：Phase 0 首次运行必检前两项；缺失则经 `AskUserQuestion` 授权后追加，禁止静默写入
   - `.claude/slim-task.json`（语言偏好持久化配置）
   - `.claude/slim-task/`（Phase 5 审计落盘目录）
   - `.claude/worktrees/`（仅 `--worktree` 模式必检）
5. **分支命名强制校验**：Phase 0 前置校验当前分支名匹配 `^(feat|fix|refactor|docs|chore|test|perf)/[a-z0-9-]+$`（代码未写时改名零成本），Phase 6 commit 前再复核，不合规则阻断
6. **BASE_REF 记录与再验证**：Phase 0 将基础分支写入 `.claude/slim-task.json` 的 `baseRef`；Phase 6 push 前须再验证该分支仍存在（防中途被删/改名）
7. **副产物 commit 与运行时产物隔离**：Phase 6 staging 必须包含 `docs/tasks/*.md`、三维审计证据 `.claude/slim-task/audits/{task-slug}/*.json`、`.gitignore` 增量行；必须排除运行时产物 `.claude/slim-task/checkpoints/`、`.claude/worktrees/`（属断点续跑临时态，不入库）
8. **断点续跑落盘**：执行段（Phase 3-5）每个 Phase 转换/每层完成/每轮修复/每次异常暂停前落盘 checkpoint 到 `.claude/slim-task/checkpoints/`，会话中断后可恢复；Phase 6 commit 成功后清理

### Phase 5 反作弊隔离

1. **审计 Agent 与实现 Agent 必须隔离 context**：Phase 5 派发的 scope-auditor / practice-auditor / engineering-auditor / fixer 子 Agent 的 prompt 严禁注入 Phase 4 实现 Agent 的对话历史、思考记录、自评结论
2. **审计 Agent 一律 `general-purpose` subagent_type 独立派发**：不复用 Phase 4 任何 Agent ID
3. **审计产物落盘可追溯**：`.claude/slim-task/audits/{task-slug}/{scope,practice,engineering}-audit.json`
4. **修复循环上限 3 次**：超过上限必须停下让用户人工介入，禁止无限自洗
5. **注入审计的 diff 必须消毒**：用 `git diff --unified=0 --no-ext-diff --ignore-all-space` 剥离上下文、commit message、实现痕迹，防盲审隔离被泄漏破坏
6. **文件边界硬校验**：实现 Agent 经 schema 强制汇报 `modified_files`，与 Phase 2 影响范围表白名单实时比对，越界即拦截（不依赖事后审计才发现）

### 用户检查点强制工具调用

1. **审批 gate 必须调用 `AskUserQuestion`**：仅 Phase 1 / Phase 2 / Phase 6 三处审批 gate 强制调用，禁止纯文本提问替代；自由文本回复不视为采纳。Phase 0/3/4/5 为自动 transition，默认不询问用户（`--interactive` 模式除外）
2. **审批 gate 决策卡至少 3 选项**：「采纳进入下阶段」「修改后重审」「终止流程」
3. **Phase 6 双决策卡**：第一次决策卡确认 commit，commit 后立即第二次决策卡确认 push 与 PR；禁止合并为单次询问
4. **历史指令不构成本次授权**：用户在更早消息中的笼统指令（"提交推送拉 PR"、"全部弄完"）不能跳过 Phase 6 的两次 AskUserQuestion；违反即视为绕过用户授权
5. **执行段自动推进不豁免质量约束**：Phase 3-5 免去用户**确认动作**，但三维盲审、影响范围合约、修复循环上限等质量约束全部保留；`--interactive` 开关仅影响是否询问用户，不影响质量门

<!-- DEV-ONLY-END -->
