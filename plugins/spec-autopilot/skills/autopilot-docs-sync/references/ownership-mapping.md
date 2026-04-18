# 源码 → 文档所有权映射 (Ownership Mapping)

本文档定义 `detect-doc-drift.sh` 所使用的**源码 → 文档**同步契约。当左侧文件变更时，必须同步右侧文件，否则触发对应 Rule。

## R1: SKILL.md ↔ README

| 源 | 目标 | 说明 |
|----|------|------|
| `plugins/spec-autopilot/skills/<skill>/SKILL.md` | `plugins/spec-autopilot/README.md` | 插件 README 应包含该 skill 的简要描述 |
| `plugins/spec-autopilot/skills/<skill>/SKILL.md` | `plugins/spec-autopilot/README.zh.md` | 中文 README 同上 |

**豁免**：

- `skills/autopilot-*-internal/` 前缀命名的内部 skill 可加入 `.drift-ignore` 逐条忽略

## R2: Runtime Script ↔ .dist-include

| 源 | 目标 | 说明 |
|----|------|------|
| 新增 `plugins/spec-autopilot/runtime/scripts/<X>.sh` | `plugins/spec-autopilot/runtime/scripts/.dist-include` | 必须在 `.dist-include` 登记，否则构建时不会打包 |

## R3: CLAUDE.md ↔ README 版本横幅

| 源 | 目标 | 说明 |
|----|------|------|
| `plugins/spec-autopilot/CLAUDE.md` | `plugins/spec-autopilot/README.md` | 若 CLAUDE.md 引入新红线/约束，README 可能需更新版本 banner 或 "What's New" 段落。本规则为 info 级提示，不强制 |

## R4: Autopilot 主控 Skill ↔ 流程图

| 源 | 目标 | 说明 |
|----|------|------|
| `plugins/spec-autopilot/skills/autopilot/SKILL.md` | `docs/plans/*.md` | Phase 总览表变化时，相关流程图可能需刷新。info 级提示 |

## R5: 新增 SKILL.md ↔ 根 README 插件表格

| 源 | 目标 | 说明 |
|----|------|------|
| 新增 `plugins/spec-autopilot/skills/<new>/SKILL.md` | 仓库根 `README.md` / `README.zh.md` | 根 README 的插件总表需包含该 skill 或明确说明其属于 spec-autopilot 内部 skill |

## 扩展指南

若后续需要新增规则（例如 Rxx）：

1. 在 `detect-doc-drift.sh` 中添加新的 for-loop 分支
2. 在此文档中记录映射关系
3. 在 `test_detect_doc_drift.sh` 中补 3 个测试用例（正常 / 触发 / 忽略）
4. 如果涉及新的配置开关，更新 `autopilot.config.yaml` 示例
