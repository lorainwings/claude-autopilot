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
├── .github/workflows/           # CI: test-spec-autopilot / test-parallel-harness / test-daily-report / release-please
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
- 查看 CI 定义 → `.github/workflows/`
- 查看版本清单 → `.release-please-manifest.json`

## Git Worktree 安全规范

1. **绝对禁止将任何工作树修改为 bare 仓库**: 包括但不限于 `git config core.bare true`、`git clone --bare` 替换、以及任何等效操作
2. **保护主仓库与所有关联 worktree**: 多 worktree 环境依赖正常的工作树结构运作，将任何一个改为 bare 会破坏整个 worktree 链路，导致所有关联工作树不可用且恢复代价极高
3. **遇到相关建议时立即拒绝**: 若任何工具、文档或 AI 建议将工作树转为 bare，应拒绝并提醒风险
4. **Worktree 用途**: 主仓库保持 `main` 分支，worktree 用于插件独立开发（如 `release/parallel-harness` 分支）
5. **Worktree 目录隔离**: worktree 产生的目录已在 `.gitignore` 中排除（`.worktrees/`、`.parallel-harness`），禁止手动将这些目录加入版本控制

## 构建纪律

### Makefile 作为唯一入口

所有构建、测试、lint 操作**必须**通过 Makefile target 执行:

| 操作 | spec-autopilot | parallel-harness | daily-report |
|------|---------------|-----------------|-------------|
| 初始化 | `make setup` | `make ph-setup` | — |
| 测试 | `make test` | `make ph-test` | — |
| 构建 dist | `make build` | `make ph-build` | `make dr-build` |
| Lint | `make lint` | `make ph-lint` | `make dr-lint` |
| 类型检查 | `make typecheck` | `make ph-typecheck` | — |
| 格式检查 | `make format` | — | — |
| 完整 CI | `make ci` | `make ph-ci` | `make dr-ci` |

### dist 目录管理

1. **dist/ 是 git tracked 的构建产物**: 供 Claude Code 插件市场直接安装使用
2. **禁止手动修改 dist/ 下任何文件**: 所有变更在 `plugins/<name>/` 源码中进行
3. **构建脚本自动生成**: 每个插件的 `tools/build-dist.sh` 负责从源码生成 dist
4. **pre-commit 自动重建**: 当 `plugins/<name>/` 有实质性变更时，pre-commit hook 自动执行构建并 `git add dist/<name>/`
5. **CI 验证 freshness**: CI 会对比 dist 目录，确保提交的 dist 与 fresh build 一致
6. **测试文件永不进入 dist**: `tests/` 目录不在构建白名单中

## 版本管理与发版纪律

### release-please (主要方式)

1. **自动化流程**: PR 合入 `main` → release-please 自动创建 Release PR → 合并即发版
2. **Conventional Commits 驱动**: commit message 遵循 `feat:` / `fix:` / `refactor:` / `perf:` 等前缀，release-please 据此计算版本号和生成 CHANGELOG
3. **多包配置**: `release-please-config.json` 定义三个插件的发版规则，每个插件独立版本
4. **post-release 自动化**: CI 发版后自动更新 dist/、README badge、marketplace.json 版本号

### 手动 fallback

- `tools/release.sh` (交互式向导) 仅在 release-please 不可用时使用
- 预览模式: `make release-dry`

### 版本一致性铁律

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

### Conventional Commits 规范

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

## 代码质量标准

### Lint 工具链

| 语言 | 工具 | 配置 |
|------|------|------|
| Shell | shellcheck + shfmt | `.shellcheckrc` (全局); shfmt: `-i 2 -ci` |
| Python | ruff + mypy | `plugins/spec-autopilot/pyproject.toml`; mypy target 3.9 |
| TypeScript | `tsc --noEmit` (strict mode) | 各插件 `tsconfig.json` |

**本项目不使用 ESLint 和 Prettier。禁止引入这两个工具或其配置文件。**

