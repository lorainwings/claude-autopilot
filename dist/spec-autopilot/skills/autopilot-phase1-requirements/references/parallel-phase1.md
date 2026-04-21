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
> - 旧字段 `phases.requirements.research.web_search.agent` 已 deprecated（向后兼容残留），其能力以条件子任务方式合并至 `research.agent`，详见文末 Deprecation Notice。

### ScanAgent 四要素契约（Four-Field Task Contract）

ScanAgent prompt 必须按下列 YAML 注入到 dispatch 模板（嵌入在 markdown 中），令子 Agent 在执行前能精确判断"哪些事我做、哪些事不属于我"：

```yaml
scan_agent:
  agent: config.phases.requirements.auto_scan.agent  # setup SKILL 强制写入；推荐 OMC explore-forked（具备 Write 权限）
  task_boundary:
    your_scope: |
      1. 扫描项目结构、技术栈与既有实现，产出 project-context.md / existing-patterns.md / tech-constraints.md
      2. 在 envelope.decision_points[] 中列出项目层面的关键取舍（例如：沿用现有状态管理 vs 引入新库），并给出 recommendation
      3. **发现项目模式与需求冲突时，写入 envelope.conflicts_detected[]，并产出对应 decision_points**
         （例如：现有单租户架构 vs 新需求多租户要求 → conflicts_detected 记录矛盾，
         decision_points 记录需要用户裁定的选项）
    not_your_scope: "需求相关性/技术可行性/CVE 调研（由 ResearchAgent 负责）/ 跨路冲突仲裁（由 SynthesizerAgent 负责）"
  tool_boundary:
    allowed: [Read, Grep, Glob, "Bash (read-only)", Write]
    forbidden: [Edit, "Write to non-context paths", WebSearch, WebFetch, Task]
  output_format:
    envelope_schema: runtime/schemas/phase1-scan-envelope.schema.json
    files:
      - context/project-context.md
      - context/existing-patterns.md
      - context/tech-constraints.md
```

> **decision_points 必填（C14 起）**：即使 ScanAgent 判断当前项目无待决策点，也必须输出 `decision_points: []`（schema required 字段）。空数组允许，缺字段即 L2 Hook 阻断。
>
> **conflicts_detected 触发条件**：当扫描出的既有模式（existing_patterns）与用户需求存在语义冲突（架构、数据模型、安全策略、依赖锁定等）时，必须同时写入 `conflicts_detected[]` 与对应的 `decision_points[]` 条目；两者通过 `related_decision_point`（可选）交叉引用，供 SynthesizerAgent 做跨路仲裁。
>
> **严格禁止**：在 envelope.summary 或其他字段中返回扫描全文。全文必须 Write 到 output_files 中列出的路径；主线程仅消费信封。

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

汇合后: 主线程**先派发 SynthesizerAgent（串行第三路）整合两路信封 + 全文** → 主线程仅 Read `context/phase1-verdict.json`，再注入到 需求分析 Agent 的 dispatch prompt。

### SynthesizerAgent 四要素契约（Four-Field Task Contract）

SynthesizerAgent 是 Phase 1 第 3 路 Agent，作为 ScanAgent + ResearchAgent 完成后的**串行汇总仲裁者**：

