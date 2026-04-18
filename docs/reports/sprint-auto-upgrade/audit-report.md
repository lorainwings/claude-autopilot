# Sprint 升级全量审查报告（2026-04-18）

## 总览

- **改动文件**: 已跟踪修改 12 个 + 新增 untracked 42 个 ≈ 54 个变更入口
- **代码行数**: 已跟踪修改 +323/-14；untracked（新 skill / 脚本 / 测试 / rubric / docs）规模再叠加约数千行
- **主要新增**:
  - 3 个新 skill：`autopilot-risk-scanner` / `autopilot-phase5.5-redteam` / `autopilot-learn`
  - 7 个新 runtime 脚本：`risk-scan-gate.sh` / `feedback-loop-inject.sh` / `validate-agent-registry.sh` / `learn-episode-write.sh` / `learn-episode-schema-validate.sh` / `learn-inject-top-lessons.sh` / `learn-promote-candidate.sh`
  - 6 个 rubric YAML（phase1/3/5/6 ×（feat/bugfix））
  - 6 个新测试文件：`test_agent_dispatch_resolution` / `test_learn_episode` / `test_learn_injection` / `test_learn_promotion` / `test_phase55_redteam` / `test_risk_scanner`
  - 修订 8 个 SKILL.md + plugin CLAUDE.md（第 10 条红线）
- **总结论**: **BLOCKED** — 测试与脚本本身合规且通过，但 4 个 SKILL.md 中描述的脚本调用与脚本实际接受的参数不一致，将导致主线流程注入的"主动学习"链路在运行时被 silent fail（exit 2 + `|| true` 兜底吞错），**关键功能名义上加入但实际无法落地**

## 审查发现

### 合规性

- **info** | shellcheck/shfmt 全绿 | 14 个新脚本 0 警告 0 diff
- **info** | YAML 解析全部成功 | 6 个 rubric YAML 经 `yaml.safe_load` 通过
- **info** | 新 skill frontmatter 三件齐备（name/description/user-invocable=false）且 description 均以 `[ONLY for autopilot orchestrator]` 前缀
- **info** | `.dist-include` 已登记 7 个新脚本（learn-* / risk-scan-gate / feedback-loop-inject / validate-agent-registry）
- **info** | `dist/spec-autopilot/` 已包含全部新 skill 目录、rubric YAML 与新脚本，build 后 size 2.3M

### 测试纪律（CLAUDE.md 铁律）

- **info** | 6 个新测试文件均 ≥3 case，含正常/边界/错误路径（risk-scanner: 18 / phase55-redteam: 21 / learn-episode: 12 / learn-injection: 9 / learn-promotion: 7 / agent-dispatch: 19）
- **info** | 单独运行均 100% pass；全套件 1691 pass / 7 fail（fail 集中在 `test_autopilot_server_aggregation`，单独跑 11/11 pass，属并行端口/临时目录污染，**与 Sprint 改动无因果**）
- **info** | 新测试无恒真断言、无被跳过 case，命名规范（如 "1a. ok phase exits 0"）
- **warn** | 新测试**未覆盖** SKILL.md 文档中描述的实际调用方式（仅测试脚本本身的合法参数集，不验证 SKILL.md ↔ 脚本契约一致性），导致 BLOCK#2/#3/#4 未被测试网捕获 | 建议增加 docs_consistency layer 的契约测试，对每个引用 runtime/scripts/*.sh 的 SKILL.md 命令做参数语法白盒解析

### BUG 修复（dispatch 字面量解析）

