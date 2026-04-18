# Phase 1 并行调度配置与模板

> 本文件从 `parallel-dispatch.md` 拆分，仅在 Phase 1 按需加载。
> 通用并行编排协议（适用条件、Union-Find、模板、结果收集、降级策略）见 `parallel-dispatch.md`。

## Phase 1: 需求调研并行

```yaml
parallel_tasks:
  - name: "auto-scan"
    agent: config.phases.requirements.agent  # 默认 "general-purpose"
    prompt_template: "分析项目结构和现有代码模式..."
    merge_strategy: "none"
  - name: "tech-research"
    agent: config.phases.requirements.research.agent  # 默认 "general-purpose"
    prompt_template: "分析与需求相关的代码、依赖兼容性..."
    merge_strategy: "none"
  - name: "web-search"
    agent: config.phases.requirements.research.agent  # 默认 "general-purpose"
    prompt_template: "联网搜索最佳实践和竞品方案..."
    merge_strategy: "none"
    condition: "search_policy.default: search — 规则判定跳过时不派发此 Agent"
```

**子 Agent 自写入约束**：每个调研 Agent 必须自行 Write 产出到指定路径，返回 JSON 信封仅包含摘要。

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
> **主线程仅消费信封**，不 Read 产出文件。产出文件由需求分析 Agent（config.phases.requirements.agent）和 Phase 2-6 子 Agent 直接 Read。

汇合后: 主线程从信封提取 decision_points + tech_constraints → 注入到 需求分析 Agent 的 dispatch prompt

## Phase 1 并行调度模板

主线程同时派发 2-3 个 Task（不含 autopilot-phase 标记，不受 Hook 校验）。

> **Sub-Agent 名称硬解析（必须在派发前执行）**：
> 下述模板中的 `{{RESOLVED_AGENT_NAME}}` / `{{RESOLVED_RESEARCH_AGENT_NAME}}` **必须**由主线程在构造 Task 参数前用实际已注册 agent 名替换
> （从 `autopilot.config.yaml` 的 `config.phases.requirements.agent` / `config.phases.requirements.research.agent` 读取；未配置时使用默认值 `general-purpose`）。
> 替换后必须通过 `runtime/scripts/validate-agent-registry.sh <agent_name>` 校验（exit 0 方可派发，exit 1 即 fail-fast 返回 blocked）。
> 禁止将 `config.phases.xxx.agent` 字面量直接作为 `subagent_type` 传入 Task —— LLM 看到字面量后会从 description 启发式选择 `Explore` / `general-purpose`，导致预设 agent 身份丢失。

```markdown
# Task 1: Auto-Scan（解析后的 agent 名，Phase 1 Auto-Scan 允许 general-purpose）
Task(subagent_type: "{{RESOLVED_AGENT_NAME}}", run_in_background: true,
  prompt: "分析项目结构，生成 Steering Documents:
  - project-context.md（技术栈、目录结构）
  - existing-patterns.md（现有代码模式）
  - tech-constraints.md（技术约束）
  输出到: openspec/changes/{change_name}/context/"
)

# Task 2: 技术调研（解析后的 research agent 名）
Task(subagent_type: "{{RESOLVED_RESEARCH_AGENT_NAME}}", run_in_background: true,
  prompt: "分析与需求相关的代码:
  需求: {RAW_REQUIREMENT}
  重点: 影响范围、依赖兼容性、技术可行性
  输出到: openspec/changes/{change_name}/context/research-findings.md"
)

# Task 3: 联网搜索（条件派发）
{if config.phases.requirements.web_search.enabled}
Task(subagent_type: "{{RESOLVED_RESEARCH_AGENT_NAME}}", run_in_background: true,
  prompt: "联网搜索与需求相关的最佳实践:
  需求: {RAW_REQUIREMENT}
  搜索不超过 {config.phases.requirements.web_search.max_queries} 个查询
  输出结构化结果到: openspec/changes/{change_name}/context/web-research-findings.md
  注意: 输出到独立文件 web-research-findings.md，不要修改 research-findings.md"
)
{end if}
```

