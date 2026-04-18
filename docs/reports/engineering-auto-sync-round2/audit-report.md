# Round 2 全量复审报告（2026-04-18）

## 总览

- **集成测试**：129 files, **1853 PASS / 0 FAIL**（确认）
- **新增脚本**：7 个 runtime 脚本，合计 1522 行
  - `scan-code-ref-anchors.sh` 244 · `detect-anchor-drift.sh` 118
  - `generate-doc-fix-patch.sh` 173 · `generate-test-fix-patch.sh` 162 · `apply-fix-patch.sh` 224
  - `test-mutation-sample.sh` 347 · `test-health-score.sh` 254
- **新增 skill**：`autopilot-docs-fix` / `autopilot-test-fix` / `autopilot-test-health`（各含 SKILL.md + references/）
- **新增测试**：7 个 `test_*_anchor_*` / `test_*_fix_*` / `test_mutation_*` / `test_health_*`；修改 8 个既有测试
- **删除测试**：`test_references_dir.sh` / `test_allure_install.sh`（合并至 `test_reference_files.sh` / `test_allure_enhanced.sh`）
- **净 diff**：24 files changed, 239 insertions(+), 136 deletions(-) + 39 新 untracked
- **构建**：`bash tools/build-dist.sh` 成功（2.4M, 85 个 script 清单）
- **总结论**：**有警告**（无阻断性问题；但存在若干须在主线修复的健壮性 / 文档补齐项）

---

## 各维度发现

### 1. 集成一致性

#### Finding 1.1 · info · engineering-sync-gate 已集成 anchor drift
- **证据**：`plugins/spec-autopilot/runtime/scripts/engineering-sync-gate.sh:62` 调用 `detect-anchor-drift.sh`；空 staging 实测 `TOTAL_CANDIDATES=14 ENGINEERING_SYNC_RESULT=ok`
- **结论**：集成已就位（无需另行接入）

#### Finding 1.2 · warn · scan-code-ref-anchors 在真实仓库识别 15 条锚点，其中多条明显误识别
- **证据**：`bash scan-code-ref-anchors.sh` 输出 15 个 anchor entries，其中：
  - `plugins/spec-autopilot/CLAUDE.md` 第 77 行 docs 解析为 `` ` ``（单个反引号）
  - `plugins/spec-autopilot/tests/test_scan_anchors.sh:49` docs 解析为 `` docs/...) ``（fixture 正则演示文本被吞）
  - `docs/plans/engineering-auto-sync/01-design.md:12` docs 为 `path#symbol`（文档中的示例占位符被当真）
  - `skills/autopilot-docs-sync/references/anchor-syntax.md` 自身作为 CODE-OWNED-BY 目标出现（示例块被作为真实锚点）
- **影响**：`detect-anchor-drift.sh` 输出 14 条 `R6/R7 warn`，其中 11 条为自身演示 / fixture 噪声，真实漂移 <3 条
- **修复建议**：
  1. scanner 增加**排除清单**（fixture、reference/anchor-syntax.md、test_scan_anchors.sh、test_detect_anchor_drift.sh）
  2. 对 docs 路径做格式校验（正则：`^[A-Za-z0-9_./\-]+(\.[a-z]+)?$`），过滤 `` ` `` 与 `path#symbol` 占位符
  3. 或在 `.drift-ignore` 中为这些示例文件预置抑制规则

#### Finding 1.3 · info · mutation 引擎在干净 repo 工作正常
- **证据**：在 `/tmp/mut-test2` 构造 `scripts/good_target.sh` + `tests/test_good_target.sh`，`--sample-size 1 --targets 'scripts/*.sh'` 得 `MUTATION_KILL_RATE=1.00 SURVIVORS=0`
- **结论**：引擎自身工作正常

#### Finding 1.4 · warn · 用户提示的 fixture glob 无法直接用于 mutation
- **证据**：原任务提示 `--targets 'plugins/spec-autopilot/tests/fixtures/mutation/runtime_*'` 匹配的是目录（非 `.sh` 文件），scanner 需 `runtime_*/scripts/*.sh`
- **影响**：fixture 目录结构（`runtime_good/scripts/` + `runtime_good/tests/`）更适合 `test_mutation_sample.sh` 而非手动命令行调用
- **修复建议**：`autopilot-test-health` SKILL.md 示例命令需明确 glob 必须穿透到 `.sh`

### 2. 参数契约一致性（Round 1 BLOCKER 复现检查）

#### Finding 2.1 · info · 新 skill SKILL.md 参数全部匹配脚本
逐条实测：