```yaml
synthesizer_agent:
  triggers_after: [scan_agent, research_agent]   # 串行依赖：必须在两路并行 Agent 完成后派发
  agent: config.phases.requirements.synthesizer.agent  # setup SKILL 强制写入；推荐 OMC architect / judge 类（强综合 + 冲突识别）
  task_boundary:
    your_scope: |
      1. Read 全部前序产物（context/project-context.md, context/existing-patterns.md,
         context/tech-constraints.md, context/research-findings.md）正文
      2. 跨路冲突检测：对比两路 envelope 的 decision_points 与 tech_constraints
      3. 语义去重：合并相似 topic（语义相似度 >0.8 视为同一 topic）。
         **同主题同推荐 → 相似 topic 合并** 为单条 merged_decision_point，并在
         **evidence_refs 中保留所有源路径**（`scan:` / `research:` 前缀双源齐写）；
         **同主题不同推荐 → 写入 conflicts[]**，不进入 merged_decision_points。
      4. 输出 verdict.json（schema: runtime/schemas/synthesizer-verdict.schema.json）
      5. 在 verdict.merged_decision_points 中保留唯一决策点集合，附 evidence_refs 指回原始来源
      6. 在 verdict.ambiguities 中插入 [NEEDS CLARIFICATION: ...] 标记，指明仍需用户澄清的问题
      7. 当两路 decision_points 出现矛盾 topic 时，verdict.conflicts 必须非空，
         逐条记录 positions / resolution（adopted | deferred_to_user | irreconcilable）
    not_your_scope: "需求草稿撰写（由 BA Agent 负责）/ 用户澄清（由主线程 AskUserQuestion 负责）/ 重新触发联网调研（由 ResearchAgent 负责）"
  tool_boundary:
    allowed: [Read, Write, Bash]   # Bash 限 jq/diff，仅用于结构化对比
    forbidden: [WebSearch, WebFetch, Edit, Task]
  output_format:
    envelope_schema: runtime/schemas/synthesizer-verdict.schema.json
    files: [context/phase1-verdict.json]
```

> **配置驱动纪律**：`synthesizer_agent.agent` 字段必须从 `autopilot.config.yaml` 的 `phases.requirements.synthesizer.agent` 读取（与 ScanAgent / ResearchAgent 同一约定）。setup SKILL 强制写入；不得硬编码 agent 名，不得使用 `Explore`（Explore 无 Write 权限，无法产出 verdict.json）。
>
> **派发时机（串行约束）**：SynthesizerAgent **不可** 与 ScanAgent / ResearchAgent 并行；必须等待两路 background Task 完成、各自写出产物文件之后，主线程在新一条消息中前台派发 SynthesizerAgent。
>
> **Read 权限红线**：SynthesizerAgent 是 Phase 1 唯一被允许 Read `context/*.md` **正文全文**的子 Agent（含 project-context.md / existing-patterns.md / tech-constraints.md / research-findings.md）。主线程仍受上下文隔离红线约束，**不得** Read 这些正文。
>
> **Conflict 检测铁律**：当 ScanAgent 与 ResearchAgent envelope 中存在 topic 语义匹配但 recommendation 相反的 decision_points 时，verdict.conflicts 数组必须非空；空 conflicts 但下游 BA 检出冲突即视为 SynthesizerAgent 失职，由 L2 Hook 阻断 Phase 1→2 跳变（详见 autopilot-gate Phase 1→2 三重校验）。
>
> **Ambiguities 输出**：当 SynthesizerAgent 判断仍存在无法在前序产物中解决的歧义时，必须在 `verdict.ambiguities` 中以 `[NEEDS CLARIFICATION: <问题描述>]` 格式追加；BA Agent 模板会强制透传这些标记到需求草稿。

### SynthesizerAgent 返回信封（与 schema 对齐）

```json
{
  "coverage_ok": true,
  "conflicts": [
    {
      "topic": "状态管理选型",
      "positions": [
        {"source": "scan", "claim": "现有代码使用 Redux Toolkit"},
        {"source": "research", "claim": "推荐迁移至 Zustand 以降低样板"}
      ],
      "resolution": "deferred_to_user",
      "chosen": ""
    }
  ],
  "confidence": 0.82,
  "requires_human": true,
  "ambiguities": ["[NEEDS CLARIFICATION: 是否允许引入新状态管理库？]"],
  "rationale": "两路 decision_points 在状态管理上存在矛盾，需要用户决策后才能进入 BA。",
  "merged_decision_points": [
    {
      "topic": "状态管理选型",
      "options": ["保留 Redux Toolkit", "迁移至 Zustand"],
      "recommendation": "deferred_to_user",
      "evidence_refs": ["scan:existing-patterns.md#state", "research:research-findings.md#state-mgmt"]
    }
  ]
}
```

