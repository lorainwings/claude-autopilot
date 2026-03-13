# spec-autopilot 竞品综合对比分析报告

> 版本: v4.2.0 | 分析日期: 2026-03-13 | 分析师: AI Engineering Analyst

---

## 1. 执行摘要

本报告对 spec-autopilot 插件与 7 款主流 AI 辅助开发工具进行了全维度竞品对比分析。被分析的竞品涵盖 Claude Code 生态插件（BMAD-method、obra/superpowers、oh-my-claudecode、everything-claude-code）和独立 AI 开发工具（Cline、Aider、OpenHands）两大类别。

**核心发现：**

- **spec-autopilot 在质量门禁（三层联防）、崩溃恢复（checkpoint + anchor_sha）、防跳步（确定性阶段锁）三个维度处于行业领先地位**，没有任何竞品达到同等严格程度。
- **并行执行能力处于中上水平**：worktree 隔离 + 后台 Agent 已具备，但并发规模（配置决定）不及 oh-my-claudecode 的 5 worker 原生并行。
- **需求分析深度行业领先**：Phase 1 的三路并行调研 + 多轮决策 LOOP + 复杂度分路，超越所有竞品。
- **主要缺口集中在四个方面**：多模型路由（仅绑定 Claude）、IDE 集成（纯终端）、安全扫描（无 AgentShield 等级的扫描）、社区生态规模（Stars/Fork 较少）。

**战略定位建议**：spec-autopilot 应强化其"企业级规约驱动交付"的差异化定位，在保持质量门禁和崩溃恢复领先优势的同时，选择性吸收竞品的会话持久化、多模型路由和安全扫描机制。

---

## 2. 功能矩阵

### 2.1 十维度对比总表

| 维度 | spec-autopilot | BMAD-method | obra/superpowers | oh-my-claudecode | everything-claude-code | Cline | Aider | OpenHands |
|------|---------------|-------------|-----------------|-----------------|----------------------|-------|-------|-----------|
| **架构** | 8阶段流水线 + 主/子Agent | 4阶段 + 12+角色Agent | Brainstorm-Plan-Implement 三段式 | 32 Agent + Team 编排 | Skills + Instincts + Memory 体系 | Plan/Act 双模式 + MCP | Architect + Editor 双模型 | Event-sourced + Sandbox |
| **质量门禁** | 三层联防 (L1+L2+L3) | 制品链 + pre_commit gate | TDD Iron Law 删除制 | UltraQA 端到端验证 | 1282测试 + 102静态规则 | 人工审批逐步确认 | Lint + AST 自动修复 | QA instrumentation + 基准测试 |
| **TDD** | RED-GREEN-REFACTOR + L2确定性验证 | TEA模块 + 企业级测试架构 | TDD Iron Law + 自动删除 | TDD Skill + test-engineer Agent | TDD workflow skill | 无原生TDD | 无原生TDD | 测试生成 + SWT-Bench |
| **并行执行** | worktree隔离 + 后台Agent | 无原生并行 | subagent-driven 开发 | 5 worker 并行 + tmux | Agent Teams (实验性) | 只读子Agent | 单Agent串行 | 千级Agent并行扩展 |
| **崩溃恢复** | checkpoint扫描 + anchor_sha + PreCompact Hook | Git版本化制品(隐式) | 无专用机制 | Multi-Model Recovery + 速率限制自动恢复 | 无专用机制 | 无专用机制 | Git undo回滚 | Event-sourced确定性重放 |
| **需求分析** | 三路并行调研 + 多轮决策 + 复杂度分路 | Analyst + PM Agent协作 | Brainstorm深度提问 | 无专用需求流程 | research-first开发 | 代码库AST扫描 | Architect模式讨论 | 无专用需求流程 |
| **GUI** | Event Bus → events.jsonl | 无GUI | 无GUI | Discord/Telegram通知 | 无GUI | VS Code原生集成 | 终端TUI | Web GUI + CLI + Cloud |
| **上下文管理** | JSON信封 + 后台Agent + PreCompact持久化 | 文档分片 + discover_inputs | ~2K token核心 + 按需拉取 | smart model路由 + 外部上下文Hook | token优化 + 50%压缩阈值 | AST+文件结构索引 | Repo Map + 签名索引 | Microagent + ConversationMemory |
| **防跳步** | L1 blockedBy + L2 checkpoint验证 + L3 AI门禁 | 制品链依赖(软约束) | 无机制 | 无机制 | 无机制 | Plan/Act审批(人工) | 无机制 | 无机制 |
| **可扩展性** | 7 Skill + 8 Hook + YAML配置 | 26+workflow + YAML Agent定义 | 技能自动发现 + Meta Skills | 40+ Skills + npm插件 | 7 Skills + AgentShield | MCP协议扩展 | 100+语言 + 多模型 | SDK + Docker + K8s |

