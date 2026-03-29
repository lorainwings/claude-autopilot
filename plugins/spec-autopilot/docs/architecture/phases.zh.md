> [English](phases.md) | 中文

# 阶段详解

> 各阶段执行指南，涵盖输入、输出、检查点格式和关键行为。

## 阶段概览

| 阶段 | 执行者 | 关键行为 | 检查点 |
|------|--------|---------|--------|
| 0 | 主线程 | 环境检查 + 崩溃恢复 | 无 |
| 1 | 主线程 | 多轮决策循环 + 需求类型路由 (routing_overrides, v4.2) | `phase-1-requirements.json` |
| 2 | 子 Agent | 创建 OpenSpec 变更目录 | `phase-2-openspec.json` |
| 3 | 子 Agent | FF 生成全部制品 | `phase-3-ff.json` |
| 4 | 子 Agent | 测试用例设计（必选） | `phase-4-testing.json` |
| 5 | 子 Agent | 实施：串行 / 并行 / TDD | `phase-5-implement.json` |
| 6 | 子 Agent | 测试报告生成（必选） | `phase-6-report.json` |
| 7 | 主线程 | 汇总 + Archive Readiness 自动归档 | `phase-7-summary.json` |

## Phase 0：环境检查 + 崩溃恢复

**执行者**：主线程

### 步骤

1. 检查 `autopilot.config.yaml` 是否存在 → 不存在则调用 `autopilot-init`
2. 通过 `validate-config.sh` 验证配置 schema
3. 检查 settings.json 中已启用的插件
4. 调用 `autopilot-recovery` Skill 扫描检查点
5. 创建 8 个阶段任务，设置 blockedBy 依赖链
6. 写入 `.autopilot-active` 锁文件
7. 创建锚点提交：`git commit --allow-empty -m "autopilot: start <name>"`

### 输出

- 锁文件：`openspec/changes/.autopilot-active`
- 任务系统中的 8 个任务（含依赖链）

## Phase 1：需求理解

**执行者**：主线程
**参考文档**：`references/phase1-requirements.md`

### 步骤

1. 解析 `$ARGUMENTS`（文件路径、文本或空 → 向用户询问）
2. **自动扫描**：扫描项目结构 → 生成引导文档（project-context.md、existing-patterns.md、tech-constraints.md）
3. **调研 Agent**：派遣 Explore Agent → 分析相关代码、依赖兼容性、技术可行性 → research-findings.md
4. **复杂度路由**：基于调研结果评估复杂度（小型 ≤2 文件 / 中型 3-5 文件 / 大型 6+ 文件）
5. 派遣业务分析师子 Agent 进行分析（注入引导文档 + 调研上下文）
6. **多轮决策循环**，直到所有要点澄清（复杂度影响循环深度）
7. 生成结构化提示词
8. 用户最终确认
9. 写入检查点
10. 可选用户门禁（`config.gates.user_confirmation.after_phase_1`）

### 模式

| 模式 | 行为 |
|------|------|
| `structured`（默认） | 标准 AskUserQuestion 流程 |
| `socratic` | 按 6 步协议提出额外质询问题 |

#### Socratic 模式步骤（v5.0.6 扩展）

| 步骤 | 内容 |
|------|------|
| 1-6 | 标准 6 步质询协议 |
| **7 (v5.0.6)** | 非功能需求质询：性能指标、安全约束、可访问性、国际化需求 |

### 复杂度路由

| 复杂度 | 讨论深度 | Socratic 模式 | 最少 QA 轮次 |
|--------|---------|---------------|-------------|
| 小型 | 快速确认 — 展示调研结论，用户确认 | 禁用 | 1 |
| 中型 | 标准 — 完整决策循环 | 遵循配置 | 2-3 |
| 大型 | 深度 — 强制 Socratic 模式 | 强制开启 | 3+ |

当可行性评分低、存在高严重性风险或需要 3 个以上新依赖时，自动升级为 `large`。

### 引导文档（自动生成）

| 文件 | 内容 |
|------|------|
| `context/project-context.md` | 技术栈、目录结构、关键依赖、编码约束、测试基础设施 |
| `context/existing-patterns.md` | API 模式、数据模型、组件模式、错误处理 |
| `context/tech-constraints.md` | 硬性约束、依赖约束、基础设施约束 |
| `context/research-findings.md` | 影响分析、依赖检查、可行性评估、风险 |

