> [English](configuration.md) | 中文

# 配置参考

> `.claude/autopilot.config.yaml` 完整 YAML 字段参考。

## 顶层字段

| 字段 | 类型 | 必需 | 默认值 | 说明 |
|------|------|------|--------|------|
| `version` | string | 是 | — | 配置 schema 版本（当前为 `"1.0"`） |
| `services` | object | 是 | — | 健康检查服务定义 |
| `phases` | object | 是 | — | 各阶段配置 |
| `test_suites` | object | 是 | — | 测试套件定义 |
| `test_pyramid` | object | 推荐 | 见下文 | 测试分布阈值 |
| `gates` | object | 推荐 | 见下文 | 用户确认门禁 |
| `context_management` | object | 推荐 | 见下文 | Git 与上下文保护设置 |
| `async_quality_scans` | object | 可选 | 见下文 | Phase 6→7 质量扫描配置 |
| `brownfield_validation` | object | 可选 | 见下文 | 棕地漂移检测（需手动启用） |
| `default_mode` | string | 否 | `"full"` | 默认执行模式：`"full"`、`"lite"` 或 `"minimal"` |
| `background_agent_timeout_minutes` | number | 否 | `30` | 所有后台 Agent 的硬超时（分钟）（Phase 2/3/6.5/7 知识提取） |
| `project_context` | object | 推荐 | 见下文 | 子 Agent 分发的项目特定上下文（由 init 自动检测） |

## `services`

每个服务条目：

| 字段 | 类型 | 必需 | 说明 |
|------|------|------|------|
| `health_url` | string | 是 | 健康检查 URL（必须以 `http://` 或 `https://` 开头） |
| `name` | string | 否 | 服务显示名称 |

```yaml
services:
  backend:
    health_url: "http://localhost:8080/actuator/health"
    name: "Backend Service"
  frontend:
    health_url: "http://localhost:5173/"
    name: "Frontend Dev Server"
```

## `phases`

### `phases.requirements`

| 字段 | 类型 | 必需 | 默认值 | 说明 |
|------|------|------|--------|------|
| `agent` | string | 是 | — | 需求分析的子 Agent 类型 |
| `min_qa_rounds` | number | 否 | `1` | 确认前的最少问答轮数 |
| `mode` | string | 否 | `"structured"` | `"structured"` 或 `"socratic"` — socratic 模式使用 6 步挑战式提问 |
| `auto_scan.enabled` | boolean | 否 | `true` | 启用项目结构自动扫描以生成引导文档 |
| `auto_scan.max_depth` | number | 否 | `2` | 模块布局的目录树扫描深度 |
| `research.enabled` | boolean | 否 | `true` | 在讨论前启用研究 Agent 进行技术可行性分析 |
| `research.agent` | string | 否 | `"Explore"` | 研究用子 Agent 类型（Explore 快速且只读） |
| `complexity_routing.enabled` | boolean | 否 | `true` | 启用自动复杂度评估和讨论深度路由 |
| `complexity_routing.thresholds.small` | number | 否 | `2` | "小型"复杂度的最大文件数（快速确认模式） |
| `complexity_routing.thresholds.medium` | number | 否 | `5` | "中型"复杂度的最大文件数（标准讨论） |

### `phases.testing`

| 字段 | 类型 | 必需 | 默认值 | 说明 |
|------|------|------|--------|------|
| `agent` | string | 是 | — | 测试设计的子 Agent 类型 |
| `instruction_files` | array | 否 | `[]` | 测试设计指令文件路径 |
| `reference_files` | array | 否 | `[]` | 测试设计参考文件路径 |
| `gate.min_test_count_per_type` | number | 是 | — | 每种类型的最少测试数（第 3 层阈值） |
| `gate.required_test_types` | array | 是 | — | 必需的测试类型（如 `[unit, api, e2e, ui]`） |

### `phases.implementation`