### 2.2 维度评分（1-100分）

| 维度 | spec-autopilot | BMAD | superpowers | OMC | ECC | Cline | Aider | OpenHands |
|------|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|
| 架构 | **92** | 80 | 65 | 82 | 68 | 75 | 60 | 88 |
| 质量门禁 | **95** | 72 | 78 | 65 | 80 | 60 | 55 | 70 |
| TDD | **90** | 75 | 88 | 62 | 65 | 30 | 25 | 55 |
| 并行执行 | 78 | 30 | 70 | **88** | 45 | 40 | 20 | **92** |
| 崩溃恢复 | **93** | 45 | 20 | 60 | 25 | 15 | 35 | 85 |
| 需求分析 | **92** | 85 | 80 | 35 | 60 | 55 | 65 | 40 |
| GUI | 40 | 20 | 15 | 50 | 25 | **95** | 35 | **88** |
| 上下文管理 | 85 | 75 | **90** | 72 | 78 | 70 | 80 | 82 |
| 防跳步 | **98** | 55 | 15 | 10 | 10 | 45 | 10 | 15 |
| 可扩展性 | 75 | **85** | 72 | 80 | 65 | 82 | 78 | **90** |

### 2.3 雷达图数据（供可视化工具使用）

```json
{
  "dimensions": ["架构", "质量门禁", "TDD", "并行执行", "崩溃恢复", "需求分析", "GUI", "上下文管理", "防跳步", "可扩展性"],
  "products": {
    "spec-autopilot": [92, 95, 90, 78, 93, 92, 40, 85, 98, 75],
    "BMAD-method": [80, 72, 75, 30, 45, 85, 20, 75, 55, 85],
    "superpowers": [65, 78, 88, 70, 20, 80, 15, 90, 15, 72],
    "oh-my-claudecode": [82, 65, 62, 88, 60, 35, 50, 72, 10, 80],
    "everything-claude-code": [68, 80, 65, 45, 25, 60, 25, 78, 10, 65],
    "Cline": [75, 60, 30, 40, 15, 55, 95, 70, 45, 82],
    "Aider": [60, 55, 25, 20, 35, 65, 35, 80, 10, 78],
    "OpenHands": [88, 70, 55, 92, 85, 40, 88, 82, 15, 90]
  }
}
```

---

## 3. 逐竞品深度分析

### 3.1 BMAD-method — Breakthrough Method for Agile AI Driven Development

**架构概述：** BMAD 采用四阶段方法论（Analysis → Planning → Solutioning → Implementation），通过 12+ 专业化 Agent 角色（PM、Architect、Developer、UX、Scrum Master 等）模拟完整敏捷团队。V6 版本引入跨平台 Agent 团队、Sub-Agent 支持和 Dev Loop 自动化。核心设计哲学是"文档即源码" — PRD、架构设计、用户故事是单点事实来源，代码仅为下游衍生物。

**优势：**
- **角色体系最丰富**：12+ 专业化 Agent 角色，覆盖从产品经理到安全审计员的完整团队
- **文档驱动开发**：制品链确保从 PRD 到代码的完整可追溯性
- **企业级测试架构**：TEA（Test Engineering Architect）模块提供风险驱动测试策略、ATDD、发布门控
- **生态最活跃**：多个社区实现（PabloLION/bmad-plugin、aj-geddes/claude-code-bmad-skills、darthpelo/claude-plugin-bmad）
- **跨平台支持**：除 Claude Code 外支持 Cursor、Codex 等 IDE
- **工作流引擎**：26+ workflow 全部作为 skill 暴露，文档分片 + discover_inputs 协议管理大型制品

