# spec-autopilot Scripts 工程化重构蓝图

状态: Proposed

日期: 2026-03-18

适用范围: `plugins/spec-autopilot/`

目标读者: 负责实施重构的 Claude Code / 工程维护者

---

## 1. 执行摘要

当前 `scripts/` 目录的真实问题，不是“文件必须全部按语言拆目录”，而是“运行时入口、开发工具、历史遗留物、服务端源码、发布构建逻辑”混在一个平铺目录里，导致维护边界不清、构建纯净度脆弱、文档与测试迁移成本被低估。

本方案的核心判断如下：

1. `dist/scripts/` 的平铺结构是运行时契约，不能直接推翻。
2. 源码重构必须优先按“职责边界”分层，而不是机械按语言分层。
3. 第一优先级不是移动所有文件，而是先建立可验证的发布清单、质量门禁、兼容迁移策略。
4. `autopilot-server.ts` 可以从 `scripts/` 中分离，但必须通过双路径兼容和构建回填保证源码态与 dist 态同时可运行。
5. deprecated 脚本不能一步硬删，必须先完成测试、文档、技能引用迁移，再进入兼容淘汰期。

一句话总结：

**先清“边界”和“构建”，再动“物理位置”；先做兼容迁移，再做删除清理。**

---

## 2. 当前基线（2026-03-18 实测）

以当前仓库为准，重构实施前应以此基线校验：

- `plugins/spec-autopilot/scripts/` 共 51 个文件
- 其中:
  - 42 个 Shell 脚本
  - 4 个 Python 文件
  - 1 个 TypeScript 服务端
  - 1 个 JavaScript 调试脚本
  - 3 个 Bun/TS 配置文件
- `plugins/spec-autopilot/tests/` 下共有 76 个 `test_*.sh`
- `dist/spec-autopilot/` 当前约 1560 KB，103 个文件
- `docs/`、`skills/`、`tests/`、`README*` 中对 `autopilot-server.ts` 的直接引用较多
- `docs/`、`skills/`、`tests/`、`README*` 中对 deprecated 脚本也仍有大量历史引用

这意味着任何“移动文件”或“删除脚本”的操作，都不是单点改动，而是**源码、构建、测试、文档、技能说明、发布包**的联动改动。

---

## 3. 设计目标

本次重构必须同时满足以下目标：

### 3.1 工程目标

- 让 `scripts/` 只承载运行时契约面
- 让构建逻辑从“排除式复制”升级为“显式清单式复制”
- 建立 Shell / Python / TypeScript 的最小可行质量门禁
- 将开发辅助工具与运行时脚本解耦
- 为后续继续拆分 GUI server 留出明确迁移路径

### 3.2 稳定性目标

- 不破坏 `hooks.json` 既有命令路径契约
- 不破坏 `dist/spec-autopilot/` 的运行时布局
- 不破坏 pre-commit、Makefile、CI 的基本使用方式
- 不因删除 deprecated 文件而立刻打爆历史测试和说明文档

### 3.3 组织目标

- 让 Claude 按阶段可实施
- 每个阶段都有明确验收标准
- 任一阶段失败都可以局部回滚，而不需要全盘撤销

---

## 4. 非目标

以下内容不在本轮重构范围内：

- 不引入 monorepo 工具（如 Nx、Turborepo、pnpm workspace）
- 不重写现有 bash 测试框架
- 不把 Python 运行时库整体迁移到新目录
- 不批量重写 `docs/reports/` 和 `docs/archive/` 中的历史快照路径
- 不在本轮引入 Docker、Coverage 平台或复杂发布系统

这些事情不是做不到，而是**当前收益不如成本**。

---

## 5. 不可违反的运行时契约

实施过程中，以下契约必须始终成立：

