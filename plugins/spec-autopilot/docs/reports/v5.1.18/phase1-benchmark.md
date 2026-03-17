# Phase 1 需求质量 Benchmark 报告

> 评审日期: 2026-03-17
> 评审版本: spec-autopilot `v5.1.20`
> 方法: 文档协议审计 + 路由/搜索/后置校验测试取证

## 执行摘要

Phase 1 相比早期版本已经明显成熟，尤其是“需求信息量评估”“需求类型分类与路由覆盖”“非 AI 搜索决策规则”三块，已经不是纯提示词约定，而是接近规则引擎。综合评分 **86/100**。

- 强项:
  - 需求清晰度前置检测，能避免模糊需求直接触发高噪音调研。
  - `bugfix/refactor/chore/feature` 路由覆盖会向 Phase 4/5 传播动态阈值。
  - 搜索策略默认 `search`，并明确采用规则引擎而非 AI 自评。
- 短板:
  - 真实调研产物仍高度依赖 Agent 输出质量，缺少“存量代码调研覆盖率”的确定性指标。
  - Phase 1 的阶段快照当前无法稳定写回，削弱了评审与恢复能力。
  - 对复合需求的“优先级冲突解释”还不够产品化。

## 证据基线

已核查:

- `skills/autopilot/references/phase1-requirements.md`
- `skills/autopilot/references/phase1-requirements-detail.md`
- `tests/test_search_policy.sh`
- `tests/test_routing_overrides.sh`
- `tests/test_post_task_validator.sh`

关键验证:

- `test_search_policy.sh`: 搜索策略、强制搜索关键词、非 AI 决策均通过。
- `test_routing_overrides.sh`: Phase 1 输出的 `routing_overrides` 能动态调整后续门禁。
- `test_post_task_validator.sh`: Phase 1 checkpoint 缺失 `decisions` 会被 block。

## 三个基准场景

### 场景 A: 模糊需求

输入:

```text
优化性能
```

评估:

- `Step 1.1.5` 的信息量检测会命中 `brevity/no_tech_entity/no_metric` 等标记。
- 按当前规则，应进入“需求澄清预循环”，而不是立刻三路并行调研。

评分:

| 维度 | 分数 | 结论 |
|---|---:|---|
| 需求理解 | 9 | 已有确定性前置筛查 |
| 澄清深度 | 8 | 规则明确，但仍取决于问题模板质量 |
| Token 效率 | 8 | 能避免最明显的噪音调研 |

结论: 这是 Phase 1 当前最明显的提升点。

### 场景 B: 跨模块安全需求

输入:

```text
给现有管理后台增加企业 SSO、RBAC 和审计日志，保留原邮箱登录。
```

评估:

- 命中 `new_feature + security_related + architecture_decision`
- 搜索规则会强制联网调研
- Phase 1 会产出决策卡片，并将高约束结果传播到后续阶段

评分:

| 维度 | 分数 | 结论 |
|---|---:|---|
| 隐藏约束挖掘 | 8 | 能抓到安全/兼容/依赖风险 |
| 调研覆盖 | 8 | 三路并行设计合理 |
| 工程价值 | 9 | 路由结果能影响后续门禁，不是纸面分析 |

短板:

- 没有确定性“威胁建模完成度”度量
- 对接口契约、迁移窗口、回滚策略仍主要依赖 analyst 输出质量

### 场景 C: 存量改造 / 兼容迁移

输入:

```text
把现有 REST API 逐步迁移到 GraphQL，保持旧接口兼容，先迁查询再迁写入。
```

评估:

- 会被识别为 `refactor`，并可能叠加 `feature`
- `routing_overrides` 会推高 `change_coverage` 阈值
- 持久化上下文 + `existing-patterns.md` 对 brownfield 项目有帮助

评分:

| 维度 | 分数 | 结论 |
|---|---:|---|
| 存量代码调研 | 7 | 有扫描框架，但覆盖仍偏“结构级” |
| 兼容迁移分析 | 8 | 规则与调研方向是对的 |
| 澄清问题价值 | 8 | 能促使用户明确阶段目标与兼容边界 |

短板:

- Auto-Scan 更像“目录/依赖/模式扫描”，不是语义级 API 拓扑分析
- 缺少确定性“已识别关键接口清单”的产物门禁

## 质量评分矩阵

| 维度 | 评分 | 说明 |
|---|---:|---|
| 需求分析与理解 | 88 | 有前置信息量评估与多轮决策 |
| 隐藏约束挖掘 | 84 | 安全、迁移、依赖场景有明显改进 |
| 存量代码调研覆盖率 | 76 | 仍偏结构扫描，语义覆盖不足 |
| 澄清问题工程价值 | 87 | 已能把澄清转成路由与阈值 |
| 路由设计 | 92 | 最成熟，且有测试保护 |
| 搜索策略可信度 | 90 | 明确是规则引擎，不是 AI 自评 |

## 主要发现

### P1: 存量代码调研还缺“语义索引”

当前 Steering Documents 很适合建立项目全景，但对大仓库中的“接口契约、调用链、复用点、潜在重复实现”仍缺少结构化索引。这会直接影响 Phase 5 的复用率与误改风险。

### P1: Phase 1 快照链路被外部稳定性问题削弱

虽然协议要求写 `phase-1-interim.json`、最终 checkpoint、阶段快照，但当前 `save-phase-context.sh` 根目录解析有误，意味着 Phase 1 的“分析质量可回放性”下降。

### P2: 复合路由的解释层还不够可视化

协议已支持 `["refactor","feature"]` 这类复合类型，并以最严格规则合并阈值；但对用户而言，还缺少“为什么本需求被判成这个组合”的解释视图。

## 结论

当前 Phase 1 已经从“高质量 prompt 流程”进化到“部分确定性规则驱动的需求引擎”。如果下一步补上 Repo Map/语义索引与更强的可解释输出，Phase 1 可以成为整个 spec-autopilot 最具差异化的模块之一。

