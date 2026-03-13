# claude-autopilot 产品分析报告

> 版本: v3.2.0 | 分析日期: 2026-03-07

---

## 一、产品概述

### 1.1 产品定位

claude-autopilot（插件名: spec-autopilot）是一个面向 Claude Code 的**企业级规范驱动全自动软件交付框架**。它将软件开发流程编排为 8 个确定性阶段，从需求理解到代码归档实现零人工干预的自动化交付。

### 1.2 核心价值主张

| 价值维度 | 描述 |
|----------|------|
| **全闭环交付** | 需求→设计→测试→实施→报告→归档，8 阶段完整覆盖 |
| **确定性质量** | 3 层门禁（Task 依赖 + Hook 脚本 + AI Gate），零漏洞 |
| **配置驱动** | 零硬编码，所有项目路径从 config.yaml 读取 |
| **灵活模式** | full/lite/minimal 三种模式，按任务规模选择 |
| **崩溃恢复** | checkpoint + PID 回收防护 + 上下文压缩恢复 |

### 1.3 目标用户

- **中大型项目团队**: 需要规范可追溯性的开发场景
- **企业级开发**: 需要质量门控和审计追踪
- **重复性交付**: 需要标准化流程减少人工成本
- **远程协作**: 需要结构化沟通和决策记录

---

## 二、架构设计分析

### 2.1 8 阶段流水线

```
Phase 0  →  Phase 1  →  Phase 2  →  Phase 3  →  Phase 4  →  Phase 5  →  Phase 6  →  Phase 7
环境检查    需求理解    创建OpenSpec  FF生成制品   测试设计    循环实施    测试报告    汇总归档
(主线程)   (主线程)   (子Agent)    (子Agent)   (子Agent)  (子Agent)  (子Agent)  (主线程)
```

**架构约束**: 子 Agent 内部没有 Task 工具，所有 Task 派发必须在主线程中执行，禁止嵌套。

### 2.2 核心组件矩阵

| 组件 | 文件 | 行数 | 职责 |
|------|------|------|------|
| 主编排器 | `skills/autopilot/SKILL.md` | ~435 | 8 阶段流程控制 |
| 调度协议 | `skills/autopilot-dispatch/SKILL.md` | ~609 | 子 Agent prompt 构造 + 并行调度 |
| 门禁协议 | `skills/autopilot-gate/SKILL.md` | ~200 | 8 步切换检查清单 + 特殊门禁 |
| 检查点 | `skills/autopilot-checkpoint/SKILL.md` | ~100 | 状态持久化读写 |
| 崩溃恢复 | `skills/autopilot-recovery/SKILL.md` | ~80 | checkpoint 扫描 + 恢复点定位 |
| 配置初始化 | `skills/autopilot-init/SKILL.md` | ~120 | 项目扫描 + 配置生成 |
| 并行编排 | `references/parallel-dispatch.md` | ~333 | 跨阶段通用并行编排协议 |

### 2.3 Hook 系统（确定性执行层）

| Hook | 事件 | 超时 | 职责 |
|------|------|------|------|
| check-predecessor-checkpoint | PreToolUse(Task) | 30s | 前置 checkpoint 验证 + wall-clock 超时 |
| validate-json-envelope | PostToolUse(Task) | 30s | JSON 结构 + 必需字段 + test pyramid |
| anti-rationalization-check | PostToolUse(Task) | 30s | 10 种跳过模式检测 |
| code-constraint-check | PostToolUse(Task) | 30s | 禁止文件/模式/目录检查 |
| parallel-merge-guard | PostToolUse(Task) | 150s | worktree merge 冲突 + scope + typecheck |
| write-edit-constraint-check | PostToolUse(Write/Edit) | 15s | 文件越权检查 |
| save-state-before-compact | PreCompact | 15s | 编排状态持久化 |
| reinject-state-after-compact | SessionStart(compact) | 15s | 压缩后状态恢复 |

### 2.4 3 层门禁架构

```
Layer 1: TaskCreate blockedBy        — 结构化依赖链，自动阻断跳阶段
Layer 2: Hook 脚本                   — 确定性磁盘验证，无网络依赖
Layer 3: AI Gate (autopilot-gate)    — 语义验证 + 8 步切换清单
```

**设计哲学**: Hook 是确定性的自动检查（fast feedback），AI Gate 是语义验证（可考虑上下文）。Hook floor 宽松，AI gate 严格 → 给 AI 审议空间。

---

## 三、核心能力分析

### 3.1 并行执行（v3.2.0 新增）

| Phase | 并行策略 | 实现方式 |
|-------|---------|---------|
| Phase 1 | Auto-Scan + 调研 + 搜索并行 | Task(run_in_background) × 3 |
| Phase 4 | 按测试类型并行生成 | 4 个子 Agent 分别生成 unit/api/e2e/ui |
| Phase 5 | 域分区 + worktree 隔离 + 批量 review | Union-Find 分组 → 并行实施 → 合并 → review |
| Phase 6 | 按测试套件并行执行 | 每个套件独立 Agent + Allure 合并 |

### 3.2 测试集成

- **Phase 4**: 需求驱动的测试用例生成（追溯矩阵覆盖 ≥80%）
- **Phase 6**: Allure 统一测试报告（含异常提醒 + 套件级结果）
- **Phase 4→5 门禁**: test_counts + test_pyramid + dry_run 三重验证
- **Phase 5→6 门禁**: zero_skip + tasks 全部完成

### 3.3 需求理解

