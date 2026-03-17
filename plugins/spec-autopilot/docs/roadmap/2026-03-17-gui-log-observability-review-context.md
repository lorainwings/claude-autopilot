# Claude Autopilot GUI 日志增强需求上下文与审查基线

> 日期: 2026-03-17
> 适用范围: `plugins/spec-autopilot`
> 目的: 保存本次需求对话上下文，供其他 AI 或人工做架构审查、稳定性复核、回归验证与后续迭代设计

## 1. 文档用途

本文档不是纯设计稿，而是本次需求沟通的审查基线，包含:

- 用户原始目标与约束
- 被否决和保留的方案
- 最终技术路线
- 已落地实现范围
- 已完成的真实验证
- 后续审查重点

其他 AI 在继续分析前，应优先读取本文档，再结合当前代码状态审查。

## 2. 本次需求的核心目标

用户目标可以归纳为一句话:

**在不改变 Claude Code 现有 `/autopilot` 使用习惯、不接管 Claude CLI 顶层进程的前提下，让 GUI 看到尽量详细、可审计、可追溯的运行日志，并保证主编排稳定性与确定性。**

进一步拆解后，目标包括:

- 对当前插件的步骤、流程、细节做整体架构分析、代码分析、稳定性分析、确定性分析
- 找出日志观测盲区和事件链短板
- 设计低侵入方案，把 GUI 从“只看到 hooks 日志”升级为“看到更完整的会话遥测”
- 所有分析和结论必须有真实依据，不能只停留在推演
- 最大化并行执行以提高调研、实现和验证效率
- 不允许为获取日志而破坏主编排协议或改变用户习惯

## 3. 用户明确给出的硬约束

以下约束来自本次对话，属于必须遵守的边界:

### 3.1 交互习惯不能变

用户当前在 iTerm2 中直接进入 Claude Code，并通过 `/autopilot` 启动编排器。

不能接受的方向:

- 用 wrapper/PT Y 接管 Claude Code 顶层进程
- 改写用户的进入方式
- 强制用户改变既有命令习惯

可以接受的方向:

- Claude 官方生命周期能力
- 低侵入的旁路采集
- 不影响 `/autopilot` 主功能的配置增强

### 3.2 不接受高侵入接管方案

用户明确放弃“直接接管 Claude CLI stdout/stderr 进程流”的方案，原因包括:

- 接入成本高
- 对开源工具推广不友好
- 对用户环境侵入性太强

因此本轮不以 wrapper、PTY、shell alias 接管作为主线。

### 3.3 GUI 目标是“尽量详细”，不是伪全量

用户最初希望 GUI 能看到 Claude CLI 中的全部日志，后续接受了一个现实边界:

- 在不接管顶层进程的前提下，无法严格保证拿到 CLI 终端上的一切字节级输出
- 但可以通过 `hooks + statusLine + transcript_path` 构造出足够详细、可回放、可审计的 GUI 日志体系

### 3.4 必须真实验证

用户明确要求:

- 所有分析必须有依据
- 必须经过真实仿真测试
- 不能只做概念设计

## 4. 本次对话中的关键问题与结论

### 4.1 关于 PTY / wrapper 接管

用户提问:

- 由 wrapper/sidecar 用 PTY 启动 Claude Code，会不会影响现有使用习惯

结论:

- 会增加接入复杂度
- 会提高侵入性
- 不符合本次“低侵入、开源低成本接入”的主目标
- 因此被放弃，不作为本轮落地方案

### 4.2 关于“把 stdout/stderr 全量写文件”

用户提问:

- 既然 Claude CLI 输出本质就是 stdout/stderr 数据流，为什么全量落盘后 GUI 还会缺失

结论:

- 如果接管 Claude Code 顶层进程，确实可以高度逼近“全量终端字节流”
- 但本轮明确不采用该方向
- 在不接管顶层进程时，hooks / statusLine / transcript 只能获取官方暴露或间接可见的生命周期信息
- 因此 GUI 可以做到“高度详细的结构化运行日志”，但不能宣称“字节级完整复刻终端输出”