等待全部完成 → 主线程**仅从各 Agent 返回的 JSON 信封**提取 `decision_points`、`tech_constraints`、`complexity`、`key_files` 等结构化字段 → 将这些**信封摘要**（而非正文）注入到 需求分析 Agent 的 dispatch prompt。

> **上下文隔离红线**：主线程**禁止** `Read(research-findings.md)` 或 `Read(web-research-findings.md)` 获取调研全文。
> 全文由需求分析 Agent 在自己的执行环境中直接 Read。
> 主线程仅消费信封中的结构化摘要（summary、decision_points、tech_constraints、complexity、key_files）。
> 主线程仅通过 `Bash("test -s {output_file} && echo ok")` 验证产出文件存在性。

## 需求理解增强

### 复杂度自适应调研深度

| 复杂度 | Auto-Scan | 技术调研 | 联网搜索 | 竞品分析 |
|--------|-----------|---------|---------|---------|
| small | ✅ | ❌ | ❌ | ❌ |
| medium | ✅ | ✅（并行） | ❌ | ❌ |
| large | ✅ | ✅（并行） | ✅（并行） | ✅（并行） |

> 注意：复杂度评估发生在第一轮调研（Auto-Scan）完成后。small 不触发额外调研。
> medium/large 的额外调研以并行方式执行，不增加总耗时。

### 主动决策增强

所有复杂度级别均展示决策卡片（取消 small 豁免）：
- **small**: 仅关键技术决策点（1-2 个卡片）
- **medium**: 所有识别到的决策点 + 调研依据
- **large**: 全部决策点 + 调研依据 + 竞品对比 + 推荐方案

决策卡片增强字段：
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

## 需求成熟度驱动调研方案选择

### 成熟度三级分类

在 Step 1.1.5 信息量评估之后、并行调研派发之前，主线程执行需求成熟度判断：

| 成熟度 | 定义 | 判定规则 | 调研方案 |
|--------|------|---------|---------|
| **clear** | 需求明确、边界清晰、有验收标准 | flags == 0 且 RAW_REQUIREMENT 含具体组件名 + 具体行为 + 验收条件 | 轻量澄清：仅 Auto-Scan，不启动技术调研和联网搜索 |
| **partial** | 方向明确但缺少细节 | flags == 1 或 (flags == 0 但无验收标准) | 双路调研：Auto-Scan + 技术调研，联网搜索按规则引擎决定 |
| **ambiguous** | 方向不明或重大歧义 | flags >= 2 | 三路调研：Auto-Scan + 技术调研 + 联网搜索（全启动） |

### 成熟度决策伪代码

```
# 在 Step 1.1.5 评估后执行
IF flags >= 2:
    maturity = "ambiguous"
ELIF flags == 1 OR (flags == 0 AND 'no_acceptance_criteria' would have triggered):
    maturity = "partial"
ELSE:
    maturity = "clear"

# 调研方案选择
MATCH maturity:
    "clear":
        dispatch_tasks = [auto_scan]
        # 跳过技术调研和联网搜索，节省 Token
    "partial":
        dispatch_tasks = [auto_scan, tech_research]
        IF search_policy_engine.should_search(RAW_REQUIREMENT):
            dispatch_tasks.append(web_search)
    "ambiguous":
        dispatch_tasks = [auto_scan, tech_research, web_search]
        # 全量启动，最大化信息采集
```

### 成熟度写入信封

成熟度结果写入 Phase 1 最终 checkpoint 和 requirement-packet.json：

```json
{
  "requirement_maturity": "clear|partial|ambiguous",
  "research_plan": {
    "dispatched": ["auto_scan", "tech_research"],
    "skipped": ["web_search"],
    "skip_reasons": {"web_search": "maturity=partial, search_policy=skip"}
  }
}
```

> **设计意图**：避免所有需求都走三路调研。clear 需求直接用 Auto-Scan 提取项目上下文即可进入 BA 分析，节省 Token 和时间。