| 字段 | 类型 | 必需 | 默认值 | 说明 |
|------|------|------|--------|------|
| `instruction_files` | array | 否 | `[]` | 实现阶段指令文件路径 |
| `serial_task.max_retries_per_task` | number | 是 | 3 | 任务失败时的最大重试次数 |
| `wall_clock_timeout_hours` | number | 否 | `2` | Phase 5 挂钟超时时间（小时，支持小数，如 `0.5`） |
| `tdd_mode` | boolean | 否 | `false` | 启用 TDD RED-GREEN-REFACTOR 循环（仅 full 模式） |
| `tdd_refactor` | boolean | 否 | `true` | 在 TDD 循环中包含 REFACTOR 步骤 |
| `tdd_test_command` | string | 否 | `""` | 覆盖 TDD 的测试命令（为空时使用 test_suites） |
| `worktree.enabled` | boolean | 否 | `false` | 启用每个任务的 git worktree 隔离 |
| `parallel.enabled` | boolean | 否 | `false` | 启用 Phase 5 并行 Agent Team 执行 |
| `parallel.max_agents` | number | 否 | `8` | 最大并行 Agent 数量（建议 2-4） |
| `parallel.dependency_analysis` | boolean | 否 | `true` | 是否自动分析 task 依赖关系 |

### `phases.reporting`

| 字段 | 类型 | 必需 | 默认值 | 说明 |
|------|------|------|--------|------|
| `instruction_files` | array | 否 | `[]` | 报告阶段指令文件路径 |
| `format` | string | 否 | `"allure"` | 报告格式：`"allure"` 或 `"custom"` |
| `report_commands.html` | string | 否 | — | HTML 报告生成命令 |
| `report_commands.markdown` | string | 否 | — | Markdown 报告生成命令 |
| `report_commands.allure_generate` | string | 否 | — | Allure 报告生成命令 |
| `coverage_target` | number | 是 | — | 目标测试覆盖率百分比 (0-100) |
| `zero_skip_required` | boolean | 是 | — | 是否要求零跳过测试 |

### `phases.code_review`

| 字段 | 类型 | 必需 | 默认值 | 说明 |
|------|------|------|--------|------|
| `enabled` | boolean | 否 | `true` | 是否启用 Phase 6.5 代码审查 |
| `auto_fix_minor` | boolean | 否 | `false` | 是否自动修复 minor findings |
| `block_on_critical` | boolean | 否 | `true` | critical findings 是否阻断流水线 |
| `skip_patterns` | array | 否 | `["*.md", "*.json", "openspec/**"]` | 跳过审查的文件模式 |

## `test_pyramid`

第 2 层（Hook）执行宽松下限；第 3 层（AI 门禁）执行严格配置值。Hook 下限可通过 `test_pyramid.hook_floors` 配置。

| 字段 | 类型 | 默认值 | Hook 下限默认值 | 说明 |
|------|------|--------|----------------|------|
| `min_unit_pct` | number | `50` | `30` | 最低单元测试百分比 |
| `max_e2e_pct` | number | `20` | `40` | 最高 E2E 测试百分比 |
| `min_total_cases` | number | `20` | `10` | 最少测试用例总数 |

### `test_pyramid.hook_floors`

第 2 层 Hook 下限阈值的可选覆盖。这些是 `post-task-validator.sh` 执行的宽松最低值。Hook 下限不得比第 3 层严格阈值更严格（由 `validate-config.sh` 交叉验证）。

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `min_unit_pct` | number | `30` | Hook 下限：最低单元测试百分比 |
| `max_e2e_pct` | number | `40` | Hook 下限：最高 E2E 测试百分比 |
| `min_total_cases` | number | `10` | Hook 下限：最少测试用例总数 |
| `min_change_coverage_pct` | number | `80` | Hook 下限：最低变更覆盖率百分比 |

```yaml
test_pyramid:
  min_unit_pct: 50     # Layer 3 strict (config)
  max_e2e_pct: 20      # Layer 3 strict (config)
  min_total_cases: 20   # Layer 3 strict (config)
  hook_floors:          # Layer 2 lenient (configurable)
    min_unit_pct: 30
    max_e2e_pct: 40
    min_total_cases: 10
    min_change_coverage_pct: 80
```

## `gates`

### `gates.user_confirmation`

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `after_phase_1` | boolean | `true` | 需求阶段后暂停等待用户审查 |
| `after_phase_3` | boolean | `false` | 设计生成后暂停 |
| `after_phase_4` | boolean | `false` | 测试设计后暂停 |

## `context_management`

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `git_commit_per_phase` | boolean | `true` | 每个阶段后自动 git fixup 提交 |
| `autocompact_pct` | number | `80` | 推荐的 `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` 值 |
| `squash_on_archive` | boolean | `true` | Phase 7 归档时自动 squash fixup 提交 |

## `brownfield_validation`

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `enabled` | boolean | `false` | 启用漂移检测（现有代码库需手动启用） |
| `strict_mode` | boolean | `false` | `true`：漂移时阻断；`false`：仅警告 |
| `ignore_patterns` | array | `["*.test.*", "*.spec.*", "__mocks__/**"]` | 忽略的文件模式 |

