# 落地路径 — pre-commit 接入 / .drift-ignore / 人工触发

> 本文档说明如何激活工程化自动同步能力、如何写 `.drift-ignore`、以及两个 Skill 的人工触发用法。

## 1. 配置节

在 `.claude/autopilot.config.yaml` 中（新增字段，顶层）：

```yaml
engineering_auto_sync:
  enabled: false            # 默认 disabled，仅 warn；置 true 后聚合门会硬阻断
  drift_ignore_file: .drift-ignore
```

字段语义见 `plugins/spec-autopilot/skills/autopilot-docs-sync/SKILL.md:52-57`。聚合脚本通过 `read_config_value` 读取（参见 `engineering-sync-gate.sh:49-53`）。

## 2. pre-commit 接入（已落地）

本能力已作为 "Part 1.5" 接入 `.githooks/pre-commit`（参见 `plugins/spec-autopilot/CLAUDE.md` 工程自动化纪律章节）。概念上等价的伪代码 patch：

```bash
# .githooks/pre-commit — 在 dist rebuild 之后、版本一致性校验之前插入
PLUGIN_ROOT="plugins/spec-autopilot"

STAGED=$(git diff --cached --name-only --diff-filter=ACMR | tr '\n' ' ')
DELETED=$(git diff --cached --name-only --diff-filter=D | tr '\n' ' ')

bash "${PLUGIN_ROOT}/runtime/scripts/engineering-sync-gate.sh" \
  --changed-files "$STAGED" \
  --deleted-files "$DELETED" || {
    # enabled=true 时 exit 1 阻断 commit；enabled=false 时不会走到这里
    exit 1
  }
```

关键点：

- 放在 **dist rebuild 之后**：保证 dist 中的 SKILL.md / README.md 已最新，检测基于最终状态；
- 放在 **版本一致性校验之前**：gate 自身不触发版本变更，顺序无严格依赖，但使"漂移在前、版本在后"的诊断流更直观；
- release-please bot commit 经 pre-commit 入口处的分支 bypass 已跳过，无需在本 Part 重复判断。

## 3. `.drift-ignore` 使用

仓库根目录放置 `.drift-ignore`，语法三选一：

```
# 1) 全局抑制某规则
rule_id:R3

# 2) 对特定路径抑制某规则
rule_id:R1 path:plugins/spec-autopilot/skills/private/SKILL.md

# 3) 路径前缀整体抑制（所有规则）
plugins/spec-autopilot/tests/fixtures/
```

注释（`#` 开头）与空行被忽略，样例见 `plugins/spec-autopilot/tests/fixtures/engineering-sync/.drift-ignore.sample`（`autopilot-docs-sync/SKILL.md:38-44`）。

**常见误报场景与建议写法**：

| 场景 | 建议条目 |
|------|---------|
| fixture 目录下的 SKILL.md 故意与 README 不同步 | `plugins/spec-autopilot/tests/fixtures/` |
| 内部私有 Skill 不对外暴露 | `rule_id:R1 path:plugins/spec-autopilot/skills/private/SKILL.md` |
| CLAUDE.md 每次提交都动但不想每次 R3 刷屏 | `rule_id:R3` |
| 新增 runtime 脚本属于调试工具，不进 dist | `rule_id:R2 path:runtime/scripts/debug-*.sh` |

## 4. 人工触发 Skill

### `/autopilot-test-audit`（user-invocable）

声明在 `plugins/spec-autopilot/skills/autopilot-test-audit/SKILL.md:1-5`，YAML 头 `user-invocable: true`。典型触发词：

> "检测测试腐烂" / "audit tests" / "扫一下测试是不是有过期"

手动脚本入口：

```bash
bash plugins/spec-autopilot/runtime/scripts/detect-test-rot.sh \
  --changed-files "$(git diff --name-only HEAD~5 HEAD | tr '\n' ' ')" \
  --deleted-files ""
```

### `/autopilot-docs-sync`（orchestrator-only）

声明在 `plugins/spec-autopilot/skills/autopilot-docs-sync/SKILL.md:1-5`，YAML 头 `user-invocable: false`。仅在 autopilot 编排主线程中自动调用，**不接受用户直接触发**（人工扫描走 `detect-doc-drift.sh` 脚本）。

手动脚本入口：

```bash
bash plugins/spec-autopilot/runtime/scripts/detect-doc-drift.sh \
  --changed-files "$(git diff --cached --name-only | tr '\n' ' ')"
```

产物：根目录 `.drift-candidates.json` / `.test-rot-candidates.json` / `.engineering-sync-report.json`。建议提交前 review 后再决定是否启用 `enabled: true` 硬阻断。
