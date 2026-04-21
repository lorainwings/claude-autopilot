---
name: autopilot-test-fix
description: "Use when the user wants to consume the test-rot candidate list at .cache/spec-autopilot/test-rot-candidates.json and generate repair artifacts — deterministic sed-style patches for R1 orphan references and .suggestion.md files (including weak-assertion templates) for the rest. Typical triggers: '/autopilot-test-fix scan', '修复测试腐烂'. Does not directly modify tests/*.sh; application is a separate manual step via apply-fix-patch.sh."
user-invocable: true
---

# autopilot-test-fix — 测试过期候选修复生成器

## 用途

- 消费 `autopilot-test-audit` 产出的 `.cache/spec-autopilot/test-rot-candidates.json`
- 输出位置：`<project>/.cache/spec-autopilot/tests-fix-patches/`（**绝不写入 `tests/*.sh`**）
- 修复动作分类：
  - **R1**（删除脚本仍被引用）：尝试生成确定性 patch 移除引用行；上下文复杂时退化为 suggestion
  - **R3 / R4 / R5**：生成 `.suggestion.md`（R5 附弱断言补强模板）

## 触发入口

- `/autopilot-test-fix scan` — 扫描候选并生成修复产物
- `/autopilot-test-fix apply --patch-id <id>` — 应用单个 patch

## 前置依赖

若 `.cache/spec-autopilot/test-rot-candidates.json` 不存在，提示先执行：

```bash
bash plugins/spec-autopilot/runtime/scripts/detect-test-rot.sh \
  --changed-files "<files>" --deleted-files "<files>"
```

或直接触发 `autopilot-test-audit` skill。

## 规则 → 产物映射

| Rule | 类型 | 产物 | 说明 |
|------|------|------|------|
| R1 | auto / manual | `.R1.patch` 或 `.suggestion.md` | 删除 tests 中对失效脚本 basename 的引用行 |
| R3 | manual | `.suggestion.md` | 提示该 symbol 已不存在，建议删除 case |
| R4 | manual | `.suggestion.md` | hook 修改提示对应 test 回归 |
| R5 | manual | `.suggestion.md` | 弱断言模式 + `assert_contains` / `assert_json_field` 补强模板 |

## 命令

```bash
# 扫描生成
bash plugins/spec-autopilot/runtime/scripts/generate-test-fix-patch.sh \
  --candidates-file .cache/spec-autopilot/test-rot-candidates.json \
  --output-dir .cache/spec-autopilot/tests-fix-patches/

# 应用 (manual 需 --force-manual)
bash plugins/spec-autopilot/runtime/scripts/apply-fix-patch.sh \
  --index .cache/spec-autopilot/tests-fix-patches/INDEX.json \
  --patch-id <id> [--force-manual]
```

## 安全保证

- 生成阶段绝不修改 `tests/*.sh`（测试有断言守护）
- 应用阶段每次 `git stash push -u` + `git apply --check`，失败 `git stash pop` 回滚
- **禁止在 CI / pre-commit 中自动调用**

## 弱断言补强模板示例

`.suggestion.md` 中的 R5 模板片段：

```bash
# 推荐
assert_contains "case 名" "$OUTPUT" "期望子串"
assert_json_field "case 名" "$JSON_OUT" "field" "期望值"

# 避免（恒真模式）
assert_exit "x" 0 0
[ "a" = "a" ]
grep -q . .
```

详见 `references/patch-strategies.md`。
