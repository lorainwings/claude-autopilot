# 测试审计处置清单 — 基于 test-audit.md

> 来源：`docs/plans/engineering-auto-sync/test-audit.md`（基线 121 文件 / 1698 断言，DELETE=0 / UPDATE=3 / DUPLICATE=2 组 / WEAK=17（6 项合理））。
> 本文档把审计候选转为**可执行的处置动作**，并标注落地轮次。

## 处置矩阵

### A. DELETE — 0 项

无。所有测试引用脚本仍存在，元测试（如 `test_ralph_removal.sh`）属有效回归保护（`test-audit.md:13-15`）。

### B. UPDATE — 3 项

| # | 文件 | 建议改动 | 风险评估 | 建议时机 |
|---|------|----------|---------|---------|
| U1 | `tests/test_background_agent_bypass.sh:3-4` | 文件头注释声明"compatibility window"的 `anti-rationalization-check` / `code-constraint-check` 已 deprecated。建议：(1) 在 commit message/CHANGELOG 明确 v5.x 为关闭窗口的目标版本；(2) 在 case 45d 的 assert 内加 `echo "DEPRECATED: remove after <target-version>"` TODO 标记；(3) 到期后整段删除。 | **低**：当前测试仍 PASS，改为文档性注释不影响断言。关键是避免被"禁止删除测试"规则误伤——commit message 需书面说明理由。 | **下一轮**（等 5.10.x 窗口收口时一并删除） |
| U2 | `tests/test_lock_precheck.sh:3-4` | 同 U1，声明 `code-constraint-check.sh DEPRECATED since v4.0`，25 系列 case 中对该脚本的引用应随 U1 一起清理。 | 低，与 U1 同生命周期。 | 下一轮，与 U1 同批。 |
| U3 | `tests/test_auto_continue.sh:18-23` | 若 `setup-wizard.md` / `autopilot-setup/SKILL.md` 已稳定存在（当前 repo 已稳定），移除 fallback 分支 `if [ -f "$INIT_WIZARD_REF" ]; then ... else INIT_SKILL=".../autopilot-setup/SKILL.md"`，保留单一 reference 路径。 | **低-中**：若历史分支还在 CI 跑旧版，fallback 删除后会 RED。建议先加 `assert_file_exists` 明确契约，观察 1-2 个 PR 周期再删 fallback。 | **本轮主线**可先加 `assert_file_exists` 硬断言；fallback 删除放下一轮。 |

### C. DUPLICATE 合并 — 2 组

| 组 | 文件 | 动作 | 风险 | 时机 |
|----|------|------|------|------|
| D1 | `test_reference_files.sh` (Section 30) + `test_references_dir.sh` (Section 15) | 合并为单一 `test_references_dir.sh` 下的 "reference directory contract" 章节，保留所有 existence assertion，去掉路径重复扫描循环。合并后 `test_reference_files.sh` 整文件删除（commit message 说明"duplicated by test_references_dir.sh Section 15"）。 | **低**：两者都是 file-exists 类断言，合并不丢覆盖；需保证合并后的文件覆盖两个原文件引用的全部路径集合（用 `comm` 核对）。 | **本轮主线**（纯机械合并，风险可控）。 |
| D2 | `test_allure_install.sh` (Section 16) + `test_allure_enhanced.sh` (Section 20) | Section 16 的 syntax+exit-code 已被 `test_syntax.sh` 覆盖，仅 Section 16 独有的"install path resolution" case 合入 Section 20。合并后 `test_allure_install.sh` 删除。 | 低：Section 16 的弱断言部分由 `test_syntax.sh` 兜底，保留独有 case 即可。 | **下一轮**（D2 涉及 allure 执行链路，等 Allure CI job 稳定后再动）。 |

### D. WEAK_ASSERTION 补强 — 3 高优先级文件

审计明确优先补强的 3 个文件（`test-audit.md:56`），其余 14 项判定为合理或次优先。

| # | 文件 | 弱断言数 | 补强方向 | 时机 |
|---|------|---------|---------|------|
| W1 | `tests/test_auto_emit_agent.sh` | 7 | 当前仅 `exit 0` 断言。补强：(a) 对 hook 的 stdout JSON 增加 `assert_json_field '.event_type' 'agent_dispatch'`；(b) 对 `logs/events.jsonl` 追加项做 `assert_contains` 校验 payload 关键字段；(c) 对错误路径增加 `assert_exit ... 1` 的 negative case。 | **本轮主线**（high-signal，产物 JSON 已结构化，断言成本低）。 |
| W2 | `tests/test_phase_context_snapshot.sh` | 5 | 补强：(a) 校验 snapshot 文件 JSON schema（至少 `phase`, `mode`, `timestamp` 三字段）；(b) 对多次 snapshot 校验单调递增 timestamp；(c) 增加一个 negative case（phase 不合法应拒绝写入）。 | 本轮主线。 |
| W3 | `tests/test_session_hooks.sh` | 4 | 补强：(a) 校验 SessionStart hook 注入的 context 内容而非仅 exit 0；(b) 对 SessionEnd hook 校验 `.claude/state/` 下的清理产物；(c) 增加 hook 失败时的降级路径断言。 | 本轮主线。 |

其余 14 个弱断言文件：`test_guard_ask_user_phase.sh` / `test_guard_no_verify.sh` / `test_syntax.sh` 为合理（guard exit code 即业务语义 / 基线语法保护）；`test_common.sh` 为被取代候选（`test_common_unit.sh` 466 行已覆盖），进入 **P2 周期 review 队列**。

### E. smoke_release.sh 文档化

`tests/smoke_release.sh` 命名不匹配 `test_*.sh`，不被 `run_all.sh` 扫描，设计上独立运行（`test-audit.md:60-62`）。

**动作**：

- 若 `plugins/spec-autopilot/tests/README.md` 已存在 → 在其中新增 "Independent scripts" 章节，列出 `smoke_release.sh` 的触发条件（发版前人工 smoke）、预期产物、清理方式。
- 若 `tests/README.md` 不存在 → **本轮建议新增**一份最小化 README，涵盖：
  1. `run_all.sh` 覆盖的文件命名约定；
  2. `smoke_release.sh` 等独立脚本的名单与用途；
  3. 如何添加新测试文件（命名 / 断言最低要求）。

**时机**：本轮主线（文档任务，无执行风险）。

## 本轮 vs 下一轮归集

**本轮主线落地（低风险 / 高收益）**：

- U3（加 `assert_file_exists` 硬断言）
- D1（reference 目录测试合并）
- W1 / W2 / W3（三个弱断言文件补强）
- E（smoke_release.sh 文档化 / tests/README 新增）

**下一轮落地（需观察期 / 依赖外部条件）**：

- U1 + U2（等 deprecated 窗口关闭一起删除）
- U3 后半（fallback 分支删除，需观察 1-2 PR 周期）
- D2（Allure 合并，等 CI 稳定）
- 其余 14 个弱断言文件的周期性补强（排入 P2 review 队列，可由 `/autopilot-test-audit` 周期扫描输出）
