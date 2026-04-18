# 测试用例全量审计报告（2026-04-18）

<!-- CODE-OWNED-BY: plugins/spec-autopilot/runtime/scripts/detect-test-rot.sh -->

> 来源：Agent A 全量静态审计，基于 `bash tests/run_all.sh` 基线 1698 pass / 121 files。审计时间 2026-04-18。

## 总览

- **扫描范围**：123 files（121 top-level + 2 integration）/ ~1698 assertions
- **建议处理**：DELETE=0 / UPDATE=3 / DUPLICATE=2 组 / REVIEW_NEEDED=4 / WEAK_ASSERTION=17（其中 6 项判定为合理）
- **工具**：grep / bash / ls / head / wc

**总体结论**：测试套件健康度良好，无需立即删除任何文件。近期大改动（散弹 Agent 名清理、Sprint 升级）未引入过期测试。主要优化方向为**补强若干弱断言**和**合并两组重复用例**。

## 建议 DELETE（明确过期）

**无。** 所有测试引用的脚本均仍存在于 `runtime/scripts/`。元测试（如 `test_ralph_removal.sh` 验证旧产物已删除）属于有效回归保护。

## 建议 UPDATE（断言过时或需补强）

| 文件 | 行号 | Case 名 | 建议改动 | 证据 |
|------|------|---------|----------|------|
| `tests/test_background_agent_bypass.sh` | :3-4 | 45d. code-constraint-check bypass | 注释声明 "compatibility window"——需确认何时关闭该兼容窗口，届时整个 45d case 应删除 | 文件头注释 `NOTE: Some cases test deprecated scripts (anti-rationalization-check, code-constraint-check) retained during the compatibility window.` |
| `tests/test_lock_precheck.sh` | :3-4 | 25 系列部分 case | 同上，声明 `code-constraint-check.sh DEPRECATED since v4.0` | 文件头注释 |
| `tests/test_auto_continue.sh` | :18-23 | 预设模板位置 fallback | 若 `setup-wizard.md` 已稳定存在，fallback 分支可移除 | `if [ -f "$INIT_WIZARD_REF" ]; then ... else INIT_SKILL=".../autopilot-setup/SKILL.md"` |

## 建议合并/去重（DUPLICATE）

| 组 | 文件 | 重叠描述 |
|----|------|----------|
| 1 | `test_reference_files.sh` (Section 30) + `test_references_dir.sh` (Section 15) | 两者都验证 `skills/autopilot/references/` 下文件存在性。可合并为单一 "reference directory contract" 测试 |
| 2 | `test_allure_install.sh` (Section 16) + `test_allure_enhanced.sh` (Section 20) | 16 仅做 syntax + exit code（已被 `test_syntax.sh` 覆盖）；可将 16 的独有 case 合入 20 |

## 恒真/弱断言（需要补强）

17 个文件仅含 exit-code/file-exists/syntax-check 断言，无内容级验证：

| 文件 | 弱断言数 | 判定 |
|------|----------|------|
| `test_syntax.sh` | 动态 | **合理**：基线语法保护 |
| `test_common.sh` | 2 | 被 `test_common_unit.sh`(466行) 取代候选 |
| `test_hook_preamble.sh` | 2 | 仅 syntax/source 检查 |
| `test_emit_task_progress.sh` | 1 | 仅 exit 0 |
| `test_runtime_manifest.sh` | 1 | 仅 exit 0 |
| `test_allure_install.sh` | 2 | 与 test_allure_enhanced.sh 重叠 |
| `test_auto_emit_agent.sh` | 7 | **需补强**：无输出验证 |
| `test_gui_server_health.sh` | 2 | 仅 exit 0 |
| `test_has_active_autopilot.sh` | 3 | 仅 exit code |
| `test_phase_context_snapshot.sh` | 5 | **需补强**：产物无内容验证 |
| `test_phase_progress.sh` | 3 | 仅 exit code |
| `test_session_hooks.sh` | 4 | **需补强** |
| `test_scan_checkpoints.sh` | 1 | 仅 exit code |
| `test_agent_correlation.sh` | 1 | 注：实际有 inline grep |
| `test_allure_enhanced.sh` | 1 | 注：有 inline python JSON 校验 |
| `test_guard_ask_user_phase.sh` | 9 | **合理**：guard 脚本 exit code 即业务语义 |
| `test_guard_no_verify.sh` | 20 | **合理**：同上 |

**优先补强（high-signal）**：`test_auto_emit_agent.sh`、`test_phase_context_snapshot.sh`、`test_session_hooks.sh`。

## 未被 run_all.sh 扫描的文件

| 文件 | 原因 |
|------|------|
| `tests/smoke_release.sh` | 命名不匹配 `test_*.sh`，设计上独立运行。**非 bug，但需在 README 文档化** |

## 审计自动化候选（下一阶段框架可借鉴）

- **静态规则**
  - `grep -rn 'DEPRECATED\|compatibility window' tests/` → 兼容窗口到期提醒
  - `grep -l 'detect-ralph-loop'` tests/ → 已删除产物引用报警
  - 对比 `$SCRIPT_DIR/*.sh` 引用 vs `runtime/scripts/` 实际文件 → stale 引用告警
- **执行规则**
  - 弱断言文件列表（上表 17 项）纳入周期 review，逐步补强 `assert_contains` / `assert_json_field`
  - `test_common.sh` 标记为被 `test_common_unit.sh` 取代候选

## 返回信封

```json
{
  "status": "ok",
  "summary": "建议 DELETE=0 / UPDATE=3 / DUPLICATE=2组 / REVIEW=4 / WEAK_ASSERTION=17（其中6项合理）",
  "stats": {"files": 123, "assertions": 1698, "delete": 0, "update": 3, "duplicate": 2, "review": 4, "weak_assertion": 17}
}
```
