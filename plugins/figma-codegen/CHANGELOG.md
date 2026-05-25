# Changelog

## [0.1.0] - 2026-05-25

### Added

- Initial release of `figma-codegen` plugin, adapted from OpenAI's official [figma-implement-design](https://github.com/openai/skills/tree/main/skills/.curated/figma-implement-design) skill
- 7-step workflow: Get Node ID → Fetch Design Context → Capture Screenshot → Download Assets → Translate to Project Conventions → Achieve 1:1 Visual Parity → Validate Against Figma
- Three Figma MCP modes supported: Remote MCP / Figma Desktop MCP / local figma-developer-mcp
- `agents/claude.yaml` declares MCP dependency for skill marketplace
- Bilingual README (English / 简体中文)
- SKILL written in Chinese (per project global rule), with English `description` for skill router matching
