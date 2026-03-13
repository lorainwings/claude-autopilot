# spec-autopilot 插件综合分析报告

**分析版本**: v3.2.2 | **分析日期**: 2026-03-08

---

## 一、产品定位与核心价值

spec-autopilot 是一个面向 Claude Code 的**规范驱动全自动软件交付编排框架**，核心价值：

| 维度 | 说明 |
|------|------|
| **全闭环交付** | 8 阶段（环境检查→需求→OpenSpec→FF→测试设计→实施→报告→归档） |
| **确定性门控** | 3 层门禁：TaskCreate blockedBy + Hook 脚本 + AI Gate 语义验证 |
| **弹性恢复** | checkpoint 持久化 + git fixup + 上下文压缩恢复 + PID 回收防护 |
| **灵活适配** | full/lite/minimal 三种模式，覆盖大功能到快速原型 |
| **零配置接入** | v3.0.0 内置模板，新项目仅需 1 个 config 文件 |

**综合评分：8.4/10**（在 AI Agent 编排领域属于高水准实现）

---

## 二、产品原理

### 2.1 整体架构

插件采用**两层架构**：

- **Plugin Layer**（`plugins/spec-autopilot/`）：可复用的编排逻辑，包含 6 个 Skill、8 个 Hook 脚本、多个工具脚本
- **Project Layer**（用户项目的 `.claude/` 目录）：项目特定的配置、阶段指令文件、checkpoint 数据

运行时执行拓扑：

- **主线程**（Phase 0/1/7）：直接在对话上下文中执行，可使用 Task 工具派发子 Agent
- **子 Agent**（Phase 2-6）：通过 Task 工具派发，运行在隔离环境中，**没有 Task 工具**（不可嵌套）

### 2.2 核心技术机制

#### Checkpoint 机制

每个阶段完成后写入磁盘 checkpoint 文件（`phase-results/phase-N-xxx.json`），JSON 格式含标准字段（`status`、`summary`、`artifacts`、`_metrics`）。当 `git_commit_per_phase = true` 时还会 git fixup commit 持久化到 git 历史。

#### 3 层 Gate 系统

- **Layer 1（Task 系统层）**：`blockedBy` 建立依赖链，Claude Code 原生机制不可绕过
- **Layer 2（Hook 脚本层）**：确定性执行，含 predecessor-checkpoint、json-envelope、anti-rationalization、write-edit-constraint 等 8 个 Hook
- **Layer 3（AI Gate 层）**：8 步切换检查清单 + 特殊门禁 + 语义验证

#### Dispatch 机制

7 级上下文注入优先级链：阶段标记 → 项目规则扫描 → instruction_files → reference_files → 内置模板 → Steering Documents → 模型路由提示

#### Recovery 机制

- 会话崩溃恢复：扫描 checkpoint + PID/session_id 双重验证
- 上下文压缩恢复：PreCompact Hook 保存 + SessionStart Hook 注入

### 2.3 使用场景

| 场景 | 推荐模式 | 理由 |
|------|---------|------|
| 中大型新功能（500+ 行） | full | 完整需求→设计→测试→实施→报告链 |
| 需求明确的小功能（100-500 行） | lite | 跳过 OpenSpec（Phase 2/3/4） |
| 快速原型/POC | minimal | 仅保留 Phase 0/1/5/7 |

**不适合**：单文件 Bug 修复、紧急 hotfix、极度探索性研究任务。

---

## 三、各维度评分

| 维度 | 评分 | 亮点 | 短板 |
|------|------|------|------|
| 编排模式 | **9.0** | DAG 内嵌线性 + 多阶段并行 | 静态模式选择，缺动态降级 |
| 质量门控 | **9.0** | 三层门禁 + 反合理化 | 语义验证为软检查 |
| 需求分析 | **8.5** | 苏格拉底模式 + 事实驱动 | 复杂度阈值机械化 |
| 状态管理 | **8.5** | 双层持久化 + 崩溃恢复完整 | 缺 schema 版本迁移 |
| 可观测性 | **8.0** | 指标采集完整 + ASCII 分布图 | 子 agent 过程不透明、无 token 统计 |
| 错误处理 | **7.5** | 降级策略完善 | 缺自动诊断和自愈能力 |

---

## 四、版本演进分析

### 演进脉络

| 阶段 | 版本范围 | 核心能力 |
|------|---------|---------|
| 基础框架 | v1.0→v1.9 | 8 阶段流水线 + 3 层门禁 + 上下文压缩恢复 |
| 质量深化 | v2.0→v2.5 | anti-rationalization + Auto-Scan + 代码约束 Hook + 知识累积 |
| 效率提升 | v3.0→v3.2.2 | 内置模板 + 跨阶段并行 + Allure + Phase 6 三路并行 |

### 关键版本

| 版本 | 关键能力 |
|------|---------|
| v2.0.0 | Anti-rationalization + 测试金字塔 |
| v2.4.0 | 代码约束 Hook + 知识累积 |
| v2.5.0 | Write/Edit 级实时拦截 |
| v3.0.0 | 内置模板 + 零配置接入（Breaking Change）|
| v3.2.0 | 跨阶段并行 + Allure 报告 |
| v3.2.2 | Phase 6 三路并行 + 知识提取后台化 |

---

## 五、竞品对比

| 维度 | Superpowers (57K Stars) | OMC | BMAD | ECC (50K Stars) | **spec-autopilot** |
|------|:-:|:-:|:-:|:-:|:-:|
| 阶段覆盖 | 5 阶段 | 5 模式 | 4 阶段 | 4 层 | **8 阶段** |
| 质量门控 | TDD + 双阶段 Review | architect 循环 | 90% gate | Hooks 门 | **3 层门禁** |
| 并行能力 | 串行 | **5 并发** | 无 | 弱 | Phase 1/4/5/6 |
| 成本优化 | 无 | **三级模型路由** | 无 | 成本优化 | 仅提示级 |
| 跨平台 | 3 平台 | 仅 Claude Code | **4 平台** | **4 平台** | 仅 Claude Code |

