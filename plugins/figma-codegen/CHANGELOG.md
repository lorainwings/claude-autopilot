# Changelog

## [1.0.0](https://github.com/stoicatom/claude-autopilot/compare/figma-codegen-v0.1.0...figma-codegen-v1.0.0) (2026-05-25)


### ⚠ BREAKING CHANGES

* **figma-codegen:** removes the figma-handoff plugin and replaces it with figma-codegen — a faithful Claude Code adaptation of OpenAI's official figma-implement-design skill.

### Added

* **figma-codegen:** port openai figma-implement-design skill, replace figma-handoff ([5475529](https://github.com/stoicatom/claude-autopilot/commit/54755292c6a210aa3bcdd88897847ad6c5295ad3))
* **spec-autopilot:** Phase 1 三路调研独立 agent 配置（auto_scan/research/web_search） ([487858c](https://github.com/stoicatom/claude-autopilot/commit/487858c01612a888049dd300838319fc3f4a8657))

## [0.1.0] - 2026-05-25

### Added

- Initial release of `figma-codegen` plugin, adapted from OpenAI's official [figma-implement-design](https://github.com/openai/skills/tree/main/skills/.curated/figma-implement-design) skill
- 7-step workflow: Get Node ID → Fetch Design Context → Capture Screenshot → Download Assets → Translate to Project Conventions → Achieve 1:1 Visual Parity → Validate Against Figma
- Three Figma MCP modes supported: Remote MCP / Figma Desktop MCP / local figma-developer-mcp
- `agents/claude.yaml` declares MCP dependency for skill marketplace
- Bilingual README (English / 简体中文)
- SKILL written in Chinese (per project global rule), with English `description` for skill router matching
