# `recommend` 模式（默认）

展示基于调研评分的各阶段推荐 Agent 映射表：

```
╔══════════════╦═══════════════════════════╦════════════╦═══════╦══════╦═════════════════════════════════════╗
║ Phase/角色   ║ 推荐 Agent                ║ 来源       ║ Model ║ 评分 ║ 选择理由                            ║
╠══════════════╬═══════════════════════════╬════════════╬═══════╬══════╬═════════════════════════════════════╣
║ Phase 1 BA   ║ analyst                   ║ OMC        ║ opus  ║ 9/10 ║ 7 步调查协议 + 决策点识别           ║
║ Phase 1 扫描 ║ explore (forked +Write)   ║ OMC        ║ sonnet║ 8/10 ║ 符号映射 + 文件搜索专精             ║
║ Phase 1 调研 ║ architect                 ║ OMC        ║ opus  ║ 8/10 ║ 接口/依赖/可行性长期权衡            ║
║ Phase 1 联网 ║ search-specialist(forked) ║ VoltAgent  ║ sonnet║ 8/10 ║ 原生 WebSearch+WebFetch，最小权限   ║
║ Phase 2      ║ planner                   ║ OMC        ║ opus  ║ 9/10 ║ 访谈→计划→确认+共识协议              ║
║ Phase 3      ║ writer                    ║ OMC        ║ haiku ║ 8/10 ║ Haiku 成本最优+模板化精确执行        ║
║ Phase 4      ║ test-engineer             ║ OMC        ║ sonnet║ 9/10 ║ TDD铁律+70/20/10金字塔              ║
║ Phase 5      ║ executor                  ║ OMC        ║ sonnet║ 9/10 ║ 最小差异+3次升级+lsp 验证            ║
║ Phase 5.5    ║ code-reviewer             ║ OMC        ║ opus  ║ 9/10 ║ Red Team 攻击枚举 + 反例产出         ║
║ Phase 6A     ║ qa-tester                 ║ OMC        ║ sonnet║ 8/10 ║ tmux 行为验证+5阶段协议              ║
║ Phase 6B     ║ code-reviewer             ║ OMC        ║ opus  ║10/10 ║ 强制Read-Only+10步审查+严重性分级    ║
║ Phase 7      ║ git-master                ║ OMC        ║ sonnet║ 8/10 ║ 原子提交+commit style 检测           ║
╚══════════════╩═══════════════════════════╩════════════╩═══════╩══════╩═════════════════════════════════════╝

备选 Agent:
  Phase 1 BA    : business-analyst (VoltAgent, 7/10)
  Phase 1 扫描  : codebase-onboarding (alirezarezvani, 8/10) — 原生 +Write
  Phase 1 调研  : backend-architect (wshobson, 7/10)
  Phase 1 联网  : market-researcher (VoltAgent, 7/10 — 需 fork +Write)
  Phase 4       : qa-expert (VoltAgent, 8/10)
  Phase 5.5     : red-team-critic (Anthropic 官方, 8/10，需独立验证)
  Phase 6B      : code-reviewer (Anthropic 官方, 9/10, 置信度≥80 过滤)
```

> **Phase 1 三路独立**：`auto_scan.agent` / `research.agent` / `research.web_search.agent` 在 config 中**独立字段**，运行时按 prompt 引用的输出文件路径精确校验（不允许混用）。BA agent（`phases.requirements.agent`）用于需求分析阶段。

输出后提示：`输入 /autopilot-agents install 安装推荐 Agent`

## 域级 Agent 推荐（Phase 5 并行域 Agent）

```
╔═══════════════════════╦═══════════════════════╦════════════╦══════╦═══════════════════════════════════════════╗
║ 域路径前缀             ║ 推荐 Agent            ║ 来源       ║ 评分 ║ 选择理由                                  ║
╠═══════════════════════╬═══════════════════════╬════════════╬══════╬═══════════════════════════════════════════╣
║ backend/              ║ backend-developer     ║ VoltAgent  ║ 8/10 ║ API/DB/安全/微服务专精                     ║
║ frontend/             ║ frontend-developer    ║ VoltAgent  ║ 8/10 ║ React/Vue/Angular+TS strict+A11y          ║
║ node/                 ║ fullstack-developer   ║ VoltAgent  ║ 9/10 ║ DB→API→UI 全链路+类型安全                  ║
║ infra/ / devops/      ║ devops-engineer       ║ VoltAgent  ║ 8/10 ║ IaC/K8s/CI-CD/监控全覆盖                  ║
║ shared/ / libs/       ║ executor              ║ OMC        ║ 8/10 ║ 通用执行+3 次升级+最小差异                 ║
║ docs/                 ║ documentation-engineer║ VoltAgent  ║ 8/10 ║ 结构化文档+API 覆盖                       ║
║ mobile/               ║ mobile-developer      ║ VoltAgent  ║ 8/10 ║ RN/Flutter/原生+离线同步                  ║
║ data/                 ║ data-engineer         ║ VoltAgent  ║ 8/10 ║ ETL/Spark/Kafka/Airflow                   ║
╚═══════════════════════╩═══════════════════════╩════════════╩══════╩═══════════════════════════════════════════╝

来源仓库:
  VoltAgent: VoltAgent/awesome-claude-code-subagents (17k+ ★) — 域级专精 Agent 最佳来源
  OMC:       Yeachan-Heo/oh-my-claudecode (27.6k+ ★) — 工程化执行 + 通用 fallback
```

输出后提示：`输入 /autopilot-agents install 安装推荐 Agent（含域级 Agent）`
