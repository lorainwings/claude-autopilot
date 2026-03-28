# spec-autopilot 完整执行提示词

> 日期：2026-03-19
> 目的：这是一份可直接交给 Claude 的完整执行提示词，用于修复当前 `spec-autopilot` 插件。
> 使用方式：直接复制 `## 最终提示词` 下的全部内容，原样交给 Claude。

## 背景说明

当前仓库不是单插件仓库，而是一个插件市场仓库：

- 市场名称：`lorainwings-plugins`
- 当前主插件：`spec-autopilot`
- 后续会新增新插件，但本提示词只针对 `spec-autopilot`

`spec-autopilot` 的定位是：

- 规范驱动交付编排插件
- 8 阶段工作流
- 三层门禁
- crash recovery
- GUI dashboard
- event bus

它当前不应该被重构成新的通用并行 AI 平台。

## 当前已确认的问题上下文

以下问题已经通过本地审阅和测试确认，不是猜测：

### 架构与目录问题

- 打包后的目录结构仍然混乱，源码、产物、运行日志边界不清。
- `server` 代码过大，当前 [autopilot-server.ts](plugins/spec-autopilot/server/autopilot-server.ts) 约 1180 行，承担过多职责。
- `server/autopilot-server.ts` 被 [build-dist.sh](plugins/spec-autopilot/tools/build-dist.sh) 回填到 `dist/scripts/`，说明分发结构和源码结构断裂。
- `scripts/` 已经是事实上的 runtime core，但分类、命名和职责边界仍不清晰。

### 稳定性问题

本地测试结果：

- `bash plugins/spec-autopilot/tests/test_syntax.sh` 通过
- `bash plugins/spec-autopilot/tests/test_build_dist.sh` 通过
- `bash plugins/spec-autopilot/tests/test_autopilot_server_aggregation.sh` 失败

当前已暴露的失败点包括：

- session 切换后的事件视图不一致
- `/api/raw-tail` 响应异常
- cursor 无法稳定推进

### 性能与运行时风险

- snapshot 刷新采用全量重建模型
- polling + file watch 双路径并存
- 长会话、大日志、多 session 下存在退化和竞态风险

### 安全与治理问题

- API 脱敏规则仍偏基础
- 决策写回与事件 schema 治理不够严格
- 运行时边界和发布边界未完全收敛

## 本次任务的正确边界

本次任务是：

- 修复 `spec-autopilot`
- 稳定 `spec-autopilot`
- 模块化 `spec-autopilot`
- 规范 `spec-autopilot`

本次任务不是：

- 把 `spec-autopilot` 改造成新平台
- 引入大而全的并行平台能力
- 推翻已有插件定位

## 你必须参考的本地文档

在开始改代码前，你必须阅读并遵循这些文档：

- [总调研报告](docs/plans/2026-03-19-holistic-architecture-research-report.zh.md)
- [spec-autopilot 修复设计方案](docs/plans/2026-03-19-spec-autopilot-remediation-design.zh.md)
- [竞品能力复用矩阵](docs/plans/2026-03-19-competitive-capability-reuse-matrix.zh.md)

## 关键代码与测试入口

优先检查这些文件：

- [autopilot-server.ts](plugins/spec-autopilot/server/autopilot-server.ts)
- [build-dist.sh](plugins/spec-autopilot/tools/build-dist.sh)
- [test_autopilot_server_aggregation.sh](plugins/spec-autopilot/tests/test_autopilot_server_aggregation.sh)
- [overview.zh.md](plugins/spec-autopilot/docs/architecture/overview.zh.md)

## 本次必须解决的完整问题清单

### A. 稳定性止血

必须优先修复：

1. `test_autopilot_server_aggregation.sh` 当前失败的问题。
2. session 切换后 snapshot、journal、API 返回不一致的问题。
3. `/api/raw-tail` 的 cursor、边界 chunk、空 chunk、增量读取问题。
4. 损坏 JSON 行或不完整尾行的容错问题。

### B. server 模块化

必须推进：

1. 拆分 `autopilot-server.ts` 的职责。
2. 至少拆出以下模块边界：
   - session context
   - snapshot builder
   - raw ingest
   - api routes
   - ws broadcaster
   - decision service
   - sanitize/security