| Skill | 脚本调用参数 | 脚本真实参数 | 结果 |
|-------|----------|----------|------|
| `autopilot-docs-fix` | `--candidates-file / --output-dir / --index / --patch-id / --all / --dry-run / --force-manual` | 完全匹配 | ✅ |
| `autopilot-test-fix` | `--changed-files / --deleted-files / --candidates-file / --output-dir / --index / --patch-id` | 完全匹配 | ✅ |
| `autopilot-test-health` | `--targets / --sample-size / --timeout-per-mutant / --tests-dir / --threshold` | 完全匹配 | ✅ |

**结论**：Round 1 的 5 处参数错配 BLOCKER **未复发**。

### 3. 删除文件 fallout

#### Finding 3.1 · info · 两个删除测试文件无残留引用
- **证据**：`grep -rn 'test_references_dir\|test_allure_install'` 仅命中：
  - `test_reference_files.sh:16`（注释"原 test_references_dir.sh §15"）
  - `test_allure_enhanced.sh:5,64`（注释说明合并来源）
  - `docs/reports/v5.0.10/infrastructure-audit-v5.3.md`（历史报告）
- `run_all.sh` 无硬编码引用，实测 1853 PASS
- **结论**：删除安全

### 4. 工程同步集成

#### Finding 4.1 · info · engineering-sync-gate 已完整接入 R6/R7/R8
- **证据**：`engineering-sync-gate.sh:62-89` 显式调用 `detect-anchor-drift.sh`、读取 `.anchor-drift-candidates.json`、合并进 `.engineering-sync-report.json`
- **结论**：无需额外集成工作

### 5. Lint 与 Build

#### Finding 5.1 · info · 本轮新增 7 个脚本全部 shellcheck + shfmt 干净
- **证据**：`shellcheck` 全部无输出；`shfmt -i 2 -ci -d` 全部 diff 为空

#### Finding 5.2 · info · build-dist.sh 构建成功
- **证据**：`✅ dist/spec-autopilot built: 2.4M`，manifest 85 file 全部 copy

#### Finding 5.3 · info · 既有 shfmt 违规 110 个，非本轮引入
- **证据**：`shfmt -l plugins/spec-autopilot/runtime/scripts/*.sh plugins/spec-autopilot/tests/*.sh | wc -l` 得 110
- 本轮修改 `test_session_hooks.sh` 显示 shfmt diff，但 `git stash` 到 HEAD 版本后仍有 diff → 预先存在违规
- **结论**：本轮不需修复，可作为后续独立清理任务

### 6. 安全

#### Finding 6.1 · info · apply-fix-patch.sh stash 保护验证通过
- **证据**：在 `/tmp/apply-test` 构造 bad patch，`apply-fix-patch.sh` 在 `git apply --check` 阶段失败后退出（EXIT=1），原始 `foo.txt` 未变、未提交的 `uncommitted.txt` 保留完整
- **细节亮点**：第 128-133 行的 SNAPSHOT_DIR 机制预先快照 patch 目录到 `mktemp -d`，避免 `stash push -u` 吞掉未追踪的 patch 文件本身——这是一个**非平凡**的正确性设计

#### Finding 6.2 · info · test-mutation-sample 在脏 tree 正确拒绝
- **证据**：主仓库脏 tree 下直接调用得 `ERROR: git working tree must be clean before mutation run`，EXIT=2
- （之前观察到 EXIT=0 系因 `| tail` 丢失了脚本 exit code，直接调用确认为 2）

#### Finding 6.3 · warn · generate-doc-fix-patch.sh 对非标准 JSON 输入崩溃
- **证据**：候选文件内容为 `[]`（空数组）时：
  ```
  AttributeError: 'list' object has no attribute 'get'
  ```
- **影响**：仅对手工构造的非法输入崩溃。`detect-doc-drift.sh` / `detect-anchor-drift.sh` 实际输出始终为 `{"checks":[...]}`，正常路径不受影响
- **修复建议**：`generate-doc-fix-patch.sh:67` + `generate-test-fix-patch.sh` 同行加一行防御：
  ```python
  if not isinstance(data, dict):
      print("ERROR: candidates JSON must be an object with 'checks' key", file=sys.stderr)
      sys.exit(1)
  checks = data.get("checks", []) or []
  ```

### 7. 配置文件就位