### TypeScript 配置约束

1. **禁止 `"types": ["bun-types"]`**: 会导致 `Cannot find type definition file for 'bun-types'` 错误
2. **Bun 类型由 `@types/bun` 提供**: TypeScript 自动发现，`tsconfig.json` 中无需显式指定
3. **若必须显式声明**: 正确写法为 `"types": ["bun"]`（不含 `@types/` 前缀）

### 编辑器规范

遵循 `.editorconfig`: UTF-8 编码，LF 换行。Shell/TS/JS/JSON/YAML/MD: 2 空格缩进；Python: 4 空格缩进；Makefile: Tab 缩进。

## 测试纪律

### 通用规则 (跨插件)

1. **每个新功能至少 3 个测试用例**: 正常路径 + 边界条件 + 错误路径
2. **禁止弱化已有断言**: 不得将失败断言改为通过来规避问题
3. **禁止删除已有测试**: 删除必须在 commit message 中说明理由
4. **禁止跳过测试**: 不得注释或条件跳过已有测试
5. **测试失败时修复实现**: 定位具体失败断言，修复实现代码而非测试逻辑

### 插件测试命令

| 插件 | 命令 | 框架 | 基线 |
|------|------|------|------|
| spec-autopilot | `make test` | Bash 测试套件 | 76 文件, 692+ 断言 |
| parallel-harness | `make ph-test` | `bun test` | 219 tests, 499 assertions |

### 推送前检查清单

`git push` 前必须确保:

1. 完整测试套件通过 (`make test` / `make ph-test`)
2. 类型检查通过 (`make typecheck` / `make ph-typecheck`)
3. Lint 通过 (`make lint` / `make ph-lint`)
4. dist 构建成功且已提交 (`make build` / `make ph-build`)

## CI/CD 规范

### 四条 Pipeline

| Workflow | 触发条件 | Job 链 |
|----------|---------|--------|
| `test-spec-autopilot.yml` | `plugins/spec-autopilot/**` 变更 | release-discipline → test-hooks → lint → typecheck → build-dist |
| `test-parallel-harness.yml` | `plugins/parallel-harness/**` 变更 | release-discipline → ph-typecheck → ph-test → ph-lint → ph-build |
| `test-daily-report.yml` | `plugins/daily-report/**` 变更 | release-discipline → dr-lint → dr-build |
| `release-please.yml` | push to `main` | release-please → post-release (dist 构建 + 版本同步) |

### CI 关键行为

1. **路径过滤**: 每条 pipeline 仅在对应插件目录有变更时触发
2. **release-please 分支 bypass**: pre-commit hook 检测到 `release-please--*` 分支自动跳过
3. **bot commit bypass**: CI discipline 检查自动跳过 release-please 和 post-release bot 提交
4. **dist freshness 验证**: CI 构建后对比 tracked + untracked files，不一致则失败
5. **跨平台测试**: 测试在 `ubuntu-latest` + `macos-latest` 上并行运行

## 分支策略

| 分支模式 | 用途 | 示例 |
|---------|------|------|
| `main` | 默认分支，稳定基线 | — |
| `feature/*` | 功能开发 | `feature/cost-aware-routing` |
| `fix/*` | Bug 修复 | `fix/worktree-default-enabled` |
| `release/*` | 独立开发分支（用于 worktree） | `release/parallel-harness` |
| `release-please--*` | release-please 自动管理，禁止手动干预 | `release-please--branches--main` |

## Git Hooks 规范

### 基础设施

- 使用 `.githooks/` 目录（非 Husky），通过 `core.hooksPath` 配置
- 初始化: `make setup` 或 `bash scripts/setup-hooks.sh`
- pre-commit hook 包含 hooksPath 自保护机制（检测到 `/dev/null` 自动恢复）

### 严禁 hooksPath 破坏

