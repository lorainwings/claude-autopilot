# Phase 6.5: AI 代码审查 — 详细流程

> 本文件由 autopilot SKILL.md 引用，Phase 6 完成后、Phase 7 之前按需读取。

## 触发条件

当 `config.phases.code_review.enabled = true`（默认 true）时，**与 Phase 6 测试执行并行触发**（v3.2.2 三路并行）。代码审查仅需 `git diff`，不依赖测试结果。

## 审查流程

### Step 1: 收集变更范围

1. 读取 `.autopilot-active` 获取 `anchor_sha`
2. 执行 `git diff $anchor_sha..HEAD --stat` 获取变更文件列表
3. 过滤 `config.phases.code_review.skip_patterns` 中的文件模式
4. 执行 `git diff $anchor_sha..HEAD -- <filtered_files>` 获取目标 diff

### Step 2: 派发审查 Agent

使用 Task 工具派发代码审查子 Agent：

```
Task(
  subagent_type: "pr-review-toolkit:code-reviewer",
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

### Step 3: JSON 信封格式

```json
{
  "status": "ok | warning | blocked",
  "summary": "审查总结",
  "findings": [
    {
      "severity": "critical | major | minor | info",
      "file": "path/to/file",
      "line": 42,
      "message": "描述问题"
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

### 状态判定规则

| 条件 | 状态 |
|------|------|
| critical findings > 0 且 `block_on_critical = true` | `blocked` |
| major findings > 3 | `warning` |
| 其他 | `ok` |

### Step 4: 处理审查结果

| 状态 | 处理 |
|------|------|
| ok | 记录 checkpoint，继续质量扫描和 Phase 7 |
| warning | 展示 findings 给用户，AskUserQuestion 确认是否继续 |
| blocked | 展示 critical findings，要求修复后重新审查 |

### Step 5: 写入 Checkpoint

写入 `phase-results/phase-6.5-code-review.json`，格式同标准 JSON 信封，增加 `findings` 和 `metrics` 字段。

## 配置参考

```yaml
phases:
  code_review:
    enabled: true              # 默认启用
    auto_fix_minor: false      # 是否自动修复 minor findings
    block_on_critical: true    # critical findings 是否阻断流水线
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
