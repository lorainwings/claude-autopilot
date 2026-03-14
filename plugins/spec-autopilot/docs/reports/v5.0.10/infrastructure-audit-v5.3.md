# 底层测试基建与构建产物审查报告 (v5.3)

> 审查日期: 2026-03-14
> 审查员: Agent 1 (底层测试基建与构建产物审查员)

## 执行摘要

本次审查覆盖了 spec-autopilot 插件的全部测试套件、构建产物纯净度以及 CLAUDE.md 防线配置。总体结论：**基建状态优秀**。

- 测试套件：49 个模块，357 个断言，**全部通过 (100%)**
- 构建产物：dist/spec-autopilot/ 产物纯净，隔离验证通过
- gui-dist/：仅含编译产物，无源码泄露
- CLAUDE.md 防线：7 大类防线全部配置，dev-only 段落裁剪正确

---

## 1. 测试套件执行结果

执行命令：`bash tests/run_all.sh`
执行结果：**49 files, 357 passed, 0 failed**

### 模块级明细

| # | 测试模块 | 通过数 | 失败数 | 状态 |
|---|---------|--------|--------|------|
| 1 | test_syntax.sh (Syntax checks) | 29 | 0 | PASS |
| 2 | test_predecessor_checkpoint.sh | 7 | 0 | PASS |
| 3 | test_json_envelope.sh | 23 | 0 | PASS |
| 4 | test_scan_checkpoints.sh | 1 | 0 | PASS |
| 6 | test_hooks_json.sh | 4 | 0 | PASS |
| 7 | test_fail_closed.sh (deny fail-closed) | 4 | 0 | PASS |
| 8 | test_marker_bypass.sh | 4 | 0 | PASS |
| 9 | test_session_hooks.sh (SessionStart/PreCompact) | 7 | 0 | PASS |
| 10 | SessionStart async config | 1 | 0 | PASS |
| 12 | test_common.sh | 2 | 0 | PASS |
| 13 | test_lock_file_parsing.sh | 3 | 0 | PASS |
| 14 | test_phase1_compat.sh | 4 | 0 | PASS |
| 15 | test_references_dir.sh | 2 | 0 | PASS |
| 16 | test_allure_install.sh | 5 | 0 | PASS |
| 17 | test_phase6_allure.sh | 6 | 0 | PASS |
| 18 | test_save_state_phase7.sh | 2 | 0 | PASS |
| 19 | test_common_unit.sh | 14 | 0 | PASS |
| 20 | test_allure_enhanced.sh | 7 | 0 | PASS |
| 21 | test_validate_config.sh | 4 | 0 | PASS |
| 22 | test_anti_rationalization.sh | 9 | 0 | PASS |
| 23 | test_wall_clock_timeout.sh | 6 | 0 | PASS |
| 24 | test_pyramid_threshold.sh | 10 | 0 | PASS |
| 25 | test_lock_precheck.sh | 10 | 0 | PASS |
| 26 | test_has_active_autopilot.sh | 3 | 0 | PASS |
| 27 | test_two_pass_json.sh | 8 | 0 | PASS |
| 28 | test_phase6_suite_results.sh | 4 | 0 | PASS |
| 29 | test_optional_fields.sh | 8 | 0 | PASS |
| 30 | test_reference_files.sh | 5 | 0 | PASS |
| 31 | test_validate_config_v11.sh | 2 | 0 | PASS |
| 32 | test_phase4_missing_fields.sh | 7 | 0 | PASS |
| 33 | test_phase65_bypass.sh | 4 | 0 | PASS |
| 34 | test_phase7_predecessor.sh | 4 | 0 | PASS |
| 35 | test_phase6_independent.sh | 2 | 0 | PASS |
| 36 | test_quality_scan_bypass.sh | 3 | 0 | PASS |
| 37 | test_minimal_mode.sh | 4 | 0 | PASS |
| 38 | test_lite_mode.sh | 4 | 0 | PASS |
| 39 | test_parallel_merge.sh | 11 | 0 | PASS |
| 40 | test_change_coverage.sh | 13 | 0 | PASS |
| 41 | test_ralph_removal.sh | 11 | 0 | PASS |
| 42 | test_serial_task_config.sh | 7 | 0 | PASS |
| 43 | test_phase5_serial.sh | 6 | 0 | PASS |
| 44 | test_template_mapping.sh | 5 | 0 | PASS |
| 45 | test_background_agent_bypass.sh | 13 | 0 | PASS |
| 46 | test_summary_downgrade.sh | 10 | 0 | PASS |
| 47 | test_mode_lock.sh | 12 | 0 | PASS |
| 48 | test_output_file_fields.sh | 4 | 0 | PASS |
| 49 | test_phase7_archive.sh | 9 | 0 | PASS |
| 50 | test_skill_lockfile_path.sh | 5 | 0 | PASS |
| 51 | test_fixup_commit.sh | 5 | 0 | PASS |
| 52 | test_search_policy.sh | 25 | 0 | PASS |