> **禁止**：SynthesizerAgent 不得在 verdict 中复述原始调研全文；verdict 仅承载结构化判定结果（参见 schema 字段约束）。verdict.json 文件由 SynthesizerAgent 自行 Write 到 `openspec/changes/<name>/context/phase1-verdict.json`。

### SynthesizerAgent 语义去重 Few-Shot 示例

> 以下 few-shot 锚定 Synthesizer 的语义聚合行为，必须随 prompt 一并注入子 Agent 上下文。

**Case A — 同主题不同推荐（写入 conflicts[]，merged_decision_points 留空）**

```
INPUT decision_points:
  - {topic: "数据库选型", recommendation: "sqlite",   source: scan}
  - {topic: "DB choice",  recommendation: "postgres", source: research}

OUTPUT:
  conflicts: [
    {
      topic: "数据库选型",
      positions: [
        {source: scan,     claim: sqlite},
        {source: research, claim: postgres}
      ],
      resolution: "deferred_to_user"
    }
  ]
  merged_decision_points: []   # 因为是冲突，不写入 merged
```

**Case B — 同主题同推荐（相似 topic 合并，evidence_refs 双源齐写）**

```
INPUT decision_points:
  - {topic: "缓存策略",     recommendation: "Redis", source: scan}
  - {topic: "cache layer",  recommendation: "Redis", source: research}

OUTPUT:
  conflicts: []
  merged_decision_points: [
    {
      topic: "缓存策略",
      options: ["Redis", "in-memory"],
      recommendation: "Redis",
      evidence_refs: ["scan:existing-patterns.md#cache", "research:research-findings.md#cache"]
    }
  ]
```

>
> **主线程消费**：主线程仅 `Read(context/phase1-verdict.json)`（非两路调研全文），按 `verdict.requires_human || len(verdict.ambiguities) > 0` 决定是否进入 AskUserQuestion，再把 `verdict.merged_decision_points + 用户澄清答复`一并注入 BA Agent 的 dispatch prompt。

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

# Task 2: 技术调研（解析后的 research.agent 名）— 已吸收 web-search 子任务
Task(subagent_type: "{{RESOLVED_RESEARCH_AGENT}}", run_in_background: true,
  prompt: "分析与需求相关的代码:
  需求: {RAW_REQUIREMENT}
  重点: 影响范围、依赖兼容性、技术可行性、风险识别
  当且仅当 depth=deep 时执行联网调研子任务（最佳实践、竞品对比、CVE）；
  websearch_quota: 0 if depth=standard, up to {config.phases.requirements.research.websearch_quota|default=3} if depth=deep
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

## Deprecation Notice

**独立 web_search Agent 已合并至 ResearchAgent。**

- Phase 1 派发拓扑：两路并行（ScanAgent + ResearchAgent）+ 一路串行汇总（SynthesizerAgent，详见上文 SynthesizerAgent 四要素契约）。
- ResearchAgent 在 `depth=deep`（或 maturity=ambiguous / complexity=large 自动升级）时执行联网调研子任务，使用 WebSearch / WebFetch 工具，配额由 `websearch_quota` 控制（standard=0，deep≤3）。
- `depth=standard` 时禁止调用 WebSearch，越权调用由 L2 Hook `auto-emit-agent-dispatch.sh` 阻断。
- 旧 config 字段 `phases.requirements.research.web_search.agent` / `.web_search.enabled` 兼容保留但**不再被调度器读取**；若 setup 阶段检测到该字段非空，会输出 warning 提示用户迁移到新的 `research.depth` 控制方式（不阻断升级路径）。
- 相关产物 `web-research-findings.md` 不再单独输出，所有联网调研结果合并到 `research-findings.md` 的「Web Research Findings」章节，供下游 BA / Synthesizer 一次性消费。
