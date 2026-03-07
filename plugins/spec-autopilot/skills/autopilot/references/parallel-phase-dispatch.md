# 并行阶段调度模板

> 本文件由 autopilot-dispatch SKILL.md 引用。包含 Phase 1/4/5/6 的并行 Task prompt 构造模板。
> 通用并行编排协议详见 `parallel-dispatch.md`。

## 并行调度协议（v3.2.0 新增）

当阶段支持并行执行时，dispatch 按 `references/parallel-dispatch.md` 协议构造并行 Task prompt。

### 并行调度触发条件

| Phase | 并行条件 | 配置项 |
|-------|---------|--------|
| 1 | 始终并行（Auto-Scan + 调研 + 搜索） | `config.phases.requirements.research.enabled` |
| 4 | `config.phases.testing.parallel.enabled = true` | 按测试类型分组 |
| 5 | `config.phases.implementation.parallel.enabled = true` | 按文件域分组 |
| 6 | `config.phases.reporting.parallel.enabled = true`（默认 true） | 按测试套件分组 |

### Phase 1 并行调度

主线程同时派发 2-3 个 Task（不含 autopilot-phase 标记，不受 Hook 校验）：

```markdown
# Task 1: Auto-Scan（Explore agent）
Task(subagent_type: "Explore", run_in_background: true,
  prompt: "分析项目结构，生成 Steering Documents:
  - project-context.md（技术栈、目录结构）
  - existing-patterns.md（现有代码模式）
  - tech-constraints.md（技术约束）
  输出到: openspec/changes/{change_name}/context/"
)

# Task 2: 技术调研（Explore agent）
Task(subagent_type: "Explore", run_in_background: true,
  prompt: "分析与需求相关的代码:
  需求: {RAW_REQUIREMENT}
  重点: 影响范围、依赖兼容性、技术可行性
  输出到: openspec/changes/{change_name}/context/research-findings.md"
)

# Task 3: 联网搜索（条件派发）
{if config.phases.requirements.web_search.enabled}
Task(subagent_type: "general-purpose", run_in_background: true,
  prompt: "联网搜索与需求相关的最佳实践:
  需求: {RAW_REQUIREMENT}
  搜索不超过 {config.phases.requirements.web_search.max_queries} 个查询
  输出结构化结果到: research-findings.md 的 Web Research Findings 章节"
)
{end if}
```

等待全部完成 → 合并结果 → 传递给 business-analyst 分析。

### Phase 4 并行调度

按 `config.phases.testing.gate.required_test_types` 中的测试类型分组，每种类型派发一个子 Agent：

```markdown
{for each test_type in config.phases.testing.gate.required_test_types}
Task(subagent_type: "{agent_for_type}", run_in_background: true,
  prompt: "<!-- autopilot-phase:4 -->
  你是 autopilot Phase 4 的并行测试设计子 Agent（{test_type} 专项）。

  ## 需求追溯（必须遵守）
  以下是 Phase 1 确认的需求清单，每个测试用例必须关联到至少一个需求点：
  {phase1_requirements_summary}
  {phase1_decisions}

  ## 你的任务
  仅创建 {test_type} 类型的测试用例（≥ {min_test_count_per_type} 个）。
  测试套件配置: {config.test_suites[test_type]}

  ## 测试追溯要求
  每个测试用例必须包含注释，说明其追溯的需求点:
  // Traces: REQ-1.1 用户登录功能
  
  ## 返回要求
  {"status": "ok|blocked", "summary": "...", "test_counts": {"{test_type}": N}, "artifacts": [...], "test_traceability": [{"test": "...", "requirement": "..."}]}
  "
)
{end for}
```

主线程汇合后合并所有子 Agent 的 `test_counts`、`artifacts`、`test_traceability`，验证 test_pyramid。

### Phase 6 并行调度

按 `config.test_suites` 中的套件分组，每个套件派发一个子 Agent 并行执行：

