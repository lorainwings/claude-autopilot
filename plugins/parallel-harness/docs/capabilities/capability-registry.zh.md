# parallel-harness 能力清单

> 来源设计：superpowers 的 capability 清单化 + 低摩擦能力入口

每个能力包含：name, intent, required_context, worker_policy, verifier_policy。

## 已实现能力

### 1. task-graph-build
- **用途**: 从用户意图构建任务 DAG
- **意图**: 将复杂需求拆解为可并行执行的任务节点
- **所需上下文**: 用户输入、项目模块列表
- **Worker 策略**: Planner 角色, tier-3 模型
- **Verifier 策略**: review-verifier 检查图合理性

### 2. complexity-score
- **用途**: 为任务评估复杂度
- **意图**: 决定模型 tier、上下文预算和重试策略
- **所需上下文**: 任务描述、目标域、文件估计
- **Worker 策略**: 本地计算，不需模型
- **Verifier 策略**: 无需独立验证

### 3. ownership-plan
- **用途**: 为并行任务分配文件所有权
- **意图**: 防止并行执行时的写冲突
- **所需上下文**: 任务图、文件路径
- **Worker 策略**: 本地计算
- **Verifier 策略**: merge-guard 验证

### 4. context-pack
- **用途**: 为 worker 打包最小上下文
- **意图**: 减少无关信息，控制 token 成本
- **所需上下文**: 任务节点、相关文件
- **Worker 策略**: 本地计算 + 自动摘要
- **Verifier 策略**: 预算检查

### 5. model-route
- **用途**: 自动选择任务的模型 tier
- **意图**: 平衡质量与成本
- **所需上下文**: 复杂度、风险、预算、重试历史
- **Worker 策略**: 本地计算
- **Verifier 策略**: 成本追踪

### 6. schedule
- **用途**: 将任务图转为可执行批次
- **意图**: 最大化并行度，尊重依赖
- **所需上下文**: 任务图、调度配置
- **Worker 策略**: 本地计算
- **Verifier 策略**: DAG 一致性检查

## 接口预留能力

### 7. worker-dispatch
- **用途**: 将任务契约派发给 Claude Code 子 Agent
- **状态**: 接口已定义，实现待完成

### 8. merge-guard
- **用途**: 合并前检查越界和冲突
- **状态**: ownership-planner 中 validateOwnership 已实现基础检查

### 9. verify-test
- **用途**: 独立检查测试覆盖和通过情况
- **状态**: VerifierOutput schema 已定义

### 10. verify-review
- **用途**: 独立审查实现与目标的一致性
- **状态**: VerifierOutput schema 已定义

### 11. verify-security
- **用途**: 扫描安全模式和配置风险
- **状态**: VerifierOutput schema 已定义

### 12. pr-review
- **用途**: 自动化 PR review，接入任务历史
- **状态**: 架构预留

### 13. ci-analyze
- **用途**: CI 失败分析并尝试修复
- **状态**: 架构预留
