# Config Schema 与模板

> 本文件由 autopilot-setup SKILL.md 引用。包含配置文件模板和 schema 验证规则。

## 配置模板

```yaml
version: "1.0"
default_mode: "full"             # 执行模式默认值：full(默认)/lite/minimal

services:
  # 自动检测到的服务
  backend:
    health_url: "http://localhost:{detected_port}/actuator/health"
    name: "后端服务"
  frontend:
    health_url: "http://localhost:{detected_port}/"
    name: "前端服务"

phases:
  requirements:
    agent: "business-analyst"
    min_qa_rounds: 1
    max_rounds: 15             # 硬性安全阀：讨论最大轮数（强制结束）
    soft_warning_rounds: 8     # 软性提醒轮次：提示用户当前清晰度
    clarity_threshold: 0.80    # 清晰度退出阈值（0.0-1.0）
    clarity_threshold_overrides:
      small: 0.70              # small 复杂度清晰度阈值（宽松）
      medium: 0.80             # medium 复杂度清晰度阈值（标准）
      large: 0.85              # large 复杂度清晰度阈值（严格）
    challenge_agents:
      enabled: true            # 是否启用挑战代理机制
      contrarian_after_round: 4    # 反面论证代理激活轮次
      simplifier_after_round: 6    # 简化者代理激活轮次
      simplifier_scope_threshold: 5  # scope 条目超过此数才激活简化者
      ontologist_after_round: 8    # 本体论代理激活轮次
    one_question_per_round: true   # Medium/Large 一次一问（默认开启）
    mode: "structured"         # structured | socratic (苏格拉底模式深化需求)
    auto_scan:
      enabled: true
      max_depth: 2
    research:
      enabled: true
      agent: "general-purpose"
      web_search:
        enabled: true            # v3.3.7: 默认 true（默认搜索），规则引擎判定跳过
        max_queries: 5           # 最大搜索次数
        search_policy:
          default: search        # search | skip — 默认搜索，跳过是例外
          skip_keywords:         # 需求含这些关键词时允许跳过（需全部满足 skip_when_ALL_true）
            - "修复"
            - "fix"
            - "重构"
            - "refactor"
            - "样式"
            - "style"
          force_search_keywords: # 需求含任一关键词时强制搜索（覆盖 skip 判定）
            - "竞品"
            - "产品"
            - "UX"
            - "交互"
            - "体验"
            - "新功能"
            - "升级"
            - "迁移"
            - "安全"
            - "auth"
            - "加密"
        focus_areas:             # 搜索聚焦领域
          - competitive_analysis
          - best_practices
          - similar_implementations
          - dependency_evaluation
    complexity_routing:
      enabled: true
      thresholds:
        small: 2
        medium: 5
  openspec:
    agent: "Plan"              # Phase 2/3 使用 Plan agent（v3.4.0）
    instruction_files: []      # 可选：覆盖内置 OpenSpec 创建/FF 指令
    reference_files: []        # 可选：项目自定义参考文件
  testing:
    agent: "qa-expert"
    instruction_files: []      # 可选：项目自定义指令覆盖插件内置规则
    reference_files: []        # 可选：项目自定义参考文件
    gate:
      min_test_count_per_type: 5
      required_test_types: [unit, api, e2e, ui]
  implementation:
    instruction_files: []      # 可选：项目自定义指令覆盖插件内置规则
    serial_task:
      max_retries_per_task: 3  # 单个 task 最大重试次数（1-10）
    wall_clock_timeout_hours: 2  # Phase 5 超时小时数（默认 2h，支持小数如 0.5）
    tdd_mode: false            # true: 启用 TDD RED-GREEN-REFACTOR（仅 full 模式生效）
    tdd_refactor: true         # true: 包含 REFACTOR 步骤
    tdd_test_command: ""       # 可选：覆盖 test_suites 的统一 TDD 测试命令
    worktree:
      enabled: false         # 设为 true 启用 Phase 5 worktree 隔离
    parallel:
      enabled: false         # 设为 true 启用 Phase 5 并行 Agent Team 执行
      max_agents: 8          # 最大并行域数（建议 3-8，上限 10）
      dependency_analysis: true
      domain_detection: "auto"   # auto: 自动发现未配置的顶级目录 | explicit: 仅用 domain_agents
      default_agent: "general-purpose"  # 未匹配域的 fallback Agent
      domain_agents:             # 路径前缀 → Agent 映射（最长前缀匹配，每域 1 Agent）
        "backend/":
          agent: "backend-developer"
        "frontend/":
          agent: "frontend-developer"
        "node/":
          agent: "fullstack-developer"
        # ---- 多技术栈项目示例 ----
        # "services/auth/":           { agent: "java-architect" }
        # "services/payment/":        { agent: "backend-developer" }
        # "services/notification/":   { agent: "backend-developer" }
        # "gateway/":                 { agent: "backend-developer" }
        # "apps/web/":               { agent: "frontend-developer" }
        # "apps/android/":           { agent: "mobile-developer" }
        # "apps/ios/":               { agent: "mobile-developer" }
        # "packages/":               { agent: "fullstack-developer" }
  reporting:
    instruction_files: []      # 可选：项目自定义指令覆盖插件内置规则
    format: "allure"         # allure | custom
    report_commands:
      html: "python tools/report/html_generator.py -i {change_name}"
      markdown: "python tools/report/generator.py -i {change_name}"
      allure_generate: "npx allure generate allure-results -o allure-report --clean"
    coverage_target: 80
    zero_skip_required: true
  code_review:
    enabled: true              # Phase 6.5 代码审查（默认启用）
    auto_fix_minor: false      # 是否自动修复 minor findings
    block_on_critical: true    # critical findings 时是否要求用户显式确认（true: 展示 findings 并要求用户选择忽略/修复/暂停；false: 跳过检查直接自动归档）
    skip_patterns:             # 跳过审查的文件模式
      - "*.md"
      - "*.json"
      - "openspec/**"

test_pyramid:
  min_unit_pct: 50           # 单元测试最低占比（金字塔底层）
  max_e2e_pct: 20            # E2E+UI 测试最高占比（金字塔顶层）
  min_total_cases: 20        # 最少总用例数
  traceability_floor: 80     # v4.0: test_traceability 覆盖率阈值（L2 blocking，默认 80%）
  hook_floors:               # Layer 2 Hook 宽松底线（可选覆盖，默认值见下方）
    min_unit_pct: 30         # Hook 底线：单元测试最低占比（默认 30）
    max_e2e_pct: 40          # Hook 底线：E2E 测试最高占比（默认 40）
    min_total_cases: 10      # Hook 底线：最少总用例数（默认 10）
    min_change_coverage_pct: 80  # Hook 底线：变更覆盖率最低百分比（默认 80）

quality_scans:               # v4.0: Phase 6 真实静态分析工具集成（可选）
  tools:                     # 工具列表，Phase 6 路径 C 按顺序执行
    # - name: typecheck
    #   command: "npx tsc --noEmit"
    #   blocking: true        # true: 失败阻断 Phase 6; false: 仅 warning
    # - name: lint
    #   command: "npx eslint . --max-warnings 0"
    #   blocking: false
    # - name: security
    #   command: "npx audit-ci --moderate"
    #   blocking: true

gates:
  user_confirmation:
    after_phase_1: false     # v6.0: 需求确认后默认自动推进
    after_phase_3: false     # 设计生成后自动继续
    after_phase_4: false     # 测试设计后自动继续

model_routing:                   # 模型路由配置（v5.3 升级为执行级路由）
  # ── 旧格式（向后兼容，仍可用）──
  # phase_1: heavy               # heavy=Opus 级, light=Sonnet 级, auto=继承父进程
  # phase_2: light
  # ...

  # ── 新格式（推荐）──
  enabled: true                  # 是否启用模型路由（false 时退化为默认路由）
  default_session_model: opusplan  # 主线程默认模型
  default_subagent_model: sonnet   # 子 Agent 默认模型
  fallback_model: sonnet           # 模型不可用时的兜底模型
  phases:
    phase_1:
      tier: deep                 # fast/standard/deep/auto
      model: opus                # haiku/sonnet/opus/opusplan
      effort: high               # low/medium/high
    phase_2:
      tier: fast
      model: haiku
      effort: low
    phase_3:
      tier: fast
      model: haiku
      effort: low
    phase_4:
      tier: deep
      model: opus
      effort: high
    phase_5:
      tier: standard
      model: sonnet
      effort: medium
      escalate_on_failure_to: deep  # 失败时升级目标
    phase_6:
      tier: fast
      model: haiku
      effort: low
    phase_7:
      tier: fast
      model: haiku
      effort: low

  # ── 兼容映射 ──
  # heavy -> deep (opus)
  # light -> standard (sonnet)
  # auto  -> 继承父会话模型（resolver 输出 selected_tier=auto, dispatch 不覆盖模型）

  # ── 自动升级策略（内置，无需配置）──
  # fast 连续失败 1 次 → 升级到 standard
  # standard 连续失败 2 次或 critical → 升级到 deep
  # deep 仍失败 → 不自动升级，转人工决策

context_management:
  git_commit_per_phase: true # 每 Phase 完成后自动 git commit checkpoint
  autocompact_pct: 80        # 建议设置 CLAUDE_AUTOCOMPACT_PCT_OVERRIDE
  squash_on_archive: true    # Phase 7 归档时 autosquash fixup commits 为单一 commit

brownfield_validation:
  enabled: true                # v4.0: 默认开启漂移检测（greenfield 项目 Phase 0 自动关闭）
  strict_mode: false           # true: block; false: warning only
  ignore_patterns: ["*.test.*", "*.spec.*", "__mocks__/**"]

background_agent_timeout_minutes: 30  # 后台 Agent 通用硬超时（分钟），覆盖 Phase 2/3/6.5/7 知识提取等

async_quality_scans:
  timeout_minutes: 10          # 硬超时（分钟），超时后标记 timeout 继续后续步骤
  contract_testing:
    check_command: ""            # 工具检测命令（缺失则自动安装）
    install_command: ""          # 自动安装命令
    command: ""                  # 执行命令
    threshold: "all_pass"
  performance_audit:
    check_command: "npx lhci --version"
    install_command: "pnpm add -D @lhci/cli"
    command: "npx lhci autorun"
    threshold: 80
  visual_regression:
    check_command: ""
    install_command: ""
    command: ""
    threshold: "0_diff"
  mutation_testing:
    check_command: ""
    install_command: ""
    command: ""
    threshold: 60
  security_audit:                    # v2.4.0 新增：安全审计扫描
    check_command: "bash ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/check-security-tools-install.sh"
    install_command: ""              # 由检测脚本的 install_commands 动态提供
    command: ""                      # 由检测脚本的 recommended_scans 动态决定
    threshold: "0_critical"          # 0 个 critical 漏洞
    block_on_critical: false         # true: critical 发现阻断归档

# === 质量扫描 Agent 映射（v3.4.0 新增）===
# quality_scans_agents:
#   silent_failure:    "pr-review-toolkit:silent-failure-hunter"
#   type_design:       "pr-review-toolkit:type-design-analyzer"
#   comment_accuracy:  "pr-review-toolkit:comment-analyzer"
#   code_simplicity:   "pr-review-toolkit:code-simplifier"

# === 代码约束（v2.4.0 新增，可选）===
# code_constraints:
#   forbidden_files: []              # 禁止创建的文件（如 vite.config.js）
#   forbidden_patterns: []           # 禁止出现在代码中的模式
#   max_file_lines: 800              # 单文件最大行数
#   allowed_dirs: []                 # 允许修改的目录范围
#   semantic_rules:                  # v3.3.0 新增：语义规则（dispatch 注入子 Agent prompt）
#     - rule: "描述规则内容"
#       scope: "backend/"            # 适用目录范围
#       severity: "must"             # must | should | prefer

test_suites:
  # 自动检测到的测试套件

# === 项目上下文（自动检测，dispatch 动态注入子 Agent prompt） ===
project_context:
  project_structure:
    backend_dir: "{detected}"      # 如 "backend"
    frontend_dir: "{detected}"     # 如 "frontend/web-app"
    node_dir: "{detected}"         # 如 "node"，无则为空
    test_dirs:
      unit: "{detected}"           # 如 "backend/src/test/java"
      api: "{detected}"            # 如 "tests/api"
      e2e: "{detected}"            # 如 "tests/e2e"
      ui: "{detected}"             # 如 "tests/ui"

  test_credentials:                # 测试凭据（dispatch 自动注入，无需 reference 文件）
    username: "{detected}"         # 从 .env/conftest.py/fixtures 检测
    password: "{detected}"         # 未检测到则提示用户填写
    login_endpoint: "{detected}"   # 如 "POST /api/auth/login"

  playwright_login:                # Playwright 登录流程（检测到 Playwright 时生成）
    steps: |
      # 自动检测的登录步骤（从 Login 组件的 data-testid 推导）
      # 示例:
      # 1. goto /#/login
      # 2. click [data-testid="switch-password-login"]
      # 3. fill [data-testid="username"]
      # 4. fill [data-testid="password"]
      # 5. click [data-testid="login-btn"]
      # 6. waitForURL /#/dashboard
    known_testids: []              # 从 Login 组件扫描到的 data-testid 列表
```

## Schema 验证规则

写入后**必须**验证配置完整性，检查以下必须存在的 key：

```
必须的顶级 key:
  - version (string)
  - services (object, 至少一个服务)
  - phases (object)
  - test_suites (object, 至少一个套件)

phases 内必须的 key:
  - phases.requirements.agent (string)
  - phases.testing.agent (string)
  - phases.testing.gate.min_test_count_per_type (number, >= 1)
  - phases.testing.gate.required_test_types (array, non-empty)
  - phases.implementation.serial_task.max_retries_per_task (number, >= 1)
  - phases.reporting.coverage_target (number, 0-100)
  - phases.reporting.zero_skip_required (boolean)

每个 service 必须有:
  - health_url (string, 以 http:// 或 https:// 开头)

每个 test_suite 必须有:
  - command (string, non-empty)
  - type (string, one of: unit, integration, e2e, ui, typecheck)
  - allure (string, one of: pytest, playwright, junit_xml, none)
  - allure_post (string, optional, only when allure=junit_xml)
```

如果校验失败 → 输出缺失/错误的 key 列表，AskUserQuestion 要求用户修正后重试。

