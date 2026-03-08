# Config Schema 与模板

> 本文件由 autopilot-init SKILL.md 引用。包含配置文件模板和 schema 验证规则。

## 配置模板

```yaml
version: "1.0"

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
    mode: "structured"         # structured | socratic (苏格拉底模式深化需求)
    auto_scan:
      enabled: true
      max_depth: 2
    research:
      enabled: true
      agent: "Explore"
      web_search:
        enabled: true            # standard/deep depth 默认 true，basic 自动跳过
        max_queries: 5           # 最大搜索次数
        focus_areas:             # 搜索聚焦领域
          - best_practices
          - similar_implementations
          - dependency_evaluation
    complexity_routing:
      enabled: true
      thresholds:
        small: 2
        medium: 5
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
      enabled: true
      max_iterations: 30
      fallback_enabled: true
    worktree:
      enabled: false         # 设为 true 启用 Phase 5 worktree 隔离
    parallel:
      enabled: false         # 设为 true 启用 Phase 5 并行 Agent Team 执行
      max_agents: 3          # 最大并行 Agent 数量（建议 2-4）
      dependency_analysis: true  # 自动分析 task 依赖关系
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
    block_on_critical: true    # critical findings 是否阻断
    skip_patterns:             # 跳过审查的文件模式
      - "*.md"
      - "*.json"
      - "openspec/**"

test_pyramid:
  min_unit_pct: 50           # 单元测试最低占比（金字塔底层）
  max_e2e_pct: 20            # E2E+UI 测试最高占比（金字塔顶层）
  min_total_cases: 20        # 最少总用例数

gates:
  user_confirmation:
    after_phase_1: true      # 需求确认后暂停，让用户审查
    after_phase_3: false     # 设计生成后自动继续
    after_phase_4: false     # 测试设计后自动继续

model_routing:                   # 每阶段模型等级提示（heavy=Opus 级, light=Sonnet 级, auto=继承父进程）
  phase_1: heavy                 # 需求分析需要深度推理
  phase_2: light                 # OpenSpec 创建是机械性操作
  phase_3: light                 # FF 生成是模板化操作
  phase_4: heavy                 # 测试设计需要创造力
  phase_5: heavy                 # 代码实施需要完整能力
  phase_6: light                 # 报告生成是机械性操作
  phase_7: light                 # 汇总较简单

context_management:
  git_commit_per_phase: true # 每 Phase 完成后自动 git commit checkpoint
  autocompact_pct: 80        # 建议设置 CLAUDE_AUTOCOMPACT_PCT_OVERRIDE
  squash_on_archive: true    # Phase 7 归档时 autosquash fixup commits 为单一 commit

brownfield_validation:
  enabled: false               # 存量项目手动开启漂移检测
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
    check_command: "bash ${CLAUDE_PLUGIN_ROOT}/scripts/check-security-tools-install.sh"
    install_command: ""              # 由检测脚本的 install_commands 动态提供
    command: ""                      # 由检测脚本的 recommended_scans 动态决定
    threshold: "0_critical"          # 0 个 critical 漏洞
    block_on_critical: false         # true: critical 发现阻断归档

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

