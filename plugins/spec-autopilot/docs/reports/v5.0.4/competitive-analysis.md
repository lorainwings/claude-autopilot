# v5.0.4 竞品综合对比报告

> 版本: v5.0.4 | 分析日期: 2026-03-13 | 分析师: AI Engineering Analyst (Agent 4)

---

## 1. 执行摘要

本报告对 spec-autopilot 插件（v4.2.0）与 **10 款**主流 Vibe Coding 工具进行全方位对比分析，覆盖 Claude Code 生态插件（Tier 1）、独立 Agent（Tier 2）和企业 IDE（Tier 3）三个层次。相较 v5.0 报告新增 Cursor 和 Windsurf 两个 Tier 3 竞品。

**核心发现：**

1. **spec-autopilot 在需求工程、规约生成、质量门禁、状态持久化四个维度仍处于行业领先**，三层确定性门禁（L1+L2+L3）和 checkpoint + anchor_sha 崩溃恢复在所有竞品中独一无二。
2. **并行执行差距扩大**：OpenHands 千级 Agent、OMC 5 Worker + Teams 编排、Cursor Background Agent 均已超越 spec-autopilot 的 worktree 并行。
3. **GUI 可视化是最大短板**：Cursor 和 Windsurf 的原生 IDE 体验、Cline 的 VS Code 集成、OpenHands 的 Web GUI 均远超 spec-autopilot 的 events.jsonl 文本日志。
4. **社区生态规模差距显著**：superpowers 81K Stars、OpenHands 65K Stars、Cline 59K Stars、ECC 50K Stars、Aider 42K Stars、BMAD 39K Stars，spec-autopilot 作为新晋插件需要加速生态建设。
5. **Tier 3 企业 IDE（Cursor/Windsurf）在代码生成和学习曲线上具有碾压优势**，但在需求工程、规约生成、测试自动化、质量门禁等 spec-autopilot 核心能力上几乎为零。

**战略结论**：spec-autopilot 的差异化定位 --"企业级规约驱动质量流水线"-- 在 2026 年 3 月的竞争格局中依然成立且更加稀缺。大量竞品在"让 AI 写代码"维度高度同质化，而在"保证 AI 写对代码"维度仍几乎空白。

---

## 2. 竞品能力矩阵（评分表）

### 2.1 十二维度评分（1-10 分）

| 维度 | spec-autopilot | BMAD | superpowers | OMC | ECC | Cline | Aider | OpenHands | Cursor | Windsurf |
|------|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|
| **需求工程** | **9** | 8 | 7 | 4 | 5 | 5 | 6 | 4 | 3 | 3 |
| **规约生成** | **9** | 8 | 6 | 3 | 4 | 2 | 2 | 3 | 2 | 2 |
| **代码生成** | 7 | 6 | 7 | 7 | 6 | 8 | 8 | 8 | **9** | **9** |
| **测试自动化** | **9** | 7 | 8 | 6 | 6 | 4 | 5 | 5 | 4 | 4 |
| **质量门禁** | **10** | 6 | 7 | 5 | 7 | 5 | 4 | 6 | 3 | 3 |
| **并行执行** | 7 | 3 | 6 | 8 | 4 | 4 | 2 | **9** | 7 | 6 |
| **状态持久化** | **9** | 4 | 2 | 5 | 2 | 2 | 3 | 8 | 5 | 5 |
| **长上下文** | 8 | 7 | **9** | 6 | 7 | 6 | 8 | 7 | 8 | 8 |
| **GUI 可视化** | 3 | 2 | 1 | 4 | 2 | **9** | 3 | 8 | **9** | **9** |
| **扩展性** | 7 | 8 | 7 | 7 | 6 | 8 | 7 | **9** | 7 | 7 |
| **社区生态** | 2 | 7 | **9** | 5 | 8 | 8 | 7 | 8 | **9** | 8 |
| **学习曲线** | 4 | 5 | 7 | 6 | 5 | 8 | 7 | 5 | **9** | **9** |
| **总分（均分）** | **7.0** | 5.9 | 6.3 | 5.4 | 5.2 | 5.7 | 5.2 | 6.7 | 6.3 | 6.1 |
| **加权总分** | **7.6** | 6.2 | 6.5 | 5.4 | 5.5 | 5.4 | 5.0 | 6.5 | 5.6 | 5.4 |

