# `install` 模式

## Contents

- Step 1: 检测已安装 Agent
- Step 2: 选择安装方案
- Step 3: 安装 Agent 文件
- Step 3.5: 域级 Agent 安装
- Step 4: 更新配置
- Step 5: 输出结果

## Step 1: 检测已安装 Agent

```
使用 Glob 检查 .claude/agents/*.md 是否存在
统计已安装的 Agent 数量
```

## Step 2: 选择安装方案

通过 AskUserQuestion 展示选项：

```
"选择 Agent 安装方案："

选项:
- "安装推荐 Agent (一键安装)" →
    安装 OMC 全部 8 个首选 Agent:
    analyst, planner, writer, test-engineer,
    executor, qa-tester, code-reviewer, git-master

    安装方式:
    1. 检查 OMC marketplace 是否已添加
    2. Bash('claude plugin marketplace add Yeachan-Heo/oh-my-claudecode') [若未添加]
    3. 通过 plugin install 安装，或直接复制 Agent 文件到 .claude/agents/
    4. 更新 .claude/autopilot.config.yaml 各 phase 的 agent 字段
    5. **工具权限适配（必须）**: 运行
       Bash('python3 ${CLAUDE_PLUGIN_ROOT}/runtime/scripts/adapt-agent-tools.py --project-root "$(pwd)"')
       自动检测所有 phase→agent 的 `disallowedTools` 与所需工具的冲突，
       对冲突 agent fork 到 .claude/agents/{name}.md 并剥离冲突项（如
       analyst/explore 的 Write/Edit、code-reviewer 用于域 agent 时等）。
       幂等、可重复执行；源 marketplace agent 保持不变。

- "按阶段选择 Agent" →
    逐 Phase 展示推荐 + 备选，用户每阶段可选

- "使用通用 Agent" →
    不安装，config 保持 general-purpose
```

## Step 3: 安装 Agent 文件

```
对选定的每个 Agent:
1. 检查 .claude/agents/{name}.md 是否已存在
2. 已存在 → AskUserQuestion 确认覆盖
3. 安装 Agent 定义文件
4. 验证安装: Read(.claude/agents/{name}.md) 检查 frontmatter
```

## Step 3.5: 域级 Agent 安装

在 Phase-level Agent 安装完成后，检查并引导域级 Agent 安装：

```
IF config.phases.implementation.parallel.domain_agents 中已有非 general-purpose agent:
  → 输出 "✓ 已检测到 {N} 个域级 Agent 配置"
  → 跳过

ELSE:
  # 检测项目域（利用 Glob 扫描）
  detected_domains = []
  FOR dir IN ["backend/", "frontend/", "node/", "infra/", "devops/",
              "shared/", "libs/", "packages/", "docs/", "mobile/",
              "android/", "ios/", "data/", "analytics/"]:
    IF Glob("{dir}*") 有匹配文件:
      detected_domains.append(dir)

  IF detected_domains 非空:
    AskUserQuestion: "检测到 {N} 个项目域，是否安装域级专业 Agent？"
    选项:
    - "安装推荐域 Agent (Recommended)" →
        按域推荐映射表安装:
          backend/        → backend-developer (VoltAgent)
          frontend/       → frontend-developer (VoltAgent)
          node/           → fullstack-developer (VoltAgent)
          infra/ / devops/→ devops-engineer (VoltAgent)
          shared/ / libs/ / packages/ → executor (OMC, 已安装)
          docs/           → documentation-engineer (VoltAgent)
          mobile/ / android/ / ios/ → mobile-developer (VoltAgent)
          data/ / analytics/ → data-engineer (VoltAgent)

        VoltAgent Agent 安装方式:
        Bash('curl -sfL "https://raw.githubusercontent.com/VoltAgent/awesome-claude-code-subagents/main/agents/{agent_name}.md" -o ".claude/agents/{agent_name}.md"')
        验证: Read(.claude/agents/{agent_name}.md) 检查 frontmatter
        失败 → 使用 fallback agent（executor/general-purpose）

    - "使用与 Phase 5 相同的 Agent" →
        所有域使用 default_agent（如 executor）

    - "跳过域 Agent" →
        保持 general-purpose

  ELSE:
    → 输出 "未检测到多域项目结构，跳过域级 Agent 安装"
```

## Step 4: 更新配置

```
读取 .claude/autopilot.config.yaml
更新以下字段:
  # Phase 1 BA + 三路调研（四字段独立）
  phases.requirements.agent: "{selected_phase1_ba_agent}"
  phases.requirements.auto_scan.agent: "{selected_phase1_autoscan_agent}"
  phases.requirements.research.agent: "{selected_phase1_research_agent}"
  phases.requirements.research.web_search.agent: "{selected_phase1_websearch_agent}"
  # Phase 1 Synthesizer（专职汇总 auto_scan + research + BA）
  phases.requirements.synthesizer.agent: "{selected_phase1_synthesizer_agent}"
  # 推荐链：OMC "architect" > "Plan" > 用户自配（architect/judge 类，非 explore 类）
  # 选型约束：Synthesizer 负责结构化判断与冲突仲裁，必须选 architect/judge 类 agent；
  #           禁止使用 explore 类（如 Explore / research-investigator），它们偏向发散探索，
  #           与 Synthesizer 的"收敛仲裁 + [NEEDS CLARIFICATION] 标注"职责不匹配。
  # IF 检测到旧 phases.requirements.research.web_search.agent 字段:
  #   stderr 输出: "[DEPRECATED] phases.requirements.research.web_search.agent 已合并进 research.web_search_subtask；该字段保留仅为向后兼容"
  phases.openspec.agent: "{selected_phase2_agent}"
  phases.testing.agent: "{selected_phase4_agent}"
  phases.implementation.parallel.default_agent: "{selected_phase5_agent}"
  phases.implementation.review_agent: "{selected_phase5_review_agent}"
  phases.redteam.agent: "{selected_phase5_5_redteam_agent}"
  phases.reporting.agent: "{selected_phase6_agent}"
  phases.code_review.agent: "{selected_phase6_review_agent}"
  phases.archive.agent: "{selected_phase7_agent}"

  # 域级 Agent 配置写入（Step 2.5 选定的域 Agent）
  IF 用户在 Step 2.5 选择了域级 Agent:
    FOR each (prefix, agent) in selected_domain_agents:
      phases.implementation.parallel.domain_agents."{prefix}".agent: "{agent}"
```

## Step 5: 输出结果

```
✓ 已安装 {N} 个专业 Agent

Phase-Agent 映射:
  Phase 1 (需求分析) → {agent} ({model})
  Phase 2 (OpenSpec)  → {agent} ({model})
  Phase 3 (FF 生成)   → {agent} ({model})
  Phase 4 (测试设计)  → {agent} ({model})
  Phase 5 (实施)      → {agent} ({model})
  Phase 6A (测试)     → {agent} ({model})
  Phase 6B (代码审查) → {agent} ({model})
  Phase 7 (归档)      → {agent} ({model})

域级 Agent 映射 (Phase 5 并行):
  {prefix} → {agent} ({source})
  ...

热交换 Phase Agent: /autopilot-agents swap <phase> <agent>
热交换域 Agent:     /autopilot-agents swap <domain_prefix/> <agent>
查看:               /autopilot-agents list
```
