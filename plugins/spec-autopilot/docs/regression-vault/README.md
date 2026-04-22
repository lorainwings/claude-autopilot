# Regression Vault — 反例库 (C5)

本目录收录所有由 `autopilot-risk-scanner` 拦截或 `autopilot-phase5-5-redteam` 复现的真实事故，
作为后续 autopilot 运行时的"先验风险知识库"。

## 命名规范

```
{YYYYMMDD}-{category}-{short-desc}.md
```

- `YYYYMMDD`：事故/复现首次入库的日期
- `category`：与 redteam 5 类破坏对齐 — `boundary` / `concurrency` / `state-pollution` / `dependency-regression` / `backward-incompat` / `risk-scanner` (常规扫描发现)
- `short-desc`：≤ 6 个英文单词的简短描述，用 `-` 连接

示例：
- `20260418-boundary-empty-change-name.md`
- `20260418-concurrency-double-flock-acquire.md`

## 必备内容

每个条目 Markdown 文件必须包含以下章节：

```markdown
# {标题}

## 概要 (Summary)
一句话描述被复现的缺陷。

## 来源 (Source)
- 触发 Skill: `autopilot-risk-scanner` | `autopilot-phase5-5-redteam`
- 关联 change: `openspec/changes/<change_name>/`
- 原始报告引用: `context/risk-report-phase{N}.json#check_id` 或 `context/redteam-report.json#RT-XXX-001`

## Reproducer (必填)
完整可执行的最小复现脚本，或对 `tests/generated/redteam-*.sh` 的引用。

## 根因 (Root Cause)
分析为何当前实现无法防御该攻击。

## 修复 (Fix)
- commit SHA 或 PR 链接
- 关联的正式测试入库路径 (`tests/test_<name>.sh`)

## 防御回灌 (Feedback Loop)
本条目应在哪些后续 phase 的 `prior_risks[]` 中被自动注入。
```

## 入库流程

1. `autopilot-phase5-5-redteam` 复现成功 ⇒ Phase 5 修复 ⇒ reproducer 转正式测试
2. 在本目录新建 `.md` 条目，遵循上述模板
3. `feedback-loop-inject.sh` 在后续运行中读取本目录条目，
   将 `防御回灌` 章节命中的条目作为 `prior_risks[]` 注入下游 task envelope

## 相关 Skill

- `skills/autopilot-risk-scanner/SKILL.md`
- `skills/autopilot-phase5-5-redteam/SKILL.md`
- `runtime/scripts/feedback-loop-inject.sh`
