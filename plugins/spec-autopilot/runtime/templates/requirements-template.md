# Feature: {feature_name}

> **协议来源**：本模板采用 [GitHub Spec Kit](https://github.com/github/spec-kit) 的
> `[NEEDS CLARIFICATION: ...]` 协议。**WHAT/WHY only — 不写 HOW（实现细节）**。
>
> BA Agent 在产出 `requirements-analysis.md` 时，**任何**用户原始 prompt 未覆盖的点
> **必须**用 `[NEEDS CLARIFICATION: 具体问题]` 显式标记，**严禁**填入貌似合理的假设。
> 完成需求评审前，所有标记必须被消解（替换为决策结论或转入 Open Questions）。

## Background & Goal

- **Source**: {raw_requirement_summary}
- **Business Goal**: {1-3 句业务目标}
  [NEEDS CLARIFICATION: 该需求的核心业务收益指标是什么？]

## User Stories

1. As a {role}, I want {action}, so that {benefit}.
   [NEEDS CLARIFICATION: 是否对未登录用户也生效？]
2. As a {role2}, I want {action2}, so that {benefit2}.

## Acceptance Criteria

> 每条 AC 必须可被自动化测试覆盖；含 MUST/SHOULD/SHALL 等可测试动词。

- [ ] AC1: {testable assertion, e.g. "用户提交表单后 200ms 内收到成功响应"}
- [ ] AC2: {testable assertion}
- [ ] AC3: [NEEDS CLARIFICATION: 失败重试次数上限？]

## Non-Goals

> 明确**排除**在本次交付外的功能/场景，避免 scope creep。

- {explicitly out of scope item 1}
- {explicitly out of scope item 2}

## Constraints & Assumptions

- **Constraints**: {已知技术/合规/性能约束}
- **Assumptions**: {实施前提，例如「依赖服务 X 已可用」}
  [NEEDS CLARIFICATION: 假设是否需要在实施前验证？]

## Open Questions

> 所有暂未闭合、需用户/PM 进一步澄清的点集中于此。
> 评审完成时此区块应为空（或全部已转为 decisions）。

- [NEEDS CLARIFICATION: 是否需要支持多语言？]
- [NEEDS CLARIFICATION: 与现有 module Y 的兼容策略？]

## Review Checklist

进入 Phase 2 前必须全部勾选：

- [ ] No `[NEEDS CLARIFICATION]` markers remain (template-wide grep returns empty)
- [ ] All ACs are testable (含 MUST/SHOULD/SHALL 或等价可测试动词)
- [ ] WHAT/WHY only — no HOW (implementation details, file paths, code snippets)
- [ ] Non-Goals 至少列出 1 项以锁定 scope
- [ ] Open Questions 已全部转为 decisions 或显式标记 deferred