- **Auto-Scan**: 项目持久化上下文（7 天有效 + 增量更新）
- **技术调研**: 代码影响分析 + 依赖兼容性 + 可行性评估
- **联网搜索**: WebSearch 最佳实践 + 竞品方案
- **决策协议**: 结构化卡片（2-4 选项 + 调研依据 + 推荐方案）
- **复杂度路由**: small/medium/large 自适应讨论深度

### 3.4 代码约束

- **forbidden_patterns**: 禁止使用的模式（Hook 确定性拦截）
- **required_patterns**: 必须使用的模式（v3.2.0 新增）
- **style_guide**: 代码风格指南路径注入
- **allowed_dirs**: 文件写入范围限制
- **max_file_lines**: 单文件行数限制

### 3.5 知识累积

- **Phase 7 提取**: 从所有 checkpoint 提取 pattern/decision/pitfall/optimization
- **Phase 1 注入**: top-5 相关历史知识注入到项目上下文
- **自动清理**: 超过 200 条时按置信度 + 最后使用时间淘汰

---

## 四、使用场景评估

### 4.1 最佳场景

| 场景 | 模式 | 预期效果 |
|------|------|---------|
| 中大型新功能 | full | 完整规范链 + 测试 + 质量门控 |
| 小功能/明确需求 | lite | 跳过规范，快速实施 + 测试 |
| 快速原型/POC | minimal | 极简流程，仅需求 + 实施 |
| 持续迭代 | full | 知识累积跨会话复用 |

### 4.2 不适合场景

- **探索性研究**: 需求极度模糊，无法结构化
- **单文件修改**: 流水线开销大于价值
- **紧急 hotfix**: 流程周期过长

---

## 五、成熟度评估

### v3.2.0 能力矩阵

| 能力维度 | 评分 | v3.0.1 | v3.2.0 | 说明 |
|----------|------|--------|--------|------|
| 流程完整性 | ★★★★★ | ★★★★★ | ★★★★★ | 8 阶段全闭环，3 种模式 |
| 质量门控 | ★★★★★ | ★★★★★ | ★★★★★ | 3 层确定性门禁 |
| 并行执行 | ★★★★☆ | ★★☆☆☆ | ★★★★☆ | Phase 1/4/5/6 全面并行 |
| 测试集成 | ★★★★☆ | ★★★☆☆ | ★★★★☆ | Allure + 追溯矩阵 |
| 配置驱动 | ★★★★☆ | ★★★★☆ | ★★★★☆ | 零硬编码 |
| 需求理解 | ★★★★☆ | ★★★☆☆ | ★★★★☆ | 并行调研 + 决策增强 |
| 代码约束 | ★★★★☆ | ★★★☆☆ | ★★★★☆ | 新增 required + style_guide |
| 持续学习 | ★★★☆☆ | ★★☆☆☆ | ★★★☆☆ | 知识累积（Instincts 待实现） |
| 跨平台 | ★☆☆☆☆ | ★☆☆☆☆ | ★☆☆☆☆ | 仅 Claude Code |
| 成本优化 | ★★☆☆☆ | ★★☆☆☆ | ★★☆☆☆ | 模型路由提示（无实际路由） |

---

## 六、稳定性分析

### 6.1 确定性保障

| 机制 | 稳定性等级 | 说明 |
|------|-----------|------|
| Hook 脚本 | **高** | Bash + Python 确定性执行，无 AI 幻觉风险 |
| TaskCreate blockedBy | **高** | Claude Code 原生机制，无法绕过 |
| Checkpoint 持久化 | **高** | 磁盘写入 + git commit 双保险 |
| PID 回收防护 | **高** | session_id 双重验证 |
| JSON envelope 验证 | **高** | 3 策略提取 + 两遍搜索（v3.2.0 修复） |

### 6.2 潜在风险

| 风险 | 影响 | 缓解措施 |
|------|------|---------|
| 子 Agent 不返回 JSON | 阻断 | validate-json-envelope Hook 拦截 |
| 并行合并冲突 | 降级 | parallel-merge-guard + 自动降级串行 |
| 上下文压缩 | 状态丢失 | PreCompact + SessionStart Hook 恢复 |
| 工具未安装 | 阻断 | 主动安装 + 降级方案 |

---

## 七、最佳实践符合度

| 最佳实践 | 符合度 | 说明 |
|----------|--------|------|
| 配置即代码 | ★★★★★ | autopilot.config.yaml 驱动一切 |
| 关注点分离 | ★★★★★ | 6 个 Skill 模块 + 8 个 Hook 脚本 |
| 确定性优先 | ★★★★★ | Hook 确定性 → AI 语义验证 分层 |
| 幂等性 | ★★★★☆ | checkpoint 恢复 + 扫描跳过 |
| 向后兼容 | ★★★★☆ | 旧配置继续生效 + 新字段可选 |
| 可观测性 | ★★★☆☆ | stderr 日志 + metrics 收集 |
| 文档完整性 | ★★★★★ | references/ + templates/ + docs/ |

---

## 八、v3.2.0 增强亮点

1. **跨阶段并行编排** — 通用 parallel-dispatch 协议，Phase 1/4/5/6 全面并行
2. **混合模式实施** — 域分区并行 + 批量 review，兼顾速度和质量
3. **Allure 统一报告** — 异常提醒 + 套件级结果 + 访问链接
4. **需求追溯矩阵** — 测试用例必须关联需求点，覆盖 ≥80%
5. **决策增强** — 所有复杂度级别展示决策卡片，附调研依据
6. **代码约束增强** — 新增 required_patterns + style_guide
7. **JSON envelope 修复** — 两遍搜索避免工具 JSON 误匹配

---

*本文档由 autopilot v3.2.0 迭代过程自动生成，作为产品评估的基准参考。*
