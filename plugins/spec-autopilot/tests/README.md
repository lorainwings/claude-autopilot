# spec-autopilot 测试套件说明

本目录下所有 `test_*.sh` 文件共同构成 spec-autopilot 插件的测试基线。

## 目录总览

测试文件按"测试层"自动分类（由 `run_all.sh` 读取文件首部 `# TEST_LAYER:` 注释动态判定）：

| 层 | 定义 | 示例 |
|----|------|------|
| `contract` | 运行时契约断言：reference 文件存在性、plugin.json 版本、hooks.json 结构 | `test_reference_files.sh` |
| `behavior` | 行为级验证：hook/脚本在各种输入下的副作用和产物 | `test_auto_emit_agent.sh`、`test_lock_precheck.sh` |
| `docs_consistency` | 文档一致性：SKILL.md、references/*.md 中约定内容未被意外修改 | `test_auto_continue.sh` |

> 未声明 `# TEST_LAYER:` 的文件默认归类为 `behavior`。

## 执行方式

```bash
# 全量运行（推荐：每次 git push 前必做）
bash plugins/spec-autopilot/tests/run_all.sh

# 单文件运行（用于定位问题）
bash plugins/spec-autopilot/tests/test_<name>.sh
```

全量输出末尾格式：

```
Test Summary: N files, P passed, F failed
By Layer:
  contract:         …
  behavior:         …
  docs_consistency: …
```

单文件输出末尾必须为：

```
Results: $PASS passed, $FAIL failed
```

## smoke_release.sh 专项说明

`smoke_release.sh` **不在** `run_all.sh` 扫描范围内（命名不匹配 `test_*.sh`）。它是独立的发布烟雾测试，用于发版前验证 dist 构建产物的可用性，由 `tools/release.sh` 或手动在发版流水线中调用，与本目录下的 `test_*.sh` 单元/行为测试职责正交。

## 弱断言基线（Intentionally weak — exit-code only）

以下文件的若干 case **合理**地仅检查 `exit_code`，不追加内容断言，原因是被测脚本本身是"静默 guard hook"（正常路径零输出，只通过退出码表达"放行/阻断"意图）：

- `test_lock_precheck.sh`：验证 precheck 脚本在无锁文件或 marker 文本场景下**静默放行**（输出必须为空或不含 `deny`/`block`）
- `test_background_agent_bypass.sh` §45a-45f：验证后台 Agent 绕过时**静默放行**
- `test_syntax.sh`：`bash -n` 语法检查，退出码即结论
- `test_auto_emit_agent.sh` §1c/1d：empty stdin no-op
- `test_session_hooks.sh` §11e/11f：边界条件下静默 fallthrough（已补强为"exit 0 + 输出不含 error/reinject 关键字"）

如果未来为上述 case 新增内容断言，请使用 `assert_not_contains`（验证输出**不含**阻断关键字）或 `assert_contains` 断言具体放行语义，**禁止**改动现有 `assert_exit` 为"`1 → 0`"的弱化方向。

## 测试写法规范

1. **文件命名**：必须为 `test_*.sh`，否则 `run_all.sh` 不会扫描
2. **结尾汇总格式**：必须以 `echo "Results: $PASS passed, $FAIL failed"` 收尾
   - `run_all.sh` 的聚合 grep 依赖此精确字符串
   - case 级 `PASS:/FAIL:` 输出必须走 `green`/`red` 辅助函数（加两空格前缀），避免与汇总行冲突
3. **退出码规约**：`[ "$FAIL" -gt 0 ] && exit 1; exit 0`
4. **TEST_LAYER 声明**：contract / docs_consistency 层必须在第 2 行写 `# TEST_LAYER: contract` 或 `# TEST_LAYER: docs_consistency`；behavior 层可不写
5. **基础设施只读**：`_fixtures.sh` / `_test_helpers.sh` 只能新增函数，不得改动现有函数签名
6. **路径动态推导**：所有路径基于 `$TEST_DIR` / `$SCRIPT_DIR`，禁止硬编码绝对路径
7. **断言强度**：新增 `exit_code` 断言必须配套一条内容校验（`assert_contains` / `grep -q` 检查产物字段或文件内容关键词），除非落入"弱断言基线"豁免范围

## 新增测试文件清单

1. 文件名 `test_<主题>.sh`
2. 第 1 行 shebang：`#!/usr/bin/env bash`
3. 第 2 行（可选）`# TEST_LAYER: <层名>`
4. 标准前置：`set -uo pipefail` + `TEST_DIR` / `SCRIPT_DIR` 解析 + source `_test_helpers.sh` + `_fixtures.sh`
5. `setup_autopilot_fixture` / `teardown_autopilot_fixture` 包裹
6. 每个 case 明确编号（如 `# 3a. <description>`）
7. 结尾 `Results: $PASS passed, $FAIL failed` + exit 码守卫

## 相关入口

- 测试编排：`run_all.sh`
- 共享辅助：`_test_helpers.sh`（断言函数）、`_fixtures.sh`（环境准备/清理）
- 发布烟雾：`smoke_release.sh`（独立流程，与本 README 弱关联）