> **加权规则**：需求工程 x1.3、规约生成 x1.3、质量门禁 x1.5、状态持久化 x1.3、测试自动化 x1.2，其余 x1.0。权重反映 spec-autopilot 目标用户场景（企业级自动化交付）的优先级。

### 2.2 竞品 GitHub Star 数一览（截至 2026-03-13）

| 竞品 | GitHub Stars | 趋势 |
|------|:-----------:|------|
| obra/superpowers | ~81K | 急速增长，3 月达 81K，但近期遭遇 Marketplace 兼容性问题 |
| OpenHands | ~65K | 稳步增长，Series A $18.8M 融资加速 |
| Cline | ~59K | 稳定增长，5M+ VS Code 安装 |
| everything-claude-code | ~50K | 爆发式增长，9 天 31.9K Stars |
| Aider | ~42K | 稳定增长，1170+ 贡献者 |
| BMAD-METHOD | ~39K | 稳步增长，V6 发布 + 4+ 社区 Fork |
| oh-my-claudecode | N/A (活跃) | 频繁发布，v4.1.7 Teams 重构 |
| Cursor | 非开源 | 企业产品，$20-200/月 |
| Windsurf | 非开源 | 被 Cognition AI $250M 收购 |

### 2.3 雷达图数据（供可视化工具使用）

```json
{
  "dimensions": ["需求工程", "规约生成", "代码生成", "测试自动化", "质量门禁", "并行执行", "状态持久化", "长上下文", "GUI可视化", "扩展性", "社区生态", "学习曲线"],
  "products": {
    "spec-autopilot": [9, 9, 7, 9, 10, 7, 9, 8, 3, 7, 2, 4],
    "BMAD-method":    [8, 8, 6, 7, 6, 3, 4, 7, 2, 8, 7, 5],
    "superpowers":    [7, 6, 7, 8, 7, 6, 2, 9, 1, 7, 9, 7],
    "OMC":            [4, 3, 7, 6, 5, 8, 5, 6, 4, 7, 5, 6],
    "ECC":            [5, 4, 6, 6, 7, 4, 2, 7, 2, 6, 8, 5],
    "Cline":          [5, 2, 8, 4, 5, 4, 2, 6, 9, 8, 8, 8],
    "Aider":          [6, 2, 8, 5, 4, 2, 3, 8, 3, 7, 7, 7],
    "OpenHands":      [4, 3, 8, 5, 6, 9, 8, 7, 8, 9, 8, 5],
    "Cursor":         [3, 2, 9, 4, 3, 7, 5, 8, 9, 7, 9, 9],
    "Windsurf":       [3, 2, 9, 4, 3, 6, 5, 8, 9, 7, 8, 9]
  }
}
```

---

## 3. 逐竞品深度分析

### 3.1 Tier 1: Claude Code 生态

#### 3.1.1 BMAD-METHOD — Breakthrough Method for Agile AI Driven Development

- **GitHub Stars**: ~39K (官方仓库) + 多个社区 Fork
- **最新版本**: V6（2026 年初）
- **核心架构**: 4 阶段方法论（Analysis - Planning - Solutioning - Implementation），12+ 专业化 Agent 角色（PM、Architect、Developer、UX、Scrum Master 等），26+ workflow 全部作为 skill 暴露

**V6 新特性**:
- Cross Platform Agent Team + Sub Agent 支持
- Skills Architecture + BMad Builder v1
- Dev Loop Automation
- Agent Teams Sprint Automation（实验性）

**优势**:
- 角色体系最丰富：12+ Agent 角色模拟完整敏捷团队
- 文档驱动开发：PRD - 架构 - 用户故事的完整制品链
- TEA 模块：风险驱动测试策略、ATDD、发布门控
- 跨平台：支持 Claude Code、Cursor、Codex
- 生态最活跃：PabloLION/bmad-plugin、aj-geddes/claude-code-bmad-skills、auto-bmad 等 4+ 社区实现

