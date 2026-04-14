# Archive Readiness 检查与归档操作

> 本文件由 `autopilot-phase7-archive/SKILL.md` 通过 `**执行前读取**` 引用。
> 包含 Step 3（Archive Readiness 检查）、Step 4（归档操作）、Step 5（阻断处理）。

## Step 3: Archive Readiness 检查与归档决策

**Archive Readiness 自动化**: 归档前执行统一的 archive-readiness 判定。所有判定条件通过时自动归档，无需人工确认；任一条件失败时硬阻断并展示原因。

### Step 3.1: 构建 archive-readiness.json

收集以下字段，写入 `${change_dir}context/archive-readiness.json`：

```json
{
  "timestamp": "ISO-8601",
  "mode": "full|lite|minimal",
  "checks": {
    "all_checkpoints_ok": true,
    "fixup_completeness": { "passed": true, "fixup_count": 5, "checkpoint_count": 5 },
    "anchor_valid": true,
    "worktree_clean": true,
    "review_findings_clear": true,
    "zero_skip_passed": true
  },
  "overall": "ready|blocked",
  "block_reasons": []
}
```

各检查项定义：

- `all_checkpoints_ok`: 所有已执行 phase 的 checkpoint status 为 ok 或 warning
- `fixup_completeness`: `FIXUP_COUNT >= CHECKPOINT_COUNT`（**硬阻断**，不再是 warning）
- `anchor_valid`: `git rev-parse $ANCHOR_SHA` 成功
- `worktree_clean`: `git status --porcelain` 为空（工作区残留变更已提交）
- `review_findings_clear`: 当 `block_on_critical = true` 时，无未解决 critical findings；否则总是 true
- `zero_skip_passed`: Phase 5 checkpoint 中 `zero_skip_check.passed === true`（minimal 模式豁免）

### Step 3.2: 判定逻辑

```
IF archive-readiness.overall === "ready":
  → 日志输出 [ARCHIVE] Readiness check: PASSED — auto-archiving
  → 直接进入 Step 4 归档操作（无需 AskUserQuestion）
ELSE:
  → 日志输出 [ARCHIVE] Readiness check: BLOCKED — {block_reasons}
  → AskUserQuestion 展示阻断原因，选项:
    - "修复后重新检查"
    - "放弃归档"
  → 禁止 "忽略继续归档" 选项（fail-closed 原则）
```

**block_on_critical 语义保留**: 当 `config.phases.code_review.block_on_critical = true` 时：

1. 检查 `phase-6.5-code-review.json` 中是否存在 `critical` 级别 findings
2. 如有 critical findings 未修复 → `review_findings_clear = false`，归入 `block_reasons`
3. 如无 critical findings 或 `block_on_critical = false` → `review_findings_clear = true`

**进度写入**: `Bash('AUTOPILOT_PROJECT_ROOT=$(pwd) bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/write-phase-progress.sh 7 summary_complete complete')`

## Step 4: 归档操作（archive readiness 通过后自动执行）

a. **归档前清理**：

- 更新 Phase 7 Checkpoint（完成）：调用 Skill(`spec-autopilot:autopilot-gate`) checkpoint 管理更新 `phase-7-summary.json`：

    ```json
    {"status": "ok", "phase": 7, "description": "Archive complete", "archived_change": "<change_name>", "mode": "<mode>"}
    ```

- 删除临时文件：`openspec/changes/<name>/context/phase-results/phase5-start-time.txt`（如存在）

b. **Git 自动压缩**（当 `config.context_management.squash_on_archive` 为 true，默认 true）：

- **进度写入**: `Bash('AUTOPILOT_PROJECT_ROOT=$(pwd) bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/write-phase-progress.sh 7 autosquash_started in_progress')`
- **独立脚本**: 所有 fixup 完整性检查、非 autopilot fixup 检查、anchor 验证/重建、rebase 操作已封装到 `autosquash-archive.sh`：

    ```bash
    Bash('bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/autosquash-archive.sh "$(pwd)" "${ANCHOR_SHA}" "${change_name}"')
    ```

    解析返回的 JSON（`{"status":"ok|blocked|needs_confirmation","anchor_sha":"...","squash_count":N,"non_autopilot_fixups":[...],"error":"..."}`）：
  - `status: "ok"` → 修改 commit message 为 `feat(autopilot): <change_name> — <summary>`，继续归档
  - `status: "needs_confirmation"` → 展示 `non_autopilot_fixups` 列表，AskUserQuestion 确认是否继续
    - 用户选择"继续" → **必须**使用确认标志重新调用：

        ```bash
        Bash('bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/autosquash-archive.sh "$(pwd)" "${anchor_sha_from_json}" "${change_name}" true')
        ```

    - 用户选择"取消" → 中止归档，不执行 rebase
  - `status: "blocked"` → 硬阻断归档（fail-closed），展示 `error` 信息
    - fixup 不完整时：`[BLOCKED] fixup 完整性检查失败: ${FIXUP_COUNT} fixup commits < ${CHECKPOINT_COUNT} checkpoints.`
    - anchor 重建失败时：`[BLOCKED] anchor 重建失败，无法执行 autosquash。归档中止。`
    - autosquash 失败时：`[BLOCKED] autosquash 失败，无法合并 fixup commits。归档中止。`

  > **上下文优化**: 主线程不再内联执行 ~50 行 git 操作，仅调用一次 Bash 并解析 JSON 结果。

c. **归档**（模式感知）：

- **full 模式**: 执行 Skill(`openspec-archive-change`)（完整 OpenSpec 归档）
- **lite/minimal 模式**: 跳过 OpenSpec 归档，仅完成 git squash

## Step 5: Archive Readiness 阻断时的用户选择

当 Step 3.2 判定 `overall === "blocked"` 时，用户选择"修复后重新检查"：
→ 提示用户根据 `block_reasons` 修复问题，修复后重新执行 Step 3.1 构建 archive-readiness.json

当用户选择"放弃归档"：展示手动归档命令，结束流程。
