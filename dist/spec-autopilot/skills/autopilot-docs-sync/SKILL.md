---
name: autopilot-docs-sync
description: "Use when the autopilot orchestrator or pre-commit hook needs deterministic static detection of documentation drift between SKILL.md, runtime scripts, CLAUDE.md and their README / .dist-include / root plugin table targets."
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

- `pre-commit` hook（建议在 dist rebuild 之后调用 `engineering-sync-gate.sh`）
- 手动：`bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/detect-doc-drift.sh --changed-files "<files>"`

## 检测规则

| Rule | Severity | 触发条件 | 建议同步动作 |
|------|----------|---------|-------------|
| R1 | warn | `skills/<X>/SKILL.md` 修改但 `plugins/spec-autopilot/README*.md` 未触及 | 同步 README 描述章节 |
| R2 | warn | 新增 `runtime/scripts/<X>.sh` 但未登记 `.dist-include` | 在 `.dist-include` 追加文件名 |
| R3 | info | `plugins/spec-autopilot/CLAUDE.md` 修改 | 检查 README 版本标识是否仍准确 |
| R4 | info | `skills/autopilot/SKILL.md`（Phase 总览）修改 | 检查 `docs/plans/` 流程图是否需刷新 |
| R5 | warn | 新增 `skills/<new>/SKILL.md` 但根 `README.md` 表格未提及 | 在根 README 插件表格中追加条目 |

## 产物

- `<project_root>/.cache/spec-autopilot/drift-candidates.json` —— `{timestamp, checks:[{rule_id, severity, source_file, target_file, reason, evidence}]}`

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

## References 按需读取清单

以下 references 文件**互不强制串读**，按当前任务上下文显式择一加载，禁止链式跳转：

| 场景 | 文件 | 用途 |
|------|------|------|
| 排查 R1–R5 规则定义、严重度、建议同步动作 | `references/ownership-mapping.md` | Rule → 动作映射表 |
| 在源码 / 文档中插入双向 ownership 锚点 | `references/anchor-syntax.md` | `# CODE-REF:` / `<!-- CODE-OWNED-BY: -->` 语法规范 |
| 配置 fallback ownership（`.claude/docs-ownership.yaml`） | `references/ownership-config.md` | YAML schema、glob 行为、优先级 |
| 复制项目级 ownership 模板 | `references/docs-ownership.yaml.example` | 可直接 `cp` 到 `.claude/docs-ownership.yaml` 的样例 |

> 三份 references 之间互为参照而非强制依赖：内联锚点语法（anchor-syntax）、配置 fallback（ownership-config）、可执行模板（docs-ownership.yaml.example）任一切入点都自洽，无需顺序读取。