**劣势**:
- 无确定性门禁（制品链为软约束，Agent 可绕过）
- 无原生并行执行
- 无 checkpoint 崩溃恢复
- LLM 即引擎，大型项目上下文压力大

**与 spec-autopilot 差异**: BMAD 是"团队模拟器"（角色丰富度），spec-autopilot 是"质量流水线"（执行确定性）。BMAD 的制品链是 spec-autopilot OpenSpec 的灵感来源之一，但缺少 L1+L2 硬阻断。

---

#### 3.1.2 obra/superpowers — Agentic Skills Framework

- **GitHub Stars**: ~81K（Claude Code 生态第一）
- **最新状态**: 2026-03 遭遇 Marketplace 兼容性问题
- **核心架构**: Brainstorm - Plan - Implement 三段式，~2K token 核心 + 按需拉取

**关键特性**:
- TDD Iron Law：先测试后实现，违反即删除（spec-autopilot SKILL.md 明确引用"Superpowers 原则"）
- Subagent-Driven Development：Claude 可自主工作数小时
- Meta Skills：技能本身可 TDD 测试
- 上下文效率极高：核心仅 ~2K token
- 官方 Marketplace 上架（2026-01-15）

**优势**:
- 社区影响力最大（81K Stars）
- TDD 纪律表达简洁
- 上下文效率行业最优
- 2-3x 开发效率实证

**劣势**:
- 无崩溃恢复、无状态持久化
- 无防跳步机制（完全依赖 AI 自律）
- 无质量门禁系统（TDD 是建议非强制）
- 无配置化（技能行为固定）
- 近期 Marketplace 兼容性问题影响可用性

**与 spec-autopilot 差异**: superpowers 是"轻量级纪律框架"，spec-autopilot 是"重量级确定性流水线"。superpowers 的 TDD Iron Law 是 spec-autopilot TDD 模式的灵感来源，spec-autopilot 将其从建议提升为 L2 确定性验证。

---

#### 3.1.3 oh-my-claudecode (OMC) — Teams-first Multi-Agent Orchestration

- **GitHub Stars**: 活跃开发中（未公开具体数字）
- **最新版本**: v4.1.7（Teams 重构）
- **核心架构**: 32 Agent + 40+ Skills + 5 执行模式

**V4+ 新特性**:
- Teams 成为核心编排表面（取代 Swarm）
- 5 执行模式：Autopilot / Ultrapilot(3-5x 并行) / Swarm(已废弃) / Pipeline / Ecomode
- Deep Interview：苏格拉底式需求澄清
- Multi-provider Ask：Claude/Codex/Gemini 多模型询问
- psmux：Windows 原生 tmux 替代（76 命令兼容）
- HUD：可配置工作目录显示 + 思考指示器
- Auto-resume：速率限制自动恢复

**优势**:
- 并行执行能力最强（Claude Code 生态内）
- 智能模型路由（Haiku/Sonnet/Opus 分级）
- Agent 数量最多（32 个）
- Discord 通知集成
- Windows 原生支持（psmux）

**劣势**:
- 无确定性质量门禁
- 无结构化需求分析流程
- 防跳步能力为零
- TDD 支持浅（独立 Skill，非流水线集成）

**与 spec-autopilot 差异**: OMC 追求并发规模和工具链集成，spec-autopilot 追求阶段确定性和质量深度。OMC 的 Teams 编排和 5 执行模式是 spec-autopilot 可借鉴的并行增强方向。

---

#### 3.1.4 everything-claude-code (ECC) — Agent Harness Performance Optimization

- **GitHub Stars**: ~50K（爆发式增长，9 天 31.9K）
- **来源**: Cerebral Valley x Anthropic 黑客松（2026-02）
- **核心架构**: 13 Agent + 40+ Skills + 32 快捷命令

**关键特性**:
- AgentShield 安全扫描：CLAUDE.md/Hook/MCP/settings.json 漏洞检测，--opus 红蓝对抗审计
- NanoClaw v2：模型路由 + 技能热加载 + 会话分支/搜索/导出/压缩/指标
- 1,282 测试 + 98% 覆盖率 + 102 静态规则
- ecc.tools：分析 git 历史自动生成 Skills
- 跨平台：Claude Code/Cursor/OpenCode/Codex

