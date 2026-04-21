# Phase 6.5: AI 代码审查 — 详细流程

> 本文件由 autopilot SKILL.md 引用，Phase 6 完成后、Phase 7 之前按需读取。

## 触发条件

当 `config.phases.code_review.enabled = true`（默认 true）时，**与 Phase 6 测试执行并行触发**（三路并行）。代码审查仅需 `git diff`，不依赖测试结果。

## 审查流程

### Step 1: 收集变更范围

1. 读取 `.autopilot-active` 获取 `anchor_sha`
2. 执行 `git diff $anchor_sha..HEAD --stat` 获取变更文件列表
3. 过滤 `config.phases.code_review.skip_patterns` 中的文件模式
4. 执行 `git diff $anchor_sha..HEAD -- <filtered_files>` 获取目标 diff

### Step 1.5: 模型路由（critical=true 强制 Opus）

代码审查是发现隐藏缺陷的最后防线，dispatch 前必须调用 resolver 以 `critical=true` 获取模型路由：

```bash
ROUTING_JSON=$(bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/resolve-model-routing.sh "$(pwd)" 6 "" "" 0 true)
```

`critical=true` 触发自动升级到 `deep/opus`，无论用户选择了何种策略预设。从 `ROUTING_JSON` 提取 `selected_model` 用于 Task 的 `model` 参数。

### Step 2: 派发审查 Agent

使用 Task 工具派发代码审查子 Agent（model 从 Step 1.5 路由结果获取）：

```
Task(
  subagent_type: config.phases.code_review.agent,
  model: "{selected_model}",
  run_in_background: true,
  prompt: "你是代码审查专家。审查以下代码变更：

    ## 变更范围
    {git_diff_stat}

    ## 审查清单

    ### 1. 安全性检查
    - [ ] 无硬编码凭证或 API Key
    - [ ] 无 SQL 注入风险
    - [ ] 无 XSS 漏洞
    - [ ] 无命令注入风险

    ### 2. 代码质量
    - [ ] 无重复代码（DRY）
    - [ ] 函数/方法不超过 50 行
    - [ ] 圈复杂度 < 15
    - [ ] 命名清晰一致

    ### 3. 架构一致性
    - [ ] 遵循项目现有模式
    - [ ] 无不必要的依赖引入
    - [ ] 接口设计向后兼容

    ### 4. 测试覆盖
    - [ ] 新增代码有对应测试
    - [ ] 测试覆盖关键路径

    ### 5. 项目规则合规（从 rules-scanner 注入）
    {rules_scan_result}
    {if config.code_constraints.semantic_rules}
    额外语义规则检查：
    {for each rule in config.code_constraints.semantic_rules}
    - [ ] {rule.rule}（scope: {rule.scope}）
    {end for}
    {end if}

    返回 JSON 信封。"
)
```

### Step 3: JSON 信封格式（结构化 findings）

```json
{
  "status": "ok | warning | blocked",
  "summary": "审查总结",
  "findings": [
    {
      "severity": "critical | major | minor | info",
      "file": "path/to/file",
      "line": 42,
      "message": "描述问题",
      "evidence": "具体代码片段或 diff 引用",
      "blocking": true,
      "owner": "reviewer-agent-id"
    }
  ],
  "metrics": {
    "files_reviewed": 12,
    "findings_count": {
      "critical": 0,
      "major": 1,
      "minor": 3,
      "info": 5
    }
  }
}
```

#### findings 字段规范

每个 finding **必须** 包含以下字段：

| 字段 | 必填 | 说明 |
|------|------|------|
| `severity` | 是 | `critical` / `major` / `minor` / `info` |
| `file` | 是 | 问题所在文件路径 |
| `line` | 推荐 | 问题所在行号 |
| `message` | 是 | 问题描述 |
| `evidence` | 是 | 具体代码片段、diff 引用或检测工具输出 |
| `blocking` | 是 | 是否阻断归档（`true` = 必须修复后才能归档） |
| `owner` | 推荐 | 产出该 finding 的 agent 标识 |

### 状态判定规则

| 条件 | 状态 |
|------|------|
| 存在 `blocking: true` 的 findings | `blocked`（Phase 7 归档被硬阻断，直到所有 blocking findings 被解决） |
| critical findings > 0 且 `block_on_critical = true` | `blocked` |
| major findings > 3 | `warning` |
| 其他 | `ok` |

### Step 4: 处理审查结果（fail-closed 门禁）

| 状态 | 处理 |
|------|------|
| ok | 记录 checkpoint，继续质量扫描和 Phase 7 |
| warning | 记录 checkpoint，展示 findings 供用户可见，但**不弹 AskUserQuestion**、不阻断 Phase 7；是否阻断归档由 Phase 7 的 archive-readiness 统一判定 |
| blocked | 写入 `blocked` checkpoint 并展示 blocking findings；后续是否允许继续由 Phase 7 的 archive-readiness + `block_on_critical` 统一判定，主线程此处不额外插入“是否继续”的确认问题 |

> **治理约束**: review findings 不是纯 advisory。`blocking: true` 的 finding 会：
> 1. 将 review checkpoint 状态设为 `blocked`
> 2. Phase 7 的 post-task-validator (Validator 6c) 会检查 review checkpoint
> 3. 存在未解决的 blocking finding 时，Phase 7 被硬阻断
> 4. 只有所有 blocking findings 被标记为 `resolved: true` 后，归档才能继续

### Step 5: 写入 Checkpoint

写入 `phase-results/phase-6.5-code-review.json`，格式同标准 JSON 信封，增加 `findings` 和 `metrics` 字段。

## 配置参考

```yaml
phases:
  code_review:
    enabled: true              # 默认启用
    auto_fix_minor: false      # 是否自动修复 minor findings
    block_on_critical: true    # critical findings 时硬阻断归档（fail-closed）
    skip_patterns:             # 跳过审查的文件模式
      - "*.md"
      - "*.json"
      - "openspec/**"
```

## 与 Hook 门禁的关系

Phase 6.5 不是整数阶段，因此：
- **不受 Layer 2 Hook 门禁校验**（Hook 只检查整数阶段的 predecessor checkpoint）
- 主线程仍执行 JSON 信封解析和状态检查
- checkpoint 文件命名为 `phase-6.5-code-review.json`（带小数点）
- Phase 7 的 post-task-validator (Validator 6c) 会读取此 checkpoint，
  检查是否存在未解决的 `blocking: true` findings。如果存在，Phase 7 被硬阻断。
  这使得 review findings 真实影响归档结果，而非纯 advisory。

## Review Findings 生命周期

```
1. Phase 6.5 审查 Agent 产出 findings（含 severity + blocking 标记）
2. 写入 phase-6.5-code-review.json
3. 如果存在 blocking findings:
   a. checkpoint status 设为 "blocked"
   b. 主线程展示 findings，要求修复
   c. 修复后重新 review 或手动标记 resolved
   d. 更新 checkpoint: finding.resolved = true
4. Phase 7 启动前, post-task-validator 检查:
   - 读取 phase-6.5-code-review.json
   - 遍历 findings 中 blocking=true 的条目
   - 如果任何 blocking finding 未标记 resolved → 阻断 Phase 7
5. 所有 blocking findings 解决后 → Phase 7 放行
```