1. `hooks/hooks.json` 中的 hook 路径仍然使用 `${CLAUDE_PLUGIN_ROOT}/scripts/<name>.sh`
2. 发布产物中的运行时脚本仍位于 `dist/spec-autopilot/scripts/`
3. Shell 脚本通过 `$SCRIPT_DIR/_*.py` 调用 Python helper 的行为不能被打断
4. GUI 启动脚本在源码态和 dist 态都必须能找到可执行的 server 入口
5. `dist/` 中不得混入 `tests/`、`docs/`、`node_modules/`、纯开发调试资产

设计上要接受一个现实：

**源码目录可以演进，但运行时表面契约必须稳定。**

---

## 6. 目标架构

### 6.1 最终职责边界

```text
plugins/spec-autopilot/
├── scripts/                       # 运行时契约面: hooks + runtime helpers + runtime entrypoints
│   ├── _common.sh
│   ├── _hook_preamble.sh
│   ├── _config_validator.py
│   ├── _envelope_parser.py
│   ├── _constraint_loader.py
│   ├── _post_task_validator.py
│   ├── guard-no-verify.sh
│   ├── post-task-validator.sh
│   ├── unified-write-edit-check.sh
│   ├── start-gui-server.sh
│   └── [其余活跃运行时脚本]
│
├── server/                        # GUI server 源码与其工具链
│   ├── autopilot-server.ts
│   ├── package.json
│   ├── tsconfig.json
│   └── bun.lock
│
├── tools/                         # 仓库开发/发布工具
│   ├── build-dist.sh
│   ├── bump-version.sh
│   └── mock-event-emitter.js
│
├── tests/                         # 测试
├── gui/                           # 前端
├── hooks/                         # hook 配置
├── skills/                        # skills
└── docs/                          # 文档
```

### 6.2 关于 `scripts/` 的关键设计决策

`scripts/` 不再追求“完全纯语言分层”，而是定义为：

**面向 Claude 运行时与发布产物的契约面。**

这意味着：

- 活跃 hook 脚本应保留在这里
- 被 hook 直接依赖的 Python helper 应保留在这里
- 必须在 dist 中直接出现的入口文件应保留在这里，或可由构建阶段稳定回填
- 构建工具、发布工具、mock 调试工具不应继续放在这里

这比“按语言搬家”更符合当前项目的真实约束。

---

## 7. 核心设计原则

### 7.1 原则一：先建立清单，再搬文件

在没有发布清单的情况下移动文件，等于把风险交给 `cp` 和运气。

因此第一步必须先把 `dist/scripts/` 的来源从：

- “复制整个 `scripts/`，再手工排除少数文件”

升级为：

- “按显式 allowlist 或 manifest 复制运行时资产”

### 7.2 原则二：兼容迁移优先于一次性清理

只要某个文件仍被测试、README、技能文档、外部使用说明引用，就不应直接硬删。

正确顺序是：

1. 先迁移 live reference
2. 再保留一段兼容窗口
3. 最后删除历史 wrapper 或 tombstone

### 7.3 原则三：历史快照不追求路径实时正确

`docs/reports/` 和 `docs/archive/` 是历史审计材料，不应为了“路径整洁”大面积改写。

可接受做法：

- 保留历史文本原样
- 在 live docs 中声明“旧报告中的 `scripts/autopilot-server.ts` 为历史路径”

### 7.4 原则四：质量门禁必须先保证可执行，再追求严格

Lint / format / typecheck 的引入必须遵循：

1. 先让命令可运行
2. 再让 CI 能观察到结果
3. 最后逐步收紧为 hard gate

不要一上来把全仓库变成红海。

---

## 8. 分阶段实施方案

## Phase 0: 基线冻结与清单化

### 目标

建立“什么是运行时必须文件”的单一事实源，停止继续靠排除名单构建 dist。

### 动作

1. 在 `plugins/spec-autopilot/` 新增运行时发布清单，例如：
   - `runtime-manifest.txt`
   - 或 `scripts/.dist-include`
2. 清单必须覆盖：
   - 所有 hooks 直接引用的 `.sh`
   - 所有运行时依赖的 `_*.py`
   - `start-gui-server.sh`
   - `autopilot-server.ts` 或其构建回填目标
