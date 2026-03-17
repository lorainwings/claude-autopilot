# Phase 6 TDD 流程纯洁度与测试质量评审报告

> 评审日期: 2026-03-17
> 评审版本: spec-autopilot `v5.1.20`
> 方法: TDD 协议审计 + Hook/Validator 测试 + Phase 6 报告链路验证

## 执行摘要

Phase 6 与 TDD 相关链路目前有一个很鲜明的特征: 串行 TDD 的确定性约束足够硬，并行 TDD 仍然保留“先自证、再汇总校验”的信任面。综合评分 **84/100**。

- 强项:
  - RED/GREEN/REFACTOR 写入隔离测试全部通过。
  - REFACTOR 回滚脚本可用，文件追踪链路有效。
  - Phase 6 JSON 验证、Phase 5→6 门禁、断言质量拦截形成组合保护。
- 风险:
  - 并行 TDD 仍缺串行模式那种逐 task 的主线程 L2 失败验证。
  - `suite_results` 仍是推荐字段，不是硬门槛，降低了测试报告颗粒度。
  - 测试反模式更多是 prompt 注入与 Gate Function，自然语言约束仍多于静态语义检查。

## 实测基线

执行命令:

```bash
bash tests/run_all.sh test_tdd_isolation test_tdd_rollback test_phase6_independent test_phase6_suite_results test_post_task_validator test_unified_write_edit test_code_constraint
```

关键结果:

- `test_tdd_isolation.sh`: `RED/GREEN/REFACTOR` 文件写入隔离全部通过
- `test_tdd_rollback.sh`: REFACTOR 回滚脚本通过
- `test_phase6_independent.sh`: Phase 6 不依赖 6.5 字段
- `test_phase6_suite_results.sh`: 缺失或空 `suite_results` 不会 block
- `test_post_task_validator.sh`: 关键 Phase 字段校验通过

## 纯洁度审计

### 串行 TDD

结论: **强**

证据:

- `skills/autopilot/references/tdd-cycle.md` 明确要求主线程在 RED/GREEN/REFACTOR 之间进行 Bash 级验证
- `unified-write-edit-check.sh` / `write-edit-constraint-check.sh` 对 RED 与 GREEN 的写入做硬阻断
- `tdd-refactor-rollback.sh` 对 REFACTOR 失败后的恢复有明确机制

评价:

- 这部分已经不是“建议遵守 TDD”，而是“把 TDD 状态编码进文件系统和 Hook”

### 并行 TDD

结论: **中**

证据:

- `tdd-cycle.md` 明确写出设计约束: 并行模式下域 Agent 内部 RED/GREEN 为 L1 自查，主线程只做合并后的全量测试

影响:

- 可以证明“最终全量测试通过”
- 但不能像串行模式那样证明“每个 task 都真正经历过失败测试再写实现”

这是当前 TDD 纯洁度最主要的保留风险。

## 测试质量审计

### 已有强保护

- 恒真断言拦截: `expect(true).toBe(true)` 会被阻断
- TODO/FIXME/HACK 拦截: 防止交半成品
- `code_constraints` 与作用域约束: 防止测试/实现越界

### 仍偏软约束的部分

- `testing-anti-patterns.md` 对 mock 行为测试、盲目 mock、不完整 mock 等定义得很好
- 但这些大多通过 prompt 注入和 Gate Function 自查实现
- 缺少专门的静态分析器来确定性检查“测试是否只是在断言 mock 回值”

## Mock 与依赖隔离

结论: **中强**

优点:

- 文档明确强调只 mock 外部 I/O
- 并行 Phase 6 三路拆分有利于把测试执行、代码审查、质量扫描解耦

风险:

- 反模式主要还是“被告知不要这样做”，而不是“脚本能必然抓住”

## 主要发现

### P1: 并行 TDD 仍有 L1 信任面

这是当前最值得明确写进后续演进计划的问题。系统已在文档里诚实承认这一点，但工程上仍建议继续缩小这一信任面。

### P1: `suite_results` 非强制，报告粒度不足

当前只要有 `artifacts + pass_rate + report_path/report_format` 就能通过。这保证了兼容性，但会让:

- 套件维度失败分布
- 单元/API/E2E 的贡献占比
- 异常簇定位

变得不够稳定。

### P2: 断言反模式缺少静态语义检测

系统已经能抓恒真断言，但还不能系统性识别:

- mock.return_value 与断言一一对应的“伪测试”
- 测试逻辑过薄、mock setup 过重
- 不完整 mock 与真实 schema 偏离

## 结论

spec-autopilot 的 TDD 纪律在同类工具里仍然很强，尤其是串行模式。下一步应该优先把“并行 TDD 的可信证明”和“测试反模式静态检测”补齐，这两项补上后，Phase 6 可以从“强协议”进化成“强证据”。

