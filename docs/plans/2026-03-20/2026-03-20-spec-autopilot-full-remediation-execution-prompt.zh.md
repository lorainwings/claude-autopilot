# Spec Autopilot 全量修复执行提示词

你现在在仓库 `/Users/lorain/Coding/Huihao/claude-autopilot` 中工作。

目标不是分析，不是写方案，不是只补文档，而是**一次性全量实施修复**以下 5 个问题，并把实现、测试、文档、可观测性全部补齐。  
优先级只是执行顺序，不代表可以只做前几项。**必须把 5 项全部落地。**

请全程使用中文简体输出，并直接在仓库中修改代码。

---

# 一、总目标

经过实际使用，`spec-autopilot` 插件存在以下 5 类问题，需要完整修复：

1. 中间过程中无法体现“模型是否已经切换”
2. 循环实施节点中，本地 GUI 仪表盘服务会断掉；页面日志过于粗略，缺少足够详尽的运行日志
3. 整体过程中，需求分析和决策流程速度慢，需要深度优化“让 AI 快速且准确澄清/理解需求”的机制
4. 崩溃恢复流程中，未清理 fixup 提交；等待 AI 扫描完成后又弹出 AskUserQuestion 让用户确认，这个流程体验差，需要明确设计并优化
5. 循环实施过程中，`parallel.enabled=true` 仍可能退化为串行，无法达到最大效率

**重要要求：**
- 不能只改 `SKILL.md` / `references/*.md` / 说明文档。
- 必须把关键改动落实到**运行时代码、GUI、脚本、测试**。
- 如果某项受 Claude Code / Task API 能力限制，必须做“诚实实现”：
  - 真实支持的能力要做实
  - 不支持的能力不能伪装成已支持
  - UI 和日志必须明确区分 `requested / effective / fallback / unknown`
- 最终要保证：
  - 功能可运行
  - 行为可观测
  - 测试可验证
  - 文档与实际实现一致

---

# 二、你必须先核实并基于现状修改的关键文件

请优先阅读并基于这些实现做真实改造，而不是另起炉灶：

## 模型路由 / Phase 调度
- `plugins/spec-autopilot/skills/autopilot-dispatch/SKILL.md`
- `plugins/spec-autopilot/skills/autopilot/references/dispatch-prompt-template.md`
- `plugins/spec-autopilot/runtime/scripts/resolve-model-routing.sh`
- `plugins/spec-autopilot/runtime/scripts/emit-model-routing-event.sh`
- `plugins/spec-autopilot/runtime/server/src/types.ts`

## GUI 服务 / 聚合服务器 / 可观测性
- `plugins/spec-autopilot/runtime/scripts/start-gui-server.sh`
- `plugins/spec-autopilot/runtime/server/autopilot-server.ts`
- `plugins/spec-autopilot/runtime/server/src/bootstrap.ts`
- `plugins/spec-autopilot/runtime/server/src/config.ts`
- `plugins/spec-autopilot/runtime/server/src/state.ts`
- `plugins/spec-autopilot/runtime/server/src/api/routes.ts`
- `plugins/spec-autopilot/runtime/server/src/ws/ws-server.ts`
- `plugins/spec-autopilot/runtime/server/src/snapshot/snapshot-builder.ts`
- `plugins/spec-autopilot/runtime/server/src/ingest/*.ts`
- `plugins/spec-autopilot/runtime/scripts/capture-hook-event.sh`
- `plugins/spec-autopilot/runtime/scripts/emit-tool-event.sh`
- `plugins/spec-autopilot/runtime/scripts/statusline-collector.sh`
- `plugins/spec-autopilot/runtime/scripts/install-statusline-config.sh`
- `plugins/spec-autopilot/hooks/hooks.json`

## GUI 前端
- `plugins/spec-autopilot/gui/src/App.tsx`
- `plugins/spec-autopilot/gui/src/store/index.ts`
- `plugins/spec-autopilot/gui/src/lib/ws-bridge.ts`
- `plugins/spec-autopilot/gui/src/components/TelemetryDashboard.tsx`
- `plugins/spec-autopilot/gui/src/components/LogWorkbench.tsx`
- `plugins/spec-autopilot/gui/src/components/VirtualTerminal.tsx`
- `plugins/spec-autopilot/gui/src/components/ToolTracePanel.tsx`
- `plugins/spec-autopilot/gui/src/components/TranscriptPanel.tsx`
- `plugins/spec-autopilot/gui/src/components/RawInspectorPanel.tsx`
- 如有必要可以新增组件，但不要破坏现有信息结构

