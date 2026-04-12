# Autopilot 共享协议参考

> 此文件被 autopilot-dispatch、autopilot-gate（含 checkpoint 管理）共同引用。修改时需同步评估影响。

## JSON 信封契约

每个子 Agent **必须**返回此格式：

```json
{
  "status": "ok | warning | blocked | failed",
  "summary": "单行决策级摘要",
  "artifacts": ["已创建/修改的文件路径"],
  "risks": ["可选风险列表"],
  "next_ready": true
}
```

写入 checkpoint 时自动追加 `timestamp`（ISO-8601）和 `phase`（阶段编号）字段。

## 各阶段额外返回字段

| Phase | 必须字段 | 可选字段 |
|-------|----------|----------|
| 1 | `requirements_summary`, `decisions: [DecisionPoint]`, `change_name`, `complexity: "small\|medium\|large"`, `research: { status, impact_files, estimated_loc, feasibility_score, new_deps_count }`, `discussion_rounds: number` | `open_questions`, `steering_artifacts`, `requirement_type: "feature\|bugfix\|refactor\|chore"`, `routing_overrides: { sad_path_min_ratio_pct, change_coverage_min_pct, required_test_types }`, `web_research: { queries_executed, best_practices, similar_implementations, dependency_evaluation, recommended_approach }`, `clarity_score: number`, `clarity_breakdown: object`, `challenge_agents_activated: [string]`, `challenge_insights: [object]`, `stagnation_detected: boolean` |
| 4 | `test_counts: { unit, api, e2e, ui }`, `sad_path_counts: { unit, api, e2e, ui }`, `dry_run_results: { unit, api, e2e, ui }`, `test_pyramid: { total, unit_pct, integration_pct, e2e_pct }`, `change_coverage: { change_points, tested_points, coverage_pct, untested_points }` | `test_traceability: [{ test, requirement }]` |
| 5 | `test_results_path`, `tasks_completed`, `zero_skip_check: { passed: bool }` | `iterations_used`, `code_quality: { constraint_violations: number, violations: [{rule, file, detail}] }`, `parallel_metrics: { mode, groups_count, fallback_reason }`, `tdd_metrics: { total_cycles, red_violations, green_retries, refactor_reverts }` (TDD mode), `test_driven_evidence: { phase4_tests_path, red_verified, green_verified, red_output_excerpt, red_skipped_reason }` (full mode, non-TDD). `red_verified: true` 表示测试确实先失败后通过（有效 RED→GREEN 转变）；`red_verified: false` + `red_skipped_reason` 表示 RED 阶段测试已通过，证据不完整——此 task 仅证明"实现前后测试均通过"，不构成测试驱动证据。Phase 7 汇总时应分别统计两类结果。 |
| 6 | `pass_rate`, `report_path`, `report_format` | `report_url`, `allure_results_dir`, `suite_results: [{ suite, total, passed, failed, skipped }]`, `anomaly_alerts: [string]`, `red_evidence: string`, `sample_failure_excerpt: string`. **`report_url` 说明**: Phase 6 生成时为 `file://` 本地路径；Phase 7 Step 2.5 启动 Allure 服务后更新为 `http://localhost:{port}` |
| 7 | `archive_path`, `change_name` | `cleanup_actions`, `knowledge_extracted: number` |

## 状态解析规则

| status | 主线程行为 |
|--------|-----------|
| ok | 写入 checkpoint，继续下一阶段 |
| warning | 写入 checkpoint，展示警告后继续（**Phase 4 例外**） |
| blocked | 暂停，展示给用户，要求排除阻塞 |
| failed | 暂停，展示给用户，可能需要重新执行本阶段 |

**Phase 4 特殊规则**：不接受 warning。warning 且 test_counts < 门禁阈值 → 强制覆盖为 blocked。

## 结构化标记（Hook 识别依据）

子 Agent prompt **开头第一行**必须包含：

```
<!-- autopilot-phase:{phase_number} -->
```

无标记的 Task 调用被 Hook 直接放行（exit 0）。

## 模型路由（v5.3 升级为执行级路由）

### 路由层级

| 层级 | 含义 | tier | model | effort |
|------|------|------|-------|--------|
| autopilot-fast | 机械性操作 | fast | haiku | low |
| autopilot-standard | 常规实施 | standard | sonnet | medium |
| autopilot-deep | 深度推理 | deep | opus | high |