**总计: 49 模块, 357 断言, 0 失败**

### 测试覆盖维度分析

测试套件覆盖了以下关键领域:

- **语法检查**: 29 个 shell/python 脚本语法验证
- **Hook 核心逻辑**: JSON 信封验证、前驱 checkpoint 检查、反合理化检测
- **模式兼容性**: full/lite/minimal 三种模式的 Phase 路由
- **安全防线**: fail-closed 行为、marker bypass、lock file pre-check
- **数据完整性**: Phase 4/5/6/7 各阶段 checkpoint 字段验证
- **回归保护**: ralph-loop 移除、summary 降级、fixup commit、lockfile 路径
- **搜索策略**: v3.3.7 规则引擎 25 个 case 全覆盖

---

## 2. 构建产物审查

### 2.1 构建执行

```
$ bash scripts/build-dist.sh
✅ dist/spec-autopilot built: 1.3M (source: 297M)
```

构建成功，压缩比约 99.6%（297M -> 1.3M）。

### 2.2 dist/spec-autopilot/ 产物纯净度

| 检查项 | 结果 | 说明 |
|--------|------|------|
| gui/ 源码目录 | 不存在 | 正确剔除 |
| tests/ 目录 | 不存在 | 正确剔除 |
| docs/ 目录 | 不存在 | 正确剔除 |
| CHANGELOG.md | 不存在 | 正确剔除 |
| README.md | 不存在 | 正确剔除 |
| scripts/bump-version.sh | 不存在 | 开发脚本正确排除 |
| scripts/build-dist.sh | 不存在 | 构建脚本正确排除 |
| hooks.json 引用完整性 | 7/7 脚本均存在 | 无悬空引用 |
| CLAUDE.md dev-only 段落 | 0 处 DEV-ONLY 标记 | 裁剪正确 |

**dist 内容清单（82 文件）:**
- `.claude-plugin/plugin.json` — 插件元数据
- `CLAUDE.md` — 裁剪后的工程法则（无测试纪律/构建纪律/发版纪律段落）
- `hooks/hooks.json` — Hook 配置
- `scripts/` — 27 个运行时脚本（排除 2 个开发专用脚本）
- `skills/` — 7 个 SKILL 目录 + references + templates
- `gui-dist/` — GUI 编译产物

### 2.3 gui-dist/ 纯净度

| 检查项 | 结果 |
|--------|------|
| .tsx/.ts/.jsx 源码文件 | 无 |
| .map 源码映射文件 | 无 |
| node_modules/ | 无 |
| 文件构成 | 1 个 index.html + 1 个 CSS + 1 个 JS + 9 个 woff2 字体 (共 12 文件) |

gui-dist/ 仅包含 Vite 编译后的纯产物，无任何源码泄露。

### 2.4 构建脚本隔离验证机制

build-dist.sh 内建 3 层校验:
1. **hooks.json 引用校验**: 遍历 hooks.json 中所有 scripts/ 引用，确认文件存在
2. **CLAUDE.md 裁剪校验**: 验证 dist 中 CLAUDE.md 不含"测试纪律"、"构建纪律"、"发版纪律"关键字
3. **禁止路径校验**: 检查 gui/docs/tests/CHANGELOG.md/README.md 均不在 dist 中

---

## 3. CLAUDE.md 防线验证

### 3.1 源文件防线覆盖度（完整版，含 dev-only）

| 防线类别 | 条目数 | 关键内容 |
|----------|--------|----------|
| 状态机跳变红线 | 7 条 | Phase 顺序、三层门禁、模式互斥、降级条件、Phase 4 warning 拒绝、Phase 5 zero_skip、归档确认 |
| TDD Iron Law | 5 条 | 先测试后实现、RED 必须失败、GREEN 必须通过、测试不可变、REFACTOR 回滚 |
| 代码质量硬约束 | 7 条 | TODO 拦截、恒真断言、Anti-Rationalization、代码约束、Test Pyramid、Change Coverage、Sad Path |
| 需求路由 | 3 类 | Bugfix/Refactor/Chore 差异化阈值 |
| GUI Event Bus | 5 类事件 | phase_start/end、gate_pass/block、task_progress、decision_ack |
| 子 Agent 约束 | 6 条 | 禁读计划、禁写 checkpoint、JSON 信封、Write 到文件、文件所有权、L2 验证 |
| 发版纪律 (dev-only) | 4 条 | 唯一入口、禁止散弹修改、同步范围、验证闭环 |
| 测试纪律铁律 (dev-only) | 4 大类 | 修改方向矩阵、边界约束、绝对禁止反模式、新功能测试清单 |
| 构建纪律 (dev-only) | 4 条 | 修改后必须重建、dist 禁止手动修改、白名单管理、测试文件隔离 |