**优势**:
- 安全扫描最强（AgentShield 5 类 14 模式）
- 框架自身质量标杆（1282 测试/98% 覆盖）
- 模型路由（NanoClaw v2）
- 跨平台支持最广

**劣势**:
- 无流水线编排（Skills 为独立单元）
- 无崩溃恢复
- 无防跳步机制
- 并行执行实验性
- 架构松散

**与 spec-autopilot 差异**: ECC 是"能力增强包"，spec-autopilot 是"流程编排器"。ECC 的 AgentShield 是 spec-autopilot 缺失的重要安全能力，NanoClaw v2 的模型路由值得借鉴。

---

### 3.2 Tier 2: 独立 Agent

#### 3.2.1 Cline — VS Code Autonomous Coding Agent

- **GitHub Stars**: ~59K
- **安装量**: 5M+ VS Code 安装
- **核心架构**: Plan/Act 双模式 + MCP 扩展 + Computer Use

**2026 新特性**:
- CLI 2.0（v3.58）：支持并行 Agent + 无头 CI/CD
- Native Subagents：解决早期子 Agent 只读限制
- 企业特性：SSO/SAML/OIDC + 审计追踪 + VPC/私有链接

**优势**:
- GUI 集成最强（VS Code 原生）
- 人机协作最成熟（逐步审批）
- 浏览器自动化（Computer Use）
- MCP 生态最丰富
- 企业特性完整
- 模型无关（OpenAI/Anthropic/本地模型）

**劣势**:
- 无 TDD 原生支持
- 无崩溃恢复
- 无规约驱动流程
- 防跳步仅为人工审批
- API 成本高（$5-20/会话，$50-200/月）

**与 spec-autopilot 差异**: Cline 是"IDE 内的交互式助手"（人机协作），spec-autopilot 是"终端中的自动化流水线"（无人值守）。两者互补而非竞争。

---

#### 3.2.2 Aider — Terminal AI Pair Programming

- **GitHub Stars**: ~42K
- **贡献者**: 1,170+
- **核心架构**: Git-native + Repo Map + Architect/Editor 双模型

**关键特性**:
- Repo Map：tree-sitter AST 索引全仓库函数签名
- Git 深度集成：原子 commit + /undo 即时回滚
- Architect + Editor 分离：高级模型做决策，编辑模型执行
- 100+ 编程语言
- 语音 + 多模态输入
- Lint 自动修复 + AST 级错误修复

**优势**:
- Git 集成最深
- Repo Map 上下文质量极高
- 语言覆盖最广
- 成本效率高（双模型分离）

**劣势**:
- 无 TDD / 无质量门禁 / 无并行 / 无崩溃恢复 / 无防跳步
- 单 Agent 串行
- 无需求分析流程

**与 spec-autopilot 差异**: Aider 是"AI 结对编程伙伴"（Git 深度），spec-autopilot 是"自动化交付编排器"（流水线深度）。Aider 的 Repo Map 是 spec-autopilot Phase 1 Auto-Scan 可借鉴的上下文增强技术。

---

#### 3.2.3 OpenHands — AI Software Engineering Platform

- **GitHub Stars**: ~65K
- **融资**: Series A $18.8M
- **核心架构**: Event-sourced + Docker 沙箱 + V1 SDK

**关键特性**:
- Event-sourced 状态模型：确定性重放恢复
- Docker/K8s 沙箱隔离
- 千级 Agent 弹性扩展
- V1 SDK：不可变配置 + 类型化工具 + MCP 集成
- SWE-bench 87% 解决率
- 多界面：CLI + Web GUI + Cloud + REST API

**优势**:
- 可扩展性最强（千级 Agent）
- 架构最成熟（event-sourced）
- 崩溃恢复最优雅（确定性重放）
- 安全性企业级（Docker 沙箱）
- 基准测试领先

**劣势**:
- 无规约驱动流程
- 无需求分析
- 无 TDD 强制
- 防跳步能力弱
- 部署复杂度高