## 崩溃恢复 / 清理 / Phase 7
- `plugins/spec-autopilot/skills/autopilot-recovery/SKILL.md`
- `plugins/spec-autopilot/runtime/scripts/recovery-decision.sh`
- `plugins/spec-autopilot/runtime/scripts/clean-phase-artifacts.sh`
- `plugins/spec-autopilot/runtime/scripts/scan-checkpoints-on-start.sh`
- `plugins/spec-autopilot/skills/autopilot-phase7/SKILL.md`
- `plugins/spec-autopilot/skills/autopilot/SKILL.md`

## Phase 1 需求理解 / 决策流程
- `plugins/spec-autopilot/skills/autopilot/references/phase1-requirements.md`
- `plugins/spec-autopilot/skills/autopilot/references/phase1-requirements-detail.md`
- 相关测试与报告中提到的现有设计缺陷也要一起核对并落实

## 并行实施 / Phase 5
- `plugins/spec-autopilot/skills/autopilot/references/parallel-phase5.md`
- `plugins/spec-autopilot/skills/autopilot/references/parallel-dispatch.md`
- `plugins/spec-autopilot/skills/autopilot/references/mode-routing-table.md`
- `plugins/spec-autopilot/skills/autopilot/references/phase5-implementation.md`
- 所有与并行 merge / ownership / fallback / task progress 有关的脚本和测试

---

# 三、五大问题的强制实施要求

---

## 问题 1：模型切换不可见

### 现状问题
当前仓库里已经有 `model_routing` 解析与事件发射，但 GUI 没有把它作为显式状态展示；更严重的是，dispatch 层更多停留在协议/Prompt 注入，未形成“真实模型选择 → 运行时回传 → GUI 可见”的完整闭环。

### 你必须实现
1. 建立**模型路由可观测性闭环**
   - 在 GUI 中显式展示：
     - `requested_tier`
     - `requested_model`
     - `requested_effort`
     - `effective_model`
     - `fallback_model`
     - `routing_reason`
     - `fallback_applied`
     - `model_status`（如 `requested`, `effective`, `fallback`, `unknown`, `unsupported`）
   - 不允许只在 raw/event 面板里隐式存在，必须在主界面显式可见

2. 明确区分：
   - “路由器建议使用的模型”
   - “运行时实际使用的模型”
   - “statusLine / transcript 推断到的当前模型”
   - “由于平台限制无法确认实际模型”

3. 如果 Claude Code 当前环境**无法真实给 Task 传 per-task model 参数**
   - 不要伪装成“已经真实切换”
   - UI 必须诚实显示：
     - `requested_model`
     - `effective_model: unknown` 或从 statusLine 推断值
     - `capability_note: runtime model override unsupported`
   - 同时仍保留路由事件和行为提示注入

4. 如果当前仓库结构允许真实传递 model 参数
   - 则实现真实 dispatch model 传参
   - 并补 runtime fallback 逻辑
   - 失败时记录 fallback 事件与 effective model 变化

5. 事件层需要新增或扩展
   - `model_routing`
   - `model_effective`
   - `model_fallback`
   - 保证 GUI 和日志工作台能消费

### 验收标准
- 用户能在主界面中直接看到“本阶段/本 Agent 请求用什么模型、实际观测到什么模型”
- 不再出现“后台发生路由，但用户完全无感知”的情况
- 实现和文档一致，不能继续停留在“文档说会切换，代码只是在 Prompt 里提醒”

---

## 问题 2：GUI 服务会断、日志过粗

### 现状问题
目前 GUI server 通过 `nohup ... >/dev/null 2>&1 &` 裸起，无守护、无 pid 管理、无日志落盘；前端有重连，但后端死掉后无法自恢复。日志虽然已有 events/hooks/statusline/transcript/tool panels，但首页默认信息仍太粗，且故障时缺少 server 自身日志。

### 你必须实现
1. 重构 `start-gui-server.sh`
   - 增加 pid 文件
   - 增加 server stdout/stderr 日志文件
   - 增加健康检查
   - 增加“若进程死掉则可重启”的守护机制
   - 至少做到单机本地可稳定恢复，不要求引入复杂外部守护器

2. 聚合服务器增强
   - 不要吞掉关键错误
   - 对 snapshot/build/watch/parse 错误进行结构化记录
   - 服务端自身也要有 `server.log` / `server.err.log` 或统一日志
   - 对 session 切换、文件读取失败、raw 日志缺失、transcript 解析失败等都记录原因