#### Finding 7.1 · warn · `.claude/docs-ownership.yaml` 未激活
- **证据**：`.claude/` 下已有 `docs-ownership.yaml.example`（与 `plugins/.../references/docs-ownership.yaml.example` 一字不差），但**没有 active 的 `.claude/docs-ownership.yaml`**
- **影响**：ownership fallback 未启用（detect-anchor-drift 仅能依赖 inline 锚点，fixture 噪声更显眼）
- **修复建议**：主线在合入前执行：
  ```bash
  cp .claude/docs-ownership.yaml.example .claude/docs-ownership.yaml
  ```
  或确认"模板先行、用户按需启用"是预期行为并在 plugin CLAUDE.md 补充说明

### 8. 文档更新

#### Finding 8.1 · warn · plugin README skills 表未登记新 skill
- **证据**：`plugins/spec-autopilot/README.md:266-277` skills 表仅含 7 条旧 skill，缺 `autopilot-docs-fix` / `autopilot-test-fix` / `autopilot-test-health`；同时早先引入的 `autopilot-docs-sync` / `autopilot-test-audit` / `autopilot-learn` 也未登记
- **修复建议**：补充 3 行（或统一补齐 6 行）

#### Finding 8.2 · info · plugin CLAUDE.md 已补充相应章节
- **证据**：`plugins/spec-autopilot/CLAUDE.md` 包含"工程自动化纪律（engineering-sync-gate）§候选-修复闭环（Round 2 新增）"和"测试健康度纪律（Round 2 新增）"两个完整章节
- **结论**：约束落地，无需补充

#### Finding 8.3 · info · 根 README 未列入新 skill
- **证据**：`README.md` / `README.zh.md` 查无新 skill 名
- 根 README 版本表由 release-please 维护，skill 级别条目原本就不在插件表中——**非本轮责任**

---

## 阻断性问题

**无**（EXIT=2 / stash 回滚 / 参数契约 全部验证通过）。

---

## 建议主线 commit 前完成的合并动作清单

依严重度排序：

### 必修（warn→须在合入前解决）
1. **scan-code-ref-anchors 加排除规则**（Finding 1.2）：否则真实仓库会常态出现 14 条 false positive drift，稀释真实信号
   - 建议：在 scanner 中预置排除 `anchor-syntax.md` 自身、`test_scan_anchors.sh` / `test_detect_anchor_drift.sh` fixture、docs 路径格式校验
2. **generate-doc-fix-patch / generate-test-fix-patch 防御非 dict 输入**（Finding 6.3）：一行 `isinstance` 判断即可
3. **README skills 表补登新 skill**（Finding 8.1）：docs-fix / test-fix / test-health

### 建议
4. **激活 `.claude/docs-ownership.yaml`**（Finding 7.1）：`cp` 模板或文档化"按需启用"流程
5. **SKILL.md 示例 glob 明确穿透到 `.sh`**（Finding 1.4）：避免用户 copy-paste 到目录 glob

### 可选清理
6. 本轮不修 110 处预先存在 shfmt 违规，作为独立任务排期（Finding 5.3）

---

## Round 1 vs Round 2 对比

| 维度 | Round 1 | Round 2 |
|------|---------|---------|
| 参数契约错配 BLOCKER | 5 处（SKILL.md 参数与脚本实现不一致） | **0 处** ✅ 未复发 |
| shellcheck 清洁度 | 多项违规 | 7 个新脚本全部 0 违规 ✅ |
| shfmt 清洁度 | 多项违规 | 7 个新脚本全部 0 违规 ✅ |
| 集成测试 | 断言基线未明确 | 1853 PASS / 0 FAIL / 129 files ✅ |
| 安全设计 | 缺保护 | stash + SNAPSHOT_DIR 双层保护 + 脏 tree 拒绝 ✅ |
| 健壮性缺口 | — | Finding 6.3（非 dict 输入崩溃，低风险） |
| 文档完整性 | — | README skills 表与 `.claude/` 配置有遗漏 |
| 噪声信号 | — | Finding 1.2（锚点误识别 11/14） |

### 各 Agent 产出质量评分

- **ANCHOR Agent**：功能正确但缺排除机制，锚点信号噪比偏低；集成到 sync-gate 完成度好
- **FIX Agent**：参数契约一致（relative Round 1 显著改善）；stash 保护设计完整；健壮性对非标输入存在一行可修补的缺口
- **AUDIT-FIX Agent**：删除合并安全，测试未减少基线；1853 PASS 确认
- **MUTATION Agent**：安全约束到位（cksum 确定性采样 + 脏 tree 拒绝 + 双重 diff 校验），产出引擎工作正常

**整体**：Round 2 是 Round 1 的显著改进；**无阻断**，但 Findings 1.2 / 6.3 / 7.1 / 8.1 建议合入前修复。