3. 为 `build-dist.sh` 增加 manifest 校验：
   - 清单中的每个文件都存在
   - `hooks.json` 中引用的脚本都在清单里
   - 发布后 `dist/scripts/` 中不出现清单外文件
4. 为 `tests/` 新增一个“manifest 与 hooks 一致性测试”

### 产出

- 构建复制逻辑从黑盒变成显式声明
- 后续移动文件时有稳定护栏

### 验收标准

- `make build` 仅依赖清单复制运行时文件
- `dist/scripts/` 中不再出现 `mock-event-emitter.js`
- `dist/scripts/` 中不再出现纯开发配置文件，除非它们是运行时必须

---

## Phase 1: 先拆开发工具，再碰运行时入口

### 目标

把明显不属于运行时契约面的文件搬出 `scripts/`，先把“最脏的一层”清掉。

### 应移动文件

从 `plugins/spec-autopilot/scripts/` 迁出到 `plugins/spec-autopilot/tools/`：

- `build-dist.sh`
- `bump-version.sh`
- `mock-event-emitter.js`

### 级联更新

- `Makefile`
- `.githooks/pre-commit`
- 相关 README / 操作文档
- 相关测试用例

### 设计说明

这是低风险高收益步骤，因为：

- 这些文件不是 hooks.json 的运行时入口
- 它们不需要出现在发布包里
- 它们对“scripts 目录看起来像 runtime surface”帮助最大

### 验收标准

- `scripts/` 中不再混入构建/发版/调试工具
- `make build`、pre-commit、CI 全部改为引用 `tools/build-dist.sh`
- `dist/scripts/` 纯净度明显提升

---

## Phase 2: 建立最小工程化底座

### 目标

引入最小但可持续的工程化工具链。

### 建议新增文件

- 仓库根 `.editorconfig`
- 仓库根 `.shellcheckrc`
- `plugins/spec-autopilot/pyproject.toml`

### 建议新增命令

- `make lint`
- `make format`
- `make typecheck`
- `make ci`

### 关键约束

1. `Makefile` 中 GUI 测试必须使用真实命令，不允许 `|| true` 吞失败
2. TypeScript typecheck 必须分别覆盖：
   - `gui/`
   - `server/` 或 server 源码所在位置
3. pre-commit 中的 staged lint 应是附加快检，不能替代全量测试

### 实施细节

#### Shell

- 先接入 `shellcheck` + `shfmt`
- 初期允许 CI 观察告警，但不要立即全量阻断

#### Python

- 使用 `ruff` + `mypy`
- 范围仅限 4 个运行时 Python helper

#### TypeScript

- 前端使用现有 `vite.config.ts` 为主配置
- Vitest 配置必须复用 Vite 配置，不能绕开 `__PLUGIN_VERSION__` 等现有 define
- 不建议写一个与 `vite.config.ts` 完全脱钩的平行测试配置

### 验收标准

- `make lint`、`make format`、`make typecheck` 本地可执行
- CI 中新增独立的 `lint` / `typecheck` job
- 新增门禁不破坏原有 `test-hooks` job

---

## Phase 3: GUI Server 正式分层

### 目标

把 GUI server 从 `scripts/` 的噪音里分离出来，但不破坏源码态和 dist 态运行。

### 目标布局

迁移到 `plugins/spec-autopilot/server/`：

- `autopilot-server.ts`
- `package.json`
- `tsconfig.json`
- `bun.lock`

### 兼容策略

`scripts/start-gui-server.sh` 必须支持双路径解析：

1. 先找 `$SCRIPT_DIR/autopilot-server.ts`
2. 若不存在，再找 `$SCRIPT_DIR/../server/autopilot-server.ts`
3. 两者都不存在才报错

这样可以保证：

- 旧源码态仍可工作
- 新源码态可工作
- dist 态因为构建回填到 `dist/scripts/autopilot-server.ts` 也可工作