### 3.2 dist 版本防线覆盖度

dist 版本正确保留了 6 大运行时防线（状态机、TDD、代码质量、需求路由、Event Bus、子 Agent），裁剪了 3 个开发专用段落（发版/测试/构建纪律）。

### 3.3 防线与 Hook 脚本映射

| CLAUDE.md 防线 | 对应 Hook 脚本 | 测试覆盖 |
|----------------|----------------|----------|
| Phase 顺序不可违反 | check-predecessor-checkpoint.sh | test_predecessor_checkpoint.sh (7 cases) |
| Phase 4 不接受 warning | validate-json-envelope.sh | test_json_envelope.sh (23 cases) |
| Phase 5 zero_skip_check | validate-json-envelope.sh | test_json_envelope.sh |
| 禁止 TODO/FIXME/HACK | unified-write-edit-check.sh | test_syntax.sh (syntax) |
| 禁止恒真断言 | unified-write-edit-check.sh | test_syntax.sh (syntax) |
| Anti-Rationalization | anti-rationalization-check.sh | test_anti_rationalization.sh (9 cases) |
| Test Pyramid 地板 | validate-json-envelope.sh | test_pyramid_threshold.sh (10 cases) |
| Change Coverage | validate-json-envelope.sh | test_change_coverage.sh (13 cases) |
| 代码约束 | code-constraint-check.sh | test_syntax.sh (syntax) |
| 文件所有权 | parallel-merge-guard.sh | test_parallel_merge.sh (11 cases) |

---

## 4. 发现的问题

### 4.1 无阻断性问题

本次审查未发现任何阻断性问题。

### 4.2 观察项（非阻断）

| 编号 | 类别 | 描述 | 严重度 |
|------|------|------|--------|
| O-1 | 测试 | unified-write-edit-check.sh 缺少独立功能测试模块（仅有 syntax 验证） | 低 |
| O-2 | 测试 | code-constraint-check.sh 缺少独立功能测试模块 | 低 |
| O-3 | 构建 | dist 中包含 mock-event-emitter.js 和 autopilot-server.ts，这些可能不属于运行时必需脚本 | 信息 |
| O-4 | 构建 | gui-dist 中 JS bundle 仅 54 字节（最后一行），说明是高度压缩的单文件产物，无问题 | 信息 |

---

## 5. 评分

| 维度 | 得分 | 满分 | 说明 |
|------|------|------|------|
| 测试通过率 | 30 | 30 | 49 模块 357 断言全部通过，100% 通过率 |
| 构建产物纯净度 | 25 | 25 | gui/tests/docs 完全剔除，dev 脚本排除，CLAUDE.md 裁剪正确，hooks.json 引用完整 |
| 测试基建完备度 | 22 | 25 | 覆盖面广（52 个测试编号），但 unified-write-edit-check 和 code-constraint-check 缺独立测试 |
| CLAUDE.md 防线覆盖度 | 18 | 20 | 9 大类防线全部声明，dev-only 裁剪机制健全；部分防线（恒真断言、代码约束）的 Hook-测试映射可加强 |
| **总分** | **95** | **100** | |

---

## 6. 改进建议

### 优先级 P2（建议改进）

1. **新增 unified-write-edit-check.sh 功能测试**
   - 当前仅有 syntax 验证（bash -n），缺少对 TODO/FIXME/HACK 拦截、恒真断言拦截的端到端测试
   - 建议新增 `test_unified_write_edit.sh`，覆盖正常/边界/错误路径

2. **新增 code-constraint-check.sh 功能测试**
   - 应验证 forbidden_files/patterns 的阻断行为
   - 建议新增 `test_code_constraint.sh`

### 优先级 P3（可选优化）

3. **审查 dist scripts/ 白名单**
   - `mock-event-emitter.js` 和 `autopilot-server.ts` 是否为运行时必需？若仅用于开发/调试，应加入 EXCLUDE_SCRIPTS
   - 当前 EXCLUDE_SCRIPTS 仅排除 `bump-version.sh` 和 `build-dist.sh`

4. **测试编号连续性**
   - 当前测试编号有跳跃（如无 #5），虽不影响功能，但补齐编号可提高可维护性

---

*报告生成完毕。总体评估：基建状态优秀，测试覆盖率高，构建产物纯净，防线配置完整。*