### 默认 Phase 路由策略

| Phase | tier | model | 理由 |
|-------|------|-------|------|
| 1 | deep | opus | 需求分析需要深度推理 |
| 2 | fast | haiku | OpenSpec 创建是机械性操作 |
| 3 | fast | haiku | FF 生成是模板化操作 |
| 4 | standard | sonnet | 测试设计（SWE-bench Sonnet≈Opus，有 gate 兜底，失败自动升级） |
| 5 | deep | opus | 代码实施需要最强推理能力 |
| 6 | fast | haiku | 报告生成是机械性操作 |
| 7 | fast | haiku | 汇总与归档较简单 |

### 升级与回退策略

| 触发条件 | 动作 | 执行层 |
|----------|------|--------|
| fast 连续失败 1 次 | 升级到 standard | resolver（静态） |
| standard 连续失败 2 次 | 升级到 deep | resolver（静态） |
| critical 任务 | 直接使用 deep | resolver（静态） |
| deep 仍失败 | 不自动升级，转人工决策 | resolver（静态） |
| 配置 tier 无效 | 回退到 fallback_model | resolver（静态） |
| 运行时模型不可用 | 用 fallback_model 重试 Task | dispatch（运行时） |

> resolver 是预分析阶段，只处理配置级和重试级路由决策。运行时模型不可用（overloaded / capacity 等）由 dispatch 主线程在 Task 失败后根据错误类型判断，使用 resolver 输出的 `fallback_model` 字段重试。

### 路由解析器

dispatch 子 Agent 前调用 `resolve-model-routing.sh` 统一解析：

```bash
bash <plugin_scripts>/resolve-model-routing.sh "$PROJECT_ROOT" "$PHASE" "$COMPLEXITY" "$REQUIREMENT_TYPE" "$RETRY_COUNT" "$CRITICAL"
```

返回结构化 JSON:
```json
{
  "selected_tier": "fast|standard|deep|auto",
  "selected_model": "haiku|sonnet|opus|auto",
  "selected_effort": "low|medium|high",
  "routing_reason": "解析路由的详细原因",
  "escalated_from": null,
  "fallback_applied": false,
  "fallback_model": "sonnet"
}
```

> 当 `selected_tier` / `selected_model` 为 `"auto"` 时，dispatch 不传递 model 参数，继承父会话模型。

### 路由证据事件（v5.4 扩展为三种事件类型）

`emit-model-routing-event.sh` 支持三种事件类型，通过第 6 参数 `event_type` 选择：

**`model_routing`**（默认）— 路由决策事件，每次路由决策时发射：

```json
{
  "type": "model_routing",
  "phase": 5,
  "payload": {
    "selected_tier": "standard",
    "selected_model": "sonnet",
    "selected_effort": "medium",
    "routing_reason": "默认 phase 5 路由: standard",
    "escalated_from": null,
    "fallback_applied": false,
    "fallback_model": "sonnet",
    "agent_id": "phase5-task-3"
  }
}
```

**`model_effective`** — 运行时实际模型确认事件，子 Agent 启动后确认实际运行模型时发射：

```json
{
  "type": "model_effective",
  "phase": 5,
  "payload": {
    "effective_model": "sonnet-4",
    "effective_tier": "standard",
    "inference_source": "statusline",
    "requested_model": "sonnet",
    "match": true,
    "agent_id": "phase5-task-3"
  }
}
```

**`model_fallback`** — 模型降级触发事件，模型不可用触发 fallback 时发射：

```json
{
  "type": "model_fallback",
  "phase": 5,
  "payload": {
    "requested_model": "opus",
    "fallback_model": "sonnet",
    "fallback_reason": "model_not_available",
    "agent_id": "phase5-task-3"
  }
}
```

## Checkpoint 文件命名

```
phase-results/
├── phase-1-requirements.json
├── phase-2-openspec.json
├── phase-3-ff.json
├── phase-4-testing.json
├── phase-5-implement.json
├── phase-6-report.json
└── phase-7-summary.json
```

## DecisionPoint 格式（v2.4.0 增强）

Phase 1 JSON 信封中的 `decisions` 数组，每个元素为 DecisionPoint：

