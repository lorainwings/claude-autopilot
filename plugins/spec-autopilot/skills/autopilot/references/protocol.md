# Autopilot 共享协议参考

> 此文件被 autopilot-dispatch、autopilot-gate、autopilot-checkpoint 共同引用。修改时需同步评估影响。

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
| 1 | `requirements_summary`, `decisions: [DecisionPoint]`, `change_name`, `complexity: "small\|medium\|large"`, `research: { status, impact_files, estimated_loc, feasibility_score, new_deps_count }` | `open_questions`, `steering_artifacts`, `web_research: { queries_executed, best_practices, similar_implementations, dependency_evaluation, recommended_approach }` |
| 4 | `test_counts: { unit, api, e2e, ui }`, `dry_run_results: { unit, api, e2e, ui }`, `test_pyramid: { total, unit_pct, integration_pct, e2e_pct }` | `test_traceability: [{ test, requirement }]` |
| 5 | `test_results_path`, `tasks_completed`, `zero_skip_check: { passed: bool }` | `iterations_used`, `code_quality: { constraint_violations: number, violations: [{rule, file, detail}] }`, `parallel_metrics: { mode, groups_count, fallback_reason }` |
| 6 | `pass_rate`, `report_path`, `report_format` | `report_url`, `allure_results_dir`, `suite_results: [{ suite, total, passed, failed, skipped }]`, `anomaly_alerts: [string]` |
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

## 模型路由（v3.0 新增）

config.model_routing 定义每阶段的推荐模型等级：

| 等级 | 含义 | 适用阶段 |
|------|------|---------|
| heavy | 需要深度推理的 Opus 级任务 | Phase 1, 4, 5 |
| light | 机械性操作的 Sonnet 级任务 | Phase 2, 3, 6, 7 |
| auto | 继承父进程模型（默认） | 未配置时 |

> 向后兼容: model_routing 为可选配置。未配置时所有阶段等效 auto。

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
- `artifacts` 非空
- `dry_run_results` 全部为 0

### Phase 5 → Phase 6

- `test-results.json` 存在
- `zero_skip_check.passed === true`
- `tasks.md` 中所有任务标记为 `[x]`


## 并行调度协议字段（v3.2.0 新增）

当阶段使用并行执行时，JSON 信封增加以下可选字段：

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