3. 保持现有外部行为尽量兼容。

### C. runtime / dist 治理

必须推进：

1. 收敛 `server -> dist/scripts` 的回填式结构依赖。
2. 建立更清晰的 runtime 分层。
3. 在不破坏当前可构建性的前提下，逐步向更合理的目录结构过渡。

### C1. 目录重构是本轮明确交付项

不是“可选优化”，而是明确工作范围的一部分。

本轮至少要把目录问题作为正式实施内容推进，不能只停留在代码拆分。

你需要按渐进式方式重构当前目录，使其朝这个目标收敛：

```text
plugins/spec-autopilot/
  .claude-plugin/
  docs/
  hooks/
  gui/
  runtime/
    server/
    scripts/
  skills/
  tests/
  tools/
```

发布产物目标结构：

```text
dist/spec-autopilot/
  .claude-plugin/
  hooks/
  runtime/
    server/
    scripts/
  assets/
    gui/
  skills/
  CLAUDE.md
```

### C2. 目录重构的最小执行要求

本轮至少推进以下事项中的大部分，不能完全跳过：

1. 将 server 源码从“单文件入口”演进为独立目录结构。
2. 明确 `runtime/server` 与 `runtime/scripts` 的边界。
3. 调整 build-dist 逻辑，减少 `dist/scripts/autopilot-server.ts` 这种历史兼容式回填。
4. 为 GUI 构建产物引入更明确的发布语义，例如向 `assets/gui` 收敛，而不是长期依赖 `gui-dist` 作为半源码半产物目录。
5. 尽可能把目录迁移做成兼容式迁移，而不是暴力大搬家。

### C3. 目录重构的迁移策略

建议采用三步法：

#### 第一步：结构并存

- 新建 `runtime/server`、`runtime/scripts` 等目标目录。
- 先把实现迁入或拆入新目录。
- 旧路径保留为兼容入口或 shim。

#### 第二步：构建迁移

- 更新 `build-dist.sh`，让 dist 优先复制新目录结构。
- 如果仍需兼容旧结构，必须明确写清兼容层，而不是继续隐式回填。

#### 第三步：测试与验证

- 增加针对新 dist 结构的断言。
- 验证安装和运行入口仍然兼容。

### C4. 目录重构的验收标准

本轮结束时，至少要满足其中多数：

1. server 代码不再只依附于单个旧入口文件。
2. runtime 目录语义比当前更清晰。
3. dist 结构比当前更接近 runtime/assets 分层。
4. `build-dist.sh` 的特殊回填逻辑减少，或者已经被兼容层显式包裹。
5. 有测试保护新的目录/打包行为。

### D. 测试补强

必须增加或修复这些测试覆盖：

1. 多 session 切换一致性
2. raw-tail 增量游标
3. 损坏 JSON 行容错
4. snapshot / journal 一致性

### E. 低风险竞品能力吸收

仅允许吸收适合当前插件定位的低风险能力：

1. 更轻量的能力清单或命令体验
2. 更小的上下文包策略
3. 更清晰的质量证据输出

禁止把以下平台能力塞进当前插件：

- 完整 task graph platform
- 通用 multi-agent scheduler
- 大规模模型自动路由平台
- CI / PR 全闭环平台

## 实施原则

### 必须遵守

1. 直接改代码，不要停留在分析。
2. 小步推进，但要在当前会话中尽量完成。
3. 任何大改动前先阅读相关文件和测试。
4. 每完成一个关键阶段就跑对应测试。
5. 不要修改无关文件。
6. 不要回退用户已有改动。
7. 保持当前插件定位稳定。

### 允许做的结构调整

- 合理新增模块文件
- 迁移 server 内部实现
- 增加 schema / types / utility files
- 增加 tests
- 适度调整 build/dist 结构，只要不破坏现有安装兼容

### 不要做的事情

- 不要把当前插件重写成另一套平台
- 不要大规模重命名所有目录导致仓库失控
- 不要仅修改文档而不改代码
- 不要跳过测试

## 建议实施顺序

### 第一阶段：建立上下文并定位失败