```json
{
  "point": "决策点描述",
  "options": [
    {"label": "A", "description": "...", "pros": ["..."], "cons": ["..."], "recommended": false},
    {"label": "B", "description": "...", "pros": ["..."], "cons": ["..."], "recommended": true}
  ],
  "choice": "B",
  "rationale": "用户选择理由或 AI 推荐理由",
  "affected_components": ["frontend-sync", "backend-api"]
}
```

> **向后兼容**: 旧格式 `{"point": "...", "choice": "..."}` 仍被 checkpoint 和 gate 接受。增强字段（`options`、`rationale`、`affected_components`）为可选，validation hook 不强制检查。

## Web Research 格式（v2.4.0 增强）

Phase 1 JSON 信封中的 `web_research` 可选字段：

```json
{
  "queries_executed": ["Vue 3 real-time collaboration best practices 2026", "Y.js vs Automerge comparison 2026"],
  "best_practices": [
    {"source": "https://...", "pattern": "使用 WebSocket + CRDT", "relevance": "high"}
  ],
  "similar_implementations": [
    {"repo": "github.com/...", "approach": "Y.js + WebSocket", "pros": ["成熟"], "cons": ["体积大"]}
  ],
  "dependency_evaluation": [
    {"package": "yjs", "security_status": "clean", "maintenance_status": "active", "bundle_size": "45KB", "alternatives": ["automerge", "sharedb"]}
  ],
  "recommended_approach": "基于调研结果，推荐使用 Y.js + WebSocket 方案，理由：社区成熟、bundle 体积可控、与 Vue 3 集成良好"
}
```

### 字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `queries_executed` | `string[]` | 实际执行的搜索查询列表 |
| `best_practices` | `{source, pattern, relevance}[]` | 结构化最佳实践，source 为来源 URL，relevance 为 high/medium/low |
| `similar_implementations` | `{repo, approach, pros, cons}[]` | 同类实现对比，含仓库地址、方案描述、优缺点 |
| `dependency_evaluation` | `{package, security_status, maintenance_status, bundle_size, alternatives}[]` | 依赖评估，含安全状态、维护状态、体积、替代方案 |
| `recommended_approach` | `string` | 基于调研的最终推荐方案摘要 |

## 特殊门禁

### Phase 4 → Phase 5

- `test_counts` 每个字段 ≥ `config.phases.testing.gate.min_test_count_per_type`
- `test_pyramid` 比例符合 `config.test_pyramid` 约束（unit_pct ≥ 50%）

> **L2/L3 分层策略说明**: L2 Hook 使用宽松底线（`unit_pct >= 30`, `e2e_pct <= 40`, `total_cases >= 10`, `change_coverage_pct >= 80`）确保极端倒金字塔被确定性拦截；L3 AI Gate 使用严格配置阈值（`unit_pct >= 50`, `e2e_pct <= 20`, `total_cases >= 20`）进一步收敛。这种分层设计允许 L3 在特殊情况下酌情放宽，同时 L2 提供不可绕过的硬底线。
- `artifacts` 非空
- `dry_run_results` 全部为 0

### Phase 5 → Phase 6

- `test-results.json` 存在
- `zero_skip_check.passed === true`
- `tasks.md` 中所有任务标记为 `[x]`


## 并行调度协议字段（v3.2.0 新增, v5.4 确定性调度器增强）

当阶段使用并行执行时，JSON 信封增加以下可选字段：

### 确定性并行计划（v5.4 新增）

`generate-parallel-plan.sh` 是确定性调度器脚本，接收任务列表 JSON，输出 `parallel_plan.json`。核心逻辑：

1. **文件所有权图**（Union-Find）— 检测文件冲突
2. **依赖图构建** — 显式 `depends_on` + 文件冲突隐式依赖
3. **拓扑排序 + batch 生成** — 按依赖层次分批

输出结构：
```json
{
  "plan_version": "1.0",
  "generated_at": "ISO-8601",
  "parallel_enabled": true,
  "total_tasks": 5,
  "dependency_graph": {"task-3": ["task-1"]},
  "batches": [
    {"batch_index": 0, "tasks": ["task-1", "task-2"], "can_parallel": true, "reason": "no file ownership conflict"},
    {"batch_index": 1, "tasks": ["task-3"], "can_parallel": false, "reason": "single task in batch"}
  ],
  "max_parallelism": 2,
  "fallback_to_serial": false,
  "fallback_reason": null,
  "scheduler_decision": "batch_parallel"
}
```

