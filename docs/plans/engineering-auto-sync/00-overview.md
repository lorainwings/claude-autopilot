# 工程化自动同步能力 — 总览

> 单点真相文档（00/01/02/03 系列共四份）。本轮目标：让"代码改了文档没跟、测试积陈年灰"两类**确定性问题**在 pre-commit 阶段被静态捕获，不引入 LLM、不阻塞默认流程。

## 背景

- spec-autopilot 测试库基线 121 文件 / 1698 断言（见 `docs/plans/engineering-auto-sync/test-audit.md:7`），单位测试规模已超出"凭记忆维护"的安全水位。
- SKILL.md / runtime 脚本 / CLAUDE.md 等"事实源"文件改动后，README、`.dist-include`、根插件表格容易遗漏同步（Agent R 在 `research.md:8` 横向调研所揭示的共性问题）。
- 历史方案要么强依赖 LLM（Mintlify Autopilot），要么需要语义 anchor 改造（Swimm），不适合本轮"零 LLM、零侵入"约束。

## 目标

1. **静态优先**：纯 grep / regex 实现，秒级出结果，CI 友好。
2. **候选清单制**：只生成 `.cache/spec-autopilot/drift-candidates.json` / `.cache/spec-autopilot/test-rot-candidates.json` / `.cache/spec-autopilot/engineering-sync-report.json`（自 v5.9 迁移至 `.cache/spec-autopilot/`），**禁止自动修改源码**。
3. **人工 confirm**：修复动作走 Skill (`/autopilot-docs-sync`、`/autopilot-test-audit`) 或人工 review。
4. **向后兼容**：默认 warn-only，不破坏现有 8-step gate 流程，不影响 release-please。

## 三大产出

| 产出 | 路径 | 角色 |
|------|------|------|
| `autopilot-docs-sync` Skill | `plugins/spec-autopilot/skills/autopilot-docs-sync/SKILL.md` | 文档漂移检测 5 规则 (R1-R5)，含 ownership-mapping 参考 |
| `autopilot-test-audit` Skill | `plugins/spec-autopilot/skills/autopilot-test-audit/SKILL.md` | 测试腐烂检测 4 规则 (R1/R3/R4/R5)，user-invocable |
| `engineering-sync-gate.sh` 聚合入口 | `plugins/spec-autopilot/runtime/scripts/engineering-sync-gate.sh` | 并行调用两检测器 → 聚合 `.cache/spec-autopilot/engineering-sync-report.json` → warn/block 双模式 |

辅以 3 套测试 41 case 全 PASS、`.drift-ignore` 忽略机制、配套 fixtures。

## 验收标准

- 默认 `engineering_auto_sync.enabled: false` → 仅打印 warn 摘要，pre-commit/CI 永不阻断。
- 显式 `engineering_auto_sync.enabled: true` 后，聚合脚本在候选数 > 0 时返回 exit 1 阻断 commit/push（`engineering-sync-gate.sh:97-101`）。
- 三检测脚本退出码恒为 0，决策权在聚合层。

## ASCII 总图

```
                 ┌──────────────────────┐
 source change → │  engineering-sync-   │ ── parallel ─┬─→ detect-doc-drift.sh ─→ .cache/spec-autopilot/drift-candidates.json
 (staged files)  │       gate.sh        │              └─→ detect-test-rot.sh   ─→ .cache/spec-autopilot/test-rot-candidates.json
                 └──────────┬───────────┘
                            │ aggregate
                            ▼
                 .cache/spec-autopilot/engineering-sync-report.json
                            │
            ┌───────────────┴───────────────┐
            ▼                               ▼
    enabled=false (warn)            enabled=true (block)
    打印摘要 / exit 0               候选>0 时 exit 1
            │                               │
            └─────────── review ────────────┘
                            │
                            ▼
            /autopilot-docs-sync · /autopilot-test-audit
                  (人工 Skill 修复) · `.drift-ignore`
```