### 4.3 关于官方 API / 官方能力

用户提问:

- Claude 官方是否提供获取所有输出信息的 API

本轮结论:

- 当前落地应基于 Claude Code 已提供或可配置的官方能力:
  - `hooks`
  - `statusLine`
  - `transcript_path`
- 不依赖高侵入进程截获
- 不以非官方进程注入为主线

### 4.4 关于低成本接入

用户提问:

- 如果采用低侵入方案，在开源工具中如何做到超低成本接入

本轮结论:

- 以“声明式配置 + 脚本安装器 + 本地旁路采集”为主
- 不修改 Claude Code 主进程启动方式
- 不改变 `/autopilot` 使用习惯
- 将接入成本降到:
  - 配置 hooks
  - 配置 statusLine
  - 启动 GUI server

### 4.5 关于 hooks / statusLine / transcript_path 最终能到什么粒度

用户提问:

- 如果只用官方生命周期能力，日志最详细能到什么程度

最终结论:

- `hooks`: 可以拿到工具调用前后、会话起止、compact、subagent、用户提交等生命周期事件
- `statusLine`: 可以周期性拿到当前模型、cwd、context/cost、transcript_path 等运行遥测
- `transcript_path`: 可以从转录中恢复 conversation/system/tool 相关语义内容

三者组合后，GUI 可以展示:

- 会话生命周期
- 工具执行链
- transcript 对话消息
- 运行时状态快照
- 原始 hooks/statusLine 调试视图

## 5. 最终确定的技术路线

### 5.1 总体原则

- 不接管 Claude Code 顶层进程
- 不引入 wrapper/PT Y 作为主方案
- 不改变 `/autopilot` 主流程
- 采用旁路采集与统一聚合
- GUI 展示“统一日志工作台”，而不是仅暴露 hooks 原始日志

### 5.2 分层方案

本轮实现按 P0-P3 分层推进:

#### P0 稳定性层

目标:

- 修复并发日志序号冲突
- 修复 agent 事件串线
- 提高事件顺序确定性

#### P1 采集层

目标:

- 旁路采集 hooks 原始事件
- 接入 `statusLine`
- 不影响原有门禁和主编排逻辑

#### P2 聚合层

目标:

- 将 raw hooks、statusLine、legacy events、transcript 聚合成统一 journal
- 通过 HTTP/WS 对 GUI 暴露结构化事件流

#### P3 GUI 层

目标:

- 将 GUI 从“只看 hooks 日志”升级为“统一工作台”
- 同时展示 transcript、tool trace、原始抓包、运行时遥测

## 6. 已完成实现

以下内容为本轮已经落地的实现状态。

### 6.1 P0: 稳定性与确定性

关键文件:

- `plugins/spec-autopilot/scripts/_common.sh`
- `plugins/spec-autopilot/scripts/auto-emit-agent-dispatch.sh`
- `plugins/spec-autopilot/scripts/auto-emit-agent-complete.sh`
- `plugins/spec-autopilot/scripts/emit-tool-event.sh`

已完成内容:

- 新增会话级 `sanitize_session_key`
- 新增 session-scoped agent marker 读取
- `next_event_sequence()` 改为有界重试锁，降低并发重复/乱序风险
- 优先用 session-scoped agent marker 关联工具事件，避免并行 agent 串线

### 6.2 P1: 采集层

关键文件:

- `plugins/spec-autopilot/scripts/capture-hook-event.sh`
- `plugins/spec-autopilot/scripts/statusline-collector.sh`
- `plugins/spec-autopilot/hooks/hooks.json`

已完成内容:

- hooks 原始 stdin 会落盘到:
  - `logs/sessions/<session>/raw/hooks.jsonl`
- `statusLine` 原始 JSON 会落盘到:
  - `logs/sessions/<session>/raw/statusline.jsonl`
- 会话元信息会写入:
  - `logs/sessions/<session>/meta.json`
