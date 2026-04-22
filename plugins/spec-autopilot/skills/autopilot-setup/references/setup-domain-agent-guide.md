# 域级 Agent 配置引导 — Phase 5 并行域 Agent

> 本文件由 `autopilot-setup/SKILL.md` 通过 `**执行前读取**` 引用。
> 包含域级 Agent 推荐映射表、检测映射逻辑、安装机制和用户交互流程。

## Contents

- A. 域级 Agent 推荐映射表
- B. 检测到域的映射逻辑
- C. Agent 安装机制
- D. 用户交互流程（D.1 标准 / D.2 Strict 自动 / D.3 Relaxed 跳过）
- E. Config 写入逻辑

## A. 域级 Agent 推荐映射表

基于社区综合评估（stars、指令深度、域专精度、兼容性），为 Phase 5 并行模式推荐域级专业 Agent：

```
╔═══════════════════════╦═══════════════════════╦════════════╦══════╦═══════════════════════════════════════════╗
║ 域路径前缀             ║ 首选 Agent            ║ 来源       ║ 评分 ║ 选择理由                                  ║
╠═══════════════════════╬═══════════════════════╬════════════╬══════╬═══════════════════════════════════════════╣
║ backend/              ║ backend-developer     ║ VoltAgent  ║ 8/10 ║ API/DB/安全/微服务专精，含性能指标清单      ║
║ frontend/             ║ frontend-developer    ║ VoltAgent  ║ 8/10 ║ React/Vue/Angular+TS strict+无障碍审计     ║
║ node/                 ║ fullstack-developer   ║ VoltAgent  ║ 9/10 ║ DB→API→UI 全链路+类型安全+8 类测试策略     ║
║ infra/ / devops/      ║ devops-engineer       ║ VoltAgent  ║ 8/10 ║ IaC/K8s/CI-CD/监控/DevSecOps 全覆盖       ║
║ shared/ / libs/       ║ executor              ║ OMC        ║ 8/10 ║ 通用执行+3 次升级+lsp 验证+最小差异        ║
║ docs/                 ║ documentation-engineer║ VoltAgent  ║ 8/10 ║ 结构化文档+API 覆盖+多版本管理             ║
║ mobile/               ║ mobile-developer      ║ VoltAgent  ║ 8/10 ║ React Native/Flutter/原生模块+离线同步     ║
║ data/                 ║ data-engineer         ║ VoltAgent  ║ 8/10 ║ ETL/Spark/Kafka/Airflow/数据质量           ║
╚═══════════════════════╩═══════════════════════╩════════════╩══════╩═══════════════════════════════════════════╝

备选 Agent（首选不可用时使用）:
  backend/   → executor (OMC, 7/10)
  frontend/  → designer (OMC, 7/10)
  node/      → executor (OMC, 7/10)
  infra/     → executor (OMC, 7/10)
  shared/    → refactoring-specialist (VoltAgent, 7/10)
  docs/      → writer (OMC, 7/10)
  mobile/    → executor (OMC, 7/10)
  data/      → executor (OMC, 7/10)
```

**来源仓库**:
- **VoltAgent**: `VoltAgent/awesome-claude-code-subagents` (17k+ stars) — 域级专精 Agent 最佳来源
- **OMC**: `Yeachan-Heo/oh-my-claudecode` (27.6k+ stars) — 工程化执行 Agent + 通用 fallback

## B. 检测到域的映射逻辑

利用 Step 1 的 `project_context.project_structure` 检测结果 + 扩展 Glob 扫描，生成域推荐列表：

```
detected_domains = []

# ---- 从 Step 1 检测结果映射（必须执行） ----

IF project_structure.backend_dir != "":
  detected_domains.append({
    prefix: project_structure.backend_dir + "/",   # 如 "backend/" 或 "src/server/"
    category: "backend",
    recommended_agent: "backend-developer",
    source: "VoltAgent",
    fallback_agent: "executor",
    fallback_source: "OMC"
  })

IF project_structure.frontend_dir != "":
  detected_domains.append({
    prefix: project_structure.frontend_dir + "/",  # 如 "frontend/" 或 "frontend/web-app/"
    category: "frontend",
    recommended_agent: "frontend-developer",
    source: "VoltAgent",
    fallback_agent: "designer",
    fallback_source: "OMC"
  })

IF project_structure.node_dir != "":
  detected_domains.append({
    prefix: project_structure.node_dir + "/",      # 如 "node/"
    category: "node",
    recommended_agent: "fullstack-developer",
    source: "VoltAgent",
    fallback_agent: "executor",
    fallback_source: "OMC"
  })

# ---- 扩展目录扫描（Glob 探测） ----

# 基础设施域
FOR dir IN ["infra/", "devops/", "deploy/", "terraform/", ".infrastructure/"]:
  IF Glob("{dir}*") 有匹配文件:
    detected_domains.append({
      prefix: dir,
      category: "infra",
      recommended_agent: "devops-engineer",
      source: "VoltAgent",
      fallback_agent: "executor",
      fallback_source: "OMC"
    })
    BREAK  # 仅取第一个匹配

# 公共库域
FOR dir IN ["shared/", "libs/", "packages/", "common/", "utils/"]:
  IF Glob("{dir}*") 有匹配文件:
    detected_domains.append({
      prefix: dir,
      category: "shared",
      recommended_agent: "executor",
      source: "OMC",
      fallback_agent: "refactoring-specialist",
      fallback_source: "VoltAgent"
    })
    BREAK

# 文档域
FOR dir IN ["docs/", "documentation/"]:
  IF Glob("{dir}*") 有匹配文件:
    detected_domains.append({
      prefix: dir,
      category: "docs",
      recommended_agent: "documentation-engineer",
      source: "VoltAgent",
      fallback_agent: "writer",
      fallback_source: "OMC"
    })
    BREAK

# 移动端域
FOR dir IN ["mobile/", "android/", "ios/", "apps/mobile/", "apps/android/", "apps/ios/"]:
  IF Glob("{dir}*") 有匹配文件:
    detected_domains.append({
      prefix: dir,
      category: "mobile",
      recommended_agent: "mobile-developer",
      source: "VoltAgent",
      fallback_agent: "executor",
      fallback_source: "OMC"
    })
    BREAK

# 数据域
FOR dir IN ["data/", "analytics/", "ml/", "pipeline/", "etl/"]:
  IF Glob("{dir}*") 有匹配文件:
    detected_domains.append({
      prefix: dir,
      category: "data",
      recommended_agent: "data-engineer",
      source: "VoltAgent",
      fallback_agent: "executor",
      fallback_source: "OMC"
    })
    BREAK
```