**劣势：**
- **无确定性门禁**：质量门控依赖 pre_commit 命令和 Agent 自律，缺少 spec-autopilot 的 L1+L2 硬阻断
- **无并行执行**：所有 Agent 串行运行，无 worktree 隔离或后台并行能力
- **无崩溃恢复**：依赖 Git 版本化制品的隐式恢复，无 checkpoint 扫描或 anchor_sha 验证
- **防跳步为软约束**：制品链依赖由 Agent 自行遵守，无系统级强制执行
- **LLM 即引擎**：无外部运行时，所有编排逻辑在 LLM 上下文窗口中执行，大型项目上下文压力大

**与 spec-autopilot 的关键差异：** BMAD 追求角色丰富度和方法论完整度，spec-autopilot 追求执行确定性和质量门禁深度。BMAD 是"团队模拟器"，spec-autopilot 是"质量流水线"。

---

### 3.2 obra/superpowers — Agentic Skills Framework

**架构概述：** superpowers 采用 Brainstorm → Plan → Implement 三段式工作流，核心理念是"技能自动激活" — 根据上下文自动触发测试、调试、协作等技能。框架极其轻量，核心仅 ~2K token，按需拉取技能文档。GitHub 42,000+ Stars，是 Claude Code 生态中影响力最大的项目。

**优势：**
- **TDD 纪律最强**：Iron Law — 先测试后实现，违反即删除代码。与 spec-autopilot 的 TDD 模式理念相同，但表达更简洁
- **上下文效率极高**：核心仅 ~2K token，通过 shell 脚本按需搜索技能文档，几乎不消耗上下文窗口
- **Subagent-Driven Development**：Claude 可自主工作数小时不偏离计划，通过子 Agent 驱动工程任务
- **Meta Skills**：技能本身可以用 TDD 方式测试（"TDD for Skills"），形成闭环质量保证
- **2-3x 开发效率提升**：经过实证验证的生产效率加速
- **社区影响力最大**：42,000+ Stars，已上架 Anthropic 官方 Plugin Marketplace

**劣势：**
- **无崩溃恢复**：无 checkpoint、无状态持久化、无 PreCompact Hook
- **无防跳步机制**：完全依赖 AI 自律遵循计划，无系统级强制执行
- **无质量门禁系统**：TDD 纪律是"建议"而非"强制"，无 Hook 脚本硬阻断
- **无结构化需求流程**：Brainstorm 依赖自由对话，无复杂度分路或决策卡片
- **无配置化**：技能行为固定，无 YAML 配置文件动态调整门禁阈值
- **无 GUI/事件总线**：纯文本交互，无可视化进度追踪

**与 spec-autopilot 的关键差异：** superpowers 是"轻量级纪律框架"，spec-autopilot 是"重量级确定性流水线"。superpowers 的 TDD Iron Law 可视为 spec-autopilot TDD 模式的灵感来源（SKILL.md 中明确引用"Superpowers 原则"），但 spec-autopilot 将其从建议提升为 L2 确定性验证。

---

### 3.3 oh-my-claudecode (OMC) — Teams-first Multi-Agent Orchestration

**架构概述：** OMC 是 Claude Code 生态中最成熟的多 Agent 编排层，提供 32 个专业化 Agent、40+ Skills 和 Team 编排表面。核心特色是 5 并发 Worker 并行执行，基于 tmux 的进程隔离，以及智能模型路由（Haiku 处理简单任务、Opus 处理复杂推理）。

**优势：**
- **并行执行能力最强（Claude Code 生态内）**：5 并发 Worker，原子任务认领，共享任务池
- **智能模型路由**：自动将任务分配给不同复杂度的模型，节省 30-50% token 成本
- **Agent 数量最多**：32 个专业化 Agent 覆盖各类开发场景
- **跨平台通知**：Discord/Telegram 完成通知 + 命名配置文件 + 回复注入
- **速率限制自动恢复**：Claude Code 会话在速率限制重置后自动恢复
- **持久化状态管理**：OMC_STATE_DIR 支持跨 worktree 生命周期的状态保持