## `model_routing`（v5.3 新增）

模型路由配置，控制每个阶段使用的 AI 模型档位。支持旧格式和新格式。

### 旧格式（向后兼容）

```yaml
model_routing:
  phase_1: heavy     # heavy=深度推理 → deep/opus
  phase_2: light     # light=机械性操作 → standard/sonnet
  phase_5: auto      # auto=继承父会话模型，不覆盖
```

### 新格式（推荐）

```yaml
model_routing:
  enabled: true
  default_subagent_model: sonnet
  fallback_model: sonnet
  phases:
    phase_1:
      tier: deep
      model: opus
      effort: high
    phase_5:
      tier: deep
      model: opus
      effort: high
      escalate_on_failure_to: deep
```

### 字段说明

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `enabled` | boolean | `true` | 是否启用模型路由 |
| `default_session_model` | string | — | 主线程默认模型（如 `opusplan`） |
| `default_subagent_model` | string | `sonnet` | 子 Agent 默认模型 |
| `fallback_model` | string | `sonnet` | 模型不可用时的兜底模型 |
| `phases` | object | — | 每个阶段的模型配置 |

### Phase 级字段

| 字段 | 类型 | 说明 |
|------|------|------|
| `tier` | string | 模型档位：`fast` / `standard` / `deep` / `auto` |
| `model` | string | 具体模型：`haiku` / `sonnet` / `opus` / `opusplan` |
| `effort` | string | 推理深度：`low` / `medium` / `high` |
| `escalate_on_failure_to` | string | 失败时升级目标（如 `deep`） |

### Tier 映射表

| tier | model | effort | 适用场景 |
|------|-------|--------|----------|
| `fast` | haiku | low | 机械性操作（OpenSpec、FF、报告） |
| `standard` | sonnet | medium | 代码实施、常规分析 |
| `deep` | opus | high | 需求分析、测试设计、关键重试 |

### 升级策略

- `fast` 连续失败 1 次 → 升级到 `standard`
- `standard` 连续失败 2 次或 critical 任务 → 升级到 `deep`
- `deep` 仍失败 → 不自动升级，转人工决策

## `project_context`

由 `autopilot-init` 自动检测的项目特定上下文。Dispatch 动态将这些值注入子 Agent 提示词，**大多数情况下无需单独的指令文件**。

### `project_context.project_structure`

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `backend_dir` | string | `""` | 后端源码目录（如 `"backend"`） |
| `frontend_dir` | string | `""` | 前端源码目录（如 `"frontend/web-app"`） |
| `node_dir` | string | `""` | Node 服务目录（如 `"node"`） |
| `test_dirs.unit` | string | `""` | 单元测试目录路径 |
| `test_dirs.api` | string | `""` | API 测试目录路径 |
| `test_dirs.e2e` | string | `""` | E2E 测试目录路径 |
| `test_dirs.ui` | string | `""` | UI 测试目录路径 |

### `project_context.test_credentials`

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `username` | string | `""` | 测试账号用户名。为空 → Phase 1 自动扫描发现 |
| `password` | string | `""` | 测试账号密码。为空 → Phase 1 自动扫描发现 |
| `login_endpoint` | string | `""` | 登录 API 端点（如 `"POST /api/auth/login"`） |

> **安全提示**：这些仅为测试/开发凭据。请勿使用生产凭据。

### `project_context.playwright_login`

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `steps` | string | `""` | 多行登录流程描述（从 Login 组件自动检测） |
| `known_testids` | array | `[]` | Login 组件中发现的 data-testid 属性 |

> 所有 `project_context` 字段均为**可选**。空字段在运行时由 Phase 1 自动扫描 + 研究 Agent 补充。

## `routing_overrides`（Phase 1 自动生成, v4.2）

Phase 1 完成后自动写入 checkpoint，供 L2 Hook 在后续阶段读取。**无需手动配置**。

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `requirement_type` | string\|array | `"feature"` | 需求分类: `"feature"`, `"bugfix"`, `"refactor"`, `"chore"`, 或数组 `["feature","bugfix"]` |
| `sad_path_min_pct` | number | `20` | Sad path 测试最低比例 (bugfix 自动提升至 40) |
| `change_coverage_min_pct` | number | `80` | 变更覆盖率最低值 (bugfix/refactor 自动提升至 100) |
| `require_reproduction_test` | boolean | `false` | 是否要求复现测试 (bugfix 自动启用) |
| `require_behavior_preservation_test` | boolean | `false` | 是否要求行为保持测试 (refactor 自动启用) |

