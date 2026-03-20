# parallel-harness MVP 范围说明

## 版本：0.1.0 (Beta)

## 已实现模块

### 核心 Schema ✅
- [x] TaskNode / TaskGraph schema（含工厂函数、验证函数、拓扑排序、就绪任务查询）
- [x] ContextPack schema（含工厂函数、验证函数）
- [x] VerifierResult / SynthesizedResult schema（含工厂函数、判断函数）
- [x] RoleContract schema + 四个预定义角色合同

### 任务理解层 ✅
- [x] IntentAnalyzer（关键词匹配 + 正则提取 + 复杂度估算）
- [x] TaskGraphBuilder（file-based/feature-based/layer-based 三种拆分策略）
- [x] ComplexityScorer（六维度加权评分 + 模型层级推荐）
- [x] OwnershipPlanner（路径分配 + 冲突检测 + 序列化解决 + MergeGuard 预留）

### 调度执行层 ✅
- [x] Scheduler MVP（就绪任务识别 + 三种优先策略 + 分层执行计划）
- [x] WorkerDispatch（Worker 分发 + 槽位管理 + 隔离模式）
- [x] RetryManager（指数/线性/固定退避 + 可重试错误过滤）
- [x] DowngradeManager（重试耗尽/超时/预算超支触发 + 层级降级 + 验证器简化）

### 模型路由层 ✅
- [x] ModelRouter（三层路由 + 成本估算 + 默认模型配置）
- [x] CostController（预算追踪 + 预警阈值 + 硬/软限制 + 任务成本估算）
- [x] EscalationPolicy（验证失败/任务失败/低质量触发升级 + 升级历史记录）

### 验证 Swarm 层 ✅
- [x] TestVerifier（测试覆盖检查）
- [x] ReviewVerifier（代码质量审查）
- [x] SecurityVerifier（安全扫描）
- [x] PerfVerifier（性能反模式检测）
- [x] ResultSynthesizer（加权综合 + 摘要生成）

### 工程控制面层 ✅
- [x] EventBus（发布/订阅 + 22 种事件类型 + 事件历史 + 异步通知）
- [x] ObservabilityService（五维指标：任务/Worker/成本/验证/性能 + EventBus 自动订阅）
- [x] SessionState（会话快照 + 任务结果记录 + 自动保存）

### CI/PR 集成 ✅
- [x] PRReviewer（Markdown 评论生成 + 行级评论 + 折叠显示 + 多语言）
- [x] CIRunner（JSON/JUnit/Markdown 输出 + exit code + 多 provider 支持）
- [x] CoverageReporter（覆盖率计算 + 阈值检查 + 详细报告）

### Skills ✅
- [x] /parallel-plan（核心入口 skill：意图分析 → 任务图 → 复杂度评分 → 所有权规划 → 执行计划）
- [x] /parallel-execute（内部执行引擎 skill：调度 → 验证 → 综合）

### Hooks ✅
- [x] hooks.json（SessionStart 事件注册）

### 构建与发布 ✅
- [x] build-dist.sh（类型检查 + 测试 + 复制 + 九重校验）
- [x] dist/parallel-harness/ 产物（37 个模块）

### 测试 ✅
- [x] 119 个测试，482 个断言，全部通过
- [x] 覆盖：schema、task-graph-builder、ownership-planner、model-router、context-packager、verifiers、worker-dispatch、retry-manager、downgrade-manager、cost-controller、escalation-policy、event-bus、pr-reviewer、ci-runner

## 市场接入 ✅

- [x] 已接入 marketplace.json（lorainwings-plugins 第二个插件）
- [x] dist 产物已生成并通过校验

## 路线图

### Alpha ✅ → 核心 schema + 任务理解层 + 调度 + 模型路由 + 验证 swarm
### Beta (当前) ✅ → 全模块实现 + skills + hooks + dist + marketplace 接入
### GA → GUI 可观测面板 + 实际 Worker 进程隔离 + 生产级 CI/CD 集成

## 下一步计划

1. 实现 GUI 可观测面板（任务图可视化、Worker 状态、成本仪表盘）
2. Worker 进程真实隔离（git worktree 模式）
3. 与 Claude Code Agent SDK 集成实现真正的多 Agent 并行
4. 生产级 CI/CD 集成（GitHub Actions workflow）
5. 端到端集成测试