3. GUI 前端增强
   - 在主界面明确展示 server 连接状态，不只是 WS 是否连上
   - 区分：
     - HTTP 健康
     - WS 连接
     - telemetry 可用
     - transcript 可用
     - raw hooks/statusline 可用
   - 在界面上显式提示“statusLine 未安装/未接入”，而不是只显示“暂无数据”

4. 日志工作台增强
   - 默认“事件流”不能只给粗粒度摘要
   - 必须增加可切换的详细模式，至少覆盖：
     - `tool_use`
     - `hook_event`
     - `model_routing`
     - `status_snapshot`
     - `transcript_message`
     - `agent_dispatch/complete`
     - `gate_*`
   - 提供按 phase / agent / event type 过滤
   - 允许看到关键 payload 字段，而不是只能看一行摘要

5. 自动化接入 statusLine
   - 检查当前 Phase 0 是否应自动安装 statusLine 配置
   - 如果不适合强装，也至少在 Phase 0/Banner/GUI 中明确提示未安装，并给出一键修复入口或命令提示
   - 总之不能让用户以为“GUI telemetry 是坏的”，实际上只是没装 statusLine

### 验收标准
- GUI server 杀掉后可以被脚本自动识别并恢复
- server 自身错误可查
- 首页可看出是“server 挂了 / WS 断了 / statusLine 缺失 / transcript 不可用 / raw 日志缺失”
- 日志工作台的细节足够排查问题，而不是只有简化事件流

---

## 问题 3：需求分析与决策流程慢

### 现状问题
Phase 1 当前同时存在两个问题：
- 对模糊需求的前置澄清不够精准，`flags >= 3` 才强制澄清，`flags = 2` 灰区容易直接进入三路调研
- 复杂度评估过度依赖 `impact_analysis.total_files`
- BA 输出未强约束“所有 open_questions 必须映射到 decision_points”
- 对跨系统需求仍偏单 Agent research

### 你必须实现
1. 重构 Phase 1 为“先收敛，后调研”
   - 在正式三路调研前，新增一个**极轻量定向澄清阶段**
   - 对信息不足需求先问最高价值的 1-3 个问题，而不是直接全量调研
   - 不允许把所有模糊需求都扔进三路并行研究

2. 调整澄清触发阈值
   - 现有 `flags >= 3` 强制预循环保留
   - 但 `flags >= 2` 必须至少触发“定向澄清 1-2 问”
   - 增加“无范围限定 / 无验收标准 / 无目标对象”之类的检测维度，避免“系统性能优化”这种灰区直接调研发散

3. 优化复杂度评估
   - 不能只依赖 `total_files`
   - 至少综合：
     - 是否跨模块
     - 是否安全/认证/支付/性能/迁移等高风险域
     - 是否引入新依赖
     - 是否存在明确非功能约束
     - 是否存在多决策点
   - 让“少文件但高风险”不会误判为 small

4. 强化 BA 输出约束
   - 强制要求 `open_questions` 全部映射到 `decision_points`
   - 强制输出：
     - `goal`
     - `scope`
     - `non_goals`
     - `acceptance_criteria`
     - `decision_points`
     - `assumptions`
     - `risks`
   - 没有这些字段时不能直接放行

5. 优化速度
   - 简单、清晰、小范围需求要能快速通过
   - 模糊需求先收敛再调研，减少噪音和 token 浪费
   - 尽量减少不必要的大 Prompt 注入和无差别搜索
   - 如果能做到，拆分 Phase 1 中常驻/按需加载内容，减少 SKILL 冗余注入

6. 对跨系统需求
   - 评估并实现更合理的多域 research 机制，至少允许按系统域拆分 research，而不是单一 agent 全包
   - 如果短期不适合完整并行，也要给出结构化 research plan 和更严格输出格式

### 验收标准
- 简单清晰需求明显更快
- 模糊需求先被收敛，不再一上来就三路发散调研
- Phase 1 输出的结构化信息更完整，后续 Phase 不再频繁因需求不清返工
- 对“性能优化”“跨系统认证”“迁移类改造”等场景的澄清质量显著提高

---

## 问题 4：崩溃恢复流程体验差

### 现状问题
当前流程中：
- fixup 提交通常要等到 Phase 7 autosquash 才清理
- 恢复扫描后通常仍弹 AskUserQuestion 让用户决定
- 这在“单一候选、无歧义”的恢复场景里很影响体验

### 你必须实现
1. 明确恢复语义
   - “继续恢复”默认是否保留 fixup
   - “指定阶段恢复”是否会清理 fixup / 回退 git 状态
   - “从头开始”如何处理历史残留
   - 这些必须在代码、日志、文档、用户提示中统一

