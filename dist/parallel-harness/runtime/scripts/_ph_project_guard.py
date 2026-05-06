"""Project relevance guard shared by parallel-harness runtime scripts.

These helpers exist to keep ``.parallel-harness/`` from leaking into
unrelated projects when the plugin's global hooks (``record-skill-tool-event``,
``statusline-collector``) fire in sessions that never use the harness.

Two responsibilities:

1. ``is_parallel_harness_project(root)`` answers "should this project ever
   own a ``.parallel-harness/`` directory?" — passive observers must call
   this before creating any files.
2. ``resolve_project_root(cwd)`` chooses the directory that should host the
   data dir. It prefers the nearest existing ``.parallel-harness/`` marker
   so monorepo subdirectories never up-shoot data into the parent repo.
"""

from __future__ import annotations

import os
import subprocess
from pathlib import Path
from typing import Iterable, Optional


_SETTINGS_FILES: tuple[str, ...] = (
    os.path.join(".claude", "settings.local.json"),
    os.path.join(".claude", "settings.json"),
)
_PLUGIN_MANIFEST = os.path.join(".claude-plugin", "marketplace.json")


def _settings_reference_parallel_harness(root: Path) -> bool:
    for rel in _SETTINGS_FILES:
        path = root / rel
        if not path.is_file():
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except Exception:
            continue
        if "parallel-harness" in text or "statusline-collector.sh" in text:
            return True
    manifest = root / _PLUGIN_MANIFEST
    if manifest.is_file():
        try:
            if "parallel-harness" in manifest.read_text(encoding="utf-8"):
                return True
        except Exception:
            pass
    return False


def is_parallel_harness_project(project_root: str | os.PathLike[str]) -> bool:
    """Return True only if the project genuinely consumes parallel-harness.

    Truthy signals (any one is sufficient):

    * ``.parallel-harness/`` already exists (definitive evidence — created
      either by a prior harness run or by the active-creation scripts).
    * Project-scope or local-scope ``settings*.json`` references the
      ``parallel-harness`` plugin or the statusline collector script.
    * ``.claude-plugin/marketplace.json`` lists ``parallel-harness``.
    """
    root = Path(project_root)
    if not root.exists():
        return False
    if (root / ".parallel-harness").is_dir():
        return True
    return _settings_reference_parallel_harness(root)


def _git_toplevel(start: Path) -> Optional[str]:
    try:
        out = subprocess.check_output(
            ["git", "rev-parse", "--show-toplevel"],
            cwd=str(start),
            stderr=subprocess.DEVNULL,
            text=True,
        ).strip()
        return out or None
    except Exception:
        return None


def _walk_up(start: Path) -> Iterable[Path]:
    yield start
    for parent in start.parents:
        yield parent


def resolve_project_root(cwd: str) -> str:
    """Pick the directory that owns this project's ``.parallel-harness/``.

    Resolution order (constrained by the git repo boundary so we never
    cross-mount onto a polluted ``/tmp/.parallel-harness/`` or a sibling
    project's marker that happens to sit on a shared filesystem):

    1. If ``cwd`` is inside a git repo:
       - Walk from ``cwd`` upward toward the git toplevel. Stop at the
         first ancestor (inclusive of toplevel) that contains a
         ``.parallel-harness/`` directory — anchors monorepo subdirectories
         correctly without leaking past the repo root.
       - If none found, return the git toplevel itself.
    2. If ``cwd`` is **not** inside any git repo (typical for ephemeral
       tmpdirs): return ``cwd`` as-is. Never walk up — sharing ``/tmp``
       with stray markers from other tools/users would otherwise hijack
       the project root.

    The previous implementation walked all the way to ``/`` regardless of
    git boundary, which caused ``mkdtemp`` based tests to be hijacked by
    stray ``/tmp/.parallel-harness/`` markers.
    """
    start = Path(cwd).resolve() if cwd else Path(os.getcwd()).resolve()
    git_root_str = _git_toplevel(start)

    if git_root_str:
        try:
            git_root = Path(git_root_str).resolve()
        except Exception:
            return git_root_str
        current = start
        while True:
            if (current / ".parallel-harness").is_dir():
                return str(current)
            if current == git_root:
                return git_root_str
            parent = current.parent
            if parent == current:
                # Reached filesystem root without hitting git boundary —
                # shouldn't happen, but fall through gracefully.
                return git_root_str
            current = parent

    return str(start)


def mark_created(project_root: str | os.PathLike[str], creator: str) -> None:
    """Drop a ``.parallel-harness/.created-by`` anchor for active creators.

    Active creation paths (``execute-harness.ts`` via runtime, and the
    deterministic ``parallel-harness:`` skill hook) call this so that
    subsequent passive observers can confidently treat the directory as
    intentional rather than stray.
    """
    root = Path(project_root) / ".parallel-harness"
    try:
        root.mkdir(parents=True, exist_ok=True)
        marker = root / ".created-by"
        if marker.exists():
            return
        marker.write_text(f"{creator}\n", encoding="utf-8")
    except Exception:
        pass