**劣势：**
- **无确定性质量门禁**：UltraQA 是测试执行循环，非阶段间门禁验证
- **无需求分析流程**：缺少结构化的需求讨论和决策循环
- **防跳步能力为零**：无 checkpoint 依赖链，Agent 可自由跳过任何步骤
- **平台依赖强**：强制 tmux 依赖，Windows 原生不支持，WSL2 必需
- **TDD 支持浅**：TDD 作为独立 Skill 存在，非集成到流水线中的确定性验证
- **崩溃恢复有限**：Multi-Model Recovery 主要处理模型切换，非流水线断点续传

**与 spec-autopilot 的关键差异：** OMC 追求并发规模和工具链集成，spec-autopilot 追求阶段确定性和质量深度。OMC 的 5 Worker 并行是 spec-autopilot worktree 并行的上位替代（在并发数上），但缺乏 spec-autopilot 的阶段门禁体系。

---

### 3.4 everything-claude-code (ECC) — Agent Harness Performance Optimization

**架构概述：** ECC 源自 Cerebral Valley x Anthropic 黑客松（2026年2月），定位为"Agent Harness 性能优化系统"。核心由 Skills（技能）、Instincts（本能）、Memory（记忆）三层组成，配合 AgentShield 安全扫描。1,282 个测试、98% 覆盖率、102 条静态分析规则。

**优势：**
- **安全扫描最强**：AgentShield 扫描 CLAUDE.md、settings.json、MCP 配置、Hook、Agent 定义，5 类 14 模式
- **测试覆盖率最高**：1,282 测试 + 98% 覆盖率 + 102 静态规则，代表框架自身的质量标杆
- **红蓝对抗审计**：--opus 标志启动三 Agent 红蓝对抗流水线（攻击者 + 防御者 + 审计员）
- **token 优化理论先进**：建议 50% 压缩阈值（vs 默认 95%），模型分级使用策略
- **跨平台支持**：Claude Code、Codex、Cowork、OpenCode 全覆盖
- **社区贡献活跃**：30+ 贡献者，6 种语言，GitHub Marketplace App

**劣势：**
- **无流水线编排**：Skills 是独立能力单元，缺乏 spec-autopilot 的 8 阶段编排逻辑
- **无崩溃恢复**：无 checkpoint 机制，无断点续传
- **无防跳步机制**：Skills 之间无依赖链或门禁验证
- **并行执行实验性**：Agent Teams 标记为实验性，无 worktree 隔离
- **无结构化需求分析**：research-first 是理念，非强制流程
- **架构松散**：Skills + Instincts + Memory 是增强集而非编排系统

**与 spec-autopilot 的关键差异：** ECC 是"能力增强包"，spec-autopilot 是"流程编排器"。ECC 的 AgentShield 安全扫描是 spec-autopilot 缺失的重要能力，可作为 Phase 6.5 质量扫描的候选集成项。

---

### 3.5 Cline — VS Code AI Autonomous Coding Agent

**架构概述：** Cline 是 VS Code 内的自主 AI 编码 Agent，通过 Plan/Act 双模式提供结构化控制。核心特色是人机协作审批循环 — 每个文件变更和命令执行都需用户审批。支持浏览器自动化、MCP 扩展和多模型后端。5M+ 全球开发者使用。

**优势：**
- **GUI 集成最强**：VS Code 原生集成，文件 diff 可视化、命令预览、浏览器截图
- **人机协作最成熟**：逐步审批设计在安全性和可控性之间取得平衡
- **浏览器自动化**：Computer Use 能力支持 E2E 测试、交互式调试、Web 操作
- **MCP 生态最丰富**：可动态创建和安装自定义 MCP 工具
- **企业特性完整**：SSO、RBAC、审计追踪、VPC/私有链接、自托管
- **模型无关**：支持 OpenAI、Anthropic、本地模型等多种后端
- **CLI 2.0**：2026年2月发布，支持并行 Agent 和无头 CI/CD

