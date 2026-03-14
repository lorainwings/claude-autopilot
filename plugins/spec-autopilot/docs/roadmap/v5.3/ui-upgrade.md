# Role: Principal Frontend Architect & UI/UX Refactoring Expert (首席前端架构师 & 视觉重构专家)

## 📌 任务背景 (The Context)

我们正在进行一次跨时代的 UI 升级。请仔细阅读以下工程关系：

1. **【V1 现有工程】**: 位于 `gui/` 目录下。它拥有完整且成熟的业务逻辑（Zustand Store 状态管理、WebSocket 通信底层），但视觉风格较老。
2. **【PRD 需求快照】**: 位于 `ui-design/ui-redesign-prd.md`。这是基于 V1 逻辑逆向提取出的全局需求文档。
3. **【V2 视觉原型】**: 位于 `ui-design/` 目录下。这是基于 PRD，由高级 AI UI 生成器（Stitch）产出的全新原型代码。它视觉酷炫（Tailwind + Framer Motion），但**数据全是 Mock 的死数据，缺乏真实的通信逻辑**。

## 🎯 核心目标 (The Objective)

将 `gui/` 目录下的 V1 工程，整体视觉风格无损升级到 V2 状态。
**通俗地说：把 V2 的“酷炫皮囊”剥下来，完美穿在 V1 的“逻辑骨架”上，最后确保能顺利打包输出到 `gui-dist/` 目录。**

---

## ⚠️ 绝对重构纪律 (Iron Laws of Refactoring)

1. **视觉 100% 继承 (Protect the Vibe):** V2 原型中的 Tailwind 类名、CSS 动画、DOM 结构必须原封不动地保留！绝不允许为了图省事而简化或阉割 V2 的样式代码。
2. **逻辑 100% 锚定 (Anchor the Logic):** 升级后的组件，其数据源**只能**来自 `gui/src/store/index.ts`。所有的按钮交互（如发送决策），**只能**调用 `gui/src/services/ws-bridge.ts`。彻底抛弃 V2 原型里的假数据数组和本地假状态。
3. **环境同步 (Sync Env):** V2 很可能引入了新的 UI 依赖（如 `framer-motion`, `lucide-react`）或新的 `tailwind.config.js` 颜色变量。你必须先把这些基建同步到 `gui/` 工程中。

---

## 🛠️ V1 升级 V2 执行流水线 (Upgrade Pipeline)

请按照以下顺序，极其严谨地执行重构：

### [Phase 1] 基建与依赖对齐 (Infrastructure Sync)

1. 检查 `ui-design/` 中的依赖项，并在 `gui/` 目录下执行 `npm install` 安装缺失的包（如 framer-motion, 图标库等）。
2. 将 V2 原型中自定义的 Tailwind 配置（如赛博朋克主题色、霓虹阴影等）合并到 `gui/tailwind.config.js` 和全局 CSS 文件中。

### [Phase 2] 核心状态适配 (State Adaptation)

1. 对比 V2 组件所需的数据结构与 `gui/src/store/index.ts` 中现有的真实数据。
2. 若 V2 需要新的衍生数据（例如将日志格式化、计算耗时等），请在 Zustand store 中新增 getter 或 selector，**严禁修改后端传来的原始事件流定义**。

### [Phase 3] 组件换皮与神经接入 (UI Replacement & Wiring)

逐个重构 `gui/src/components/` 下的组件：

1. **主看板/时间轴**: 用 V2 的酷炫 UI 替换，但 map 循环的数据源改为 Store 中的 `events` 和 `taskProgress`。
2. **终端控制台**: 将现有的真实 `xterm.js` 实例塞进 V2 设计的极客外壳中，确保 ANSI 颜色和滚动逻辑存活。
3. **拦截门禁弹窗 (GateBlock)**: 这是重中之重。用 V2 的 UI 替换后，必须将“Override”、“Retry”、“Fix”按钮精准绑定到现有的 `ws-bridge` 决策发送接口上；确保新增的 `fix_instructions` 输入框内容能被正确捕获并发送给底层引擎。

### [Phase 4] 全局拼装与构建验证 (Assembly & Build)

1. 使用 V2 的顶级布局重构 `gui/src/App.tsx`。
2. 验证 `gui/vite.config.ts` (或 webpack 配置)，确保 `outDir` 指向平级的 `../gui-dist` 目录。
3. 在 `gui/` 下运行构建命令，确保没有 TS 类型报错，且产物正确输出到了 `gui-dist/`。

---

## 🚀 启动口令

请确认你已深刻理解 V1、PRD、V2 三者的关系，以及“留 V2 的皮，保 V1 的骨”的战略意图。准备就绪后，请回复“视觉升维与逻辑锚定已启动”，并立即从 Phase 1 开始检查依赖！