> **注意**: 路径前缀使用实际检测到的目录名（如 `src/server/` 而非硬编码 `backend/`），确保非标准项目结构也能正确映射。

## C. Agent 安装机制

### VoltAgent 域级 Agent 安装

VoltAgent agent 文件为独立 `.md` 文件，直接下载到 `.claude/agents/`：

```
mkdir -p .claude/agents

# 下载域级 Agent（根据推荐映射表选择的 agent）
FOR each (agent_name) IN selected_agents:
  # Step 1: 尝试从 VoltAgent 仓库下载
  Bash('curl -sfL "https://raw.githubusercontent.com/VoltAgent/awesome-claude-code-subagents/main/agents/{agent_name}.md" -o ".claude/agents/{agent_name}.md"')

  # Step 2: 验证安装
  IF Read(".claude/agents/{agent_name}.md") 包含有效的 frontmatter (name 字段):
    → 输出 "✓ 已安装 {agent_name}"
  ELSE:
    → 输出 "⚠ {agent_name} 安装失败，使用 fallback agent"
    → 如果 fallback agent 是 OMC agent:
        检查 .claude/agents/{fallback}.md 是否已存在（Step 5.3 安装的 OMC agent）
        存在 → 使用 fallback agent
        不存在 → 使用 general-purpose
```

### OMC Agent（shared/libs 域 + 备选）

OMC agent 在 Step 5.3 的 Phase-level 安装中已处理（executor, designer, writer 等）。域级配置直接引用已安装的 OMC agent 名称即可。

### 安装失败回退链

```
VoltAgent 下载失败 → 尝试备选 Agent → 备选也不可用 → general-purpose
```

## D. 用户交互流程

### D.1 标准流程（domain_agents_strategy == "ask"）

```
IF detected_domains 非空:

  展示推荐表格:
  "检测到以下项目域，推荐配置域级专业 Agent（提升 Phase 5 并行执行质量）："

  ╔══════════════════╦═══════════════════════╦════════════╦══════╗
  ║ 域路径前缀        ║ 推荐 Agent            ║ 来源       ║ 评分 ║
  {for each domain in detected_domains}
  ║ {domain.prefix}  ║ {domain.recommended_agent} ║ {domain.source} ║ {score} ║
  {end for}
  ╚══════════════════╩═══════════════════════╩════════════╩══════╝

  AskUserQuestion:
  选项:
  - "安装推荐域 Agent (Recommended)" →
      对每个 detected_domain:
        1. 安装推荐 agent 到 .claude/agents/（Section C 安装机制）
        2. 更新 config domain_agents[prefix].agent = recommended_agent

  - "使用与 Phase 5 相同的 Agent" →
      对每个 detected_domain:
        config domain_agents[prefix].agent = config.phases.implementation.parallel.default_agent
      (全域统一使用 default_agent，如 executor)

  - "自定义配置" →
      对每个 detected_domain 逐个 AskUserQuestion:
        "{prefix} 域使用哪个 Agent？"
        选项: [{recommended_agent} (Recommended), {fallback_agent}, "general-purpose"]

  - "跳过域 Agent 配置" →
      所有 domain_agents 保持 general-purpose

ELSE:
  → 输出 "未检测到多域项目结构，跳过域级 Agent 配置"
```

### D.2 Strict 预设自动流程（domain_agents_strategy == "recommended"）

```
不弹出 AskUserQuestion，直接执行 "安装推荐域 Agent" 路径:
  对每个 detected_domain:
    1. 安装推荐 agent
    2. 更新 domain_agents[prefix].agent = recommended_agent
  输出: "✓ Strict 模式: 已自动安装 {N} 个推荐域 Agent"
```

### D.3 Relaxed 预设跳过（domain_agents_strategy == "skip"）

```
输出: "跳过域 Agent 配置（Relaxed 模式）"
所有 domain_agents 保持 general-purpose
```

## E. Config 写入逻辑

```
写入 .claude/autopilot.config.yaml:

FOR each (domain) IN selected_domains:
  设置 phases.implementation.parallel.domain_agents."{domain.prefix}".agent: "{domain.selected_agent}"

# 移除未检测到的默认域（保持 config 干净）
IF project_structure.backend_dir 未检测到:
  不写入 "backend/" 默认条目（避免空域配置）
同理 frontend_dir / node_dir

# 提示信息
IF 至少一个域使用了非 general-purpose agent:
  输出: "域级 Agent 已配置。启用并行模式后（parallel.enabled: true），Phase 5 将自动使用域级 Agent。"
  IF config.phases.implementation.parallel.enabled == false:
    输出: "提示: 当前并行模式未启用。可编辑 config 设置 parallel.enabled: true 以启用。"
```
