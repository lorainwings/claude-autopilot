---
name: autopilot
description: "Full autopilot orchestrator: requirements → OpenSpec → implementation → testing → reporting → archive. Triggers: '全自动开发流程', '一键从需求到交付', '启动autopilot'. NOT for single-phase tasks like /opsx:apply or /opsx:ff."
argument-hint: "[需求描述或 PRD 文件路径]"
---

# Autopilot — 主线程编排器

在主线程中直接执行 8 阶段全自动交付流水线。Phase 2-6 通过 Task 工具派发**单层**子 Agent。

> **架构约束**: 子 Agent 内部没有 Task 工具，所有 Task 派发必须在主线程中执行，禁止嵌套。

## 配置加载

启动时**必须**读取 `.claude/autopilot.config.yaml`，从中获取：

| 配置节 | 用途 |
|--------|------|
| `services` | 服务健康检查地址 |
| `phases.requirements` | 需求分析 Agent、最少 QA 轮数 |
| `phases.testing` | 测试 Agent、instruction_files、reference_files、gate 门禁阈值 |
| `phases.implementation` | instruction_files、ralph_loop 配置（enabled/max_iterations/fallback_enabled） |
| `phases.reporting` | instruction_files、report_commands、coverage_target、zero_skip_required |
| `test_suites` | 各测试套件命令和类型 |

如果配置文件不存在 → 自动调用 Skill(`spec-autopilot:autopilot-init`) 扫描项目生成配置。

## 协议技能

| 技能 | 用途 |
|------|------|
| `spec-autopilot:autopilot-recovery` | 崩溃恢复协议 |
| `spec-autopilot:autopilot-gate` | 阶段门禁验证 |
| `spec-autopilot:autopilot-dispatch` | 子 Agent 调度构造 |
| `spec-autopilot:autopilot-checkpoint` | 检查点读写管理 |

## 阶段总览

| Phase | 执行位置 | Description |
|-------|----------|-------------|
| 0 | 主线程 | 环境检查 + 崩溃恢复 |
| 1 | 主线程 | 需求理解与多轮决策（LOOP 直到全部澄清） |
| 2 | Task 子 Agent | 创建 OpenSpec 并保存上下文 |
| 3 | Task 子 Agent | OpenSpec 快进生成制品 |
| 4 | Task 子 Agent | 测试用例设计（强制，不可跳过） |
| 5 | Task 子 Agent | Ralph Loop / Fallback 循环实施 |
| 6 | Task 子 Agent | 测试报告生成（强制，不可跳过） |
| 7 | 主线程 | 汇总展示 + **用户确认**归档 |

---

## Phase 0: 环境检查 + 崩溃恢复

1. 检查 `.claude/autopilot.config.yaml` 是否存在
   - **不存在** → 调用 Skill(`spec-autopilot:autopilot-init`) 自动扫描项目并生成配置
   - **存在** → 直接读取并解析所有配置节
2. 读取 `.claude/settings.json` 的 `enabledPlugins` → 检查 ralph-loop 插件是否启用
3. **调用 Skill(`spec-autopilot:autopilot-recovery`)**：扫描 checkpoint，决定起始阶段
4. 使用 TaskCreate 创建 8 个阶段任务 + blockedBy 依赖链
   - 崩溃恢复时：已完成阶段直接标记 completed

## Phase 1: 需求理解与多轮决策（主线程）

**核心原则**: 绝不假设，始终列出选项由用户决策。

### 1.1 获取需求来源

- `$ARGUMENTS` 为文件路径 → 读取文件内容
- `$ARGUMENTS` 为文本 → 直接作为需求描述
- `$ARGUMENTS` 为空 → AskUserQuestion 要求输入

### 1.2 需求分析

调用 Task(subagent_type = config.phases.requirements.agent) 分析需求，产出:
- 功能清单
- 疑问点列表（每个疑问必须转化为决策点）
- 技术可行性初判

### 1.3 多轮决策循环（LOOP）