**与 spec-autopilot 差异**: OpenHands 是"通用平台"（可扩展性），spec-autopilot 是"专用流水线"（质量深度）。OpenHands 的 event-sourced 架构是 spec-autopilot 崩溃恢复的理论上位替代。

---

### 3.3 Tier 3: 企业 IDE

#### 3.3.1 Cursor — AI-Native IDE

- **类型**: 商业产品（非开源）
- **定价**: Free / Pro $20 / Pro+ $60 / Ultra $200 / Teams $40 / Enterprise 自定义
- **核心架构**: VS Code 基础 + AI Agent + Tab Completions + 信用池

**关键特性**:
- AI Agent：多文件复杂任务处理
- Codebase-Aware Context：全仓库索引
- Tab Completions：预测式自动补全
- Inline Editing：选中即改
- Background Agent：后台长任务执行
- 信用池模型：Auto 模式无限 + 手动选模型消耗信用
- 多模型支持：GPT-4o / Claude Opus / Gemini

**优势**:
- 代码生成体验最流畅（IDE 原生）
- 学习曲线最低（开箱即用）
- 社区生态庞大
- Background Agent 支持长任务
- 企业特性完整

**劣势**:
- 无需求工程（直接写代码）
- 无规约生成
- 无质量门禁（依赖外部 CI/CD）
- 无 TDD 强制
- 无崩溃恢复（会话级）
- 闭源 + 付费

**与 spec-autopilot 差异**: Cursor 优化"写代码"，spec-autopilot 优化"写对代码"。Cursor 用户可以通过 Claude Code + spec-autopilot 补齐需求工程和质量门禁。两者不直接竞争，可形成互补生态。

---

#### 3.3.2 Windsurf — Agentic AI IDE (formerly Codeium)

- **类型**: 商业产品（被 Cognition AI $250M 收购）
- **定价**: Free / Pro $15 / Teams $30 / Enterprise $60
- **核心架构**: VS Code 基础 + Cascade 智能体 + Memory 系统

**关键特性**:
- Cascade：追踪开发意图的 Agentic AI（不同于简单的代码补全）
- Tab/Supercomplete：预测下一编辑位置
- Memory 系统：持久化学习编码风格和模式
- Turbo Mode：自主终端命令执行
- MCP 集成：GitHub/Slack/Stripe/Figma/数据库连接
- Previews & Deploys：内置预览和部署
- 多模型：Gemini 3.1 Pro / Claude Sonnet 4.6 / GPT-5.3-Codex-Spark

**优势**:
- Cascade 意图追踪独特（自动拉取相关文件）
- Memory 系统避免重复解释
- 定价低于 Cursor（$15 vs $20）
- LogRocket AI Dev Tool #1 排名（2026-02）
- AI 写 94% 代码的实证数据

**劣势**:
- 与 Cursor 相同的结构性缺陷（无需求/规约/门禁/TDD）
- 被收购后战略方向不确定（与 Devin 合并）
- 闭源 + 付费

**与 spec-autopilot 差异**: Windsurf 的 Memory 系统和 Cascade 意图追踪是有趣的差异化方向，但在交付流水线维度与 Cursor 具有相同的结构性空白。

---

## 4. 当前插件缺失能力清单 (P0/P1/P2)

### P0 — 阻碍核心竞争力

| # | 缺失能力 | 来源竞品 | 影响 | 补齐难度 |
|:-:|---------|---------|------|:-------:|
| P0-1 | **GUI 可视化仪表板** — 实时进度、Phase 状态、门禁结果可视化 | Cursor/Windsurf/Cline/OpenHands | Event Bus 已有数据源（events.jsonl），但无前端消费层，用户体验与竞品差距最大 | 高 |
| P0-2 | **安全扫描集成** — CLAUDE.md/Hook/MCP 配置漏洞检测 | ECC (AgentShield) | 企业客户合规准入必需，Phase 0 或 Phase 6.5 可集成 | 中 |
| P0-3 | **社区生态建设** — Marketplace 上架 + 文档翻译 + 示例项目 | superpowers/BMAD/ECC | 当前 Stars 远低于竞品，影响采用率 | 中 |

### P1 — 影响用户体验

