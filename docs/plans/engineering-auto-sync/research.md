# 工程化自动同步能力竞品调研

> 作用域：为 spec-autopilot 设计「代码变更后自动同步文档 + 自动审计历史测试」两大能力。
> 排除 `docs/reports/` 的自动刷新（历史报告永久快照，不纳入 drift 范围）。

## 1. 竞品横向对比

| 产品 / 方案 | 核心机制 | 触发时机 | 技术路线 | 可借鉴点 |
|-------------|----------|----------|----------|----------|
| **Swimm Auto-sync** | 代码片段 ↔ 文档绑定 (snippet anchor)，变更时做上下文/历史分析 | PR / push | 静态 anchor 追踪 + 置信度阈值，低置信度升级人工 | 「ownership 映射 + confidence gating」双层策略 |
| **Mintlify Autopilot / Workflows** | Agent 克隆仓库、按 prompt 自更新文档并开 PR | GitHub Action / 自定义触发 | LLM Agent + workflow 声明式编排 | 不自动合并，始终走 PR 让人工 review |
| **Claude Code SessionStart hook** | 会话启动时执行脚本，注入"文档漂移"上下文 | 每次新会话 | 本地 hook 脚本 | 与现有 `.claude/settings.json` hook 生态天然契合 |
| **Cursor rules / evo analyze** | 规则文件描述"AI 不应写成这样"，drift 扫描器对比实际代码 | IDE / PR | rule-as-code + 静态分析 | rule-based drift 比纯 LLM 便宜且稳定 |
| **semantic-release** | Conventional Commits → 版本号 + CHANGELOG | push to main | commit-analyzer + release-notes-generator 插件链 | 复用项目已有的 release-please 规范做 doc trigger |
| **ADR + arc42 自动化** | ADR 与代码同仓，PR 检查是否需新增/更新 ADR | pre-commit / CI | adr-tools CLI + LLM 审稿 | 架构变更才触发文档，缩小 drift 噪音面 |
| **Diffblue Cover** | RL + LLM 生成/维护 Java 单测；Test Asset Insights 识别低质量测试 | CI Agent | 强化学习 + 确定性执行 | "测试资产健康度"指标化，作为审计产物 |
| **Qodo Cover (CodiumAI)** | 分析覆盖率缺口，生成/修复回归测试，验证 pass & 覆盖增量 | GitHub Action / CLI | Meta TestGen-LLM + 自验证循环 | "生成 → 运行 → 验证 → 开 PR" 闭环模式 |
| **Stryker / Mutmut** | 注入变异体 (mutant)，survived 即弱测试/僵尸测试 | 定时 CI (昂贵) | 源码变异 + 覆盖率比对 | 定期跑一次即可暴露 obsolete 断言 |
| **Jest / Vitest obsolete snapshot** | 收集当前 `toMatchSnapshot` 调用反推 orphan 快照 | test 运行时 | 引用追溯 | 对 shell 测试：静态扫描 `@covers` 注释标识引用的 symbol/文件 |

## 2. 推荐方案（适配 spec-autopilot）

### 2.1 触发时机选型

采取**三层分级**，而非单一 hook：

| 层级 | 触发点 | 职责 | 理由 |
|------|--------|------|------|
| L1 轻量 | `.githooks/post-commit` (新建) | 计算受影响区 → 写 drift 报告到 `.claude/state/doc-drift.json`，**不阻塞** | commit 已落地，避免 pre-commit 阻塞带来的坏体验；本地反馈迅速 |
| L2 拦截 | 既有 `.githooks/pre-push` | 强一致校验：高置信 drift 或 orphan test 必须处理 | 复用已有的 dist freshness 最终防线 |
| L3 深度 | CI `ci.yml` + 定时 `ci-sweep.yml` | 跑 mutation / LLM 重写 / PR 评论 | 成本高的检查集中到 CI |

**不推荐** PostToolUse hook 同步触发：Claude Code 的 hook 是同步阻塞，LLM 重写会拖慢交互；它适合做轻量 drift **标记**而非执行。

### 2.2 文档同步机制（rule-first + AI-fallback）

借鉴 Swimm 的 snippet anchor + Mintlify 的 Workflow agent，形成**三段式**：

1. **Ownership 映射** (`.claude/docs-ownership.yaml`)
   ```
   plugins/spec-autopilot/skills/autopilot/        → plugins/spec-autopilot/SKILL.md
   plugins/spec-autopilot/lib/                     → plugins/spec-autopilot/README.md#architecture
   .githooks/ + Makefile + CI                      → CLAUDE.md#构建纪律
   ```
   post-commit 通过 git diff 计算命中范围。

2. **Drift 检测（启发式优先）**
   - 锚点：文档中用 `<!-- CODE-REF: path#symbol -->` 注释绑定代码坐标；
   - 静态扫描器（bash + ripgrep）验证锚点 symbol/文件是否仍存在；失配 → drift；
   - README 版本号表格比对 `marketplace.json`（项目已有能力，沿用）。

