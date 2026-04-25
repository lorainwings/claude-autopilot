> [English](README.md) | 中文

# figma-handoff

> Figma 设计稿 → 前端代码像素级高保真还原工作流。

[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](../../LICENSE)
![Version](https://img.shields.io/badge/version-0.1.0-blue.svg)

## 它解决什么问题

直接使用 Figma 官方 Dev Mode MCP 还原设计稿,常见痛点:

- 输出"看起来像但不对" — `get_design_context` 返回的是 React+Tailwind reference,被照抄到异构栈(Vue/Naive/SwiftUI)即失真
- 颜色字号偏差,装饰丢失,图标 emoji 替代,绝对定位崩屏
- 验收靠肉眼,主观、不可证伪、容易自评通过

本 skill 把"主观对比"变成"客观证伪",强制 6 阶段流水线 + 像素 diff 硬门禁。目标是在交付前完成内部 diff 修复闭环,用户无需多轮肉眼调参。

## 核心理念

`get_design_context` 是参考,**不是权威**。权威是:

- `get_screenshot` — 视觉金本位
- `get_variable_defs` — token 真相源
- `get_code_connect_map` — 已映射组件清单
- MCP assets — 图片 / SVG 真值

## 工作流(6 阶段)

| 阶段 | 产物 | 硬门禁 |
| --- | --- | --- |
| -1 Preflight | `.cache/figma-handoff/preflight.json` | blocking 项必须清零 |
| 0 规格采集 | metadata + variables + code-connect + reference + screenshot + assets 六件套 | 顺序不可乱、不可跳 |
| 1 三表映射 | tokens / node-map / component-policy | token 覆盖率 100% |
| 2 转译 | 静态骨架 → 数据态 → 交互态 三步迭代 | 每步独立 diff |
| 3 像素 diff | figma / local / diff 三图对比 | diff ≤ 0.5%、关键 token 零偏差 |
| 4 独立 review | review 报告 | 节点溯源 100%、违规清零 |

## 适用范围

✅ 适用:

- 用户给出 figma.com URL 要求实现页面/组件
- 抱怨 Figma MCP 还原度低、设计稿对不上
- 已存在 figma-spec 但 diff > 阈值

❌ 不适用:

- 从零设计 / 仅做原型(用 `frontend-design` / `ui-ux-pro-max`)
- 纯交互修改、无视觉变更

## 技术栈支持

主 SKILL.md 框架技术栈无关,核心规则与适配器在 `references/` 单独维护:

- `references/translation-core.md` — 跨框架转译铁律
- `references/adapters/framework-vue.md` / `framework-react.md` — 框架适配
- `references/adapters/lib-vant.md` — Vant 4 (移动端 H5)
- `references/adapters/lib-element-plus.md` — Element Plus (PC)
- 其他栈按需新增

## 前置依赖

- Claude Code ≥ 2.x
- Figma Dev Mode MCP server 已配置(`mcp__figma__*` 工具可用)
- Chrome DevTools MCP 或 Playwright(用于本地截图)
- `pixelmatch` + `pngjs`(像素 diff)

## 触发方式

- 自然语言:"把这个 Figma 还原成 Vue 页面"、"figma mcp 还原度太低"、"高保真实现"
- 显式调用:`/figma-handoff` 或 `Skill(figma-handoff)`

## 文件结构

```
plugins/figma-handoff/
├── .claude-plugin/plugin.json
├── README.zh.md / README.md
├── CHANGELOG.md
└── skills/figma-handoff/
    ├── SKILL.md                       # 工作流骨架(技术栈无关)
    └── references/
        ├── preflight.md               # 阶段 -1 能力探测
        ├── figma-mcp-protocol.md      # 阶段 0 规格采集协议
        ├── translation-core.md         # 阶段 2 reference→目标栈转译铁律
        ├── pixel-diff-protocol.md      # 阶段 3 截图与 diff 操作规范
        ├── adapters/                   # framework/lib 适配器
        └── prompt-template.md          # 给业务需求文档的引用模板
```

## 许可证

MIT