- **info** | A1-A5 主修复路径完整：`validate-agent-registry.sh` 覆盖空输入 / `{{...}}` / `config.phases.*` / `config.*` / 未注册 / 内置白名单 (general-purpose, Explore, Plan)；19 个测试 case 全 pass
- **info** | PreToolUse hook `auto-emit-agent-dispatch.sh` 正确实现 Phase ≥ 2 禁 Explore（line 136-139）+ prompt 残留占位符兜断（line 144-147），且通过 stdout JSON `{"decision":"block",...}` 而非 exit code（与 hook 协议吻合）
- **info** | 注释口径"PostToolUse"误用，实际钩子为 PreToolUse（hook 头注释 line 3 + hooks.json line 25 的 matcher `^Task$` 在 PreToolUse 块中）。设计正确，文档措辞偏差
- **warn** | `references/parallel-phase5.md` / `parallel-phase6.md` / `parallel-dispatch.md` / `phase1-requirements.md` / `phase6-code-review.md` / `phase5-implementation.md` 等多处仍含 `subagent_type: config.phases.X.Y` 字面量（属"模板伪代码"语义），但未在文件顶部明确标注"以下为占位符待替换"，存在被 LLM 误解为字面量调用的可能 | 建议在所有含此类模式的 references/* 顶部加 `> 注：本文件为模板，subagent_type 为 config 路径占位符，主线必须替换为已注册 agent 名` 的导言

### 架构一致性

- **info** | `autopilot/SKILL.md` line 70-72 已登记 3 个新 skill；line 96 在 phase 流程图中加入 5.5；与 phase5/phase6 描述未冲突
- **info** | `autopilot-gate/SKILL.md` 加入 Step 0（标号从 0 起，原 8 个 step 不动），与 8-step checklist 完全兼容
- **info** | `autopilot-phase7-archive/SKILL.md` Step 0.5 学习钩子在归档前注入合理（episode 数据需在 commit/squash 前固化）
- **warn** | `autopilot-phase0-init/SKILL.md` Step 4.6 在 Step 5/6 (recovery) **之前**执行 — 若 recovery_phase > 0，`.autopilot-lessons.json` 会被覆写一次。考虑到该文件来源为基于"raw_requirement 相似度"的幂等查询，覆写后内容不变，**未造成污染**，但仍属"非必要重复 IO" | 建议在 Step 4.6 前加 `[ -f "$LOCK_FILE" ] && grep -q '"recovery_phase"' "$LOCK_FILE" && skip` 短路

### BUG 修复 / 主动学习 — 严重契约不一致（核心 BLOCKER）

> 以下 4 项为 **block** 级缺陷，集中表现：SKILL.md 文档示例命令中传入的参数名**不被脚本接受**，脚本会 `exit 2 + "unknown argument"`。所有调用点均挂 `|| true` / `|| echo "[]"` 兜底，因此**不会阻断主流程**，但功能彻底静默失败。

- **block** | `autopilot-phase0-init/SKILL.md:127` 调用 `learn-inject-top-lessons.sh --episodes-dir ...` | **证据**: 脚本 line 27 仅接受 `--episodes-root`；实测 `bash learn-inject-top-lessons.sh --raw-requirement test --episodes-dir /tmp` → `unknown argument: --episodes-dir EXIT=2` | **修复**: 将 `--episodes-dir` 改为 `--episodes-root`，或在脚本中追加 `--episodes-dir` 别名

- **block** | `autopilot-phase7-archive/SKILL.md:39-42` 调用 `learn-episode-write.sh --phase ... --checkpoint ... --version ... --status ok --mode {mode}` | **证据**: 脚本 line 28-54 仅接受 `--phase --checkpoint --version --out-dir --run-id`；实测 `--status ok` 即 `unknown argument: --status EXIT=2` | **修复**: 删除 `--status ... --mode ...` 两段（脚本会从 checkpoint JSON 自动提取 status/mode），或扩展脚本参数

- **block** | `autopilot-phase7-archive/SKILL.md:48-50` 调用 `learn-promote-candidate.sh --episodes-dir ... --output-dir ...` | **证据**: 脚本 line 22-39 仅接受 `--episodes-root --out-dir --threshold`；实测 → `unknown argument: --episodes-dir EXIT=2` | **修复**: `--episodes-dir → --episodes-root`、`--output-dir → --out-dir`

- **block** | `autopilot-learn/SKILL.md:64-65` Step 3 调用 `learn-promote-candidate.sh --version "$version"` | **证据**: 脚本不接受 `--version`；实测 → `unknown argument: --version EXIT=2` | **修复**: 删除 `--version` 参数（脚本默认扫描 `docs/reports/*/episodes/*.json`）

- **block** | `autopilot-gate/SKILL.md:73` 阻断时调用 `learn-episode-write.sh ... --status blocked` | **证据**: 同上，`--status` 未支持 → exit 2 | **修复**: 删除 `--status` 段，由脚本从 checkpoint 自动判定

### 风险扫描器自身

- **warn** | `risk-scan-gate.sh` 缺失 risk-report.json 时 exit 2（脚本注释 "fail-closed"），但 `autopilot-gate/SKILL.md` Step 0 旁注说"按 mode 视为 warning（不阻断）" — 文档与实现矛盾 | 后果：现有不调用 risk-scanner 的运行将被硬阻断在 gate Step 0。建议二选一统一 — 推荐脚本支持 `--allow-missing` 软模式标志或 SKILL.md 明确"必须先派发 risk-scanner Critic Agent"

### 构建与发版纪律

- **info** | `bash plugins/spec-autopilot/tools/build-dist.sh` exit 0；新 3 skill + 7 脚本 + 6 rubric YAML 全部进入 `dist/spec-autopilot/`
- **info** | `docs/regression-vault` 与 `docs/learned` 未进入 dist — 因 `build-dist.sh` line 186 显式将 `docs` 列入"forbidden"白名单。这两个目录定位为"运行时积累产物"，不打包符合既定设计，但需文档化（README 已有）
- **info** | `plugin.json` / `marketplace.json` 版本号未被人为修改，符合"散弹禁止"
- **info** | marketplace.json 不需新增 skill 登记（skill 由 plugin 目录自动扫描，符合既定架构）

### 安全与隐私

- **info** | 14 个新脚本无 `eval $USER_INPUT` / `bash -c "$X"` 等高危模式；用户输入均经引用变量传递
- **info** | episode JSON 仅记录 phase/goal/actions/gate_result/failure_trace 等结构化字段；不持久化用户原始 prompt 或 secrets
- **info** | `learn-*` MCP 调用在 SKILL.md 中明确标注 dry-run 占位（`autopilot-learn/SKILL.md:50` "MCP 不可用时输出规范化 JSON 产物"），未误用真实外部服务

### 向后兼容

- **info** | `learn-episode-write.sh` / `learn-promote-candidate.sh` / `learn-inject-top-lessons.sh` 在 episodes 目录不存在时均返回 `[]` / exit 0 / 空候选，**不阻断主流程**
- **info** | `feedback-loop-inject.sh` 报告不存在 → stdout `[]` exit 0，dispatch SKILL.md 已用 `|| echo "[]"` 兜底
- **warn** | `risk-scan-gate.sh` 报告缺失 → exit 2，gate SKILL.md 未用 `|| true` 包装。若 Sprint 升级在生产环境部署但用户尚未启用 risk-scanner，则 Phase N 的 gate Step 0 会被硬阻断 | 建议参考向后兼容铁律加 `|| true` 或 `--allow-missing`
- **info** | `validate-agent-registry.sh` 内置白名单 `general-purpose / Explore / Plan` 覆盖现有所有合法用法

## 阻断性问题（severity=block）清单

1. **B1** `autopilot-phase0-init/SKILL.md:127` `--episodes-dir` ≠ `--episodes-root`
2. **B2** `autopilot-phase7-archive/SKILL.md:39-42` `learn-episode-write.sh --status ok --mode {mode}` 未知参数
3. **B3** `autopilot-phase7-archive/SKILL.md:48-50` `--episodes-dir/--output-dir` ≠ `--episodes-root/--out-dir`
4. **B4** `autopilot-learn/SKILL.md:64-65` `learn-promote-candidate.sh --version` 未知参数
5. **B5** `autopilot-gate/SKILL.md:73` `learn-episode-write.sh --status blocked` 未知参数

> 主线**必须**在合并前修复：要么调整 SKILL.md 调用为脚本实际支持的参数集，要么扩展脚本参数表（推荐前者，工作量更小）。否则"主动学习"功能虽 build 进 dist，但运行时全部 silent fail，仅留下 `episodes/` 目录始终为空的尴尬结果。

## 测试统计

- **新测试用例总数**: 86 个 case 跨 6 个文件
- **单独运行**: 86 / 86 PASS
- **全套件运行**: 1691 PASS / 7 FAIL（FAIL 全部集中在 `test_autopilot_server_aggregation`，单独跑 11/11，属端口/tmp 并发冲突，与 Sprint 改动**无因果关系**）
- **shellcheck**: 14/14 clean
- **shfmt -i 2 -ci**: 14/14 无 diff
- **YAML 校验**: 6/6 yaml.safe_load OK

## 构建验证

- 命令: `bash plugins/spec-autopilot/tools/build-dist.sh`
- 退出码: 0
- 输出关键行:
  - `📋 Manifest-driven copy: 75 files → dist/runtime/scripts/`
  - `📋 Server modules: 19 files → dist/runtime/server/src/`
  - `✅ dist/spec-autopilot built: 2.3M (source: 330M)`
- diff 摘要: `dist/spec-autopilot/skills/{autopilot-learn,autopilot-phase5.5-redteam,autopilot-risk-scanner}/` 三目录新增；`dist/spec-autopilot/skills/autopilot/references/rubrics/*.yaml` 6 个 YAML 新增；`dist/spec-autopilot/runtime/scripts/{risk-scan-gate,feedback-loop-inject,validate-agent-registry,learn-*}` 7 个脚本新增。`docs/regression-vault` 与 `docs/learned` 按设计不进入 dist