| # | 缺失能力 | 来源竞品 | 影响 | 补齐难度 |
|:-:|---------|---------|------|:-------:|
| P1-1 | **Repo Map / AST 索引** — 全仓库函数签名索引 | Aider | Phase 1 Auto-Scan 和 Phase 5 跨文件编辑的上下文质量显著提升 | 高 |
| P1-2 | **通知系统** — Discord/Slack/Telegram 完成推送 | OMC | 无人值守场景用户体验关键缺失 | 低 |
| P1-3 | **智能模型路由** — 子 Agent 按复杂度路由到不同模型 | OMC/ECC(NanoClaw) | token 成本降低 30-50%，但依赖 Claude Code 原生支持 | 高 |
| P1-4 | **Memory 系统** — 持久化学习项目编码风格和模式 | Windsurf (Cascade Memory) | 跨会话的项目理解连续性 | 中 |
| P1-5 | **Event-sourced 恢复增强** — events.jsonl 升级为状态恢复输入源 | OpenHands | 崩溃恢复可靠性从当前水平提升至 99%+ | 高 |

### P2 — 锦上添花

| # | 缺失能力 | 来源竞品 | 影响 | 补齐难度 |
|:-:|---------|---------|------|:-------:|
| P2-1 | **Meta Skills / TDD for Skills** — 技能本身的 TDD 测试 | superpowers | 插件自身质量保证闭环 | 中 |
| P2-2 | **文档分片 / Discover Inputs** — 大型制品自动分片加载 | BMAD | 大型项目的上下文效率 | 中 |
| P2-3 | **浏览器自动化** — E2E 测试的 Computer Use 集成 | Cline | Phase 6 测试能力扩展 | 高 |
| P2-4 | **语音/多模态输入** — 语音需求描述 | Aider | Phase 1 需求输入便利性 | 低 |
| P2-5 | **跨 IDE 支持** — Cursor/VS Code 集成 | BMAD/ECC | 用户覆盖面扩展 | 高 |
| P2-6 | **Deep Interview** — 苏格拉底式需求挖掘 | OMC | Phase 1 已有 Socratic 模式，可进一步深化 | 低 |

### 护城河能力（竞品缺失）

以下能力为 spec-autopilot 独有或显著领先：

| 能力 | 领先程度 | 最近竞品 |
|------|:-------:|---------|
| 三层确定性门禁 (L1+L2+L3) | 独有 | BMAD 制品链（软约束，差距巨大） |
| L2 Hook 确定性验证（反合理化 + 代码约束 + 测试金字塔 + TDD 阶段锁） | 独有 | ECC 静态规则（未集成到流水线） |
| checkpoint + anchor_sha 崩溃恢复 + PreCompact Hook | 独有 | OpenHands event-sourced（架构更优但场景不同） |
| Phase 1 三路并行调研 + 多轮决策 LOOP + 复杂度分路 | 独有 | BMAD Analyst+PM（无并行无决策卡片） |
| 需求路由（Feature/Bugfix/Refactor/Chore 动态门禁） | 独有 | 无竞品具备 |
| 8 阶段完整流水线 + 3 种执行模式（full/lite/minimal） | 独有 | BMAD 4 阶段（无模式切换） |
| TDD L2 确定性验证（RED 必须失败 / GREEN 必须通过 / REFACTOR 回滚保护） | 独有 | superpowers Iron Law（建议非强制） |

---

## 5. 竞品优势引入计划

### Phase 1: 快速胜利（1-2 周）

| # | 引入项 | 来源 | 工作量 | 预期收益 |
|:-:|--------|------|:------:|---------|
| 1.1 | **通知 Webhook** — Phase 7 完成时发送 Discord/Slack 通知 | OMC | 2 天 | 无人值守场景可用性提升 |
| 1.2 | **安全预检 Skill** — Phase 0 增加 Hook/MCP 基本安全扫描 | ECC | 3 天 | 企业合规准入 |
| 1.3 | **Marketplace 上架** — 提交到 Anthropic Plugin Marketplace | superpowers | 2 天 | 社区可见性飞跃 |

### Phase 2: 核心增强（2-4 周）

