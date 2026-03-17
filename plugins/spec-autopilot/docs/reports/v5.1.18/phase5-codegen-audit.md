# Phase 5 代码生成质量与规约遵从度评审报告

> 评审日期: 2026-03-17
> 评审版本: spec-autopilot `v5.1.20`
> 方法: Hook/模板/协议审计 + 代表性测试实测

## 执行摘要

Phase 5 当前最强的不是“代码写得多聪明”，而是“对错误写法有足够强的确定性约束”。规约服从、反占位符、作用域保护、并行合并守卫已经形成闭环。综合评分 **88/100**。

- 强项:
  - `CLAUDE.md` / `.claude/rules` / `code_constraints` 三层约束能进入派发和 Hook。
  - `unified-write-edit-check.sh` 对 TODO/FIXME/HACK、恒真断言、TDD 阶段写入隔离都有硬拦截。
  - `parallel-merge-guard.sh` 能约束并行产物不越界。
- 风险:
  - brownfield 复用与“不要重复造轮子”更多依赖提示词和上下文质量，缺少确定性复用指标。
  - 遗留 `anti-rationalization-check.sh` 失败说明历史表面积尚未完全收敛到现行验证器。
  - Phase 内进度/快照落盘失效会削弱 Phase 5 的恢复与追责粒度。

## 实测基线

已通过的关键测试:

- `test_unified_write_edit.sh`
- `test_code_constraint.sh`
- `test_post_task_validator.sh`
- `test_phase5_serial.sh`
- `test_parallel_merge.sh`

关键结果:

- TODO/FIXME/HACK 会被阻断
- `expect(true).toBe(true)` 之类恒真断言会被阻断
- forbidden files / patterns / 越界目录会被阻断
- 并行 merge 对 scope 外文件有稳定拦截

## 四项核心指标审计

### 1. 全局记忆与规约服从度

结论: **强**

依据:

- `rules-scanner.sh` 扫描项目规则
- `code_constraints` 进入 L2 检查
- `post-task-validator` 与 `unified-write-edit-check.sh` 在产出后做确定性拦截

评价:

- 这是 Phase 5 最大的工程优势之一
- 规约不是只在 prompt 里说一遍，而是会落到 Hook

### 2. 上下文感知与防重复

结论: **中强**

优势:

- Phase 1 Steering Documents、existing patterns、task 摘要会进入后续上下文
- 并行模式有文件所有权与 merge guard

不足:

- 当前没有“确定性复用率”指标，无法回答“本次是否本可复用已有 util 却新造了一个”
- 大仓库场景下缺少 Repo Map/符号级索引

### 3. 反偷懒检测

结论: **强，但遗留面未收口**

已验证:

- `zero_skip_check` 是硬条件
- 占位符代码与恒真断言会被阻断
- Phase 5 JSON 输出缺关键字段会被 block

风险:

- 独立 `anti-rationalization-check.sh` 脚本测试失败，虽非主链路，但会制造维护噪音
- “反偷懒”现在分散在 merged validator、write/edit guard 与协议文本中，认知成本仍偏高

### 4. 安全性与健壮性

结论: **中强**

已有保障:

- forbidden files / patterns / scope
- merge 越界拦截
- 并行文件所有权

缺口:

- 更深层的安全扫描仍主要依赖 Phase 6/异步质量扫描
- Phase 5 自身尚缺统一的“异常处理 / 日志最小要求”静态语义检查

## 评分矩阵

| 维度 | 评分 | 说明 |
|---|---:|---|
| 规约服从度 | 92 | 有 prompt 注入，也有 Hook 强制 |
| 防重复与复用 | 80 | 有上下文流转，但缺索引级增强 |
| 反偷懒能力 | 89 | 现行链路强，遗留脚本拖后腿 |
| 并行正确性 | 91 | merge guard 与 scope 设计成熟 |
| 安全与健壮性 | 86 | 基础护栏强，深度安全语义仍可增强 |

## 主要发现

### P1: Phase 5 恢复粒度被快照/进度静默失效拖累

即便代码生成本身门禁严密，若 `phase-context-snapshots` 和 `phase-progress` 无法写入，仍会影响:

- 失败任务的回放
- GUI 的阶段内可观测性
- 人工复盘并行任务时的证据链

### P1: 复用能力还停留在“上下文提示”，不是“结构化索引”

当前系统已经能把项目模式喂给 Agent，但还不能确定性回答:

- 哪个 util 与当前任务最接近
- 哪些模块已经覆盖相同职责
- 本次改动是否引入了重复抽象

### P2: 遗留反合理化脚本应退出主维护面

建议把遗留脚本彻底归档或只保留兼容薄壳，避免“现行主链路没问题，但遗留测试在报错”的状态继续扩散。

## 结论

如果只看“代码生成阶段的工程纪律”，Phase 5 已经明显领先于多数依赖纯 Agent 自觉的流水线。下一步最值得投的是“结构化上下文索引”和“把遗留验证面收口到统一 validator”。