- hooks 采集为旁路追加，不替换原有门禁脚本
- 已覆盖事件:
  - `PreToolUse`
  - `PostToolUse`
  - `PreCompact`
  - `PostCompact`
  - `UserPromptSubmit`
  - `Stop`
  - `SubagentStart`
  - `SubagentStop`
  - `SessionStart`
  - `SessionEnd`

### 6.3 P2: 聚合层

关键文件:

- `plugins/spec-autopilot/scripts/autopilot-server.ts`

已完成内容:

- 兼容 legacy `logs/events.jsonl`
- 聚合 raw hooks / statusLine / transcript
- 输出统一 journal:
  - `logs/sessions/<session>/journal/events.jsonl`
- 归一化事件类型包括:
  - `tool_use`
  - `status_snapshot`
  - `transcript_message`
  - `session_start`
  - `session_end`
  - `session_stop`
  - `compact_start`
  - `compact_end`
  - `user_prompt`
  - `subagent_start`
  - `subagent_stop`
- `/api/info` 会暴露当前 session、journalPath、telemetryAvailable、transcriptAvailable
- `/api/raw?kind=hooks|statusline` 可以直接查看原始采集
- 事件推送采用 `watch + poll` 双保险，而不是只依赖 `fs.watch`

### 6.4 P3: GUI 层

关键文件:

- `plugins/spec-autopilot/gui/src/App.tsx`
- `plugins/spec-autopilot/gui/src/store/index.ts`
- `plugins/spec-autopilot/gui/src/components/LogWorkbench.tsx`
- `plugins/spec-autopilot/gui/src/components/TranscriptPanel.tsx`
- `plugins/spec-autopilot/gui/src/components/ToolTracePanel.tsx`
- `plugins/spec-autopilot/gui/src/components/RawInspectorPanel.tsx`
- `plugins/spec-autopilot/gui/src/components/VirtualTerminal.tsx`
- `plugins/spec-autopilot/gui/src/components/TelemetryDashboard.tsx`

已完成内容:

- 中间工作区改为 Kanban + LogWorkbench
- 增加 transcript 面板
- 增加 tool trace 面板
- 增加 raw inspector 面板
- Store 改为基于 `event_id` / fallback signature 去重
- 新增 `latestStatus`
- 扩展 `VirtualTerminal` 支持更多事件类型和过滤器
- 遥测面板展示:
  - model
  - cwd
  - cost
  - worktree
  - transcript_path

## 7. statusLine 接入结论

用户特别强调:

- `statusLine` 代码已实现，但不能停留在“还需要手工配置 Claude Code”这个阶段
- 必须把接入也完成

本轮实际完成情况:

- 新增安装脚本:
  - `plugins/spec-autopilot/scripts/install-statusline-config.sh`
- 已在当前项目执行本地安装
- 已生成:
  - `.claude/settings.local.json`
  - `.claude/statusline-autopilot.sh`
- 当前本地 `statusLine.command` 已指向 bridge 脚本
- bridge 脚本再转发到:
  - `plugins/spec-autopilot/scripts/statusline-collector.sh`

因此:

- 当前仓库已经不是“还需要用户手工配置”的状态
- `statusLine` 在当前项目中已经完成接入

## 8. 已完成的真实验证

本轮强调“先实现，再真实验证”，已经完成的验证包括:

### 8.1 类型与构建

- `cd plugins/spec-autopilot/gui && bunx tsc -p tsconfig.json`
- `cd plugins/spec-autopilot/gui && bun run build`

### 8.2 全量测试

执行命令:

```bash
bash plugins/spec-autopilot/tests/run_all.sh
```

结果:

```text
75 files, 665 passed, 0 failed
```

### 8.3 新增测试覆盖

本轮新增或补充验证的测试包括:

- `plugins/spec-autopilot/tests/test_event_sequence_concurrency.sh`
- `plugins/spec-autopilot/tests/test_raw_hook_capture.sh`
- `plugins/spec-autopilot/tests/test_statusline_collector.sh`
- `plugins/spec-autopilot/tests/test_autopilot_server_aggregation.sh`
- `plugins/spec-autopilot/tests/test_install_statusline_config.sh`