### 需求类型路由（v4.2）

Phase 1 分析结果自动将需求分类为以下类型，并动态调整后续阶段门禁阈值：

| 需求类型 | 分类规则 | 门禁调整 |
|---------|---------|---------|
| **Feature** | 新功能、新组件、新 API | 默认阈值 |
| **Bugfix** | 缺陷修复、行为修正 | sad_path ≥ 40%, coverage = 100%, 必须含复现测试 |
| **Refactor** | 代码重构、性能优化 | coverage = 100%, 必须含行为保持测试 |
| **Chore** | CI/CD、文档、依赖升级 | coverage ≥ 60%, typecheck 通过即可 |

分类结果写入检查点的 `requirement_type` 字段。复合需求 (v5.0.6) 使用数组格式并通过 `routing_overrides` 传递合并后的阈值覆盖。

### 检查点格式

```json
{
  "status": "ok",
  "summary": "Requirements complete, N features, M decisions confirmed",
  "artifacts": [
    "context/prd.md", "context/discussion.md",
    "context/project-context.md", "context/existing-patterns.md",
    "context/tech-constraints.md", "context/research-findings.md"
  ],
  "requirements_summary": "...",
  "decisions": [{"point": "...", "choice": "..."}],
  "change_name": "<kebab-case-name>",
  "complexity": "small | medium | large",
  "requirement_type": "feature | bugfix | refactor | chore",
  "routing_overrides": {
    "sad_path_min_pct": 20,
    "change_coverage_min_pct": 80,
    "require_reproduction_test": false,
    "require_behavior_preservation_test": false
  },
  "research": {
    "status": "completed | skipped",
    "impact_files": 0,
    "estimated_loc": 0,
    "feasibility_score": "high | medium | low",
    "new_deps_count": 0
  },
  "steering_artifacts": [
    "context/project-context.md",
    "context/existing-patterns.md",
    "context/tech-constraints.md"
  ],
  "_metrics": { "start_time": "...", "end_time": "...", "duration_seconds": 0, "retry_count": 0 }
}
```

## Phase 2：创建 OpenSpec

**执行者**：子 Agent

### 输入

- Phase 1 检查点（需求摘要、决策）
- 配置中的项目结构

### 检查点格式

```json
{
  "status": "ok",
  "summary": "OpenSpec change created",
  "artifacts": ["openspec/changes/<name>/proposal.md"],
  "_metrics": { ... }
}
```

## Phase 3：FF 生成

**执行者**：子 Agent

### 输入

- OpenSpec 变更目录
- Phase 2 检查点

### 检查点格式

```json
{
  "status": "ok",
  "summary": "FF generated: proposal, design, specs, tasks",
  "artifacts": ["openspec/changes/<name>/design.md", "openspec/changes/<name>/tasks.md"],
  "_metrics": { ... }
}
```

## Phase 4：测试设计

**执行者**：子 Agent（必选，不可跳过）

### 输入

- Phase 3 的设计和任务
- `config.phases.testing.instruction_files`
- `config.phases.testing.reference_files`
- `config.phases.testing.gate` 阈值

### 特殊规则

- **不接受 warning 状态**：仅接受 `ok` 或 `blocked`
- **测试金字塔强制**：第 2 层（Hook）检查下限，第 3 层（AI）检查配置阈值
- **必须产出制品**：必须生成实际的测试文件

### 检查点格式

```json
{
  "status": "ok",
  "summary": "Test cases designed: N unit, M api, P e2e, Q ui",
  "artifacts": ["tests/unit/test_feature.py", "tests/e2e/test_flow.spec.ts"],
  "test_counts": { "unit": 15, "api": 8, "e2e": 5, "ui": 3 },
  "dry_run_results": { "unit": 0, "api": 0, "e2e": 0, "ui": 0 },
  "test_pyramid": { "unit_pct": 48, "e2e_pct": 16 },
  "_metrics": { ... }
}
```

## Phase 5：实施

**执行者**：子 Agent
**参考文档**：`references/phase5-implementation.md`

### 安全准备

1. Git 安全标签：`git tag -f autopilot-phase5-start HEAD`
2. 将开始时间戳写入 `phase5-start-time.txt`

### 执行模式