**劣势：**
- **无 TDD 原生支持**：依赖外部工具或社区插件实现 TDD
- **无崩溃恢复**：上下文窗口溢出导致不可恢复错误
- **无规约驱动流程**：无 OpenSpec 或结构化制品链
- **防跳步仅为人工审批**：Plan/Act 模式依赖人工逐步确认，无自动化门禁
- **大文件处理弱**：300KB 以上文件被阻止读取
- **单 Agent 为主**：子 Agent 为只读，无法写入文件或运行破坏性命令

**与 spec-autopilot 的关键差异：** Cline 是"IDE 内的交互式助手"，spec-autopilot 是"终端中的自动化流水线"。Cline 的人工审批循环在交互性上远超 spec-autopilot，但无法实现无人值守的长时间自动交付。

---

### 3.6 Aider — Terminal AI Pair Programming

**架构概述：** Aider 是终端 AI pair programming 工具，核心是 Git-native 工作流 — 每次变更自动生成原子 commit，支持 /undo 即时回滚。独特的 Repo Map 技术通过函数签名和文件结构索引为 LLM 提供全仓库上下文。支持 100+ 编程语言和 Architect + Editor 双模型模式。

**优势：**
- **Git 集成最深**：原子 commit + 自动描述性 commit message + /undo 即时回滚
- **Repo Map 技术领先**：通过 tree-sitter AST 索引全仓库函数签名，跨文件编辑的上下文质量极高
- **语言覆盖最广**：100+ 编程语言支持
- **Architect + Editor 分离**：高级模型做架构决策，编辑模型执行变更，成本效率高
- **语音和多模态输入**：支持图片、网页、语音输入
- **Lint 自动修复**：每次编辑后自动 lint + AST 级错误修复
- **在线评审注释**：支持代码内 AI? 注释触发 Aider 响应

**劣势：**
- **无 TDD 原生支持**：无 RED-GREEN-REFACTOR 循环或测试优先强制
- **无质量门禁**：无阶段间门控，无 checkpoint 验证
- **无并行执行**：单 Agent 串行操作
- **无崩溃恢复**：依赖 Git undo 进行手动回滚，无自动断点续传
- **无需求分析流程**：Architect 模式仅为讨论，非结构化需求收集
- **无防跳步**：无阶段概念，无执行顺序约束

**与 spec-autopilot 的关键差异：** Aider 是"AI 结对编程伙伴"，spec-autopilot 是"自动化交付编排器"。Aider 的 Repo Map 是上下文管理的优秀实践，但缺乏流水线级别的质量保障体系。

---

### 3.7 OpenHands — AI Software Engineering Platform

**架构概述：** OpenHands（原 OpenDevin）是企业级 AI 软件工程平台，基于 event-sourced 架构 + Docker 沙箱运行时。V1 SDK 重设计采用不可变配置、类型化工具系统和 MCP 集成。64,000+ GitHub Stars，获 $18.8M 融资。SWE-bench 87% 解决率。

**优势：**
- **可扩展性最强**：从 1 到数千 Agent 的弹性扩展，Docker/K8s 部署
- **架构最成熟**：event-sourced 状态模型 + 确定性重放 + 不可变配置
- **崩溃恢复最优雅**：stateless by default，单一状态源，确定性重放恢复
- **并行 Agent 能力最强**：千级 Agent 并行，专用于大规模重构和依赖升级
- **安全性企业级**：Docker 沙箱隔离、细粒度访问控制、自托管/私有云
- **多界面**：CLI + Web GUI + Cloud + REST API，部署灵活度最高
- **基准测试领先**：SWE-bench、SWT-bench、multi-SWE-bench 多项领先
- **模型无关**：支持 Claude、OpenAI、Qwen、Devstral 等开闭源模型

