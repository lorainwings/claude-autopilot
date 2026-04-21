---
name: autopilot-test-health
description: "Use when the user wants to quantify test effectiveness — running lightweight shell-layer mutation testing and static health scoring to confirm the test suite would actually catch regressions. Typical triggers include weekly CI sweeps, on-demand audits asking 'how healthy are our tests', or '/autopilot-test-health score|mutate|all' invocations. Not part of any phase gate."
user-invocable: true
argument-hint: "[score|mutate|all] — 默认 all"
---

# Autopilot Test Health — 测试有效性量化

> **用途**：在已有 `autopilot-test-audit`（静态扫描候选清单）之上，再加一层"用变异测试量化测试有效性"的能力。避免测试存在但无信号。

## 何时使用

- **CI weekly sweep**：定时跑 `/autopilot-test-health all` 输出 dashboard
- **人工 audit**：发版前评估测试套件健康度
- **新手定位弱测试**：top-10 weak files 直接给出改进目标

> **不建议挂 pre-commit**：变异测试每次至少跑 N 个 mutant × test，开销太大。

## 模式

| 模式 | 含义 | 输出 |
|------|------|------|
| `mutate` | 仅跑变异测试 | `.cache/spec-autopilot/mutation-report.json` |
| `score` | 仅跑静态健康度评分（含读入已有 mutation 结果） | `.cache/spec-autopilot/test-health-report.json` |
| `all`（默认） | 先 mutate 再 score | 两份报告 |

## 执行步骤

### Step 1: 解析参数

```bash
MODE="${1:-all}"
case "$MODE" in
  mutate|score|all) ;;
  *) echo "用法: /autopilot-test-health [score|mutate|all]"; exit 1 ;;
esac
```

### Step 2: 执行变异测试（mutate / all）

```bash
bash plugins/spec-autopilot/runtime/scripts/test-mutation-sample.sh \
  --targets "plugins/spec-autopilot/runtime/scripts/*.sh" \
  --sample-size 10 \
  --timeout-per-mutant 30
```

输出：
- `.cache/spec-autopilot/mutation-report.json`（含 targets / overall_kill_rate / survivors）
- stdout: `MUTATION_KILL_RATE=0.XX SURVIVORS=N`

### Step 3: 执行静态评分（score / all）

```bash
bash plugins/spec-autopilot/runtime/scripts/test-health-score.sh \
  --tests-dir plugins/spec-autopilot/tests \
  --threshold 60
```

输出：
- `.cache/spec-autopilot/test-health-report.json`
- stdout: `HEALTH_SCORE=X` 与可选 `HEALTH_BELOW_THRESHOLD=1`

### Step 4: 总结

读取两份报告，汇总 dashboard：

```
Mutation kill_rate: 0.XX  (survivors: N)
Health overall:    XX/100
  assertion_density: 0.XX
  weak_ratio:        0.XX
  duplicate_ratio:   0.XX
  kill_rate:         0.XX (来自 mutation 报告)
```

## 安全约束

1. **要求 git working tree 干净**：变异测试会临时编辑源文件，脏 tree 直接 exit 2
2. **变异 + 恢复后 git diff 必须为空**：双重校验
3. **超时强制 kill**：避免 sleep / 死循环阻塞
4. **失败不阻断 CI**：两个脚本都 exit 0；阈值命中仅以 `HEALTH_BELOW_THRESHOLD=1` 提示

## 输出消费建议

- `kill_rate < 0.5` → 该批 runtime 脚本测试质量整体不达标
- `weak_ratio > 0.3` → 大量测试只断言 exit code，需补内容/格式断言
- `duplicate_ratio > 0.2` → case 命名重复，可能是复制粘贴未改名
- `top_weak` 列表中的文件 → 优先改进对象

## 配置

`.claude/autopilot.config.yaml` 可加：

```yaml
test_health:
  thresholds:
    overall: 60
    assertion_density: 2.0
    weak_ratio_max: 0.3
```

## 参考

- 变异规则：`references/mutation-strategies.md`
- 健康指标：`references/health-metrics.md`