| # | 引入项 | 来源 | 工作量 | 预期收益 |
|:-:|--------|------|:------:|---------|
| 2.1 | **GUI 仪表板 v1** — 基于 events.jsonl 的 Web 进度面板 | OpenHands/Cline | 1.5 周 | 用户体验质变，缩小与 IDE 竞品差距 |
| 2.2 | **Event-sourced 恢复增强** — events.jsonl 升级为状态恢复输入源 | OpenHands | 1 周 | 崩溃恢复可靠性提升 |
| 2.3 | **文档分片协议** — 大型 OpenSpec 自动分片 | BMAD | 1 周 | 大型项目上下文效率提升 30% |

### Phase 3: 深度演进（1-2 月）

| # | 引入项 | 来源 | 工作量 | 预期收益 |
|:-:|--------|------|:------:|---------|
| 3.1 | **Repo Map 集成** — Phase 1 Auto-Scan 引入 AST 索引 | Aider | 2 周 | 跨文件编辑上下文质量飞跃 |
| 3.2 | **AgentShield 级安全扫描** — 5 类漏洞检测 + 红蓝对抗 | ECC | 2 周 | 企业级安全保障 |
| 3.3 | **Memory 系统** — 跨会话项目编码风格持久化 | Windsurf | 2 周 | 减少重复解释，提升连续性 |

### Phase 4: 战略方向（3-6 月）

| # | 引入项 | 来源 | 工作量 | 预期收益 |
|:-:|--------|------|:------:|---------|
| 4.1 | **智能模型路由** — 按任务复杂度路由模型 | OMC/ECC | 依赖 CC 支持 | token 成本降低 30-50% |
| 4.2 | **GUI 仪表板 v2** — 实时 WebSocket + Phase 控制 | Cursor/Windsurf | 1 月 | 接近 IDE 级体验 |
| 4.3 | **千级 Agent 扩展** — Docker 沙箱 + K8s 编排 | OpenHands | 2 月 | 大型企业场景 |

---

## 6. 与 v5.0 报告对比

### 6.1 竞品格局变化

| 维度 | v5.0 报告（2026-03-13 v4.2.0） | v5.0.4 报告（2026-03-13 更新） |
|------|-------------------------------|-------------------------------|
| **竞品范围** | 8 款（Tier 1 + Tier 2） | 10 款（新增 Cursor + Windsurf Tier 3） |
| **评分维度** | 10 维度（100 分制） | 12 维度（10 分制），新增学习曲线和社区生态 |
| **superpowers Stars** | 42K | 81K（+93% 爆发式增长） |
| **ECC Stars** | 未明确 | 50K（9 天 31.9K 的现象级增长） |
| **BMAD Stars** | 未明确 | 39K |
| **OpenHands Stars** | 未明确 | 65K |
| **Cline Stars** | 未明确 | 59K |
| **OMC 架构** | 5 Worker + tmux | Teams 核心编排 + 5 执行模式 + psmux Windows 支持 |
| **ECC 架构** | Skills + Instincts + Memory | 新增 NanoClaw v2 模型路由 + ecc.tools 自动技能生成 |
| **Cline 架构** | Plan/Act + MCP | 新增 CLI 2.0 + Native Subagents |

### 6.2 spec-autopilot 能力变化（v4.2.0 基准）

| 维度 | v5.0 评分 | v5.0.4 评分 | 变化原因 |
|------|:---------:|:-----------:|---------|
| 需求工程 | 92/100 | 9/10 | 基准持平，仍为行业领先 |
| 质量门禁 | 95/100 | 10/10 | v5.1 统一 Hook + TDD 阶段状态文件进一步强化 |
| TDD | 90/100 | 9/10 | v5.1 .tdd-stage L2 确定性门禁提升 |
| 并行执行 | 78/100 | 7/10 | 竞品并行能力增长（OMC Teams / OpenHands 千级）导致相对排名下降 |
| GUI 可视化 | 40/100 | 3/10 | Cursor/Windsurf 加入后短板更加突出 |
| 社区生态 | N/A | 2/10 | 新增维度，Stars 差距客观存在 |

### 6.3 缺口优先级调整

