---
name: parallel-plan
description: "并行任务规划器：从自然语言需求生成结构化任务图，包含依赖分析、复杂度评分、模型路由和所有权规划。触发词：'并行规划'、'任务拆解'、'parallel plan'、'task decomposition'。"
argument-hint: "[需求描述] — 支持自然语言或文件路径"
---

# parallel-plan — 并行任务规划

## 概述

`/parallel-plan` 是 parallel-harness 的核心入口 skill。它从用户的自然语言需求出发，自动完成完整的任务规划流程。

## 执行流程

### Step 1: 意图分析
- 解析用户输入，提取结构化意图
- 识别任务类型（feature/bugfix/refactor/test/docs）
- 提取影响范围（文件路径、模块名）
- 估算整体复杂度和风险级别

### Step 2: 任务图构建
- 根据意图分析结果拆解为 DAG 任务图
- 支持三种拆分策略：
  - `file-based`: 按文件拆分，每文件一个任务
  - `feature-based`: 按功能模块拆分
  - `layer-based`: 按架构层拆分（schema → impl → test）
- 自动推断任务间依赖关系

### Step 3: 复杂度评分
- 为每个任务节点计算复杂度分数（0-100）
- 六维度加权：文件数(15%)、行数(10%)、依赖(20%)、风险(25%)、跨切(15%)、测试(15%)
- 根据分数推荐模型层级：
  - 0-30 → tier-1 (haiku): 搜索、格式化、低风险重构
  - 31-65 → tier-2 (sonnet): 实现、一般审查
  - 66-100 → tier-3 (opus): 规划、设计、关键审查

### Step 4: 所有权规划
- 为每个任务分配 allowed_paths（可操作文件）
- 为每个任务设置 forbidden_paths（禁止操作文件）
- 检测文件冲突，通过序列化依赖解决
- 确保并行执行时不产生文件竞争

### Step 5: 执行计划
- 生成分层执行计划（每层可并行）
- 估算模型成本
- 输出验证器配置（test/review/security/perf）

## 输出格式

完成规划后，输出：
1. 📊 任务图概览（节点数、依赖数、估计层数）
2. 📋 分层执行计划（每层的任务列表）
3. 💰 成本估算（按模型层级）
4. ⚠️ 风险提示（高风险任务、文件冲突）
5. ✅ 下一步建议（开始执行 or 调整计划）

## 使用示例

```
/parallel-plan 重构 src/auth/ 模块，拆分为独立的 login/register/token 服务
/parallel-plan 为 api/routes/ 下所有端点添加输入验证和错误处理
/parallel-plan 修复 #123 issue：用户无法在 Safari 中上传文件
```

## 注意事项

- 本 skill 仅生成计划，不执行实际代码修改
- 规划完成后，用户可审查并调整后再启动执行
- 与 spec-autopilot 的 /autopilot 互不干扰，可独立使用
