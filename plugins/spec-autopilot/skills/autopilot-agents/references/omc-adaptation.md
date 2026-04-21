# 适配说明

## OMC `analyst` → Phase 1 适配

OMC 原版 `analyst` 的 `disallowedTools: Write, Edit` 与 Phase 1 不兼容（需要 Write 调研产出文件）。

安装时自动适配：fork `analyst.md`，将 `disallowedTools: Write, Edit` 改为 `disallowedTools: Edit`（保留禁止 Edit，允许 Write）。

## OMC `planner` → Phase 2/3 适配

保持原版，Phase 2/3 的 dispatch prompt 已包含 OpenSpec 文档生成指令，叠加即可。
