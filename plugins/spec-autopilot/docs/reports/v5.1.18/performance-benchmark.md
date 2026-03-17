# 全阶段性能与消耗评估报告

> 评审日期: 2026-03-17
> 评审版本: spec-autopilot `v5.1.20`
> 方法: 指标脚本、事件链路、构建链路与测试运行成本综合评估

## 执行摘要

spec-autopilot 当前的性能画像可以概括为: “编排层已经很轻，观测层足够细，但构建链路和上下文索引仍是主要成本点。” 综合评分 **80/100**。

- 优势:
  - 模式化状态机、并行派发和事件总线设计合理，主控制流本身不重。
  - `collect-metrics.sh` 已按最新 checkpoint 读取，避免旧指标污染。
  - `clean-phase-artifacts.sh` 对历史产物清理和事件过滤已具备较好控制。
- 主要瓶颈:
  - GUI 构建链路当前不可用，导致发布性能与稳定性一起受损。
  - 缺少真实 token 采集闭环，目前更多依赖阶段时长、事件量、重试数等代理指标。
  - 没有 Repo Map/语义索引时，大仓库上下文供给成本会转嫁到 Agent token 消耗上。

## 实测证据

通过测试:

- `test_collect_metrics.sh`
- `test_common_unit.sh`
- `test_clean_phase_artifacts.sh`

失败相关:

- `test_build_dist.sh`
- `bun run build --mode production`

## 指标体系评估

### 当前已有指标

| 指标 | 来源 | 状态 |
|---|---|---|
| `duration_seconds` | checkpoint `_metrics` | 可用 |
| `retry_count` | checkpoint `_metrics` | 可用 |
| phase 状态汇总 | `collect-metrics.sh` | 可用 |
| 事件流 | `logs/events.jsonl` | 可用 |
| phase 内进度 | `write-phase-progress.sh` | 当前失效 |
| token 消耗 | 无统一真实采集 | 不足 |

### 评价

- “时间、重试、状态”三类指标已具备基础设施
- “token、上下文体积、搜索轮数、每阶段 worker 成本”还没有形成统一事实源

## 模式与阶段成本分析

### Full

- 最完整，phase 多，最适合做质量与恢复，但 wall-clock 成本最高
- 适合高风险需求，不适合轻量修复的日常默认

### Lite

- 跳过 `2/3/4`，在不启用全量规范设计时明显更省
- 对“快速实现 + 受控测试/报告”场景性价比较高

### Minimal

- 成本最低
- 但会放弃 Phase 6 的测试汇总与审阅能力

结论: 当前模式分层本身就是性能优化器，设计方向正确。

## 关键瓶颈

### P1: GUI 构建路径是当前最明显的性能/稳定性杀手

当前首选构建命令:

```bash
bun run build --mode production
```

直接失败于:

```text
TypeError: crypto$2.getRandomValues is not a function
```

这意味着:

- 发布链路无法稳定完成
- 无法可靠评估 dist 生成耗时
- 构建性能问题被放大成可用性问题

### P1: 缺少真实 token 与搜索成本账本

现有 Phase 1 搜索策略已经很先进，但系统尚不能稳定回答:

- 本次搜索用了多少 token
- 哪一轮搜索最值钱
- 三路并行调研的单位收益如何

这会限制真正的性能调优。

### P2: 阶段内进度失效导致观测稀疏

`write-phase-progress.sh` 当前不落盘，意味着 GUI/恢复系统只能看到较粗粒度 checkpoint，难以做:

- phase 内耗时拆分
- 卡点定位
- worker 慢点识别

## 成熟度判断

| 维度 | 结论 |
|---|---|
| 指标采集脚本 | 中强 |
| 事件总线 | 强 |
| 构建性能 | 弱 |
| token 成本管理 | 中低 |
| 观测细粒度 | 中 |

## 建议

1. 把 token、搜索轮次、上下文字节数纳入统一 metrics schema。
2. 先修复 `build-dist` 首选路径，否则所有“发布性能”讨论都没有稳定基线。
3. 修复 `write-phase-progress.sh` 后，再做 GUI/worker 级耗时拆分。
4. 引入轻量 Repo Map，减少 Phase 5/6 大仓库上下文重复注入成本。

## 结论

当前系统的性能问题主要不在状态机本身，而在“缺少更好的上下文压缩/索引”和“构建链路不稳”。一旦这两点修正，spec-autopilot 的并行编排优势会更明显地转化为真实 wall-clock 收益。