你需要先：

1. 阅读关键文档与关键代码
2. 运行或复现关键测试
3. 明确失败根因

### 第二阶段：修复聚合回归

你需要优先修复：

- session 切换逻辑
- snapshot diff/broadcast 逻辑
- raw-tail 增量读取
- cursor 推进

### 第三阶段：拆分 server

在回归修复完成后：

- 将单文件职责拆分到合理模块
- 保持对外 API 和行为兼容

### 第四阶段：补测试

你需要增加或修复关键测试，使修复可被持续验证。

### 第五阶段：治理 runtime / dist 边界

你需要渐进式减少打包例外和结构断裂。

### 第六阶段：推进目录重构

你需要把目录重构当成正式交付内容，而不是顺手优化。

至少要：

- 建立目标 runtime 分层
- 推进 server 目录化
- 推进 dist 结构向 `runtime/` 和 `assets/` 收敛
- 为旧路径保留必要兼容层

## 验收标准

至少满足以下条件：

1. `test_autopilot_server_aggregation.sh` 恢复通过，或明显缩小失败面并给出合理解释。
2. 新增或修复的测试能覆盖本轮修复点。
3. `autopilot-server.ts` 不再维持当前单文件过度集中的状态，或已实质完成第一阶段模块拆分。
4. 运行时和分发结构比当前更清晰。
5. 最终输出能清楚说明修改范围、测试结果和残留风险。
6. 目录重构已被实际推进，而不只是文档口头说明。

## 最终提示词

```text
你现在是这个仓库的高级架构修复工程师。请直接在当前代码库中执行修复工作，不要只停留在分析。

仓库根目录：
.

任务对象：
当前插件 `spec-autopilot`

产品定位：
`spec-autopilot` 是规范驱动交付编排插件，不是新的通用并行 AI 平台。本次任务必须坚持这个边界，只做修复、稳定性治理、模块化和发布边界收敛，不要把它重构成另一种产品。

你必须先阅读并遵循以下文档：
1. docs/plans/2026-03-19-holistic-architecture-research-report.zh.md
2. docs/plans/2026-03-19-spec-autopilot-remediation-design.zh.md
3. docs/plans/2026-03-19-competitive-capability-reuse-matrix.zh.md

你必须理解以下完整上下文：

一、当前已确认的问题
1. 打包结构和源码结构边界不清，`dist/spec-autopilot`、`gui-dist`、`logs`、源码目录语义混杂。
2. `plugins/spec-autopilot/server/autopilot-server.ts` 约 1180 行，是单文件控制塔，承担 HTTP、WS、事件聚合、snapshot、decision、脱敏等过多职责。
3. `plugins/spec-autopilot/tools/build-dist.sh` 仍通过回填方式把 `server/autopilot-server.ts` 放入 `dist/scripts/`，说明 runtime/dist 结构断裂。
4. 本地测试中：
   - `bash plugins/spec-autopilot/tests/test_syntax.sh` 通过
   - `bash plugins/spec-autopilot/tests/test_build_dist.sh` 通过
   - `bash plugins/spec-autopilot/tests/test_autopilot_server_aggregation.sh` 失败
5. 当前可复现的问题包括：
   - session 切换后 snapshot / journal / API 结果不一致
   - `/api/raw-tail` 的增量游标和返回值不稳定
   - 损坏 JSON 行、空 chunk、边界 chunk 处理不够稳健
6. 当前系统还有性能风险：
   - snapshot 刷新偏向全量重算
   - polling 和 file watch 双路径并存
   - 长会话和大日志下有退化风险
7. 当前系统还有治理问题：
   - API 脱敏覆盖不够系统
   - schema 治理不够严格
   - tests 数量虽多，但运行时一致性测试仍不足

二、本次任务的正确边界
1. 这是 `spec-autopilot` 修复任务，不是新平台开发任务。
2. 允许做模块化拆分、tests 补强、runtime/dist 治理。
3. 不允许把 task graph platform、通用 multi-agent scheduler、完整模型路由平台、CI/PR 全闭环平台强行塞入当前插件。

三、本轮必须完成的完整事项

A. 稳定性止血
1. 优先修复 `plugins/spec-autopilot/tests/test_autopilot_server_aggregation.sh` 当前失败的问题。
2. 重点处理：
   - session 切换后的 snapshot / journal / API 返回一致性
   - `/api/raw-tail` 的 cursor、边界 chunk、空 chunk、增量读取
   - 损坏行、不完整尾行的容错
3. 修复后必须重新运行相关测试。

B. server 模块化
1. 当前单文件：
   - `plugins/spec-autopilot/server/autopilot-server.ts`
2. 请按合理边界拆分，至少拆出：
   - session context
   - snapshot builder
   - raw ingest
   - api routes
   - ws broadcaster
   - decision service
   - sanitize/security
3. 拆分后保持行为兼容。

C. runtime / dist 治理
1. 减少或清理 `server -> dist/scripts` 的回填式依赖。
2. 逐步建立更清晰的 runtime 分层。
3. 在不破坏当前构建和安装兼容的前提下推进结构收敛。

C1. 目录重构是本轮明确交付项，而不是可选项。
你必须把目录治理作为正式实施内容推进。目标收敛方向是：

源码目标结构：
```text
plugins/spec-autopilot/
  .claude-plugin/
  docs/
  hooks/
  gui/
  runtime/
    server/
    scripts/
  skills/
  tests/
  tools/
