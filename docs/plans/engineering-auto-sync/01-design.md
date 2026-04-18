# 设计决策 — R 推荐 vs I 落地 diff

<!-- CODE-OWNED-BY: plugins/spec-autopilot/runtime/scripts/detect-doc-drift.sh -->

> 本轮实现相对 Agent R 的调研建议做了**选择性收敛**（优先确定性、放弃语义锚点），下面逐项对照说明。

## 1. R 推荐 vs I 实际实现对照表

| 主题 | Agent R 推荐 (research.md 引用) | Agent I 实际落地 | 状态 |
|------|------------------------------|------------------|------|
| 触发分层 | L1 post-commit + L2 pre-push + L3 CI 三层（`research.md:27-31`） | 单层 pre-commit，由 `engineering-sync-gate.sh` 聚合 | 已收敛为单层（成本/收益权衡） |
| Ownership 映射 | `.claude/docs-ownership.yaml` + `<!-- CODE-REF: path#symbol -->` 锚点（`research.md:39-48`） | `autopilot-docs-sync/references/ownership-mapping.md` 静态表 + 基于文件路径 glob 的启发式命中（见 `autopilot-docs-sync/SKILL.md:25-32` 的 R1-R5 规则） | **命中方向，未实现锚点**，标为 P1 |
| Drift 检测 | R/regex + 静态 anchor 校验 + README 版本对比（`research.md:47-50`） | R1-R5 共 5 规则，基于 grep + 路径模式；version 对比暂未纳入 | 命中主线，版本对比留 P1 |
| AI fallback | 生成 patch 到 `.claude/candidates/docs/` 但不自动 commit（`research.md:52-55`） | 本轮**完全不接 LLM**，候选清单存 `.cache/spec-autopilot/drift-candidates.json` 由人工 / Skill 修复 | 暂未实现，标为 P1 |
| 测试审计 S1 静态 | ripgrep 比对 orphan 引用 + `# @covers` 约定（`research.md:62-64`） | R1 (deleted script refs) + R4 (weak assertion) + R5 (duplicate case) 三条；`@covers` 约定未强制推行 | 命中 S1 核心，`@covers` 待下一轮 |
| 测试审计 S2 语义 | `# @rationale` 注释 + 相似度阈值（`research.md:63-64`） | 未实现 | P2（需自学习闭环） |
| 测试审计 S3 变异 | 周 sweep 跑 mutmut 风格变异（`research.md:65`） | 未实现 | P2 |
| 人工闭环 | `CANDIDATE_REMOVE/UPDATE/KEEP` 三类标记 + `confirm` 子命令（`research.md:67-70`） | 候选清单仅含 `{rule_id, severity, source_file, target_file, reason, evidence}`，未分三类；confirm 交互走 Skill | 概念命中，标签语义收敛到 severity |
| .drift-ignore 抑制 | 未明确提出 | 新增 `.drift-ignore`（`rule_id:Rx` / `path:...` / 路径前缀），fixture 附 sample | **I 新增能力**，相对 R 有增强 |
| warn/block 双模式 | 默认 warn（`research.md:29` L1 不阻塞） | `engineering_auto_sync.enabled` 开关 → warn|block（`engineering-sync-gate.sh:48-53`） | 命中 |

## 2. ownership 锚点机制 — 现状与下一轮计划

**R 的理想形态**：

```
<!-- CODE-REF: plugins/spec-autopilot/runtime/scripts/foo.sh#some_func -->
```

扫描器在文档里找 anchor，反向校验 symbol 仍存在，不存在 → drift。

**I 的当前形态**：基于路径 glob 的启发式命中，例如 R1（`autopilot-docs-sync/SKILL.md:27`）：

> `skills/<X>/SKILL.md` 修改但 `plugins/spec-autopilot/README*.md` 未触及 → warn

这是**粗粒度 ownership**，能抓到"改了 Skill 没改 README"这类大类，但无法识别"改了函数签名没改文档里的函数说明"这类细粒度 drift。

**下一轮 P1 计划**：

1. 引入 `<!-- CODE-REF: path#symbol -->` 注释规范并在 spec-autopilot README/CLAUDE 先行示范。
2. 在 `detect-doc-drift.sh` 增加 R6 规则：解析所有 `CODE-REF`，逐条校验 symbol 存在性。
3. `.drift-ignore` 扩展支持 `code-ref:<path>#<symbol>` 形式。

## 3. 与 autopilot-learn 协同

按 `research.md:82-83` 的建议：

- `.cache/spec-autopilot/engineering-sync-report.json` 中的 `doc_drift.candidates` / `test_rot.candidates` 可作为 **failure_pattern** 输入喂给 `autopilot-learn` 的 episodes 库。
- 例：某 `skills/autopilot-phaseX/SKILL.md` 频繁触发 R1 而 README 始终滞后，episodes 可积累"该 SKILL 改动后必同步 README § 某章节"的 rationale，为未来 Phase 4 测试设计提供反例。
- 接入方式：autopilot-learn 读取 `.cache/spec-autopilot/engineering-sync-report.json`（只读），不修改本轮产物格式。

## 4. 与 autopilot-gate 协同（关键：保持解耦）

- **触发时机**：pre-commit hook 内（参见 02-rollout），**不嵌入** `autopilot` 8-step gate。
- **理由**：8-step gate 面向 Phase 级 AI 行为判定，本能力面向物理层文件一致性，两者关注点不同；若挂进 gate，会在 Phase 1/2/3 频繁误报（需求/spec 阶段尚无代码修改）。
- **产物隔离**：`.cache/spec-autopilot/engineering-sync-report.json` 与 `phase-results/checkpoint-*.json` 互不引用，防止循环依赖。
- **退出码契约**：三个检测脚本退出码恒为 0（`detect-doc-drift.sh`、`detect-test-rot.sh`），决策权集中在 `engineering-sync-gate.sh:48-101`，保证 gate 外部可预测。