### 构建策略

`tools/build-dist.sh` 必须：

1. 从 `server/autopilot-server.ts` 复制 canonical server 到 `dist/scripts/`
2. 继续保持 `dist/scripts/` 平铺
3. 验证 `start-gui-server.sh` 在 dist 环境可找到 server

### 依赖策略

`server/package.json` 至少应包含：

- `@types/bun`
- `@types/node`
- `typescript`

不能只保留 `@types/bun`，因为 server 代码同时使用 Node 模块和 `process`

### 测试策略

以下内容必须一并更新：

- server 相关 bash 测试
- 直接引用 `scripts/autopilot-server.ts` 的 live docs
- troubleshooting / getting-started / README 等运行说明

以下内容不强制改动：

- `docs/reports/`
- `docs/archive/`

### 验收标准

- 源码态可通过 `start-gui-server.sh` 成功启动
- dist 态可通过 `start-gui-server.sh` 成功启动
- server typecheck 通过
- live docs 中不再把旧路径作为主路径

---

## Phase 4: deprecated 脚本进入兼容淘汰期

### 目标

把 deprecated 脚本从“混在主目录的真实实现”变为“受控兼容资产”。

### 涉及脚本

- `anti-rationalization-check.sh`
- `assertion-quality-check.sh`
- `banned-patterns-check.sh`
- `write-edit-constraint-check.sh`
- `code-constraint-check.sh`

### 正确做法

分两步：

#### 第一步：迁移 live references

先更新：

- `tests/`
- `README.md` / `README.zh.md`
- `skills/` 下仍面向当前用户的参考文档
- `docs/architecture/`、`docs/getting-started/`、`docs/operations/` 等 live docs

#### 第二步：进入兼容窗口

有两种可接受方案，二选一：

1. 保留这些脚本一个小版本周期，并在头部明确 tombstone/deprecated 注释
2. 将原实现迁出到 `legacy/`，在 `scripts/` 中保留轻量 wrapper 或明确错误提示

不建议直接硬删，原因是：

- 现有测试仍直接调用其中部分脚本
- 历史知识库中仍大量出现这些名称
- 一次性删除很容易把“可追溯性”也删掉

### 最终删除条件

只有满足以下条件才允许物理删除：

1. `tests/` 中不再直接调用旧脚本
2. live docs 中不再将其作为主入口
3. 所有当前运行链路都已切到统一入口
4. 至少经历一个明确版本周期的兼容说明

### 验收标准

- deprecated 资产不再被误认为活跃实现
- 维护者不会因目录平铺误判入口脚本
- 不因删除造成测试与知识文档大面积断裂

---

## 9. 构建与发布设计

## 9.1 `build-dist.sh` 必须从排除式转为 allowlist

现有“复制整个 `scripts/` 再排除少数文件”的方式会不断泄漏新文件。

应改为：

1. 读取 runtime manifest
2. 逐项复制 manifest 中的文件到 `dist/scripts/`
3. 对 hooks.json 执行存在性校验
4. 对 dist 纯净度执行显式校验

## 9.2 构建校验优先级

优先级顺序应为：

1. 运行时文件齐全
2. hooks 引用有效
3. 不存在不应发布的开发资产
4. GUI 构建可回退
5. 大小/校验和等附加信号

也就是说，先做“正确”，再做“精致”。

## 9.3 Checksum 与大小门禁

可保留以下附加校验：

- `.checksums.sha256`
- dist 大小上限

但它们应在 allowlist 构建稳定后再加，不应代替发布清单本身。

---

## 10. CI / Pre-commit 设计

## 10.1 CI Job 拆分建议

建议拆为四类：

1. `lint`
2. `typecheck`
3. `test-hooks`
4. `build-dist`

其中：

- `lint` 先在 Linux 跑即可
- `typecheck` 先在 Linux 跑即可
- `test-hooks` 保持 Linux + macOS matrix
- `build-dist` 至少在 Linux 跑一遍，验证 manifest 与产物纯净度

