# figma-handoff CLAUDE.md

> 此文件为 `figma-handoff` 插件**专属规则层**,与根 `CLAUDE.md` 合并使用。

## 插件定位

Figma 设计稿 → 前端代码的高保真交付协议插件。Skill 类插件(无守护进程、无 GUI),包含少量 preflight / visual-diff 辅助脚本。

## 源码文件清单

```
plugins/figma-handoff/
├── .claude-plugin/plugin.json     # 插件元信息(版本由 release-please 维护)
├── README.md / README.zh.md        # 双语文档
├── CHANGELOG.md                    # 由 release-please 自动生成
├── version.txt                     # 与 plugin.json 版本一致
├── CLAUDE.md                       # 本文件
├── tools/build-dist.sh             # 构建脚本
└── skills/figma-handoff/
    ├── SKILL.md                              # 工作流骨架(框架/组件库无关)
    └── references/
        ├── preflight.md                      # 阶段 -1 能力探测协议
        ├── figma-mcp-protocol.md             # 阶段 0
        ├── translation-core.md               # 阶段 2 核心铁律(IR 层)
        ├── pixel-diff-protocol.md            # 阶段 3
        ├── prompt-template.md                # 业务文档模板
        ├── translation-rules.md              # [stub] 兼容旧引用
        ├── vendor-vant.md                    # [stub] 兼容旧引用
        ├── vendor-element-plus.md            # [stub] 兼容旧引用
	        ├── scripts/
	        │   ├── preflight.sh                  # preflight 参考实现
	        │   └── visual-diff.mjs               # pixelmatch + pngjs 兜底 diff 脚本
        └── adapters/
            ├── framework-vue.md              # Vue3 SFC 落地差异
            ├── framework-react.md            # React TSX 落地差异
            ├── lib-tailwind.md               # 默认 fallback(无组件库)
            ├── lib-shadcn.md                 # React + shadcn/ui
            ├── lib-antd.md                   # React + Ant Design
            ├── lib-mui.md                    # React + MUI
            ├── lib-chakra.md                 # React + Chakra
            ├── lib-mantine.md                # React + Mantine
            ├── lib-vant.md                   # Vue3 + Vant(移动端)
            ├── lib-element-plus.md           # Vue3 + Element Plus
            ├── lib-naive.md                  # Vue3 + Naive UI
            ├── lib-arco.md                   # Arco Design(Vue/React)
            ├── lib-tdesign.md                # TDesign(Vue/React)
            └── lib-primevue.md               # Vue3 + PrimeVue
```

`dist/figma-handoff/` 由 `tools/build-dist.sh` 生成,只包含 `.claude-plugin/`、`skills/` 与裁剪后的 `CLAUDE.md`;不会包含 source-only 的 `tools/`、`version.txt`、`CHANGELOG.md`。

## 设计原则

1. **SKILL.md 只写工作流骨架与原则**,所有可执行细节、命令、技术栈差异下沉到 `references/`
2. **不写代码模板** — 避免诱导 LLM 幻觉照抄
3. **三层正交** — Core 铁律(translation-core) × Framework adapter(vue/react) × Component Library adapter(lib-*),文件数 N+M 而非 N×M
4. **能力探测优先** — 阶段 -1 preflight 三段式输出(ready/degraded/blocking),缺失能力给可执行修复指令而非直接 abort
5. **客观证伪门禁** — 阶段 3 探测优先(Playwright > pixelmatch > odiff),禁止主观对比

## 与根规则的对齐

- `SKILL.md` ≤ 500 行 ✓
- description 以 "Use when..." 起句,第三人称,≤ 1024 字符 ✓
- references 单层下钻,无链式跳转 ✓
- 禁止版本号/迭代标签出现在 SKILL.md ✓
- 双语 README,语言切换链接 ✓

## 维护守则

- 新增**框架** → 新增 `adapters/framework-<name>.md`,在 SKILL.md §3.2 双层加载示例表与 preflight.sh framework 探测分支同步
- 新增**组件库** → 新增 `adapters/lib-<name>.md`(限 80 行内,仅写 token 入口 + 高频组件名映射),在 preflight.sh `lib` 嗅探分支同步
- 调整 Figma MCP 调用顺序 → 改 `references/figma-mcp-protocol.md`,SKILL.md 表格同步
- 像素 diff 引擎/阈值调整 → 改 `references/pixel-diff-protocol.md`,SKILL.md 提及阈值的位置同步
- 调整 preflight 探测能力 → 同步改 `references/preflight.md` 与 `references/scripts/preflight.sh`
- **禁止**在 SKILL.md 内嵌 bash/JS 脚本片段
- **禁止** framework adapter 写组件库 API、lib adapter 写框架语法,跨界即返工

## 测试与构建

- 测试:本插件无服务型 runtime,无 `make test`;辅助脚本用 `node --check` 与场景命令验证
- 构建:`make fh-build`(复制源码到 `dist/figma-handoff/`)
- Lint:`make fh-lint`(只 shellcheck `tools/build-dist.sh`)
- CI:`make fh-ci`
