---
name: autopilot-docs-sync
description: "[ONLY for autopilot orchestrator] Static documentation drift detector. Generates candidate list (.drift-candidates.json) when SKILL.md / runtime scripts / CLAUDE.md changes are not mirrored in README, .dist-include or root plugin tables. Does NOT auto-modify; review the candidates manually."
user-invocable: false
---

# autopilot-docs-sync — 文档漂移静态检测

> **前置条件自检**：本 Skill 仅在 autopilot 编排主线程中使用。如果当前上下文不是 autopilot 编排流程，请立即停止并忽略本 Skill。

## 用途

- 在 pre-commit / Phase 7 收尾 / 人工审计时，对 staged changes 做**确定性**的文档漂移检测
- 仅基于 grep / regex / 文件存在性判断，**不调用 LLM**
- 仅生成候选清单（warn 级别），**不自动修改源码**
- 修复动作交给下一轮人工或 `autopilot-docs-fix`（未来）

## 触发入口

- `pre-commit` hook（建议在 dist rebuild ���后调用 `engineering-sync-gate.sh`）
- 手动：`bash plugins/spec-autopilot/runtime/scripts/detect-doc-drift.sh --changed-files "<files>"`

## 检测规则

| Rule | Severity | 触发条件 | 建议同步动作 |
|------|----------|---------|-------------|
| R1 | warn | `skills/<X>/SKILL.md` 修改但 `plugins/spec-autopilot/README*.md` 未触及 | 同步 README 描述章节 |
| R2 | warn | 新增 `runtime/scripts/<X>.sh` 但未登记 `.dist-include` | 在 `.dist-include` 追加文件名 |
| R3 | info | `plugins/spec-autopilot/CLAUDE.md` 修改 | 检查 README 版本标识是否仍准确 |
| R4 | info | `skills/autopilot/SKILL.md`（Phase 总览）修改 | 检查 `docs/plans/` 流程图是否需刷新 |
| R5 | warn | 新增 `skills/<new>/SKILL.md` 但根 `README.md` 表格未提及 | 在根 README 插件表格中追加条目 |

## 产物

- `<project_root>/.drift-candidates.json` —— `{timestamp, checks:[{rule_id, severity, source_file, target_file, reason, evidence}]}`

## 忽略机制

- 项目根 `.drift-ignore` 文件支持以下格式：
  - `rule_id:R1` — 全局抑制 R1
  - `rule_id:R1 path:plugins/spec-autopilot/skills/private/SKILL.md` — 仅对特定路径抑制
  - `path/prefix/` 单行 — 抑制路径前缀全部规则
- 注释（`#` 开头）与空行被忽略
- 样例：`plugins/spec-autopilot/tests/fixtures/engineering-sync/.drift-ignore.sample`

## 退出码

- 始终 `0`（warn-only）
- 实际 block / warn 由聚合脚本 `engineering-sync-gate.sh` 根据 `autopilot.config.yaml` 的 `engineering_auto_sync.enabled` 决定

## 配置示例

```yaml
# .claude/autopilot.config.yaml
engineering_auto_sync:
  enabled: false   # 默认 disabled，仅 warn；置 true 后聚合门会硬阻断
```

## 详细规则与映射

详见 `references/ownership-mapping.md`。
