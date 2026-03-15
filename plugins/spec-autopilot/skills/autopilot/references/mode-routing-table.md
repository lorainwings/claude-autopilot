# Mode Routing Table — 执行模式路由声明表

> 本文件以声明式表格定义三种模式的阶段序列、跳过规则、任务来源和路径选择逻辑。
> 主编排器引用本表进行模式路由，不在 SKILL.md 中重复条件分支。

## 1. 模式 → 阶段序列映射

| 模式 | 阶段序列 | 跳过的阶段 | 适用场景 |
|------|---------|-----------|---------|
| **full** | 0→1→2→3→4→5→6→7 | 无 | 中大型功能，完整规范 |
| **lite** | 0→1→5→6→7 | 2, 3, 4 | 小功能，需求明确 |
| **minimal** | 0→1→5→7 | 2, 3, 4, 6 | 极简需求 |

## 2. 模式解析优先级

```
1. $ARGUMENTS 首个 token 匹配 full|lite|minimal → 直接使用
2. config.default_mode → 配置默认值
3. 未指定 → "full"
```

## 3. Phase 5 任务来源（模式感知）

| 模式 | 任务来源 |
|------|---------|
| **full** | `openspec/changes/<name>/tasks.md`（Phase 3 生成） |
| **lite/minimal** | Phase 5 启动时从 `phase-1-requirements.json` 自动拆分 → `context/phase5-task-breakdown.md` |

## 4. Phase 5 路径选择（互斥）

> **HARD CONSTRAINT**: 路径选择由配置决定，禁止 AI 自主判断。

| 条件 | 路径 | 说明 |
|------|------|------|
| `tdd_mode: true` 且 `mode: full` | **C — TDD** | 优先级最高，RED-GREEN-REFACTOR 循环 |
| `parallel.enabled: true` | **A — 并行** | worktree 隔离 + 后台 Task |
| `parallel.enabled: false` 或降级 | **B — 串行** | 逐个前台 Task，上下文隔离 |

### 路径 A 降级条件（仅此情况允许）

| 条件 | 动作 |
|------|------|
| 合并失败 > 3 文件 | 降级至路径 B |
| 连续 2 组 Agent 失败 | AskUserQuestion 决策 |
| 用户显式选择 | 切换模式 |

## 5. Phase 4 TDD 跳过逻辑

| 条件 | Phase 4 行为 | 输出 |
|------|-------------|------|
| `tdd_mode: true` 且 `mode: full` | **跳过** | 写入 `phase-4-tdd-override.json` |
| 其他 | **正常执行** | 按 gate 门禁验证 |

## 6. 门禁跳过矩阵（模式感知）

| 切换点 | full | lite | minimal |
|--------|------|------|---------|
| 1→2 | 正常 | **跳过** | **跳过** |
| 2→3 | 正常 | **跳过** | **跳过** |
| 3→4 | 正常 | **跳过** | **跳过** |
| 4→5 | 正常 + 特殊门禁 | **跳过**（1→5） | **跳过**（1→5） |
| 5→6 | 正常 + 特殊门禁 | 正常 + 特殊门禁 | **跳过**（5→7） |
| 6→7 | 正常 | 正常 | **跳过** |

## 7. Phase 6 三路并行

| 路径 | 内容 | 参考文档 | 阻断关系 |
|------|------|---------|---------|
| A | 测试执行 | `parallel-phase6.md` | Phase 7 必须等待 |
| B | 代码审查（可选） | `phase6-code-review.md` | 不阻断路径 A |
| C | 质量扫描 | `quality-scans.md` | 不阻断路径 A |

所有路径 `run_in_background: true`。路径 B/C 不含 `autopilot-phase` 标记。Phase 7 统一收集。