```

发布目标结构：
```text
dist/spec-autopilot/
  .claude-plugin/
  hooks/
  runtime/
    server/
    scripts/
  assets/
    gui/
  skills/
  CLAUDE.md
```

C2. 目录重构的最小要求：
1. 让 server 源码演进为目录化结构，而不是继续只靠旧单文件入口。
2. 明确 `runtime/server` 与 `runtime/scripts` 的边界。
3. 更新 `build-dist.sh`，让 dist 优先复制新的结构，减少历史回填式逻辑。
4. 逐步让 GUI 产物向 `assets/gui` 语义收敛，而不是继续长期依赖 `gui-dist` 的半产物状态。
5. 采用渐进式迁移：允许兼容层，但不能继续让旧结构无限期成为真实主结构。

C3. 目录重构的执行策略：
1. 先新建目标目录并迁入实现。
2. 再修改构建脚本和复制逻辑。
3. 再补充测试，验证新结构。
4. 必要时保留 shim 或兼容入口，但必须明确其临时性质。

D. 测试补强
1. 增加或修复这些测试覆盖：
   - 多 session 切换
   - raw-tail 增量游标
   - 损坏 JSON 行容错
   - snapshot / journal 一致性
2. 若某项本轮无法完整覆盖，必须在最终汇报中明确说明原因和下一步。

E. 吸收低风险竞品能力
只允许吸收适合当前插件定位的低风险能力：
1. 更轻量的能力清单或命令体验
2. 更小的上下文包策略
3. 更清晰的质量证据输出

四、必须遵守的执行规则
1. 直接改代码，不要停留在分析。
2. 先阅读相关文件，再动手修改。
3. 小步推进，但尽量在当前会话完成闭环。
4. 每完成一个关键阶段就跑对应测试。
5. 不要修改无关文件。
6. 不要回退用户已有改动。
7. 除非有充分必要，不要改动市场配置和仓库主 README。

五、建议优先检查的文件
1. plugins/spec-autopilot/server/autopilot-server.ts
2. plugins/spec-autopilot/tools/build-dist.sh
3. plugins/spec-autopilot/tests/test_autopilot_server_aggregation.sh
4. plugins/spec-autopilot/docs/architecture/overview.zh.md

六、建议执行顺序
1. 先读文档和关键代码
2. 复现 server 聚合测试失败
3. 修复 session / raw-tail / 增量读取问题
4. 拆分 server 控制面
5. 推进目录重构和 runtime/dist 收敛
6. 补测试
7. 校验兼容性和构建

七、最终输出必须包含
1. 你修改了哪些文件
2. 你修复了哪些问题
3. 你运行了哪些测试，结果如何
4. 还有哪些残留风险或下一步建议
5. 目录重构推进到了哪一步，哪些旧结构仍保留兼容层

现在开始，不要只给计划，直接实施。
```