**循环条件**: 存在任何未澄清的决策点

每轮循环:
1. 梳理当前所有未决策点
2. 将每个决策点转化为 AskUserQuestion（2-4 个选项，推荐方案标 Recommended）
3. 收集用户决策结果
4. 检查是否产生新的决策点
5. 重复直到**所有点全部澄清**

### 1.4 生成结构化提示词

整理所有决策结果，包含: 背景与目标、功能清单、决策结论、技术约束、验收标准。

### 1.5 最终确认

展示完整提示词，AskUserQuestion:
"以上需求理解是否准确？如有遗漏请补充。"
选项: "确认，开始实施 (Recommended)" / "需要补充修改"
- 选"补充" → 回到 1.3 循环

---

## Phases 2-6: 统一调度模板

对于每个 Phase N（2 ≤ N ≤ 6），在**主线程**中执行：

```
Step 1: 调用 Skill("spec-autopilot:autopilot-gate")
        → 执行 8 步阶段切换检查清单（验证 Phase N-1 checkpoint）
Step 2: 调用 Skill("spec-autopilot:autopilot-dispatch")
        → 按协议构造 Task prompt
        → 从 config.phases[当前阶段].instruction_files 注入指令文件路径
        → 从 config.phases[当前阶段].reference_files 注入参考文件路径
Step 3: 使用 Task 工具派发子 Agent
        → prompt 开头必须包含 <!-- autopilot-phase:N --> 标记
        → Hook 脚本自动校验前置 checkpoint 和返回 JSON
Step 4: 解析子 Agent 返回的 JSON 信封
        → ok → 继续
        → warning → **Phase 4 特殊处理**（见下方）
        → blocked/failed → 暂停展示给用户
Step 5: 调用 Skill("spec-autopilot:autopilot-checkpoint")
        → 写入 phase-results checkpoint 文件
Step 6: TaskUpdate Phase N → completed
```

### Phase 4 特殊门禁

autopilot-gate 额外验证（阈值从 config.phases.testing.gate 读取）：
- `test_counts` 每个字段 ≥ config.phases.testing.gate.min_test_count_per_type
- `artifacts` 包含 config.phases.testing.gate.required_test_types 对应文件
- `dry_run_results` 全部为 0（exit code）

**Phase 4 warning 降级阻断规则**：

Phase 4 返回 `status: "warning"` 时，主线程**必须**执行以下检查：
1. 检查 `test_counts` 是否所有字段 ≥ min_test_count_per_type
2. 检查 `artifacts` 是否非空
3. **如果 test_counts 任一字段 < min_test_count_per_type 或 artifacts 为空**：
   - 将 status 强制覆盖为 `"blocked"`
   - 不写入 checkpoint
   - 展示给用户：「Phase 4 返回 warning 但未创建足够测试用例，视为 blocked」
   - 重新 dispatch Phase 4

Phase 4 **不允许**以 warning 状态通过门禁。要么 ok（测试全部创建），要么 blocked（需要排除障碍）。

### Phase 5 特殊处理

1. 检查 `.claude/settings.json` 中 `enabledPlugins` 是否包含 `ralph-loop`
2. **可用** → 通过 Skill 调用 `ralph-loop:ralph-loop`，读取 config.phases.implementation
3. **不可用但 config.phases.implementation.ralph_loop.fallback_enabled** → 进入手动循环模式
   - 每次迭代执行 Skill(`openspec-apply-change`) 实施一个任务
   - 每任务后运行 quick_check，每 3 任务运行 full_test
   - 遵循 3 次失败暂停策略
   - 最大迭代次数从 config.phases.implementation.ralph_loop.max_iterations 读取
