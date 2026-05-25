# figma-codegen CLAUDE.md

> 此文件为 `figma-codegen` 插件**专属规则层**,与根 `CLAUDE.md` 合并使用。

## 插件定位

把 Figma 设计稿翻译为生产级前端代码,追求 1:1 视觉一致。改编自 OpenAI 官方 [figma-implement-design](https://github.com/openai/skills/tree/main/skills/.curated/figma-implement-design),针对 Claude Code 生态适配。

Skill 类插件(无守护进程、无 GUI),只含一份 SKILL.md + 资产文件,不含运行时脚本。

## 源码文件清单

```
plugins/figma-codegen/
├── .claude-plugin/plugin.json     # 插件元信息(版本由 release-please 维护)
├── README.md / README.zh.md        # 双语文档
├── CHANGELOG.md                    # 由 release-please 自动生成
├── version.txt                     # 与 plugin.json 版本一致
├── CLAUDE.md                       # 本文件
├── tools/build-dist.sh             # 构建脚本
└── skills/figma-codegen/
    ├── SKILL.md                              # 工作流 7 步骨架(中文为主)
    ├── LICENSE.txt                           # 上游 OpenAI / Figma Developer Terms
    ├── agents/
    │   └── claude.yaml                       # MCP 依赖声明 + skill 元信息
    └── assets/
        ├── figma.png                         # skill marketplace 图标(大)
        ├── figma-small.svg                   # skill marketplace 图标(小)
        └── icon.svg                          # Figma 品牌 icon
```

`dist/figma-codegen/` 由 `tools/build-dist.sh` 生成,只包含 `.claude-plugin/`、`skills/` 与裁剪后的 `CLAUDE.md`;不包含 source-only 的 `tools/`、`version.txt`、`CHANGELOG.md`。

## 设计原则

1. **与上游对齐**:SKILL.md 7 步流程严格对应 OpenAI figma-implement-design,便于追上游 diff
2. **轻量入口**:不同于姊妹 skill 强调"硬门禁与重保还原",本 SKILL 走轻量直观路径,适合大多数日常 Figma → 代码场景
3. **三模式 MCP 适配**:同时支持 Remote MCP / Figma Desktop MCP / 本地 figma-developer-mcp
4. **不写代码模板**:SKILL 只描述 7 步动作,具体语法由 Claude 实时根据项目栈推断
5. **资产硬规则**:Figma MCP 返回的 assets 直接落地,严禁用占位图或新增 icon 包替代

## 与根规则的对齐

- `SKILL.md` ≤ 500 行 ✓(实际 316 行)
- description 以 "Translates ..." 起句,触发条件清晰,≤ 1024 字符 ✓
- frontmatter 含 user-invocable / argument-hint ✓
- 双语 README,语言切换链接 ✓
- 禁止版本号/迭代标签出现在 SKILL.md ✓

## 维护守则

- **追上游**:OpenAI 上游 SKILL.md 升级时,同步对照本仓 SKILL.md 的 7 步骨架进行 diff merge
- **资产**:`assets/figma-small.svg` / `figma.png` / `icon.svg` 与上游保持二进制一致(便于 marketplace 视觉一致)
- **agents/claude.yaml**:MCP `url` 字段固定 `https://mcp.figma.com/mcp`(官方 Remote MCP);`default_prompt` 字段保留英文(skill 选择器匹配优先英文 trigger)
- **禁止**在 SKILL.md 内嵌 bash/JS 脚本片段
- **禁止**新增 references/ 子目录(本 SKILL 主张单文件 SKILL,与上游一致)

## 测试与构建

- 测试:本插件无服务型 runtime,无 `make test`
- 构建:`make fc-build`(复制源码到 `dist/figma-codegen/`)
- Lint:`make fc-lint`(只 shellcheck `tools/build-dist.sh`)
- CI:`make fc-ci`
