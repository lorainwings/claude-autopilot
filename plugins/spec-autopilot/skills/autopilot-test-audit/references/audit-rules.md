# 测试过期审计规则 (Audit Rules)

本文档定义 `detect-test-rot.sh` 使用的静态检测规则及其 evidence 格式。

## R1: 死链引用（Dangling Reference）

**触发**：`git diff --diff-filter=D` 中 `plugins/spec-autopilot/runtime/scripts/<X>.sh` 被删除，但 `tests/` 下仍有文件包含该脚本名。

**Evidence 格式**：`refs=<tests/file_a.sh;tests/file_b.sh;...>`（最多 3 条）

**建议修复**：

1. 若脚本真被删除 → 更新或删除引用的测试
2. 若仅重命名 → 在测试中同步新名称
3. 误报 → 加入 `.drift-ignore`

## R2: Symbol 引用过期

**触发**：源码中函数名 `foo_bar()` 被删除，测试中仍出��� `foo_bar`。

**注意**：本规则是启发式，可能有误报（同名但不同含义）。当前实现仅标注 hint，不自动分析 AST。

## R3: Hook 修改提示

**触发**：`plugins/spec-autopilot/hooks/**` 下任一文件修改。

**建议动作**：手动跑一次相关 test_hooks_* 套件回归。Info 级，不阻断。

## R4: 弱断言模式

| 模式 | 示例 | 问题 |
|------|------|------|
| `assert_exit "x" 0 0` | `assert_exit "noop" 0 0` | 期望值与实际值都是 0 硬编码 |
| `[ "a" = "a" ]` | `[ "pass" = "pass" ]` | 恒真 tautology |
| `grep -q . .` | `grep -q . .` | 对 `.` 文件 grep 任意字符，几乎恒真 |

**Evidence 格式**：`<line_number>:<match_line>`

## R5: 重复 Case 名称

**触发**：`assert_exit "<name>"` 中 `<name>` 在 `tests/test_*.sh` 全量中出现 ≥ 2 次。

**Evidence 格式**：`case=<name> count=<N>`

**建议修复**：

1. 重命名其中一方（如追加 `-variant` 后缀）
2. 若确为同一语义断言复用 → 提取到 `_test_helpers.sh` 的共享函数

## 扩展指南

新增规则流程：

1. 在 `detect-test-rot.sh` 的对应 section 增加检测分支
2. 本文件记录规则定义
3. 在 `test_detect_test_rot.sh` 补 3 个用例（触发 / 不触发 / 边界）
4. 若新规则是 block 级别，确认 `engineering-sync-gate.sh` 的聚合逻辑能正确处理