> `routing_overrides` 存储在 Phase 1 checkpoint (`phase-1-requirements.json`) 中，不是 `autopilot.config.yaml` 的字段。记录在此是因为 L2 Hook 的验证逻辑依赖它。

## `code_constraints` (v4.2)

项目级代码约束，由 L2 Hook (`unified-write-edit-check.sh`, v5.1) 在 Write/Edit 时强制执行。

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `forbidden_files` | array | `[]` | 禁止修改的文件路径列表 (支持 glob，如 `["*.lock", "package-lock.json"]`) |
| `forbidden_patterns` | array | `[]` | 禁止出现的代码模式 (正则，如 `["TODO", "FIXME", "HACK"]`) |
| `allowed_dirs` | array | `[]` | 允许写入的目录白名单（为空则不限制） |

```yaml
code_constraints:
  forbidden_files:
    - "package-lock.json"
    - "*.lock"
  forbidden_patterns:
    - "TODO"
    - "FIXME"
    - "HACK"
    - "console\\.log"
  allowed_dirs:
    - "src/"
    - "tests/"
```

> `forbidden_patterns` 中的 `TODO/FIXME/HACK` 由 `unified-write-edit-check.sh` (v5.1) 确定性拦截，不依赖 AI 判断。

## GUI 与事件总线 (v5.0.8)

GUI 大盘通过 `autopilot-server.ts` 提供双模服务，无需在 `autopilot.config.yaml` 中配置。

### 服务器命令行参数

```bash
bun run runtime/server/autopilot-server.ts [options]
```

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `--project-root` | `.` | 项目根目录，用于事件文件发现 |
| `--no-open` | `false` | 启动时不自动打开浏览器 |
| `--events-file` | `logs/events.jsonl` | 事件文件路径 |

> **注意**: HTTP 端口 (9527) 和 WebSocket 端口 (8765) 为源码中的硬编码常量，不支持通过命令行参数配置。如遇端口冲突，需终止已有进程后重启。

### 端口映射

| 协议 | 端口 | 用途 |
|------|------|------|
| HTTP | 9527 | Vite 构建产出的静态资源（三栏布局 GUI） |
| WebSocket | 8765 | 实时事件推送 + decision_ack 回传 |

> GUI 为可选组件，不影响 CLI 模式下的功能。

## `async_quality_scans`

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `timeout_minutes` | number | `10` | 扫描完成的硬超时 |

每种扫描类型（`contract_testing`、`performance_audit`、`visual_regression`、`mutation_testing`）：

| 字段 | 类型 | 说明 |
|------|------|------|
| `check_command` | string | 检查工具是否已安装的命令 |
| `install_command` | string | 安装工具的命令 |
| `command` | string | 运行扫描的命令 |
| `threshold` | string/number | 通过阈值 |

## `test_suites`

每个测试套件条目：

| 字段 | 类型 | 必需 | 说明 |
|------|------|------|------|
| `command` | string | 是 | 运行测试套件的命令 |
| `type` | string | 是 | 以下之一：`unit`、`integration`、`e2e`、`ui`、`typecheck` |
| `allure` | string | 是 | 以下之一：`pytest`、`playwright`、`junit_xml`、`none` |
| `allure_post` | string | 否 | 后处理命令（仅当 `allure=junit_xml` 时使用） |

```yaml
test_suites:
  backend_unit:
    command: "cd backend && ./gradlew test"
    type: unit
    allure: junit_xml
    allure_post: 'cp -r backend/build/test-results/test/*.xml "$ALLURE_RESULTS_DIR/"'
  api_test:
    command: "python3 -m pytest tests/api/ -v"
    type: integration
    allure: pytest
  e2e:
    command: "npx playwright test"
    type: e2e
    allure: playwright
```

## Schema 验证

运行 `validate-config.sh` 检查配置：

```bash
bash plugins/spec-autopilot/runtime/scripts/validate-config.sh /path/to/project
```

输出：
```json
{
  "valid": true,
  "missing_keys": [],
  "type_errors": [],
  "range_errors": [],
  "cross_ref_warnings": [],
  "warnings": []
}
```

### 验证层级

