# Phase 5: 循环实施（内置模板）

> 此模板由插件内置提供。项目可通过 config.phases.implementation.instruction_files 覆盖。

## 服务健康检查（每次测试前必须运行）

{for each service in config.services}
curl -sf {service.health_url} || echo "WARN: {service.name} 不可达"
{end for}

任一服务不可达 → 记录警告，仅运行不依赖该服务的测试。

## 实施指令

### 测试驱动验证（full 模式标准流程）

> 当 Phase 4 测试文件可用时，**主线程在 dispatch 前后执行 L2 RED/GREEN 验证**。
> 子 Agent 内部也应遵循 RED→GREEN 流程，与主线程 L2 验证形成双重保障。

**主线程 L2 验证**（由主线程执行，子 Agent 不可干预）：
- dispatch 前: 主线程运行 Phase 4 测试，确认 RED（测试失败）
- dispatch 后: 主线程运行 Phase 4 测试，确认 GREEN（测试通过）

**子 Agent L1 验证**（由子 Agent 自行执行，作为 L2 的补充）：

当 Phase 4 的测试用例文件已存在时（由控制器注入 `phase4_test_files`），每个 task 的实施必须遵循以下测试驱动流程：

1. **RED 验证**（实施前）：运行 Phase 4 设计的与当前 task 相关的测试用例，确认测试**失败**（证明测试有效且功能尚未实现）
   ```
   {for each test_file in phase4_test_files relevant to current task}
   运行: {suite.command} {test_file}
   预期: exit_code ≠ 0（测试应失败）
   记录: red_output_excerpt（失败输出摘要）
   {end for}
   ```
   > **RED 已通过处理**：如果测试已通过（exit_code = 0），说明功能已存在或测试无效：
   > - 设置 `red_verified: false`（不能证明经历了有效的 RED→GREEN 转变）
   > - 设置 `red_skipped_reason: "test_already_passing"`
   > - 继续实施 task（不阻断），但证据标记为不完整

2. **实施 task**：按照任务描述实现功能代码（正常实施流程）

3. **GREEN 验证**（实施后）：运行相同的 Phase 4 测试用例，确认测试**通过**
   ```
   {for each test_file in phase4_test_files relevant to current task}
   运行: {suite.command} {test_file}
   预期: exit_code = 0（测试应通过）
   {end for}
   ```
   > 如果测试仍失败，修复实现代码（禁止修改测试用例），直到测试通过。

4. **记录 RED→GREEN 证据**：在返回信封中包含 `test_driven_evidence` 字段：
   ```json
   "test_driven_evidence": {
     "phase4_tests_path": "测试文件路径",
     "red_verified": true/false,
     "green_verified": true/false,
     "red_output_excerpt": "失败输出摘要（前 3 行）",
     "red_skipped_reason": null | "test_already_passing"
   }
   ```
   > `red_verified: true` 仅当 RED 阶段测试确实失败时设置。若测试已通过则 `red_verified: false` + `red_skipped_reason`。

> **无 Phase 4 测试时**（lite/minimal 模式）：跳过测试先行验证，直接进入正常实施流程。

### 正常实施流程

1. 执行 openspec-apply-change 逐个实施 tasks.md 中的未完成任务
2. 分级测试策略：

### 快速校验（每个任务后）
{for each suite in config.test_suites where suite.type in ["typecheck", "unit"]}
- `{suite.command}`
{end for}

### 完整测试（每 3 个任务或全部完成时）
{for each suite in config.test_suites}
- `{suite.command}`
{end for}

## 约束

- 每次 ≤3 个文件，≤{config.code_constraints.max_file_lines || 800} 行代码
- 测试失败时仅修改实现代码，绝对禁止修改测试用例
- 所有 openspec 制品必须全部完成

## 测试失败处理

同一测试连续失败 3 次：
1. 服务健康检查
2. 测试数据检查
3. 输出诊断结果
4. 等待用户决策（修复/标记已知问题/中止）

核心原则：绝不静默跳过失败测试。

## 写入结构化测试结果

完整测试运行后，写入 test-results.json：
- 每个 suite 的 command、exit_code、total/passed/failed/skipped
- zero_skip_check: { passed: true/false, violations: [] }

## 退出条件

- 所有任务完成 + 所有测试通过 → 正常退出
- 达到最大迭代次数 → 强制退出
- 遇到不可解决的阻塞 → 暂停等待用户