### 8.4 已更新的相关测试

- `plugins/spec-autopilot/tests/test_agent_correlation.sh`
- `plugins/spec-autopilot/tests/test_gui_store_cap.sh`
- `plugins/spec-autopilot/tests/test_session_hooks.sh`

## 9. 本轮明确不采用的方案

为了避免后续审查偏航，需要明确以下方案已被否决或搁置:

### 9.1 不采用 wrapper/PT Y 顶层接管

原因:

- 与用户当前 iTerm2 + `/autopilot` 的习惯冲突
- 对开源接入成本不友好
- 侵入性高

### 9.2 不宣称“GUI 已拿到 CLI 全量字节流”

原因:

- 当前方案基于官方生命周期能力与 transcript 聚合
- 不是基于顶层终端字节流代理
- 因此应准确表述为:
  - GUI 已获得尽量详细的结构化运行日志
  - 而不是严格复刻 CLI 上的所有 stdout/stderr 原始字节

## 10. 审查时应重点关注的问题

其他 AI 如果继续复核，建议优先关注以下方向:

### 10.1 稳定性

- session 级事件序号在高并发下是否仍可能冲突
- agent marker 是否可能在极端并行场景串线
- `watch + poll` 双通路是否可能造成重复投递或边界抖动

### 10.2 完整性

- transcript 解析是否覆盖 Claude Code 当前实际输出格式
- raw hooks 与 statusLine 的会话归档是否存在跨会话污染
- journal 聚合时是否可能丢掉晚到事件

### 10.3 GUI 一致性

- `event_id` 去重策略是否会误去重
- 高速事件流下 `VirtualTerminal` 与各面板是否保持一致
- `latestStatus` 是否始终与最新 status snapshot 对齐

### 10.4 运维与接入

- `install-statusline-config.sh` 在不同 scope 下的兼容性
- `.claude/settings.local.json`、`.claude/statusline-autopilot.sh` 的本地排除策略是否足够稳妥
- 是否需要在 GUI 中显式显示 `statusLine` 已接入/未接入

## 11. 审查入口文件

建议其他 AI 审查时优先阅读这些文件:

- `plugins/spec-autopilot/scripts/autopilot-server.ts`
- `plugins/spec-autopilot/scripts/capture-hook-event.sh`
- `plugins/spec-autopilot/scripts/statusline-collector.sh`
- `plugins/spec-autopilot/scripts/install-statusline-config.sh`
- `plugins/spec-autopilot/hooks/hooks.json`
- `plugins/spec-autopilot/gui/src/App.tsx`
- `plugins/spec-autopilot/gui/src/store/index.ts`
- `plugins/spec-autopilot/gui/src/components/LogWorkbench.tsx`
- `plugins/spec-autopilot/gui/src/components/TranscriptPanel.tsx`
- `plugins/spec-autopilot/gui/src/components/ToolTracePanel.tsx`
- `plugins/spec-autopilot/gui/src/components/RawInspectorPanel.tsx`
- `plugins/spec-autopilot/gui/src/components/VirtualTerminal.tsx`
- `plugins/spec-autopilot/gui/src/components/TelemetryDashboard.tsx`

## 12. 当前结论

本轮结论不是“做了一个日志功能”，而是:

- 在不接管 Claude Code 顶层进程的情况下
- 基于 Claude Code 官方能力与低侵入旁路采集
- 为 `spec-autopilot` 建立了一条更稳定、可审计、可聚合、可视化的 GUI 日志链路

并且当前已经满足:

- 不影响 `/autopilot` 既有使用方式
- 不破坏主编排逻辑
- `statusLine` 已在当前项目完成接入
- P0-P3 已落地
- 已通过真实回归验证

后续如果继续迭代，应在此基线上做增量审查，而不是回到高侵入 wrapper 接管路线。
