# 健康度指标 (Health Metrics)

## 5 个核心指标

### 1. assertion_density (权重 30%)

**定义**：每文件 PASS 断言数 / SLoC

**计算**：扫描每个 `test_*.sh`：
- SLoC = 非空 + 非注释行
- 断言计数 = 包含 `assert_` 或 `if [` 的行

**判读**：
- ≥ 2.0 → 强测试
- 0.5–2.0 → 中等
- < 0.5 → 弱测试（断言密度过低）

### 2. weak_ratio (权重 25%)

**定义**：仅含 exit-code 断言的文件数 / 总文件数

**判定弱文件**：
- 包含 `exit` 模式
- 且未包含任何强模式（`assert_*` / `if [` / `case` / `grep` / `[ ... ]`）
- 或断言数为 0

### 3. duplicate_ratio (权重 15%)

**定义**：跨文件 case 名重复 ≥ 2 次的 case 数 / 总 case 数

**采集**：从注释 `# Case: <name>` 提取

**判读**：
- > 0.2 → 大量复制粘贴未改名，潜在虚假 case

### 4. age_distribution

**定义**：基于 `git log --diff-filter=A` 首次出现时间分桶

| Bucket | 含义 |
|--------|------|
| `<30d` | 新增 |
| `30-180d` | 活跃维护 |
| `>180d` | 旧测试，可能与代码漂移 |
| `unknown` | 未在 git 历史中找到（如 untracked） |

仅作信息展示，不参与评分。

### 5. kill_rate (权重 30%，仅当 mutation report 存在)

**定义**：来自 `.cache/spec-autopilot/mutation-report.json` 的 `overall_kill_rate`

**判读**：
- ≥ 0.8 → 测试有效性强
- 0.5–0.8 → 中等
- < 0.5 → 大量变异未被捕获，测试质量不足

## 权重策略

| 场景 | assertion_density | weak_ratio | duplicate_ratio | kill_rate |
|------|------------------|------------|-----------------|-----------|
| 含 mutation report | 30% | 25% | 15% | 30% |
| 无 mutation report | 43% | 36% | 21% | 0% |

权重在缺失 kill_rate 时按比例分摊，确保 overall_score 仍归一到 [0, 100]。

## 总分公式

```
ad_score = min(100, (assertion_density / 2.0) * 100)
wr_score = (1 - weak_ratio) * 100
dr_score = (1 - duplicate_ratio) * 100
kr_score = kill_rate * 100  # null 时不计

overall_score = w_ad * ad_score
              + w_wr * wr_score
              + w_dr * dr_score
              + w_kr * kr_score
```

## 阈值与阻断行为

- 默认阈值 `60`
- overall < threshold → stdout 增加 `HEALTH_BELOW_THRESHOLD=1`
- **不阻断 exit code**（评分工具不阻断 CI）
- 配置在 `autopilot.config.yaml` 之 `test_health.thresholds`