2. 优化恢复交互
   - 如果满足以下条件，允许自动继续而不是再次弹确认：
     - 只有一个明确可恢复的 change
     - 没有多候选歧义
     - 没有危险 git 状态冲突
     - 恢复路径是非破坏性的 continue
   - 通过配置项控制，例如：
     - `recovery.auto_continue_single_candidate`
   - 默认值请按保守但实用的原则设计

3. fixup 处理策略要真实
   - 不要自动做危险的历史改写
   - 但要明确记录：
     - 当前分支是否存在未 squash 的 autopilot fixup
     - 恢复后是否会保留它们
     - 归档时是否会自动 squash
   - GUI / CLI 输出里都应该能看到这个状态

4. 恢复扫描输出增强
   - `recovery-decision.sh` 的输出中增加更明确字段，例如：
     - `has_fixup_commits`
     - `fixup_commit_count`
     - `recovery_interaction_required`
     - `auto_continue_eligible`
     - `git_risk_level`
   - 前端/主线程据此决定是否真的需要 AskUserQuestion

5. 清理脚本与恢复脚本联动
   - `clean-phase-artifacts.sh`、`recovery-decision.sh`、Phase 7 autosquash 语义必须统一
   - 不允许出现“恢复逻辑说会清理，但实际只删文件不处理 git 提示”的不一致

### 验收标准
- 单候选、无歧义、非破坏性恢复时，不再机械弹确认框
- fixup 的保留/清理语义清晰可见
- 不进行未经用户授权的危险 git 历史改写
- 文档、实现、GUI 展示一致

---

## 问题 5：并行实施退化严重，`parallel.enabled=true` 仍可能串行

### 现状问题
当前 Phase 5 的“并行”很大程度仍停留在协议和 Prompt 约束层。  
文档说 `parallel.enabled=true` 必须走并行，但实际缺少运行时强制校验。  
并且现有“按域 1 Agent”策略对单域项目天然退化为 1 个 worktree + 1 个 agent 域内串行。

### 你必须实现
1. 不再只靠 Prompt 描述并行
   - 主线程必须生成结构化并行计划产物，例如：
     - `parallel_plan.json`
   - 内容至少包含：
     - task list
     - dependency DAG
     - ready batches
     - ownership
     - domain grouping
     - fallback reason
     - scheduler decision
   - 后续 dispatch 必须消费这个 plan，而不是让模型“自己决定串行还是并行”

2. Phase 5 调度器真实化
   - 实现确定性的 scheduler，而不是纯文档/Prompt 约束
   - 至少支持：
     - 基于依赖图的 ready-set 并行
     - 文件 ownership 检查
     - batch 级并行
     - batch 完成后再推进后续 ready tasks
   - 不要只按“域”并行

3. 单域项目也要能吃到并行收益
   - 如果 task 之间文件 ownership 不冲突、依赖可分离，即便都在 `src/` 下，也应能 batch 并行
   - “域”只能作为 ownership/agent routing 的辅助维度，不能成为并行度上限

4. 并行运行时事件补齐
   - 新增/扩展事件：
     - `parallel_plan`
     - `parallel_batch_start`
     - `parallel_batch_end`
     - `parallel_task_ready`
     - `parallel_task_blocked`
     - `parallel_fallback`
   - GUI 必须能直接看到：
     - 为什么本轮不能并行
     - 哪些 task 被依赖阻塞
     - 哪些 batch 正在并行
     - 为什么从并行降级到串行

5. 强制一致性
   - 当 `parallel.enabled=true` 时，如果实际退化为串行，必须记录**结构化 fallback reason**
   - 不能只在终端里让模型口头说“有强依赖所以串行”
   - 必须有可机器消费的证据链

6. 保持安全约束
   - ownership、openspec/checkpoint 保护、merge guard、fallback 机制不能被弱化
   - 若需要在安全性与效率间折中，请优先保留确定性护栏

### 验收标准
- `parallel.enabled=true` 不再只是“希望并行”
- 是否并行、为什么并行/不并行，主线程有结构化决策产物
- 单域项目只要任务可拆，也能获得 batch 并行收益
- GUI 能解释“为什么没有并行起来”

---

# 四、实施原则

1. **必须先修运行时，再修文档**
   - 文档必须最终更新，但不能先改文档冒充完成

2. **不能做假闭环**
   - 例如模型切换，如果 runtime 不能真实切，就诚实显示 `requested` / `effective unknown`
   - 不允许 UI 显示“已切换成功”但底层只是 Prompt 提示