## 10.2 Pre-commit 设计原则

pre-commit 中应保留三层逻辑：

1. 全量测试与构建
2. 文档/版本同步
3. staged 快速静态检查

其中 staged lint 需要：

- 仅做快反馈
- 工具缺失时跳过
- 不能覆盖掉全量测试的失败

## 10.3 文件名健壮性

所有基于 `find`、`git diff --cached` 的管道，优先改成：

- `-print0`
- `git diff -z`
- `xargs -0`

以避免空格路径导致潜在故障。

---

## 11. 文档迁移策略

文档分三类处理：

### 11.1 必须更新

- `README.md`
- `README.zh.md`
- `docs/getting-started/*`
- `docs/operations/*`
- `docs/architecture/*`
- `skills/` 下仍面向当前用户的参考材料

### 11.2 可补注释，不必全文重写

- `docs/migration/*`

### 11.3 保持历史快照

- `docs/reports/**`
- `docs/archive/**`

建议在 live docs 中增加一句统一说明：

> 历史报告中出现的 `scripts/autopilot-server.ts`、deprecated hook 名称为当时版本路径，不代表当前主入口。

---

## 12. Claude 实施纪律

这份方案是写给 Claude 执行的，因此实现时必须遵守以下纪律：

1. 不要一次性做完所有 Phase
2. 每个 Phase 独立提交、独立测试、独立验收
3. 未完成 live reference 迁移前，不要删除旧入口
4. 修改构建逻辑时，必须先补测试再改复制逻辑
5. 修改 server 路径时，必须同时验证源码态和 dist 态
6. 不要为了让测试通过而重写历史报告
7. 不要引入 workspace、Docker、全新测试框架等额外工程复杂度

---

## 13. 推荐实施顺序

建议 Claude 严格按以下顺序执行：

1. Phase 0: 建立 runtime manifest 与构建测试
2. Phase 1: 把 dev-only 工具移出 `scripts/`
3. Phase 2: 引入 lint / format / typecheck / CI
4. Phase 3: 分离 GUI server 到 `server/`
5. Phase 4: deprecated 脚本进入兼容淘汰期

不要跳步。

---

## 14. 完成定义（Definition of Done）

只有同时满足以下条件，才算本轮重构完成：

1. `scripts/` 不再混入 build/release/mock 工具
2. `dist/scripts/` 由 manifest 驱动构建
3. `dist/scripts/` 中不再泄漏调试脚本和纯开发配置
4. Shell / Python / TypeScript 均有可执行的最小质量门禁
5. GUI server 若已迁移，则源码态与 dist 态都能启动
6. deprecated 脚本不再作为“活跃主路径”出现
7. live docs 已更新，历史报告保持快照性质

---

## 15. 建议 Claude 的执行提示词

可以把下面这段作为 Claude 的任务起点：

```text
请按 docs/roadmap/2026-03-18-scripts-engineering-refactor-blueprint.md 执行，不要跨 Phase 同时施工。

要求：
1. 先完成 Phase 0，再等待我确认是否进入下一阶段。
2. 每个 Phase 结束时输出：
   - 修改文件
   - 新增/更新测试
   - 验证命令
   - 风险与回滚点
3. 不要删除 deprecated 脚本，除非文档中对应 Phase 明确允许。
4. 任何涉及 GUI server 路径的改动，都必须同时验证源码态与 dist 态。
5. 不要改写 docs/reports/ 与 docs/archive/ 的历史内容。
```

---

## 16. 最终结论

这次重构的正确姿势不是“把 `scripts/` 变成好看的树”，而是：

- 把运行时契约面定义清楚
- 把开发工具和历史遗留隔离出去
- 把构建过程变成可验证的显式清单
- 用兼容迁移而不是硬切删除完成演进

如果按本蓝图执行，`scripts/` 会从“混乱目录”变成“稳定运行时表面”，而不会在追求整洁的过程中破坏插件的真实可用性。