```markdown
{for each suite in config.test_suites}
Task(subagent_type: "general-purpose", run_in_background: true,
  prompt: "<!-- autopilot-phase:6 -->
  你是 autopilot Phase 6 的并行测试执行子 Agent（{suite_name} 专项）。

  ## 你的任务
  执行以下测试套件并收集结果:
  - 命令: `{suite.command}`
  - 类型: {suite.type}

  ## Allure 集成
  {if config.phases.reporting.format === 'allure'}
  确保测试结果输出到 Allure 格式:
  - pytest: 添加 `--alluredir=allure-results/{suite_name}`
  - Playwright: 设置 `ALLURE_RESULTS_DIR=allure-results/{suite_name}`
  - Gradle: 复制 XML 结果到 `allure-results/{suite_name}/`
  {end if}

  ## 返回要求
  {"status": "ok|warning|failed", "summary": "...", "pass_rate": N, "total": N, "passed": N, "failed": N, "skipped": N, "artifacts": [...]}
  "
)
{end for}
```

主线程汇合后:
1. 合并所有套件的测试结果
2. 运行 `npx allure generate allure-results/ -o allure-report/ --clean`
3. 汇总 pass_rate、异常提醒、报告链接

### Phase 5 并行调度

详见 `references/parallel-dispatch.md` 的 Worktree 隔离模板和 `references/phase5-implementation.md` 的并行执行模式章节。

核心增强（v3.2.0）：
1. **混合模式** — 按独立域分组并行 + 每组完成后批量 review
2. **控制器提取全文** — 主线程一次性读取所有任务文本，subagent 不自己读计划文件
3. **subagent 提问机制** — subagent 可通过 AskUserQuestion 向用户提问
4. **同一 agent 修复** — 发现问题后 resume 同一 agent 修复，不切换上下文

## 代码生成约束增强（v3.2.0 新增）

### 新增配置项

```yaml
code_constraints:
  # 已有
  forbidden_files: [...]
  forbidden_patterns: [...]
  allowed_dirs: [...]
  max_file_lines: 800
  
  # v3.2.0 新增
  required_patterns:
    - pattern: "createWebHashHistory"
      context: "Vue Router 配置文件"
      message: "Must use Hash mode routing"
  style_guide: "rules/frontend/README.md"  # 注入到 Phase 5 prompt
```

### Phase 5 prompt 增强注入

```markdown
## 代码约束（ENFORCED — Hook 确定性拦截）

### 禁止项
{for each p in config.code_constraints.forbidden_patterns}
- ❌ `{p.pattern}` → {p.message}
{end for}

### 必须使用
{for each p in config.code_constraints.required_patterns}
- ✅ `{p.pattern}` — {p.message}（在 {p.context} 中必须出现）
{end for}

### 代码风格指南
{if config.code_constraints.style_guide}
请读取并遵守: {config.code_constraints.style_guide}
{end if}
```

## 需求理解增强（v3.2.0 新增）

### 复杂度自适应调研深度

| 复杂度 | Auto-Scan | 技术调研 | 联网搜索 | 竞品分析 |
|--------|-----------|---------|---------|---------|
| small | ✅ | ❌ | ❌ | ❌ |
| medium | ✅ | ✅（并行） | ❌ | ❌ |
| large | ✅ | ✅（并行） | ✅（并行） | ✅（并行） |

> 注意：复杂度评估发生在第一轮调研（Auto-Scan）完成后。small 不触发额外调研。
> medium/large 的额外调研以并行方式执行，不增加总耗时。

### 主动决策增强

所有复杂度级别均展示决策卡片（v3.2.0 取消 small 豁免）：
- **small**: 仅关键技术决策点（1-2 个卡片）
- **medium**: 所有识别到的决策点 + 调研依据
- **large**: 全部决策点 + 调研依据 + 竞品对比 + 推荐方案

决策卡片增强字段（v3.2.0）：
```json
{
  "point": "决策点描述",
  "options": [...],
  "research_evidence": "来自 research-findings.md 的数据支撑",
  "recommended": "B",
  "recommendation_reason": "基于调研数据的推荐理由"
}
```

`config.phases.requirements.decision_mode`:
- `proactive`（默认）: AI 主动识别决策点并展示
- `reactive`: 仅在用户提问时展示