3. **所有关键改动必须补测试**
   - 至少补单测/脚本测试/聚合测试
   - 修改已有测试使其覆盖新行为
   - 尤其要补：
     - 模型路由可观测性
     - GUI server 启停与恢复
     - 恢复自动继续判定
     - 并行计划与 fallback reason
     - Phase 1 新澄清策略

4. **必须运行测试并报告结果**
   - 不能只说“理论上可行”
   - 尽量运行：
     - 现有相关 shell tests
     - GUI/server 相关 tests
     - 新增 tests
   - 如果有没法跑的测试，明确说明原因

5. **不要引入一堆空接口或未来占位**
   - 每个新增字段、事件、配置项都必须有真实消费方
   - 每个新增面板/状态都必须有真实数据来源

---

# 五、建议执行顺序（必须全做）

## Step 1
先做“模型路由闭环 + GUI 可见化 + 事件扩展”
- 修 runtime types / ingest / GUI store / dashboard / log workbench
- 实现 requested/effective/fallback/unknown 语义
- 更新相关测试

## Step 2
修“GUI server 稳定性 + 可观测性”
- 重构启动脚本
- 增加 pid/log/health/self-heal
- 丰富 server 日志与前端状态显示
- 接入 statusLine 缺失提示
- 更新测试

## Step 3
重做“Phase 1 先收敛后调研”
- 加轻量定向澄清阶段
- 提升 flags=2 处理
- 增强 complexity routing
- 强化 BA 输出约束
- 优化 token/流程速度
- 更新测试与文档

## Step 4
优化“崩溃恢复 + fixup 语义 + 自动继续”
- 扩展 recovery-decision 输出
- 实现 auto-continue eligibility
- 统一 fixup / autosquash / cleanup 语义
- 更新 GUI/CLI 提示与测试

## Step 5
实现“真实并行计划与 batch 调度”
- 生成 `parallel_plan.json`
- 实现主线程确定性 scheduler
- 增加 batch/fallback 结构化事件
- 让单域项目也能获得 batch 并行收益
- 更新 Phase 5 相关测试与 GUI

## Step 6
最后统一更新：
- `README` / `README.zh`
- `docs/operations/troubleshooting*.md`
- `docs/getting-started/*`
- 所有受影响的 skill/reference 文档
- 确保文档描述与真实代码完全一致

---

# 六、必须新增或更新的验证项

至少补这些测试，名称可以调整，但行为必须覆盖：

1. 模型路由事件不仅写入 `events.jsonl`，还会被 GUI store 正确消费
2. 当 runtime 无法确认真实模型时，UI 正确显示 `effective_model=unknown`
3. GUI server 异常退出后，启动脚本可检测并恢复
4. `/api/info` 暴露更多运行状态字段，前端正确消费
5. statusLine 未安装时，前端/接口能明确识别并提示
6. Phase 1 对 `flags=2` 模糊需求会触发定向澄清，而不是直接三路调研
7. BA 输出缺少关键字段时不会被直接放行
8. recovery 单候选无歧义时，`auto_continue_eligible=true`
9. recovery 存在 fixup 时，能明确输出 fixup 状态
10. Phase 5 在 `parallel.enabled=true` 时会生成结构化并行计划
11. 单域但无冲突任务可形成 batch 并行，而不是必然 1 域串行
12. 并行退化时会产出结构化 fallback reason，而不是只有自然语言描述

---

# 七、最终输出要求

完成后请给我：

1. 改动摘要
   - 按 5 个问题分别说明改了什么
2. 关键文件列表
   - 列出修改过的核心文件
3. 测试结果
   - 跑了哪些测试，哪些通过，哪些未跑
4. 风险与后续
   - 还剩什么平台级限制
   - 哪些地方做了诚实降级
5. 不要只给我“完成了”
   - 必须告诉我每个问题现在如何被解决、用户在界面/日志里会看到什么变化

---

# 八、额外约束

- 不要偷懒把关键逻辑继续放在 `SKILL.md` 文本约束里
- 不要把“并行调度”“模型切换”“恢复自动继续”继续设计成 AI 自觉遵守
- 要尽可能下沉到脚本、服务端、前端状态机、测试层
- 如果发现当前某些设计与这次目标根本冲突，可以重构，但必须保持现有公开能力尽量兼容
- 修改后请确保 `dist/` 与源码态行为一致；如果仓库当前有构建产物同步机制，请一并更新

开始执行。先读代码，建立最小可行改造计划，然后直接动手实现，不要停在分析。