**差异化优势**：
1. 唯一实现需求→归档全闭环
2. 3 层确定性门禁独有
3. 生成 4 层规范文档（Proposal→Design→Specs→Tasks）
4. 最完整的崩溃恢复体系

---

## 六、问题清单

### P0 严重（流程中断/数据丢失）

| 编号 | 问题 | 位置 | 影响 |
|------|------|------|------|
| P0-1 | 后台 Agent 无超时保护 | SKILL.md 并行等待逻辑 | 主线程永久阻塞 |
| P0-2 | write-edit-constraint-check lite 模式阶段误判 | write-edit-constraint-check.sh:41-68 | Write/Edit 被错误拦截 |
| P0-3 | lite 模式 tasks.md 优先级冲突 | check-predecessor-checkpoint.sh:307-322 | 任务完成状态误判 |

### P1 高（输出质量严重下降）

| 编号 | 问题 | 影响 |
|------|------|------|
| P1-1 | anti-rationalization 不支持中文 | 中文合理化跳过无法检测 |
| P1-2 | minimal 模式 Phase 5 zero_skip_check 验证可能失败 | validate-json-envelope 强制要求该字段 |
| P1-3 | 并行 Phase 4 dry_run_results 聚合逻辑未定义 | Gate 可能误判失败 |
| P1-4 | autosquash 与并行 merge commits 不兼容 | rebase 必然失败 |
| P1-5 | 语义规则无确定性传递 | hitales-commons、ServiceReturn 等规则不可靠 |

### P2 中（边界情况）

| 编号 | 问题 |
|------|------|
| P2-1 | Hook 正则可能因 JSON 序列化空白不匹配，门禁被绕过 |
| P2-2 | find_active_change 多 change 并发 fallback 选错 |
| P2-3 | Phase 5 crash recovery 后 start-time 不重置 |
| P2-4 | parallel-merge-guard scope 检查过宽 |
| P2-5 | rules-scanner 不解析 @ 引用的深层规则文件 |
| P2-6 | Phase 1 持久化上下文 7 天有效期受 git mtime 影响 |
| P2-7 | Phase 7 知识提取 agent 无超时保护 |
| P2-8 | validate-config bash fallback 嵌套 key 匹配不准确 |

### P3 低（优化建议）

共 7 项：Hook 脚本重复代码、JSON 提取性能、ownership 文件未清理、scan-checkpoints 启动性能、config schema 验证不完整、SKILL.md 与 references 信息重复、gates.md 文档错误。

---

## 七、规则遵循保障分析

### 规则传递链路可靠性

| 规则类别 | scanner 提取 | config 配置 | Hook 检测 | 子 agent 可靠感知 |
|----------|:-:|:-:|:-:|:-:|
| 简单禁止项（npm 等） | Y | Y | Y | **可靠** |
| 文件行数限制 | Y | Y | Y | **可靠** |
| hitales-commons 优先检查 | N | N | N | **不可靠** |
| ServiceReturn<T> 统一返回 | N | N | N | **不可靠** |
| Pinia Options Store 模式 | N | N | N | **不可靠** |
| OceanBase 兼容性 | N | N | N | **不可靠** |
| JDK 24 版本 | 部分 | N | N | **不可靠** |

### 三大系统性薄弱环节

1. **语义规则断层**：hitales-commons、ServiceReturn、Pinia Options Store 等无确定性传递和验证
2. **中文检测盲区**：anti-rationalization 仅匹配英文
3. **深层规则丢失**：.claude/rules/ 中 @ 引用的详细规范文件不被 scanner 提取

---

## 八、改进建议

### 立即可做（1-2 天）

| # | 改进 | 改动量 | 收益 |
|---|------|--------|------|
| 1 | anti-rationalization 增加中文模式 | ~30 行 | 修复中文合理化检测盲区 |
| 2 | config 增加 semantic_rules + dispatch 注入 | ~50 行 | 语义规则有确定性传递通道 |
| 3 | Phase 6.5 代码审查注入项目规则 | ~20 行 | 代码审查覆盖项目规则 |
| 4 | 后台 Agent 增加硬超时 | ~30 行 | 修复 P0-1 永久阻塞 |
| 5 | code-constraint-check 扩展到 Phase 4/6 | ~5 行 | 扩大约束检查范围 |

### 短期优化（1-2 周）

- Checkpoint schema 版本化
- Token 消耗追踪
- 规则摘要文件持久化（rules-digest.json）
- 子 agent 规则确认协议
- Phase 5 crash recovery 时间戳重置

### 中期提升（1-2 月）

- 动态执行路径调整（full 自动降级 lite）
- 自动修复回路（失败诊断注入重试 prompt）
- 构建后验证 Hook
- 增量执行支持
- 规则遵循度量体系

### 长期愿景（3-6 月）

- 自适应编排引擎
- 流水线可视化 Dashboard
- 跨项目知识迁移
- Smart Model Routing
- 跨平台支持评估

---

## 九、SWOT 总结

| | 正面 | 负面 |
|---|---|---|
| **内部** | **S**: 8 阶段全闭环、3 层确定性门禁、崩溃恢复深度、零配置接入 | **W**: 无实际模型路由、单平台、学习系统初级、语义规则断层 |
| **外部** | **O**: Agent Teams 原生支持、开源社区化、Instincts 学习系统 | **T**: Superpowers 57K Stars 社区壁垒、Claude Code 内置能力提升 |