| 层级 | 检查内容 | 影响 `valid` |
|------|---------|-------------|
| **必需字段** | 顶级和嵌套 key 存在性 | 是 — `valid: false` |
| **类型验证** | 字段值的数据类型（string/number/boolean） | 是 — `valid: false` |
| **范围验证** | 数值是否在合理范围内 | 否 — 仅 `range_errors` 非空 |
| **交叉引用** | 字段间逻辑一致性 | 否 — 仅 `cross_ref_warnings` 非空 |
| **推荐字段** | 可选但建议配置的字段 | 否 — 仅 `warnings` 非空 |

### 类型验证规则

| 字段路径 | 期望类型 |
|----------|---------|
| `version` | string |
| `phases.requirements.auto_scan.enabled` | boolean |
| `phases.requirements.auto_scan.max_depth` | number |
| `phases.requirements.research.enabled` | boolean |
| `phases.requirements.research.agent` | string |
| `phases.requirements.complexity_routing.enabled` | boolean |
| `phases.requirements.complexity_routing.thresholds.small` | number |
| `phases.requirements.complexity_routing.thresholds.medium` | number |
| `phases.implementation.serial_task.max_retries_per_task` | number |
| `phases.reporting.coverage_target` | number |
| `phases.code_review.enabled` | boolean |
| `phases.implementation.parallel.enabled` | boolean |
| `phases.implementation.parallel.max_agents` | number |
| `phases.requirements.min_qa_rounds` | number |
| `phases.reporting.zero_skip_required` | boolean |
| `test_pyramid.min_unit_pct` | number |
| `test_pyramid.max_e2e_pct` | number |
| `test_pyramid.min_total_cases` | number |
| `phases.implementation.wall_clock_timeout_hours` | number |
| `phases.implementation.tdd_mode` | boolean |
| `phases.implementation.tdd_refactor` | boolean |
| `phases.implementation.tdd_test_command` | string |
| `test_pyramid.hook_floors.min_unit_pct` | number |
| `test_pyramid.hook_floors.max_e2e_pct` | number |
| `test_pyramid.hook_floors.min_total_cases` | number |
| `test_pyramid.hook_floors.min_change_coverage_pct` | number |
| `default_mode` | string |
| `code_constraints.forbidden_files` | array |
| `code_constraints.forbidden_patterns` | array |
| `code_constraints.allowed_dirs` | array |
| `background_agent_timeout_minutes` | number |

### 范围验证规则

| 字段路径 | 范围 |
|----------|------|
| `phases.testing.gate.min_test_count_per_type` | [1, 100] |
| `phases.implementation.serial_task.max_retries_per_task` | [1, 10] |
| `phases.reporting.coverage_target` | [0, 100] |
| `test_pyramid.min_unit_pct` | [0, 100] |
| `test_pyramid.max_e2e_pct` | [0, 100] |
| `phases.implementation.parallel.max_agents` | [1, 10] |
| `async_quality_scans.timeout_minutes` | [1, 120] |
| `phases.requirements.auto_scan.max_depth` | [1, 5] |
| `phases.requirements.complexity_routing.thresholds.small` | [1, 20] |
| `phases.requirements.complexity_routing.thresholds.medium` | [2, 50] |
| `test_pyramid.min_total_cases` | [1, 1000] |
| `phases.implementation.wall_clock_timeout_hours` | [0.1, 24] |
| `test_pyramid.hook_floors.min_unit_pct` | [0, 100] |
| `test_pyramid.hook_floors.max_e2e_pct` | [0, 100] |
| `test_pyramid.hook_floors.min_total_cases` | [1, 1000] |
| `test_pyramid.hook_floors.min_change_coverage_pct` | [0, 100] |
| `background_agent_timeout_minutes` | [1, 120] |

### 交叉引用检查

| 检查项 | 描述 |
|--------|------|
| test_pyramid 总和 | `min_unit_pct + max_e2e_pct` 不超过 100% |
| serial_task 一致性 | max_retries_per_task 应 ≥ 1 |
| parallel 一致性 | `enabled=true` 时 `max_agents` 应 ≥ 2 |
| coverage 一致性 | `coverage_target=0` 且 `zero_skip_required=true` 可能为误配 |
| complexity_routing 一致性 | `thresholds.small` 必须 < `thresholds.medium` |

必需 key 检查：
- 顶层：`version`、`services`、`phases`、`test_suites`
- 嵌套：`phases.requirements.agent`、`phases.testing.agent`、`phases.testing.gate.*`、`phases.implementation.serial_task.*`、`phases.reporting.coverage_target`、`phases.reporting.zero_skip_required`