- **严禁 `git config core.hooksPath /dev/null`**: 任何脚本不得对主仓库执行此操作
- 临时仓库需跳过 hook 时使用 `git commit --no-verify`，且必须以 `git -C $TMPDIR` 隔离

### Pre-commit 执行流程

1. hooksPath 自保护检查
2. release-please 分支 bypass
3. spec-autopilot 变更时: 全量测试 → 测试覆盖检查 → staged lint → 版本一致性校验 → 自动重建 dist
4. parallel-harness 变更时: 自动重建 dist
5. daily-report 变更时: 自动重建 dist

## 文档规范

### 双语要求

1. 英文为默认版本 (`.md`)，中文为伴随版本 (`.zh.md`)
2. 两个版本顶部必须有语言切换链接
3. 共享内容（代码块、图表、表格）在两个版本中必须一致
4. 新增文档必须同时提供双语版本

### CLAUDE.md 特殊规范

- CLAUDE.md 使用中文撰写
- 子插件 CLAUDE.md 使用 `<!-- DEV-ONLY-BEGIN -->` / `<!-- DEV-ONLY-END -->` 标记区分开发者规则与发布规则
- `build-dist.sh` 在构建时剥离 DEV-ONLY 块，dist 中的 CLAUDE.md 仅含发布规则
- 根目录 CLAUDE.md 不使用 DEV-ONLY 标记（全部为全局规则，始终生效）

## 跨插件协作约束

### 隔离性

1. **源码隔离**: 每个插件在 `plugins/<name>/` 下完全自包含，禁止跨插件 import
2. **依赖隔离**: 每个插件有独立的 `package.json` / `bun.lock`，禁止共享 `node_modules`
3. **版本独立**: 两个插件各自独立版本号，独立 CHANGELOG
4. **CI 独立**: 各插件有独立的 CI workflow，按路径过滤触发

### 共享层

以下资源属于仓库级共享，修改需考虑对所有插件的影响:

1. **`.claude-plugin/marketplace.json`**: 市场注册表，版本号由自动化维护
2. **`.githooks/pre-commit`**: 统一 pre-commit hook，包含所有插件的检查逻辑
3. **`Makefile`**: 统一构建入口
4. **`scripts/`**: 仓库级脚本（hooks setup、release discipline 检查）
5. **`tools/release.sh`**: 跨插件发版工具
6. **根目录 `README.md`**: 包含插件版本总表

### 新增插件清单

若需新增第三个插件，必须完成以下步骤:

1. 在 `plugins/<new-name>/` 创建完整插件结构（含 CLAUDE.md、`.claude-plugin/plugin.json`）
2. 在 `.claude-plugin/marketplace.json` 注册
3. 在 `release-please-config.json` 和 `.release-please-manifest.json` 添加包配置
4. 在 `Makefile` 添加对应 target
5. 在 `.github/workflows/` 添加独立 CI workflow
6. 在 `.githooks/pre-commit` 添加对应的 dist rebuild 逻辑
7. 在根目录 `README.md` / `README.zh.md` 插件表格中添加条目
8. 在 `.gitignore` 确保 `!dist/<new-name>/` 被跟踪

## 绝对禁止清单

以下操作在任何情况下均被禁止，AI Agent 遇到相关建议时必须拒绝:

1. **禁止将工作树改为 bare 仓库** — 破坏整个 worktree 链路
2. **禁止手动修改 dist/ 下文件** — 由构建脚本自动生成
3. **禁止散弹式修改版本号** — 由 release-please 或 release.sh 统一管理
4. **禁止引入 ESLint / Prettier** — 项目不使用这些工具
5. **禁止 `git config core.hooksPath /dev/null`** — 破坏 hook 保护链
6. **禁止跨插件 import** — 插件间完全隔离
7. **禁止跳过测试套件直接推送** — 推送前必须完整测试通过
8. **禁止手动干预 release-please 分支** — 由自动化管理
