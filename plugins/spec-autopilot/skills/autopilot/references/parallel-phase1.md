# Phase 1 并行调度配置与模板

> 本文件从 `parallel-dispatch.md` 拆分，仅在 Phase 1 按需加载。
> 通用并行编排协议（适用条件、Union-Find、模板、结果收集、降级策略）见 `parallel-dispatch.md`。

## Phase 1: 需求调研并行

```yaml
parallel_tasks:
  - name: "auto-scan"
    agent: config.phases.requirements.auto_scan.agent  # setup SKILL 强制写入的代码库扫描 Agent（推荐 OMC explore forked）
    prompt_template: "分析项目结构和现有代码模式..."
    merge_strategy: "none"
  - name: "tech-research"
    agent: config.phases.requirements.research.agent   # setup SKILL 强制写入的技术兼容性分析 Agent（推荐 OMC architect）
    prompt_template: "需求相关性 + 技术可行性 + 风险识别 + (depth=deep)联网最佳实践与 CVE..."
    merge_strategy: "none"
```

> **配置驱动纪律（双路独立解析，不硬编码 agent 名）**：
> - 两路 agent 字段 `phases.requirements.auto_scan.agent` / `phases.requirements.research.agent` 必须在 setup SKILL 期间由用户分别从已安装 agent 列表中选择并写入；本文档不预设具体名称。
> - 运行时 `runtime/scripts/auto-emit-agent-dispatch.sh` 按**输出文件路径**路由校验：
>   - prompt 引用 `project-context.md` / `existing-patterns.md` / `tech-constraints.md` → 校验 `subagent_type == auto_scan.agent`
>   - prompt 引用 `research-findings.md` → 校验 `subagent_type == research.agent`
> - 不一致、为空、或配置缺失即硬阻断，不允许偏离配置。
> - `_config_validator.py` 硬阻断上述两个字段值为 `Explore`（只读，无 Write 权限）。
> - 旧字段 `phases.requirements.research.web_search.agent` 已 deprecated（v5.x 兼容残留），其能力以条件子任务方式合并至 `research.agent`，详见文末 Deprecation Notice。

### ResearchAgent 四要素契约（Four-Field Task Contract）

ResearchAgent prompt 必须按下列 YAML 注入到 dispatch 模板（嵌入在 markdown 中），令子 Agent 在执行前能精确判断"哪些事我做、哪些事不属于我"：

```yaml
research_agent:
  task_boundary:
    your_scope: "需求相关性分析 + 技术可行性 + 风险识别 + (depth=deep 时)联网调研最佳实践与 CVE"
    not_your_scope: "项目结构 Steering（由 ScanAgent 负责）/ 三路汇总仲裁（由 SynthesizerAgent 负责）"
  tool_boundary:
    allowed: [Read, Grep, Glob, WebSearch (条件), WebFetch (条件), Write]
    websearch_quota: "0 if depth=standard; up to 3 if depth=deep"
  output_format:
    envelope_schema: runtime/schemas/research-envelope.schema.json
    files: [context/research-findings.md]
```

> **WebSearch 触发约束**：当且仅当 `config.phases.requirements.research.depth == "deep"`（或 complexity == "large" 自动升级到 deep）时，ResearchAgent 才允许调用 WebSearch / WebFetch；`depth=standard` 时 websearch_quota=0，调用即视为越权由 L2 Hook 阻断。

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

主线程同时派发 2 个 Task（不含 autopilot-phase 标记，不受 Hook 校验）。

> **Sub-Agent 名称硬解析（双路独立，必须在派发前执行）**：
> 下述模板中的 `{{RESOLVED_AUTOSCAN_AGENT}}` / `{{RESOLVED_RESEARCH_AGENT}}` **必须**由主线程在构造 Task 参数前用实际已注册 agent 名替换
> （从 `autopilot.config.yaml` 的 `phases.requirements.auto_scan.agent` / `.research.agent` 读取；setup SKILL 期间已强制写入，未配置即派发是 bug）。
> 每路解析后各自通过 `runtime/scripts/validate-agent-registry.sh <agent_name>` 校验（exit 0 方可派发，exit 1 即 fail-fast 返回 blocked）。
> 禁止将 `config.phases.xxx.agent` 字面量直接作为 `subagent_type` 传入 Task —— LLM 看到字面量后会从 description 启发式选择 `Explore` / `general-purpose`，导致预设 agent 身份丢失。
>
> **配置一致性硬阻断（运行时按文件路径路由）**：
> 1. 配置层：`_config_validator.py` 硬阻断上述两个字段值为 `"Explore"`（enum_error）
> 2. 运行时：`auto-emit-agent-dispatch.sh` 读取 config，按 prompt 引用的**输出文件路径**精确路由：
>    - 引用 `project-context.md` / `existing-patterns.md` / `tech-constraints.md` → `subagent_type` 必须完全等于 `auto_scan.agent`
>    - 引用 `research-findings.md` → 必须完全等于 `research.agent`
>    不一致、为空、或 config 缺失即 stdout JSON block
> Explore 为只读 agent，无 Write 权限，无法产出调研报告；即使 Auto-Scan 任务也必须使用配置指定的 agent。

