# Autopilot Plugin — 工程法则 (CLAUDE.md)

> 此文件为 spec-autopilot 插件的**单点事实来源 (Single Source of Truth)**。
> 所有 AI Agent（主线程 + 子 Agent）在执行期间**必须**遵守以下法则。

## 状态机跳变红线 (State Machine Hard Constraints)

1. **Phase 顺序不可违反**: Phase N 必须在 Phase N-1 checkpoint status ∈ {ok, warning} 后才能开始
2. **三层门禁联防**: L1 (TaskCreate blockedBy) + L2 (Hook 确定性验证) + L3 (AI Gate 8-step)，任一层阻断即阻断
3. **模式路径互斥**: `parallel.enabled = true` 必须走并行路径，`false` 走串行路径，禁止 AI 自主切换
4. **降级条件严格**: 仅合并失败 > 3 文件、连续 2 组失败、或用户显式选择时才允许降级
5. **Phase 4 不接受 warning**: Hook 确定性阻断，warning 强制覆盖为 blocked
6. **Phase 5 zero_skip_check**: `passed === true` 必须满足，否则阻断
7. **归档 fail-closed**: archive-readiness 通过时自动执行，任一检查项失败则硬阻断（fixup 不完整、anchor 无效、review blocking findings 未解决等）

## TDD Iron Law (仅 tdd_mode: true 时生效)

1. **先测试后实现**: RED 阶段仅写测试，GREEN 阶段仅写实现，违反即删除
2. **RED 必须失败**: `exit_code ≠ 0`，L2 Bash 确定性验证
3. **GREEN 必须通过**: `exit_code = 0`，L2 Bash 确定性验证
4. **测试不可变**: GREEN 失败时修复实现代码，禁止修改测试
5. **REFACTOR 回归保护**: 重构破坏测试 → 自动 `git checkout` 回滚

## 代码质量硬约束

1. **禁止 TODO/FIXME/HACK 占位符**: L2 Hook `unified-write-edit-check.sh` 确定性拦截
2. **禁止恒真断言**: L2 Hook `unified-write-edit-check.sh` 拦截 `expect(true).toBe(true)` 等
3. **Anti-Rationalization**: 10+6 种 excuse 模式匹配 → status 强制降级为 blocked
4. **代码约束**: `code_constraints` 配置的 forbidden_files/patterns → L2 硬阻断
5. **Test Pyramid 地板**: unit_pct ≥ 30%, e2e_pct ≤ 40%, total ≥ 10 (L2 可配置)
6. **Change Coverage**: coverage_pct ≥ 80% (bugfix/refactor 路由可提升至 100%)
7. **Sad Path 比例**: sad_path_counts 每类型 ≥ test_counts 同类型 20%

## 需求路由

需求自动分类为 Feature/Bugfix/Refactor/Chore，不同类别动态调整门禁阈值：

- **Bugfix**: sad_path ≥ 40%, change_coverage = 100%, 必须含复现测试
- **Refactor**: change_coverage = 100%, 必须含行为保持测试
- **Chore**: 放宽至 change_coverage ≥ 60%, typecheck 即可

## GUI Event Bus API

事件发射到 `logs/events.jsonl`，格式见 `references/event-bus-api.md`：

- `phase_start` / `phase_end`: Phase 生命周期
- `gate_pass` / `gate_block`: 门禁判定
- `task_progress`: Phase 5 任务细粒度进度
- `decision_ack`: GUI 决策确认 (WebSocket-only)
- 所有事件含 ISO-8601 时间戳 + phase 编号 + mode + payload

## 子 Agent 约束

1. **禁止自行读取计划文件**: 上下文由主线程提取注入
2. **禁止修改 openspec/ checkpoint**: L2 Hook `unified-write-edit-check.sh` 确定性阻断，checkpoint 写入仅限 Bash 工具
3. **必须返回 JSON 信封**: `{"status": "ok|warning|blocked|failed", "summary": "...", "artifacts": [...]}`
4. **背景 Agent 产出必须 Write 到文件**: 返回信封仅含摘要，禁止全文灌入主窗口
5. **文件所有权 ENFORCED**: 并行模式下仅可修改 owned_files 范围内的文件
6. **背景 Agent 必须接受 L2 验证**: JSON 信封 + 反合理化检查不可绕过
7. **Phase 1 上下文隔离**: 主线程禁止 Read 调研/BA 正文工件（research-findings.md、web-research-findings.md、requirements-analysis.md），仅消费 JSON 信封中的结构化字段
8. **Dispatch 审计**: dispatch 记录必须包含 selection_reason、resolved_priority、owned_artifacts，由 post-task-validator 验证
9. **Review findings fail-closed**: Phase 6.5 code review 中 `blocking: true` 的 findings 硬阻断 Phase 7 归档