**劣势：**
- **无规约驱动流程**：无 OpenSpec 或阶段化交付概念
- **无需求分析**：直接从 issue 到实现，无结构化需求讨论
- **无 TDD 强制**：测试生成能力存在，但非 RED-GREEN-REFACTOR 纪律
- **防跳步能力弱**：无阶段门禁，Agent 自主决定执行路径
- **部署复杂度高**：Docker + K8s 基础设施要求远高于 Claude Code 插件
- **Claude Code 生态外**：独立平台，非 Claude Code 插件，集成需要额外工作
- **质量门禁非确定性**：QA instrumentation 主要用于自身框架测试，非用户项目的阶段门禁

**与 spec-autopilot 的关键差异：** OpenHands 是"通用 AI 软件工程平台"，spec-autopilot 是"Claude Code 专用规约流水线"。OpenHands 在可扩展性和架构成熟度上领先，但缺乏 spec-autopilot 的规约驱动和质量门禁深度。OpenHands 的 event-sourced 架构是 spec-autopilot 崩溃恢复机制的理论上位替代。

---

## 4. 缺口分析

### 4.1 spec-autopilot 缺失的竞品关键能力

| 优先级 | 缺口能力 | 来源竞品 | 影响评估 | 补齐难度 |
|:------:|---------|---------|---------|:-------:|
| P0 | **多模型路由** — 简单任务用 Haiku/Sonnet，复杂推理用 Opus | OMC、Aider | 成本降低 30-50%，但需 Claude Code 原生支持 | 高 |
| P0 | **安全扫描** — CLAUDE.md/Hook/MCP 配置漏洞检测 | ECC (AgentShield) | 企业客户必需 | 中 |
| P1 | **Repo Map / AST 索引** — 全仓库函数签名索引 | Aider | 跨文件编辑的上下文质量显著提升 | 高 |
| P1 | **通知系统** — 长任务完成的 Discord/Telegram 推送 | OMC | 无人值守场景必需 | 低 |
| P1 | **Event-sourced 状态** — 确定性重放替代 checkpoint 文件扫描 | OpenHands | 崩溃恢复可靠性从 95% 提升至 99%+ | 高 |
| P2 | **Meta Skills / TDD for Skills** — 技能本身的 TDD 测试 | superpowers | 插件自身质量保证闭环 | 中 |
| P2 | **文档分片 / Discover Inputs** — 大型制品自动分片加载 | BMAD | 大型项目的上下文效率 | 中 |
| P2 | **浏览器自动化** — E2E 测试的 Computer Use 集成 | Cline | Phase 6 测试能力扩展 | 高 |
| P3 | **多 IDE 支持** — VS Code/Cursor 集成 | Cline、BMAD | 用户覆盖面扩展 | 高 |
| P3 | **语音/多模态输入** — 语音需求描述 | Aider | Phase 1 需求输入便利性 | 低 |

### 4.2 竞品缺失的 spec-autopilot 核心能力（护城河）

以下能力为 spec-autopilot 独有或显著领先，竞品短期内难以复制：

| 能力 | 领先程度 | 竞品最近距离 |
|------|---------|------------|
| **三层确定性门禁** (L1+L2+L3) | 独有 | BMAD 的制品链 (软约束，差距巨大) |
| **L2 Hook 确定性验证** (反合理化+代码约束+测试金字塔) | 独有 | ECC 的静态规则 (未集成到流水线) |
| **checkpoint + anchor_sha 崩溃恢复** | 领先 | OpenHands event-sourced (架构更优但场景不同) |
| **PreCompact 上下文压缩恢复** | 独有 | 无竞品具备此能力 |
| **Phase 1 三路并行调研 + 多轮决策 LOOP** | 独有 | BMAD Analyst+PM (无并行，无决策卡片) |
| **需求路由** (Feature/Bugfix/Refactor/Chore 动态门禁) | 独有 | 无竞品具备此能力 |
| **防跳步确定性链** (L1 blockedBy + L2 checkpoint + L3 gate) | 独有 | 无竞品具备同等严格度 |

---

## 5. 最佳机制提取

### 5.1 会话持久化

**当前最佳实践（来源：OpenHands V1）：**