> **HARD CONSTRAINT**: 主线程必须消费 `parallel_plan.json` 的 `batches` 字段执行调度，禁止模型自行决定并行策略。

### 崩溃恢复 auto_continue 字段（v5.4 新增）

`recovery-decision.sh` 输出中新增以下字段，支持单候选变更自动继续（无需用户交互）：

| 字段 | 类型 | 说明 |
|------|------|------|
| `auto_continue_eligible` | boolean | 是否满足自动继续条件 |
| `recovery_interaction_required` | boolean | 是否需要用户交互（`auto_continue_eligible` 的逆） |
| `git_risk_level` | string | git 状态风险等级：`none` / `low`（有 fixup commits）/ `high`（rebase/merge 进行中） |

自动继续条件（全部满足时 `auto_continue_eligible = true`）：
1. 恰好一个可恢复候选变更（无多候选歧义），或通过 `--change` 显式指定
2. 存在有效的 `continue` 恢复路径
3. git 状态风险不为 `high`（无 rebase/merge 进行中）
4. 配置 `recovery.auto_continue_single_candidate` 为 true（默认 true）

### 并行子 Agent 返回格式（单个 agent）

```json
{
  "status": "ok",
  "summary": "完成 unit 测试设计，共 8 个用例",
  "artifacts": ["tests/unit/test_user.py"],
  "parallel_group": "unit-tests",
  "parallel_index": 1,
  "_metrics": {
    "start_time": "...",
    "end_time": "...",
    "duration_seconds": 120,
    "retry_count": 0
  }
}
```

### 主线程合并后的聚合格式

```json
{
  "status": "ok",
  "summary": "Phase 4 全部测试用例设计完成，共 25 个用例",
  "artifacts": ["...all merged..."],
  "parallel_metrics": {
    "mode": "parallel",
    "total_agents": 4,
    "successful_agents": 4,
    "failed_agents": 0,
    "total_duration_seconds": 180,
    "max_agent_duration_seconds": 120,
    "fallback_reason": null
  },
  "test_counts": { "unit": 8, "api": 6, "e2e": 6, "ui": 5 },
  "test_traceability": [
    { "test": "test_user_login", "requirement": "REQ-1.1 用户登录" },
    { "test": "test_create_space", "requirement": "REQ-2.1 创建工作空间" }
  ]
}
```

### Phase 6 Allure 增强返回格式

```json
{
  "status": "ok",
  "summary": "全部测试通过，Allure 报告已生成",
  "pass_rate": 96.5,
  "report_path": "allure-report/index.html",
  "report_format": "allure",
  "allure_results_dir": "allure-results/",
  "suite_results": [
    { "suite": "backend_unit", "total": 25, "passed": 25, "failed": 0, "skipped": 0 },
    { "suite": "api_test", "total": 12, "passed": 11, "failed": 1, "skipped": 0 },
    { "suite": "e2e_test", "total": 8, "passed": 8, "failed": 0, "skipped": 0 },
    { "suite": "ui_test", "total": 6, "passed": 5, "failed": 0, "skipped": 1 }
  ],
  "anomaly_alerts": [
    "API 测试: test_create_user_duplicate 失败 — 预期 409 但返回 500",
    "UI 测试: test_login_page_layout 跳过 — 缺少 Playwright 浏览器"
  ],
  "report_url": "file:///path/to/allure-report/index.html"
}
```

### Phase 6 並行 TDD 証跡フィールド（v5.1.18 新增）

| フィールド                  | 必須/可選 | 型      | 説明                                                |
|---------------------------|----------|---------|-----------------------------------------------------|
| `pass_rate`               | required | number  | 全体テスト合格率（%）                                 |
| `report_path`             | required | string  | レポートファイルパス                                   |
| `report_format`           | required | string  | レポート形式（html / allure / json）                   |
| `red_evidence`            | optional | string  | Sample RED failure excerpt (parallel TDD proof)      |
| `suite_results`           | optional | object  | Per-suite pass/fail/skip breakdown                   |
| `sample_failure_excerpt`  | optional | string  | Sample test failure output for audit trail            |
