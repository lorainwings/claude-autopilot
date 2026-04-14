# Setup Wizard — 快速启动引导

> 本文件由 `autopilot-setup/SKILL.md` 通过 `**执行前读取**` 引用。
> 包含 Wizard 的 3 步交互流程和预设模板定义。

## Wizard Step 1: 选择预设模板

通过 AskUserQuestion 展示 3 个预设：

```
"欢迎使用 autopilot！请选择质量门禁级别："

选项:
- "Strict (推荐生产项目)" →
    门禁严格：测试金字塔 unit≥50%/e2e≤20%，TDD 模式，Phase 4 必须 ok（不接受 warning），
    代码审查启用且 critical 阻断，零跳过强制，覆盖率 80%

- "Moderate (推荐日常开发)" →
    门禁适中：测试金字塔 unit≥30%/e2e≤40%，无 TDD，Phase 4 标准门禁，
    代码审查启用但不阻断，覆盖率 60%

- "Relaxed (快速原型)" →
    门禁宽松：minimal 执行模式，无测试金字塔强制，无代码审查，
    覆盖率 40%，适合 PoC/原型验证
```

## Wizard Step 2: 确认自动检测

运行标准 Step 1-2.6 的自动检测流程（`references/setup-detection-rules.md`），展示检测结果摘要。
用户确认或调整后继续。

## Wizard Step 3: 应用预设 + 写入

将预设模板值覆盖到自动检测结果上，生成最终配置。

### 预设模板映射

```yaml
# --- Strict 预设 ---
strict:
  default_mode: "full"
  model_strategy: "quality_max"  # 质量优先模型路由
  phases.implementation.tdd_mode: true
  phases.implementation.tdd_refactor: true
  phases.reporting.coverage_target: 80
  phases.reporting.zero_skip_required: true
  phases.code_review.enabled: true
  phases.code_review.block_on_critical: true
  test_pyramid.min_unit_pct: 50
  test_pyramid.max_e2e_pct: 20
  test_pyramid.min_total_cases: 20
  gates.user_confirmation.after_phase_1: false
  gates.user_confirmation.after_phase_3: false
  gates.auto_continue_after_requirement: true
  gates.archive_auto_on_readiness: true

# --- Moderate 预设 ---
moderate:
  default_mode: "full"
  model_strategy: "balanced"     # 平衡模型路由
  phases.implementation.tdd_mode: false
  phases.reporting.coverage_target: 60
  phases.reporting.zero_skip_required: true
  phases.code_review.enabled: true
  phases.code_review.block_on_critical: false
  test_pyramid.min_unit_pct: 30
  test_pyramid.max_e2e_pct: 40
  test_pyramid.min_total_cases: 10
  gates.user_confirmation.after_phase_1: false
  gates.user_confirmation.after_phase_3: false
  gates.auto_continue_after_requirement: true
  gates.archive_auto_on_readiness: true

# --- Relaxed 预设 ---
relaxed:
  default_mode: "minimal"
  model_strategy: "cost_optimized"  # 省钱优先模型路由
  phases.implementation.tdd_mode: false
  phases.reporting.coverage_target: 40
  phases.reporting.zero_skip_required: false
  phases.code_review.enabled: false
  phases.code_review.block_on_critical: false
  test_pyramid.min_unit_pct: 20
  test_pyramid.max_e2e_pct: 60
  test_pyramid.min_total_cases: 5
  gates.user_confirmation.after_phase_1: false
  gates.user_confirmation.after_phase_3: false
  gates.auto_continue_after_requirement: true
  gates.archive_auto_on_readiness: true
```

## Wizard 完成后输出

```
✓ autopilot 配置已生成: .claude/autopilot.config.yaml
  预设: {preset_name} | 模式: {default_mode} | TDD: {on/off}
  Agent: {agent_summary} | 模型策略: {model_strategy}
  测试套件: {N} 个 | 服务: {N} 个

  快速开始: 输入 /autopilot <需求描述>
  调整 Agent: /autopilot-agents [install|list|swap|recommend]
  调整模型: /autopilot-models [cost|balanced|quality]
  调整配置: 编辑 .claude/autopilot.config.yaml
```
