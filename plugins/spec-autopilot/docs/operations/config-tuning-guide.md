# 配置调优指南

> 按项目类型和团队需求优化 `.claude/autopilot.config.yaml`。

## 配置分层概念

spec-autopilot 的 60+ 配置字段分为三层，大多数场景只需关注 Level 1：

| 层级 | 字段数 | 适用场景 |
|------|--------|---------|
| **Level 1 — 核心** | ~5 | 首次使用、快速开始 |
| **Level 2 — 团队** | ~15 | 团队级定制、流程调优 |
| **Level 3 — 专家** | ~40 | 深度定制、Hook 阈值微调 |

## Level 1: 核心配置（必须设置）

```yaml
version: "1.0"
default_mode: "full"        # full | lite | minimal

services:
  backend:
    name: "后端服务"
    health_url: "http://localhost:3000/health"

test_suites:
  unit:
    command: "npm test"
    type: "unit"
```

## 按项目类型推荐配置

### 场景 A: 大型企业项目（Strict）

```yaml
default_mode: "full"
phases:
  requirements:
    min_qa_rounds: 3
    mode: "socratic"
  testing:
    gate:
      min_test_count_per_type: 5
  implementation:
    tdd_mode: true
    parallel:
      enabled: true
      max_agents: 4
    wall_clock_timeout_hours: 4
test_pyramid:
  min_unit_pct: 60
  max_e2e_pct: 15
  traceability_floor: 90
brownfield_validation:
  enabled: true
  strict_mode: true
```

### 场景 B: 中型团队项目（Moderate，推荐）

```yaml
default_mode: "full"
phases:
  requirements:
    min_qa_rounds: 1
  testing:
    gate:
      min_test_count_per_type: 3
  implementation:
    tdd_mode: false
    parallel:
      enabled: false
    wall_clock_timeout_hours: 2
test_pyramid:
  min_unit_pct: 50
  max_e2e_pct: 20
  traceability_floor: 80
brownfield_validation:
  enabled: true
  strict_mode: false
```

### 场景 C: 快速原型 / 小项目（Relaxed）

```yaml
default_mode: "lite"
phases:
  requirements:
    min_qa_rounds: 1
  testing:
    gate:
      min_test_count_per_type: 1
  implementation:
    tdd_mode: false
    parallel:
      enabled: false
test_pyramid:
  min_unit_pct: 30
  max_e2e_pct: 40
  traceability_floor: 50
  hook_floors:
    min_unit_pct: 20
    min_total_cases: 5
brownfield_validation:
  enabled: false
```

### 场景 D: TDD 驱动开发

```yaml
default_mode: "full"
phases:
  implementation:
    tdd_mode: true
    tdd_refactor: true
    tdd_test_command: "npm test -- --bail"
test_pyramid:
  min_unit_pct: 70
  traceability_floor: 90
```

TDD 模式下 Phase 4 自动跳过（测试在 Phase 5 per-task 创建），Phase 5 执行 RED-GREEN-REFACTOR 循环。

## 常见调优场景

### 调优 1: 减少不必要的用户确认

```yaml
gates:
  user_confirmation:
    after_phase_1: false   # 跳过需求确认（适合已明确的需求）
    after_phase_3: false
    after_phase_4: false
```

### 调优 2: 大型项目增加超时

```yaml
phases:
  implementation:
    wall_clock_timeout_hours: 6
background_agent_timeout_minutes: 60
async_quality_scans:
  timeout_minutes: 20
```

### 调优 3: 接入真实静态分析工具（v4.0）

```yaml
quality_scans:
  tools:
    - name: typecheck
      command: "npx tsc --noEmit"
      blocking: true
    - name: lint
      command: "npx eslint . --max-warnings 0"
      blocking: false
    - name: security
      command: "npm audit --audit-level=moderate"
      blocking: true
```

### 调优 4: 放宽 Hook 底线阈值

当 Hook 频繁阻断且确认为误报时：

```yaml
test_pyramid:
  hook_floors:
    min_unit_pct: 20       # 从 30 降到 20
    max_e2e_pct: 50        # 从 40 升到 50
    min_total_cases: 5     # 从 10 降到 5
    min_change_coverage_pct: 60  # 从 80 降到 60
```

> 注意：`hook_floors` 是 Layer 2 宽松底线，不应比 `test_pyramid` 顶级阈值更严格。配置验证器会自动检查交叉一致性。

### 调优 5: 禁用联网搜索

```yaml
phases:
  requirements:
    research:
      web_search:
        enabled: false
```

## 配置验证

修改配置后运行验证：

```bash
bash plugins/spec-autopilot/scripts/validate-config.sh
```

输出 JSON 包含：
- `valid`: 是否通过
- `missing_keys`: 缺失的必填字段
- `type_errors`: 类型错误
- `range_errors`: 范围错误
- `cross_ref_warnings`: 交叉引用警告（如 hook_floors 比 gate 更严格）