4. **不可用且 fallback 禁用** → AskUserQuestion：
   ```
   "ralph-loop 插件不可用，手动 fallback 也已禁用。请选择处理方式："
   选项:
   - "启用 fallback 模式 (Recommended)" → 修改 config 中 fallback_enabled 为 true，进入手动循环
   - "暂停流水线，手动安装 ralph-loop" → 展示安装命令，暂停等待
   - "跳过实施阶段（仅测试已有代码）" → 标记 Phase 5 为 warning，继续 Phase 6
   ```

### Phase 5→6 特殊门禁

autopilot-gate 额外验证：
- `test-results.json` 存在
- `zero_skip_check.passed === true`
- `tasks.md` 中所有任务标记为 `[x]`

---

## Phase 7: 汇总 + 用户确认归档（主线程）

1. 读取所有 phase-results checkpoint，展示状态汇总表
2. **必须** AskUserQuestion 询问用户：
   ```
   "所有阶段已完成。是否归档此 change？"
   选项:
   - "立即归档 (Recommended)"
   - "暂不归档，稍后手动处理"
   - "需要修改后再归档"
   ```
3. 用户选择"立即归档" → 执行 Skill(`openspec-archive-change`)
4. 用户选择"暂不归档" → 展示手动归档命令，结束流程
5. 用户选择"需要修改" → 提示用户修改后可重新触发或手动归档

**禁止自动归档**: 归档操作必须经过用户明确确认。

---

## 护栏约束

| 约束 | 规则 |
|------|------|
| 主线程编排 | 所有 Task 派发在主线程执行，禁止嵌套 Task |
| 配置驱动 | 所有项目路径从 autopilot.config.yaml 读取，禁止硬编码 |
| 阶段门禁 | Hook 确定性 + autopilot-gate 检查清单 |
| 阶段跳过阻断 | Hook + TaskCreate blockedBy 确定性阻断 |
| 任务系统 | Phase 0 创建 8 个阶段任务 + blockedBy 链 |
| 崩溃恢复 | autopilot-recovery Skill 扫描 checkpoint |
| 结构化标记 | 子 Agent prompt 开头包含 `<!-- autopilot-phase:N -->` |
| 结构化返回 | 子 Agent 必须返回 JSON 信封 |
| 测试不可变 | 禁止修改测试以通过；只能修改实现代码 |
| 零跳过 | Phase 6 零跳过门禁 |
| 任务拆分 | 每次 ≤3 个文件，≤800 行代码 |
| 归档确认 | Phase 7 必须经用户确认后才能归档 |

## 错误处理

| 场景 | 处理方式 |
|------|----------|
| 配置文件缺失 | 调用 autopilot-init 自动生成 |
| 工具未安装 | 主动安装，失败则联网搜索 |
| ralph-loop 异常退出 | 保存进度到 phase-results，提示用户 |
| 测试全部失败 | 分析根因，不盲目修改 |
| 子 Agent 返回异常 | JSON 解析失败 → 标记 failed |
| 阶段状态文件缺失 | 视为未完成，重新执行 |
| **上下文压缩** | 见下方恢复协议 |

## 上下文压缩恢复协议

长流水线执行中 Claude Code 可能触发上下文压缩（compaction），导致对话历史被摘要化，丢失精确的阶段状态。

### 自动机制（Hook 驱动，无需主线程干预）

1. **PreCompact Hook**：压缩前自动将当前编排状态写入 `openspec/changes/<name>/context/autopilot-state.md`
2. **SessionStart(compact) Hook**：压缩后自动将状态文件内容注入回 Claude 上下文

### 主线程恢复行为

如果检测到上下文被压缩（收到 `=== AUTOPILOT STATE RESTORED ===` 标记），主线程应：

1. 读取 `autopilot-state.md` 获取当前进度（last completed phase、next phase）
2. 读取 `autopilot.config.yaml` 重新加载配置
3. 读取 `context/phase-results/` 目录下所有 checkpoint 确认状态
4. 从下一个未完成阶段继续执行，无需重建 TaskCreate 链（已有的 Task 仍然有效）
5. 调用 Skill(`spec-autopilot:autopilot-gate`) 验证前置条件后继续 dispatch