3. **AI 重写（仅 candidate，禁止自动合入）**
   - 置信度高（纯变量/函数改名）→ 生成 patch 到 `.claude/candidates/docs/<ts>.patch`；
   - 置信度低（架构/流程）→ 生成"待人工 review 摘要"到 candidate 目录；
   - **始终由人工 `git apply` + commit**，与 Mintlify "always open PR" 原则一致。

### 2.3 测试审计机制（分层启发式）

121 个 shell 文件 + 1698 断言的审计采用**静态 → 语义 → 变异**三级：

| 级别 | 方法 | 成本 | 产出 |
|------|------|------|------|
| S1 静态扫描 | 用 ripgrep 提取测试中引用的函数/文件路径/常量；与当前源码求差集 → orphan | 秒级 | `orphan-refs.json` |
| S2 语义标注 | 约定测试头部写 `# @covers: <module>::<symbol>` + `# @rationale: <why>`；scanner 校验覆盖目标仍存在、rationale 与最近 commit 主题的相似度 | 秒级 | `rationale-mismatch.json` |
| S3 变异抽样 | 对 `lib/` 下改动模块用 mutmut 风格脚本对 bash 函数做简单变异（替换 `==` 为 `!=`、删除关键 `exit 1`），观察是否有测试 fail；全存活 → obsolete | 分钟级，仅周 sweep | `surviving-mutants.json` |

**人工闭环（强约束）**：
- 三级产物合并到 `.claude/candidates/tests/audit-<ts>.md`；
- **禁止自动删除任何测试**；只生成三类标记：`CANDIDATE_REMOVE` / `CANDIDATE_UPDATE` / `CANDIDATE_KEEP`；
- 配套 `/autopilot-test-audit confirm <id>` 交互命令让人工逐条勾选，确认后才改仓库。

## 3. 与���有体系融合点

1. **Hook 挂载**：
   - 新建 `.githooks/post-commit`（非阻塞、异步快速扫描），不修改 `pre-commit`；
   - `pre-push` 增加一层"未 resolve 的高置信 drift > 0 则阻断"。
2. **新增 Skill**：
   - `spec-autopilot:autopilot-docs-sync`：执行 ownership 计算 + drift 检测 + candidate 生成；
   - `spec-autopilot:autopilot-test-audit`：S1/S2 扫描 + candidates 列表 + `confirm` 子命令；
   - 这两个 skill 本身**只读/只写 `.claude/candidates/`**，保持与业务 phase skill 的职责隔离。
3. **与 autopilot-learn (episodes) 协同**：
   - 审计命中的 orphan/rationale-mismatch 可直接落库为 `failure_pattern`，作为未来 Phase 4 测试设计的反例；
   - Episodes 积累后可训练阈值（例如 rationale 相似度下界），实现规则自学习。
4. **与 release-please 协同**：
   - post-release bot commit 自动携带 `docs-sync: skip` trailer，避免递归触发；
   - CHANGELOG 仍由 release-please 产出，docs-sync 仅管 README/SKILL/CLAUDE/流程图。

## 4. 实施优先级

- **P0（2 周内）**
  - 新建 `.claude/docs-ownership.yaml` + `<!-- CODE-REF -->` 锚点规范；
  - `post-commit` hook + `autopilot-docs-sync` skill（仅 S1 drift + candidate 输出，不接 LLM）；
  - Test audit S1 静态扫描 + `# @covers` 约定；
- **P1（4 周）**
  - `autopilot-test-audit` 的 `confirm` 交互命令 + pre-push 阻断；
  - AI 重写 fallback（置信度门槛，落 candidate 不自动 commit）；
  - 与 autopilot-learn 的 failure_pattern 打通；
- **P2（按需）**
  - 周 sweep CI 跑 S3 变异抽样；
  - `@rationale` 相似度阈值自学习；
  - Mintlify/Swimm 风格的仓库级文档健康度评分。

## 引用

- [Swimm Auto-sync 原理](https://swimm.io/blog/how-does-swimm-s-auto-sync-feature-work)
- [Mintlify Autopilot Blog](https://www.mintlify.com/blog/autopilot)
- [Mintlify: Auto-update documentation when code changes](https://www.mintlify.com/docs/guides/automate-agent)
- [Claude Code SessionStart Hooks 指南](https://medium.com/@CodeCoup/claude-code-session-hooks-make-every-session-start-smart-and-end-clean-e505e6914d45)
- [semantic-release 官方仓库](https://github.com/semantic-release/semantic-release)
- [ADR 自动化（GitHub + LLM）](https://medium.com/@iraj.hedayati/from-stale-docs-to-living-architecture-automating-adrs-with-github-llm-e80bb066b4b6)
- [Diffblue 下一代测试平台](https://www.diffblue.com/resources/announcing-the-next-generation-of-our-best-in-class-unit-test-generation-platform/)
- [Qodo Cover (CodiumAI) GitHub](https://github.com/qodo-ai/qodo-cover)
- [Stryker mutation testing 示例](https://github.com/peter-evans/mutation-testing)
- [Jest obsolete snapshot Issue #5005](https://github.com/jestjs/jest/issues/5005)
- [Vitest fail on obsolete snapshot Discussion #7882](https://github.com/vitest-dev/vitest/discussions/7882)
