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

## 4. Phase 5 路径选择（优先级链）

> **HARD CONSTRAINT**: 路径选择由配置决定，禁止 AI 自主判断。

### 决策流程图

```
                    ┌──────────────────────┐
                    │ Phase 5 路径选择入口  │
                    └──────────┬───────────┘
                               │
                    ┌──────────▼───────────┐
                    │ tdd_mode: true       │
                    │ 且 mode: full ?      │
                    └──────┬────────┬──────┘
                      YES  │        │ NO
                           │        │
               ┌───────────▼──┐  ┌──▼──────────────┐
               ��� 路径 C: TDD  │  │ parallel.enabled │
               │ (最高优先级) │  │ = true ?         │
               └───────┬──────┘  └──┬─────────┬────┘
                       │          YES│         │NO
            ┌──────────▼─────┐  ┌───▼─────┐ ┌─▼───────┐
            │ parallel.enabled│  │ 路径 A  │ │ 路径 B  │
            │ = true ?       │  │ 并行    │ │ 串行    │
            └──┬──────┬──────┘  └─────────┘ └─────────┘
            YES│      │NO
         ┌─────▼────┐ ┌▼──────────┐
         │ 并行 TDD │ │ 串行 TDD  │
         │ C+A 混合 │ │ C+B 混合  │
         └──────────┘ └───────────┘
```

### 路径优先级表

| 优先级 | 条件 | 路径 | 说明 |
|--------|------|------|------|
| 1 (最高) | `tdd_mode: true` 且 `mode: full` 且 `parallel.enabled: true` | **C+A — 并行 TDD** | 域 Agent 内部自执行 RED-GREEN-REFACTOR + 合并后 L2 验证 |
| 2 | `tdd_mode: true` 且 `mode: full` 且 `parallel.enabled: false` | **C+B — 串行 TDD** | 每 task 3 个 sequential Task (RED→GREEN→REFACTOR) + L2 Bash 验证 |
| 3 | `tdd_mode: false` 且 `parallel.enabled: true` | **A — 并行** | worktree 隔离 + 后台 Task |
| 4 (最低) | `tdd_mode: false` 且 `parallel.enabled: false` 或降级 | **B — 串行** | 逐个前台 Task，上下文隔离 |

> **关键设计**: TDD 是**正交修饰符**而非独立第三路径。TDD 启用时与 parallel.enabled **组合使用**，不替代并行/串行的选择。
> 路径 A 与路径 B 互斥，TDD(C) 叠加在 A 或 B 之上。

### 路径 A 降级条件（仅此情况允许）

| 条件 | 动作 |
|------|------|
| 合并失败 > 3 文件 | 降级至路径 B |
| 连续 2 组 Agent 失败 | AskUserQuestion 决策 |
| 用户显式选择 | 切换模式 |

## 5. Phase 4 与 TDD 的关系（决策矩阵）

> Phase 4（测试用例设计）与 TDD 模式互斥：TDD 模式下测试在 Phase 5 per-task 创建，因此 Phase 4 跳过。

### 完整决策矩阵

```
┌─────────────────────┬─────────────────────┬──────────────────────────────┐
│ 配置组合            │ Phase 4 行为         │ Phase 5 测试来源             │
├─────────────────────┼─────────────────────┼──────────────────────────────┤
│ full + tdd_mode     │ 跳过 (skipped_tdd)  │ TDD RED 阶段创建             │
│ full + 非 tdd       │ 正常执行            │ Phase 4 测试文件 (L2 验证)   │
│ lite (任意 tdd 值)  │ 跳过 (模式跳过)     │ Phase 5 自动拆分             │
│ minimal (任意)      │ 跳过 (模式跳过)     │ Phase 5 自动拆分             │
└─────────────────────┴─────────────────────┴──────────────────────────────┘
```

### Phase 4 跳过的链路说明

**TDD 模式跳过链路** (`tdd_mode: true` + `mode: full`):
```
Phase 3 checkpoint(ok)
  → Gate 3→4 通过
  → Phase 4 Skill 调用 check-tdd-mode.sh → 返回 TDD_SKIP
  → 写入 phase-4-tdd-override.json (status:ok, tdd_mode_override:true)
  → Gate 4→5 特殊门禁: 验证 tdd-override 存在且 tdd_mode_override===true
  → Phase 5 路径 C (TDD): RED 阶段创建测试 + GREEN 阶段写实现
```

**非 TDD 正常链路** (`tdd_mode: false` + `mode: full`):
```
Phase 3 checkpoint(ok)
  → Gate 3→4 通过
  → Phase 4 Skill 调用 check-tdd-mode.sh → 返回 TDD_DISPATCH
  → 正常 dispatch 测试设计 Agent
  → 写入 phase-4-testing.json (test_counts, artifacts, dry_run_results)
  → Gate 4→5: 验证 test_counts >= min, artifacts 存在, dry_run 全 0
  → Phase 5 路径 A/B: 使用 Phase 4 测试文件进行 L2 RED/GREEN 验证
```

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