```markdown
# Task 1: Auto-Scan（解析后的 auto_scan.agent 名）
Task(subagent_type: "{{RESOLVED_AUTOSCAN_AGENT}}", run_in_background: true,
  prompt: "分析项目结构，生成 Steering Documents:
  - project-context.md（技术栈、目录结构）
  - existing-patterns.md（现有代码模式）
  - tech-constraints.md（技术约束）
  输出到: openspec/changes/{change_name}/context/"
)

# Task 2: 技术调研（解析后的 research.agent 名）— 已吸收 v5.x 第 3 路 web-search 子任务
Task(subagent_type: "{{RESOLVED_RESEARCH_AGENT}}", run_in_background: true,
  prompt: "分析与需求相关的代码:
  需求: {RAW_REQUIREMENT}
  重点: 影响范围、依赖兼容性、技术可行性、风险识别
  当且仅当 depth=deep 时执行联网调研子任务（最佳实践、竞品对比、CVE）；
  websearch_quota: 0 if depth=standard, up to {config.phases.requirements.research.web_search.max_queries|default=3} if depth=deep
  输出到: openspec/changes/{change_name}/context/research-findings.md"
)
```

等待全部完成 → 主线程**仅从各 Agent 返回的 JSON 信封**提取 `decision_points`、`tech_constraints`、`complexity`、`key_files` 等结构化字段 → 将这些**信封摘要**（而非正文）注入到 需求分析 Agent 的 dispatch prompt。

> **上下文隔离红线**：主线程**禁止** `Read(research-findings.md)` 获取调研全文。
> 全文由需求分析 Agent 在自己的执行环境中直接 Read。
> 主线程仅消费信封中的结构化摘要（summary、decision_points、tech_constraints、complexity、key_files）。
> 主线程仅通过 `Bash("test -s {output_file} && echo ok")` 验证产出文件存在性。

## 需求理解增强

### 复杂度自适应调研深度

| 复杂度 | Auto-Scan | 技术调研 | 联网调研子任务 (ResearchAgent.deep) | 竞品分析 (ResearchAgent.deep) |
|--------|-----------|---------|------------------------------------|------------------------------|
| small | YES | NO | NO | NO |
| medium | YES | YES (standard) | NO | NO |
| large | YES | YES (deep) | YES | YES |

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
| **clear** | 需求明确、边界清晰、有验收标准 | flags == 0 且 RAW_REQUIREMENT 含具体组件名 + 具体行为 + 验收条件 | 轻量澄清：仅 Auto-Scan，不启动技术调研 |
| **partial** | 方向明确但缺少细节 | flags == 1 或 (flags == 0 但无验收标准) | 双路调研：Auto-Scan + ResearchAgent(depth=standard，无 WebSearch) |
| **ambiguous** | 方向不明或重大歧义 | flags >= 2 | 双路调研：Auto-Scan + ResearchAgent(depth=deep，含 WebSearch 子任务) |

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
        # 跳过技术调研，节省 Token
    "partial":
        dispatch_tasks = [auto_scan, tech_research(depth=standard)]
        # tech_research 在 standard 模式下 websearch_quota=0
    "ambiguous":
        dispatch_tasks = [auto_scan, tech_research(depth=deep)]
        # tech_research 在 deep 模式下吸收 web-search 子任务（最佳实践、竞品、CVE）
```

### 成熟度写入信封

成熟度结果写入 Phase 1 最终 checkpoint 和 requirement-packet.json：

```json
{
  "requirement_maturity": "clear|partial|ambiguous",
  "research_plan": {
    "dispatched": ["auto_scan", "tech_research"],
    "research_depth": "standard|deep",
    "websearch_subtask_executed": false,
    "skipped": [],
    "skip_reasons": {}
  }
}
```

> **设计意图**：避免所有需求都走多路调研。clear 需求直接用 Auto-Scan 提取项目上下文即可进入 BA 分析，节省 Token 和时间。

---

## Deprecation Notice (v6.x)

**v5.x 第 3 路独立 web_search Agent 已合并至 ResearchAgent。**

- 新版 Phase 1 仅派发两路 Sub-Agent：ScanAgent + ResearchAgent（v6 后续 Task 5 会再叠加 SynthesizerAgent）。
- ResearchAgent 在 `depth=deep`（或 maturity=ambiguous / complexity=large 自动升级）时执行联网调研子任务，使用 WebSearch / WebFetch 工具，配额由 `websearch_quota` 控制（standard=0，deep≤3）。
- `depth=standard` 时禁止调用 WebSearch，越权调用由 L2 Hook `auto-emit-agent-dispatch.sh` 阻断。
- 旧 config 字段 `phases.requirements.research.web_search.agent` / `.web_search.enabled` 兼容保留但**不再被调度器读取**；若 setup 阶段检测到该字段非空，会输出 warning 提示用户迁移到新的 `research.depth` 控制方式（不阻断升级路径）。
- 相关产物 `web-research-findings.md` 不再单独输出，所有联网调研结果合并到 `research-findings.md` 的「Web Research Findings」章节，供下游 BA / Synthesizer 一次性消费。