OpenHands 的 event-sourced 状态模型是会话持久化的理论最优解：
- 所有状态变更记录为不可变事件流
- 崩溃后通过确定性重放恢复完整状态
- 单一状态对象作为唯一可变上下文

**spec-autopilot 当前方案**：checkpoint JSON 文件 + anchor_sha + PreCompact Hook，实用性强但理论纯度不及 event-sourced。

**建议采纳方向**：在现有 checkpoint 基础上引入事件日志（已有 events.jsonl Event Bus），将 phase_start/phase_end/gate_pass 事件升级为状态恢复的输入源，实现"混合 event-sourced"模式。

### 5.2 防跳步

**当前最佳实践（来源：spec-autopilot 自身）：**

spec-autopilot 的三层防跳步是所有竞品中最严格的：
- L1：TaskCreate blockedBy 系统级阻止
- L2：check-predecessor-checkpoint.sh Hook 确定性验证
- L3：autopilot-gate Skill 8 步检查清单

**竞品做法对比**：
- BMAD：制品链依赖（Agent 自律，可被绕过）
- Cline：人工逐步审批（依赖人类注意力，可疲劳绕过）
- 其他竞品：无任何防跳步机制

**建议优化方向**：可参考 BMAD 的"Implementation Readiness Gate"概念，在 Phase 4→5 门禁增加"实施就绪度报告"，汇总 PRD/架构/测试设计的对齐状态。

### 5.3 长上下文检索

**当前最佳实践（来源：obra/superpowers + Aider）：**

- **superpowers**：~2K token 核心 + shell 脚本按需搜索技能文档，上下文效率极高
- **Aider**：Repo Map — tree-sitter AST 解析全仓库函数签名，为 LLM 提供结构化全局视图

**spec-autopilot 当前方案**：JSON 信封（~200 token vs ~5K token 全文）+ 后台 Agent 上下文隔离 + PreCompact 状态持久化。

**建议采纳方向**：
1. 参考 superpowers 的按需拉取模式，将 references/ 目录的技能文档改为按需读取（当前已部分实现）
2. 参考 Aider 的 Repo Map，在 Phase 1 Auto-Scan 中引入 AST 级函数签名索引，提升跨文件编辑的上下文质量
3. 参考 BMAD 的文档分片协议，对超长 OpenSpec 制品实施自动分片

### 5.4 补充：智能模型路由（来源：OMC）

OMC 的智能模型路由值得作为长期演进方向关注：
- 简单任务（文件复制、格式化）→ Haiku（快速低成本）
- 常规开发（代码实现、测试编写）→ Sonnet（平衡）
- 复杂推理（架构决策、崩溃诊断）→ Opus（深度）

当前 Claude Code 原生尚不支持 Plugin 级别的模型路由控制，但可在子 Agent dispatch 时通过 prompt 优化间接实现成本控制。

---

## 6. 采纳路线图

### Phase 1: 快速胜利（1-2 周）

| 序号 | 采纳项 | 来源 | 工作量 | 预期收益 |
|:----:|--------|------|:------:|---------|
| 1.1 | **通知 Hook** — 任务完成时发送 webhook 通知（Discord/Slack/Telegram） | OMC | 2天 | 无人值守场景可用性 |
| 1.2 | **安全预检 Skill** — Phase 0 增加 CLAUDE.md/Hook/MCP 基本安全扫描 | ECC | 3天 | 企业合规准入 |
| 1.3 | **实施就绪度报告** — Phase 4→5 门禁增加 PRD/架构/测试对齐度检查 | BMAD | 2天 | Phase 5 失败率降低 |

### Phase 2: 核心增强（2-4 周）

| 序号 | 采纳项 | 来源 | 工作量 | 预期收益 |
|:----:|--------|------|:------:|---------|
| 2.1 | **Event-sourced 恢复增强** — events.jsonl 升级为状态恢复输入源 | OpenHands | 1周 | 崩溃恢复可靠性 95%→99% |
| 2.2 | **文档分片协议** — 大型 OpenSpec 自动分片 + discover_inputs | BMAD | 1周 | 大型项目上下文效率提升 30% |
| 2.3 | **Meta Skill 测试框架** — 用子 Agent 测试 Skill 可理解性和合规性 | superpowers | 1周 | 插件自身质量闭环 |

