---
name: autopilot-test-audit
description: "Static test rot detector. Generates candidate list (.cache/spec-autopilot/test-rot-candidates.json) when deleted runtime scripts are still referenced in tests, hook files change, weak assertions appear, or duplicate case names are detected. Read-only; review the candidates manually before fixing tests. Triggers: '检测测试腐烂', 'audit tests'."
user-invocable: true
---

# autopilot-test-audit — 测试过期静态检测

## 用途

- 在 pre-commit / 周期性审计 / 手动触发时，对 staged changes 与 tests/ 全量做**确定性**的过期检测
- 仅基于 grep / regex 模式匹配，**不调用 LLM**
- 仅生成候选清单（warn / info 级别），**不自动修改测试**
- 修复动作交给人工或 `autopilot-test-fix`（未来）

## 触发入口

- `pre-commit` hook（建议在 dist rebuild 之后调用 `engineering-sync-gate.sh`）
- 手动：`bash plugins/spec-autopilot/runtime/scripts/detect-test-rot.sh --changed-files "<files>" --deleted-files "<files>"`
- 与 docs-sync 不同，本 skill **允许人工触发**（非编排器专用）

## 检测规则

| Rule | Severity | 触发条件 |
|------|----------|---------|
| R1 | warn | 删除/重命名 `runtime/scripts/<X>.sh` 但 `tests/` 下仍有 grep 命中 |
| R2 | warn | 源码中 symbol 删除但测试仍引用（启发式：基于函数名相似度） |
| R3 | info | `hooks/` 下文件修改 → 提示相关 test 需回归 |
| R4 | warn | 弱断言模式：`assert_exit "x" 0 0` / `[ "a" = "a" ]` / `grep -q . .` |
| R5 | warn | 重复 case 名称（同一文件内 / 跨 tests/ 全量） |

## 产物

- `<project_root>/.cache/spec-autopilot/test-rot-candidates.json` —— `{timestamp, checks:[{rule_id, severity, source_file, target_file, reason, evidence}]}`

## 退出码

- 始终 `0`（warn-only）
- block 模式由 `engineering-sync-gate.sh` 根据 config 决定

## 详细规则

详见 `references/audit-rules.md`。
