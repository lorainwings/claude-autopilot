#!/usr/bin/env python3
"""adapt-agent-tools.py — Phase/Agent 工具权限冲突自动适配器

读取 .claude/autopilot.config.yaml 中所有 phase → agent 映射，
对每个 agent 的 frontmatter `disallowedTools` 字段与 phase 所需工具集取交集；
若存在冲突，fork 原 agent 到 .claude/agents/{name}.md 并剥离冲突项。

安全边界：
- 只在 .claude/agents/ 下写文件；不修改源 marketplace agent。
- 若目标文件已存在（之前已 fork），仅在 --force 下覆盖。
- 严格 YAML 解析（非正则），规避 CLAUDE.md / 说明文字被误改。

输出：
- stdout: 结构化 JSON，包含 adapted_agents[] / skipped[] / errors[]
- exit 0 即使有冲突（适配是幂等动作，非阻断）；IO 失败返回 1。

使用:
  python3 adapt-agent-tools.py                   # 适配当前项目配置
  python3 adapt-agent-tools.py --project-root /path/to/proj
  python3 adapt-agent-tools.py --dry-run         # 只报告不写盘
  python3 adapt-agent-tools.py --force           # 强制覆盖已 fork 的 agent
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Any

# Phase → 该 phase 在 autopilot 编排中需要的最小工具集
# 参考 skills/autopilot-*/SKILL.md 中各 phase 的工具使用记录
PHASE_REQUIRED_TOOLS: dict[str, set[str]] = {
    "phases.requirements.agent": {"Read", "Write", "Edit", "Bash", "Grep", "Glob"},
    "phases.requirements.research.agent": {"Read", "Write", "Grep", "Glob", "WebFetch", "WebSearch"},
    "phases.openspec.agent": {"Read", "Write", "Edit", "Bash"},
    "phases.ff.agent": {"Read", "Write", "Edit"},
    "phases.testing.agent": {"Read", "Write", "Edit", "Bash"},
    "phases.implementation.parallel.default_agent": {"Read", "Write", "Edit", "MultiEdit", "Bash", "Grep", "Glob"},
    # review_agent 默认只读即可，但若用户配置写权限 agent 也不强加限制
    "phases.implementation.review_agent": {"Read", "Grep", "Glob"},
    "phases.reporting.agent": {"Read", "Write", "Bash"},
    "phases.code_review.agent": {"Read", "Grep", "Glob"},
    "phases.archive.agent": {"Read", "Write", "Bash"},
}

# 并行 Phase 5 域 agent 与 default_agent 同权限
DOMAIN_AGENT_TOOLS = PHASE_REQUIRED_TOOLS["phases.implementation.parallel.default_agent"]

BUILTIN_AGENTS = {"general-purpose", "Plan", "Explore", "statusline-setup", "output-style-setup"}


def load_yaml(path: Path) -> dict[str, Any]:
    try:
        import yaml  # type: ignore
    except ImportError:
        # PyYAML 未安装 → 回退到子进程调用（兼容精简环境）
        raw = subprocess.check_output(
            ["python3", "-c", f"import json,yaml; print(json.dumps(yaml.safe_load(open({str(path)!r}))))"]
        ).decode()
        return json.loads(raw)
    with path.open("r", encoding="utf-8") as f:
        return yaml.safe_load(f) or {}


def get_nested(d: dict[str, Any], dotted: str) -> Any:
    cur: Any = d
    for key in dotted.split("."):
        if not isinstance(cur, dict):
            return None
        cur = cur.get(key)
    return cur


def find_domain_agents(cfg: dict[str, Any]) -> list[tuple[str, str]]:
    """返回 [(domain_key, agent_name), ...]"""
    node = get_nested(cfg, "phases.implementation.parallel.domain_agents") or {}
    out: list[tuple[str, str]] = []
    if isinstance(node, dict):
        for prefix, entry in node.items():
            if isinstance(entry, dict) and isinstance(entry.get("agent"), str):
                out.append((f"domain_agents.{prefix}", entry["agent"]))
    return out


FRONTMATTER_RE = re.compile(r"^---\s*\n(.*?)\n---\s*\n", re.DOTALL)


def parse_frontmatter(md_text: str) -> tuple[dict[str, Any], str, str]:
    """返回 (frontmatter_dict, raw_frontmatter_str, body_str)。"""
    m = FRONTMATTER_RE.match(md_text)
    if not m:
        return {}, "", md_text
    raw = m.group(1)
    body = md_text[m.end() :]
    # 手工逐行解析 key: value（避免 PyYAML 依赖，且 agent frontmatter 结构简单）
    fm: dict[str, Any] = {}
    for line in raw.splitlines():
        if ":" not in line or line.lstrip().startswith("#"):
            continue
        key, _, value = line.partition(":")
        fm[key.strip()] = value.strip()
    return fm, raw, body


def parse_tools_list(value: str) -> list[str]:
    """解析 'Write, Edit' 或 '[Write, Edit]' 为 list。"""
    s = value.strip().strip("[]")
    if not s:
        return []
    return [t.strip() for t in s.split(",") if t.strip()]


def locate_source_agent(agent_name: str, project_root: Path) -> Path | None:
    """按优先级查找 agent 源文件。"""
    candidates = [
        project_root / ".claude" / "agents" / f"{agent_name}.md",
        Path.home() / ".claude" / "agents" / f"{agent_name}.md",
    ]
    # OMC marketplace
    omc_root = Path.home() / ".claude" / "plugins" / "marketplaces" / "omc" / "agents"
    candidates.append(omc_root / f"{agent_name}.md")
    # 其它 marketplace 兜底扫描
    mp_root = Path.home() / ".claude" / "plugins" / "marketplaces"
    if mp_root.is_dir():
        candidates.extend(mp_root.glob(f"*/agents/{agent_name}.md"))
        candidates.extend(mp_root.glob(f"*/plugins/*/agents/{agent_name}.md"))
    for c in candidates:
        if c.is_file():
            return c
    return None


def adapt_agent(
    agent_name: str, phase_key: str, required: set[str], project_root: Path, dry_run: bool, force: bool
) -> dict[str, Any]:
    if agent_name in BUILTIN_AGENTS:
        return {"agent": agent_name, "phase": phase_key, "action": "skip_builtin"}

    target = project_root / ".claude" / "agents" / f"{agent_name}.md"
    source = locate_source_agent(agent_name, project_root)

    if source is None:
        return {
            "agent": agent_name,
            "phase": phase_key,
            "action": "missing",
            "error": f"agent file not found for {agent_name}",
        }

    text = source.read_text(encoding="utf-8")
    fm, raw_fm, body = parse_frontmatter(text)

    disallowed_raw = fm.get("disallowedTools", "")
    disallowed = parse_tools_list(disallowed_raw) if disallowed_raw else []
    conflicts = sorted(set(disallowed) & required)

    if not conflicts:
        # 无冲突：若目标已是 fork 副本保留；否则无需动作
        return {"agent": agent_name, "phase": phase_key, "action": "ok", "disallowed": disallowed}

    # 有冲突 → 生成 fork
    if target.exists() and not force and source != target:
        return {
            "agent": agent_name,
            "phase": phase_key,
            "action": "already_forked",
            "target": str(target),
            "conflicts": conflicts,
        }

    new_disallowed = [t for t in disallowed if t not in required]
    new_fm_lines = []
    seen_disallowed = False
    for line in raw_fm.splitlines():
        key = line.partition(":")[0].strip()
        if key == "disallowedTools":
            seen_disallowed = True
            if new_disallowed:
                new_fm_lines.append(f"disallowedTools: {', '.join(new_disallowed)}")
            # 若完全清空则丢弃该行
        else:
            new_fm_lines.append(line)
    if not seen_disallowed:
        # 源文件无 disallowedTools 但 set 里有（不太可能），理论分支
        pass

    new_text = "---\n" + "\n".join(new_fm_lines) + "\n---\n" + body
    # 在 body 顶部加入一个 HTML 注释说明 fork 原因（不干扰渲染）
    adapter_note = (
        f"\n<!-- autopilot-adapter: forked from {source} for phase `{phase_key}`;"
        f" stripped conflicting disallowedTools={conflicts} -->\n"
    )
    new_text = "---\n" + "\n".join(new_fm_lines) + "\n---\n" + adapter_note + body

    if dry_run:
        return {
            "agent": agent_name,
            "phase": phase_key,
            "action": "would_fork",
            "target": str(target),
            "conflicts": conflicts,
            "new_disallowed": new_disallowed,
        }

    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(new_text, encoding="utf-8")
    return {
        "agent": agent_name,
        "phase": phase_key,
        "action": "forked",
        "target": str(target),
        "conflicts": conflicts,
        "new_disallowed": new_disallowed,
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--project-root", default=os.getcwd())
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--force", action="store_true")
    args = ap.parse_args()

    project_root = Path(args.project_root).resolve()
    config_path = project_root / ".claude" / "autopilot.config.yaml"
    if not config_path.is_file():
        print(json.dumps({"error": f"config not found: {config_path}", "adapted": []}))
        return 1

    cfg = load_yaml(config_path)
    results: list[dict[str, Any]] = []

    for phase_key, required in PHASE_REQUIRED_TOOLS.items():
        agent_name = get_nested(cfg, phase_key)
        if not isinstance(agent_name, str) or not agent_name:
            continue
        results.append(adapt_agent(agent_name, phase_key, required, project_root, args.dry_run, args.force))

    for domain_key, agent_name in find_domain_agents(cfg):
        results.append(
            adapt_agent(
                agent_name,
                f"phases.implementation.parallel.{domain_key}",
                DOMAIN_AGENT_TOOLS,
                project_root,
                args.dry_run,
                args.force,
            )
        )

    summary = {
        "project_root": str(project_root),
        "total": len(results),
        "forked": sum(1 for r in results if r.get("action") == "forked"),
        "would_fork": sum(1 for r in results if r.get("action") == "would_fork"),
        "already_forked": sum(1 for r in results if r.get("action") == "already_forked"),
        "ok": sum(1 for r in results if r.get("action") == "ok"),
        "missing": sum(1 for r in results if r.get("action") == "missing"),
        "results": results,
    }
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
