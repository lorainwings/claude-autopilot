> **[中文版](README.zh.md)** | English (default)

# figma-handoff

> Pixel-faithful Figma → frontend code handoff workflow.

[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](../../LICENSE)
![Version](https://img.shields.io/badge/version-0.1.0-blue.svg)

## Problem

Using Figma official Dev Mode MCP directly often produces low-fidelity output:

- "Looks similar but wrong" — `get_design_context` returns React+Tailwind reference; copied verbatim into Vue/Naive/SwiftUI it drifts
- Colors / fonts / decorations / icons drift; emoji substitutes for icons; absolute positioning breaks responsiveness
- Visual review is subjective and unfalsifiable

This skill turns subjective comparison into **objective, falsifiable gates** — a 6-stage pipeline with pixel-diff hard gates. The goal is a pre-delivery internal diff-and-fix loop so users do not need repeated manual visual tuning.

## Core principle

`get_design_context` is a **reference**, not the source of truth. The real ground-truth signals are:

- `get_screenshot` — visual gold standard
- `get_variable_defs` — token truth source
- `get_code_connect_map` — already-mapped components
- MCP assets — image / SVG truth source

## Pipeline (6 stages)

| Stage | Output | Hard gate |
| --- | --- | --- |
| -1 Preflight | `.cache/figma-handoff/preflight.json` | No blocking items |
| 0 Spec acquisition | metadata + variables + code-connect + reference + screenshot + assets | Strict order, no skipping |
| 1 Three mapping tables | tokens / node-map / component-policy | 100% token coverage |
| 2 Translation | skeleton → data → interaction (3 iterations) | Diff per step |
| 3 Pixel diff | figma / local / diff triple | diff ≤ 0.5%, key tokens zero drift |
| 4 Independent review | review report | 100% node traceability |

## When to use

Use:
- Implementing a page/component from a figma.com URL
- Complaints about Figma MCP low fidelity
- Existing `figma-spec` but diff exceeds threshold

Do not use:
- Greenfield design / wireframes (use `frontend-design` / `ui-ux-pro-max`)
- Pure interaction tweaks without visual changes

## Stack support

The main `SKILL.md` is stack-agnostic. Core rules and adapters live under `references/`:

- `translation-core.md` — stack-agnostic translation rules
- `adapters/framework-vue.md` / `framework-react.md` — framework adapters
- `adapters/lib-vant.md` — Vant 4 (mobile H5)
- `adapters/lib-element-plus.md` — Element Plus (PC)
- Add more adapters as needed.

## Prerequisites

- Claude Code ≥ 2.x
- Figma Dev Mode MCP (`mcp__figma__*` available)
- Chrome DevTools MCP or Playwright (local screenshots)
- `pixelmatch` + `pngjs`

## License

MIT