| 优先级 | 模式 | 条件 |
|--------|------|------|
| 1 | 并行（worktree） | `config.phases.implementation.parallel.enabled = true` |
| 2 | 串行（前台 Task） | `config.phases.implementation.parallel.enabled = false`（默认） |

### 任务级检查点

每个完成的任务写入 `phase-results/phase5-tasks/task-N.json`：

```json
{
  "task_number": 1,
  "task_title": "Implement login API",
  "status": "ok",
  "summary": "Completed, 3 tests pass",
  "artifacts": ["src/LoginController.java"],
  "test_result": "3/3 passed",
  "_metrics": { ... }
}
```

### 墙钟超时

- 2 小时硬限制，由 Hook（第 2 层）强制执行
- Skill 级软限制：2 小时后 AskUser
- 选项：继续 / 保存并暂停 / 回滚到起始标签

### 事件发射（v4.2/v5.0）

Phase 5 每个 task 完成后通过 `emit-task-progress.sh` 发射 `task_progress` 事件：

```bash
bash scripts/emit-task-progress.sh <phase> <task_name> <status> <task_index> <task_total> [tdd_step]
```

事件实时推送到 `logs/events.jsonl` 和 WebSocket（`ws://localhost:8765`），供 GUI 大盘实时渲染任务进度。

### TDD 确定性循环（v4.1）

当 `tdd_mode: true` 时，每个 task 按 RED-GREEN-REFACTOR 循环执行：

| 阶段 | 行为 | L2 验证 |
|------|------|---------|
| **RED** | 仅写测试，运行必须失败（`exit_code != 0`） | Bash 确定性验证 |
| **GREEN** | 仅写实现，运行必须通过（`exit_code = 0`） | Bash 确定性验证 |
| **REFACTOR** | 重构，测试必须保持通过 | 失败 → `git checkout` 自动回滚 |

> GREEN 失败时修复实现代码，禁止修改测试文件。

### 检查点格式

```json
{
  "status": "ok",
  "summary": "All tasks implemented, tests passing",
  "artifacts": ["src/..."],
  "test_results_path": "testreport/test-results.json",
  "tasks_completed": 8,
  "zero_skip_check": { "passed": true },
  "tdd_metrics": {
    "red_pass": true,
    "green_pass": true,
    "refactor_pass": true,
    "cycle_count": 8
  },
  "_metrics": { ... }
}
```

## Phase 6：测试报告

**执行者**：子 Agent（必选，不可跳过）

### 输入

- Phase 5 的测试结果
- `config.phases.reporting` 设置
- `config.phases.reporting.report_commands`

### 检查点格式

```json
{
  "status": "ok",
  "summary": "Test report generated, 98.5% pass rate",
  "artifacts": ["reports/test-report.html"],
  "pass_rate": 98.5,
  "report_path": "reports/test-report.html",
  "report_format": "allure",
  "_metrics": { ... }
}
```

## Phase 6→7 过渡：并行质量扫描

**参考文档**：`references/quality-scans.md`

在 Phase 6 和 7 之间，派遣后台质量扫描：

- 契约测试
- 性能审计（Lighthouse）
- 视觉回归
- 变异测试

硬超时：`config.async_quality_scans.timeout_minutes`（默认 10 分钟）。超时 → 自动标记为 `"timeout"`，不提示用户。

## Phase 7：汇总 + 归档

**执行者**：主线程

### 步骤

1. 读取所有检查点，显示状态汇总表
2. 通过 `collect-metrics.sh` 收集指标，显示计时表
3. 收集质量扫描结果（含硬超时）
4. **AskUser**：立即归档 / 稍后 / 需要修改
5. 如果归档：
   a. Git 自动压缩 fixup 提交（如果 `squash_on_archive: true`）
   b. 执行归档 Skill
   c. 将 Phase 7 检查点更新为 `ok`
6. 清理：删除锁文件、开始时间文件、git 标签

### 指标汇总表

```
| Phase | Status | Duration | Retries |
|-------|--------|----------|---------|
| 1     | ok     | 5m 30s   | 0       |
| 2     | ok     | 2m 15s   | 0       |
| ...   | ...    | ...      | ...     |
| Total |        | 85m 00s  | 3       |
```

### 检查点格式

```json
{
  "status": "ok",
  "summary": "Archive complete",
  "phase": 7,
  "archived_change": "<name>",
  "_metrics": { ... }
}
```