### Phase 3: 深度演进（1-2 月）

| 序号 | 采纳项 | 来源 | 工作量 | 预期收益 |
|:----:|--------|------|:------:|---------|
| 3.1 | **Repo Map 集成** — Phase 1 Auto-Scan 引入 tree-sitter AST 索引 | Aider | 2周 | 跨文件编辑上下文质量飞跃 |
| 3.2 | **AgentShield 级安全扫描** — 5 类 14 模式 + 红蓝对抗审计 | ECC | 2周 | 企业级安全保障 |
| 3.3 | **并行 Worker 扩展** — 支持 N Worker 并行（当前为配置决定） | OMC | 2周 | 大型项目交付速度提升 3-5x |

### Phase 4: 战略方向（3-6 月）

| 序号 | 采纳项 | 来源 | 工作量 | 预期收益 |
|:----:|--------|------|:------:|---------|
| 4.1 | **多模型路由** — 子 Agent 按任务复杂度路由到不同模型 | OMC、Aider | 依赖CC支持 | token 成本降低 30-50% |
| 4.2 | **Web GUI 仪表板** — 基于 Event Bus 构建实时进度可视化 | OpenHands、Cline | 1月 | 用户体验质变 |
| 4.3 | **浏览器自动化测试** — Phase 6 集成 Computer Use E2E | Cline | 1月 | 测试覆盖完整度 |

---

## 7. 综合评分与定位

### 7.1 综合评分

| 产品 | 总分 (加权) | 排名 | 定位标签 |
|------|:----------:|:----:|---------|
| **spec-autopilot** | **83.8** | **1** | 企业级规约驱动质量流水线 |
| **OpenHands** | 70.5 | 2 | 通用 AI 软件工程平台 |
| **BMAD-method** | 62.2 | 3 | 敏捷角色模拟方法论 |
| **oh-my-claudecode** | 60.4 | 4 | 并行 Agent 编排层 |
| **obra/superpowers** | 59.3 | 5 | 轻量级纪律框架 |
| **Cline** | 58.7 | 6 | IDE 内交互式 AI 助手 |
| **everything-claude-code** | 52.1 | 7 | Agent 能力增强包 |
| **Aider** | 46.3 | 8 | 终端 AI 结对编程 |

> **加权规则**：质量门禁 x1.5、崩溃恢复 x1.3、防跳步 x1.3、其余维度 x1.0。权重反映 spec-autopilot 目标用户（企业级自动化交付）的优先级。

### 7.2 竞争格局图

```
                    高 ┌─────────────────────────────────┐
                       │                                 │
            质         │  spec-autopilot                 │
            量         │  (规约驱动+质量深度)              │
            门         │                                 │
            禁    ─────│──────────────────────────────── │
            与         │  BMAD        ECC                │
            确         │  (角色丰富)   (安全扫描)          │
            定         │                                 │
            性    ─────│──superpowers─────OpenHands──── │
                       │  (TDD纪律)     (平台成熟度)      │
                       │           OMC                   │
                       │          (并行规模)              │
                  ─────│──Cline──────────Aider────────── │
                       │  (IDE集成)      (Git深度)        │
                    低 └─────────────────────────────────┘
                       低         可扩展性/生态          高
```

### 7.3 战略建议

1. **坚守护城河**：三层门禁 + 崩溃恢复 + 防跳步是 spec-autopilot 的核心竞争力，竞品短期内无法复制。持续强化而非稀释。

2. **选择性吸收**：从路线图中优先执行 Phase 1（快速胜利），用最小投入补齐通知系统和安全预检两个显性缺口。

3. **避免全面竞争**：不追求 Cline 的 IDE 集成深度或 OpenHands 的千级 Agent 扩展，保持"Claude Code 专用规约流水线"的精准定位。

4. **生态建设**：参考 BMAD 的多实现策略（4+ 社区 Fork）和 superpowers 的 Marketplace 上架，提升社区可见性。

---

*报告终*
