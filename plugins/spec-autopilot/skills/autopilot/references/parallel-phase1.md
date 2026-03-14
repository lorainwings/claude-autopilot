# Phase 1 并行调度配置与模板

> 本文件从 `parallel-dispatch.md` 拆分（v5.2），仅在 Phase 1 按需加载。
> 通用并行编排协议（适用条件、Union-Find、模板、结果收集、降级策略）见 `parallel-dispatch.md`。

## Phase 1: 需求调研并行

```yaml
parallel_tasks:
  - name: "auto-scan"
    agent: "general-purpose"
    prompt_template: "分析项目结构和现有代码模式..."
    merge_strategy: "none"
  - name: "tech-research"
    agent: "general-purpose"
    prompt_template: "分析与需求相关的代码、依赖兼容性..."
    merge_strategy: "none"
  - name: "web-search"
    agent: "general-purpose"
    prompt_template: "联网搜索最佳实践和竞品方案..."
    merge_strategy: "none"
    condition: "search_policy.default: search — 规则判定跳过时不派发此 Agent"
```

**子 Agent 自写入约束**（v3.3.0）：每个调研 Agent 必须自行 Write 产出到指定路径，返回 JSON 信封仅包含摘要。

调研 Agent 返回信封格式：
```json
{
  "status": "ok",
  "summary": "简明摘要（3-5句）",
  "decision_points": [
    {"topic": "决策点标题", "options": ["方案A", "方案B"], "recommendation": "推荐方案", "rationale": "推荐理由"}
  ],
  "tech_constraints": ["约束1", "约束2"],
  "complexity": "small|medium|large",
  "key_files": ["关键文件路径"],
  "output_file": "context/research-findings.md"
}
```

> **禁止**：在信封的 summary 或其他字段中返回调研全文。全文必须 Write 到 output_file。
> **主线程仅消费信封**，不 Read 产出文件。产出文件由 business-analyst 和 Phase 2-6 子 Agent 直接 Read。

汇合后: 主线程从信封提取 decision_points + tech_constraints → 注入到 business-analyst 的 dispatch prompt

## Phase 1 并行调度模板

主线程同时派发 2-3 个 Task（不含 autopilot-phase 标记，不受 Hook 校验）：

```markdown
# Task 1: Auto-Scan（general-purpose agent）
Task(subagent_type: "general-purpose", run_in_background: true,
  prompt: "分析项目结构，生成 Steering Documents:
  - project-context.md（技术栈、目录结构）
  - existing-patterns.md（现有代码模式）
  - tech-constraints.md（技术约束）
  输出到: openspec/changes/{change_name}/context/"
)

# Task 2: 技术调研（general-purpose agent）
Task(subagent_type: "general-purpose", run_in_background: true,
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
  输出结构化结果到: openspec/changes/{change_name}/context/web-research-findings.md
  注意: 输出到独立文件 web-research-findings.md，不要修改 research-findings.md"
)
{end if}
```

等待全部完成 → 主线程合并 research-findings.md 和 web-research-findings.md（如存在）的内容 → 传递给 business-analyst 分析。

## 需求理解增强（v3.2.0）

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