<!-- DEV-ONLY-BEGIN -->
## 发版纪律

1. **主入口**: [release-please](https://github.com/googleapis/release-please) 自动管理版本号和 CHANGELOG — PR 合入 main 后自动创建 Release PR，合并即发版
2. **手动 fallback**: `tools/release.sh <patch|minor|major> <plugin-name>` 仅在 release-please 不可用时使用
3. **禁止散弹式修改**: 禁止人工或 AI 单独修改 plugin.json / marketplace.json / README.md / CHANGELOG.md 中的版本号
4. **Conventional Commits**: commit message 遵循 `feat:` / `fix:` / `refactor:` 等前缀，release-please 据此生成 CHANGELOG
5. **pre-commit 只读**: pre-commit hook 仅做一致性校验（版本三端一致），CHANGELOG 检查为信息提示
6. **推送前必须完整构建+测试**: `git push` 前必须依次执行 `bash tools/build-dist.sh`（构建）+ `bash tests/run_all.sh`（全量测试），两者均 exit 0 后才允许推送，禁止跳过
<!-- DEV-ONLY-END -->

<!-- DEV-ONLY-BEGIN -->
## 测试纪律铁律 (Test Discipline Iron Law)

> 此规则在所有 commit / pre-commit 流程中强制生效。

### 修改方向矩阵

| 场景 | 正确做法 | 禁止做法 |
|------|----------|----------|
| 新功能开发 | 在对应 `tests/test_*.sh` 中新增 test case | 不新增测试就提交功能代码 |
| Bug 修复 | 先写复现 bug 的回归测试，再修实现 | 修实现但不加回归测试 |
| 测试失败 | 定位失败的具体 assert，修复该 assert 或 fixture | 修改编排逻辑/hook 实现来让测试通过 |
| 重构 | 保持所有现有测试通过，不修改测试逻辑 | 改测试来适配重构后的接口 |

### 边界约束

1. **单文件原则**: 一次 commit 的测试修改限定在与被修改脚本对应的 `test_*.sh` 内
2. **增量优先**: 添加新 case > 修改断言值 > 删除 case（删除必须在 commit message 说明理由）
3. **禁止批量重写**: 不得一次重写超过 3 个 assert；若需大面积修改，应先修复设计
4. **基础设施不可变**: `_fixtures.sh` / `_test_helpers.sh` 只允许新增函数，禁止修改已有函数签名

### 绝对禁止的反模式

1. **禁止反向适配**: 测试失败时修改 hook 脚本的判断分支、退出码语义、JSON 输出格式来让测试通过
2. **禁止弱化断言**: 不得将 `assert_exit "name" 1 $code` 改为 `assert_exit "name" 0 $code`
3. **禁止删除测试**: 删除现存 test case 必须在 commit message 中给出书面理由
4. **禁止跳过测试**: 不得注释或条件跳过已有测试
5. **禁止硬编码路径**: 所有路径基于 `$TEST_DIR` / `$SCRIPT_DIR` 动态推导
6. **严禁设置 `core.hooksPath=/dev/null`**: 任何脚本（测试、CI、工具）不得对主仓库执行 `git config core.hooksPath /dev/null`。临时仓库中需要跳过 hook 时使用 `git commit --no-verify`，且必须以 `git -C $TMPDIR` 或 `(cd "$TMPDIR" || exit 1; ...)` 隔离，防止 cd 失败时污染主仓库配置

### 新功能测试清单

每个新功能必须包含:

- 对应 `tests/test_*.sh` 中至少 3 个 test case（正常 + 边界 + 错误路径）
- 描述性名称（如 "3a. valid Phase 4 envelope → exit 0"）
- 无实现时确认 RED，实现后确认 GREEN
<!-- DEV-ONLY-END -->

<!-- DEV-ONLY-BEGIN -->
## 构建纪律 (Build Discipline)

1. **修改运行时文件后必须重新构建**: 运行 `bash tools/build-dist.sh`（pre-commit 自动执行）
2. **dist/plugin/ 禁止手动修改**: 所有修改在源码中进行，通过构建同步
3. **新增运行时脚本须加入清单**: 在 `runtime/scripts/.dist-include` 中添加对应条目
4. **测试文件永不进入 dist**: `tests/` 目录不在构建白名单中

## TypeScript 配置纪律

1. **禁止 `"types": ["bun-types"]`**: 会报 `Cannot find type definition file for 'bun-types'`
2. **Bun 类型由 `@types/bun` 提供**: 项目已安装此包，TypeScript 自动发现，tsconfig.json 中**无需**在 `types` 字段显式指定
3. **若必须显式声明**: 正确写法为 `"types": ["bun"]`（`types` 数组中不含 `@types/` 前缀）
<!-- DEV-ONLY-END -->
