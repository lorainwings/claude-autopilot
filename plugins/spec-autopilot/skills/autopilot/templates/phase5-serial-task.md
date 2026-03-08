# Phase 5: 循环实施（内置模板）

> 此模板由插件内置提供。项目可通过 config.phases.implementation.instruction_files 覆盖。

## 服务健康检查（每次测试前必须运行）

{for each service in config.services}
curl -sf {service.health_url} || echo "WARN: {service.name} 不可达"
{end for}

任一服务不可达 → 记录警告，仅运行不依赖该服务的测试。

## 实施指令

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