| 缺口 | v5.0 优先级 | v5.0.4 优先级 | 调整原因 |
|------|:-----------:|:------------:|---------|
| GUI 可视化 | 未列入 P0 | **P0-1** | Tier 3 企业 IDE 加入后成为最大差距 |
| 安全扫描 | P0 | P0-2 | ECC AgentShield 进一步验证了需求 |
| 社区生态 | 未列入 | **P0-3** | superpowers 81K / ECC 50K 的爆发式增长凸显差距 |
| 多模型路由 | P0 | P1-3 | 降级为 P1，因依赖 Claude Code 原生支持，短期无法自主解决 |
| Memory 系统 | 未列入 | **P1-4** | Windsurf Cascade Memory 的差异化启发 |
| 通知系统 | P1 | P1-2 | 保持 |
| Event-sourced 恢复 | P1 | P1-5 | 保持 |

---

## 7. 战略建议

### 7.1 定位强化

spec-autopilot 应坚守并强化"企业级规约驱动质量流水线"定位：

- **不要追求成为通用 AI 编码助手**（Cursor/Windsurf/Cline 已高度同质化）
- **不要追求千级 Agent 扩展**（OpenHands 的基础设施投入不可复制）
- **聚焦"AI 写对代码"这一稀缺价值**：在 10 款竞品中，只有 spec-autopilot 同时具备需求工程 + 规约生成 + 质量门禁 + 崩溃恢复的完整闭环

### 7.2 三个战略方向

**方向 A: GUI 可视化突破（高优先级）**
- Event Bus（events.jsonl）已提供完整数据源
- 构建轻量 Web 面板（或 VS Code 扩展），实现 Phase 状态实时可视化
- 目标：将 GUI 评分从 3 提升至 6+
- 参考：gui-dist 已有基础构建产物

**方向 B: 安全 + 合规增强（中优先级）**
- Phase 0 集成 AgentShield 级安全预检
- Phase 6.5 集成 SAST/DAST 扫描结果
- 目标：满足企业客户安全合规准入

**方向 C: 社区生态加速（中优先级）**
- 提交 Anthropic Plugin Marketplace
- 创建 Quick Start 示例项目（5 分钟体验）
- 英文文档完善
- 目标：6 个月内 Stars 突破 1K

### 7.3 竞合关系

| 竞品 | 关系 | 策略 |
|------|------|------|
| Cursor / Windsurf | **互补** | 用户在 IDE 中写代码，用 spec-autopilot 保证质量 |
| superpowers | **竞合** | 借鉴其 TDD 纪律和上下文效率，在门禁深度上差异化 |
| BMAD | **竞合** | 借鉴其角色体系和制品链，在执行确定性上差异化 |
| OMC | **互补** | 借鉴其 Teams 编排和通知系统，在质量门禁上差异化 |
| ECC | **互补** | 借鉴其 AgentShield 安全能力，集成为 Phase 0/6.5 插件 |
| OpenHands | **差异** | 不同赛道（通用平台 vs 专用流水线），互不替代 |
| Cline | **互补** | Cline 处理 IDE 交互，spec-autopilot 处理流水线编排 |
| Aider | **互补** | 借鉴 Repo Map 技术，不在 pair programming 赛道竞争 |

### 7.4 风险预警

1. **superpowers Marketplace 下架风险传导**：superpowers 近期遭遇 Marketplace 兼容性问题（2026-03），说明 Claude Code Plugin 生态仍不稳定。spec-autopilot 上架时需做好兼容性测试。

2. **Tier 3 IDE 向下游扩展**：Cursor Background Agent 和 Windsurf Cascade 正在向"自主长任务"方向演进，可能侵蚀 spec-autopilot 的部分使用场景。应对策略：强化质量门禁和规约生成这两个 IDE 短期内无法复制的能力。

3. **ECC 爆发式增长的启示**：ECC 9 天 31.9K Stars 的增长说明 Claude Code 生态的用户关注度在急剧上升。spec-autopilot 需要抓住这个窗口期加速社区建设。

4. **OpenHands 企业化冲击**：$18.8M 融资 + V1 SDK 标志着 OpenHands 正式进入企业市场。虽然赛道不同，但在"AI 自动化交付"叙事上存在竞争。

---

*报告终*
