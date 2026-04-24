#!/usr/bin/env bash
# _agent_state.sh
# Consolidated active-agent state helper — single JSON replaces 5 legacy markers:
#   logs/.active-agent-id
#   logs/.active-agent-phase-<N>
#   logs/.active-agent-session-<session_key>
#   logs/.agent-dispatch-ts-<agent_id>
#
# Source this in scripts that need to read/write active-agent state:
#   source "$SCRIPT_DIR/_agent_state.sh"
#
# File layout (logs/.active-agent-state.json):
#   {
#     "version": 1,
#     "global":     { "agent_id": "...", "phase": 5, "updated_at": "ISO8601" },
#     "sessions":   { "<session_key>": { "agent_id": "...", "dispatched_at": "ISO8601",
#                                        "dispatch_epoch_ms": 1713974554000 } },
#     "phases":     { "5": "<agent_id>" },
#     "dispatch_ts": { "<agent_id>": 1713974554000 }
#   }
#
# Concurrency: python3 with fcntl.flock on a fixed sibling lock file
#              (logs/.agent-state.lock — NEVER delete this file via globs).
#              Writers use tmp+rename for atomic replacement.
#
# Error reporting:
# - All python heredocs WRITE error tokens to stderr on failure
#   (AUTOPILOT_AGENT_STATE_<reason>) so callers can grep / log them.
# - JSON corruption → file is quarantined as .corrupt-<epoch_ms> and a fresh
#   default state is written, NOT silently merged with empty object.
# - Bash wrappers preserve python exit code; callers that previously used
#   "|| true" to swallow errors should now branch on stderr token instead.

# Resolve state file path.
# Usage: agent_state_file <project_root>
agent_state_file() {
  echo "${1%/}/logs/.active-agent-state.json"
}

# Resolve lock file path. Stable name → never matched by `rm logs/.active-agent-*` globs.
# Usage: agent_state_lock_file <project_root>
agent_state_lock_file() {
  echo "${1%/}/logs/.agent-state.lock"
}

# Dispatch: record an agent going active.
# Usage: agent_state_dispatch <project_root> <session_key> <phase> <agent_id>
# Exit: 0 on success, non-zero on write failure (also emits stderr token).
agent_state_dispatch() {
  local project_root="$1" session_key="${2:-unknown}" phase="${3:-0}" agent_id="$4"
  [ -z "$agent_id" ] && return 0
  local state_file lock_file
  state_file="$(agent_state_file "$project_root")"
  lock_file="$(agent_state_lock_file "$project_root")"
  if ! mkdir -p "$(dirname "$state_file")" 2>/dev/null; then
    echo "AUTOPILOT_AGENT_STATE_MKDIR_FAIL state_dir=$(dirname "$state_file")" >&2
    return 1
  fi
  AGENT_STATE_FILE="$state_file" AGENT_STATE_LOCK="$lock_file" \
    AS_SESSION_KEY="$session_key" AS_PHASE="$phase" AS_AGENT_ID="$agent_id" \
    python3 - <<'PY'
import fcntl, json, os, sys, tempfile, time
from datetime import datetime, timezone

path = os.environ["AGENT_STATE_FILE"]
lock_path = os.environ["AGENT_STATE_LOCK"]
session_key = os.environ.get("AS_SESSION_KEY") or "unknown"
phase = os.environ.get("AS_PHASE") or "0"
agent_id = os.environ["AS_AGENT_ID"]
now_iso = datetime.now(timezone.utc).isoformat()
now_ms = int(time.time() * 1000)


def _quarantine_and_default():
    try:
        os.replace(path, f"{path}.corrupt-{now_ms}")
    except OSError:
        pass
    return {"version": 1, "global": {}, "sessions": {}, "phases": {}, "dispatch_ts": {}}


def _load_locked():
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except FileNotFoundError:
        return {"version": 1, "global": {}, "sessions": {}, "phases": {}, "dispatch_ts": {}}
    except json.JSONDecodeError:
        sys.stderr.write(
            f"AUTOPILOT_AGENT_STATE_CORRUPT path={path} action=quarantine\n"
        )
        return _quarantine_and_default()


def _write_atomic(state):
    tmp_fd, tmp_path = tempfile.mkstemp(prefix=".active-agent-state.", dir=os.path.dirname(path))
    try:
        with os.fdopen(tmp_fd, "w", encoding="utf-8") as f:
            json.dump(state, f, ensure_ascii=False, indent=2)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp_path, path)
    except Exception:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
        raise


try:
    with open(lock_path, "a+", encoding="utf-8") as lock:
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
        state = _load_locked()
        state.setdefault("version", 1)
        state.setdefault("global", {})
        state.setdefault("sessions", {})
        state.setdefault("phases", {})
        state.setdefault("dispatch_ts", {})

        state["global"] = {
            "agent_id": agent_id,
            "phase": int(phase) if str(phase).isdigit() else phase,
            "updated_at": now_iso,
        }
        state["sessions"][session_key] = {
            "agent_id": agent_id,
            "dispatched_at": now_iso,
            "dispatch_epoch_ms": now_ms,
        }
        state["phases"][str(phase)] = agent_id
        state["dispatch_ts"][agent_id] = now_ms

        _write_atomic(state)
except OSError as e:
    sys.stderr.write(
        f"AUTOPILOT_AGENT_STATE_WRITE_FAIL path={path} errno={e.errno} msg={e.strerror}\n"
    )
    sys.exit(2)
except Exception as e:
    sys.stderr.write(f"AUTOPILOT_AGENT_STATE_DISPATCH_UNEXPECTED err={type(e).__name__}:{e}\n")
    sys.exit(3)
PY
}

# Complete: clear markers for a completed agent; echoes its dispatch_epoch_ms to stdout.
# Usage: agent_state_complete <project_root> <session_key> <phase> <agent_id>
# Output: dispatch_epoch_ms (integer) on stdout, or empty string when unknown.
# Exit:   0 always (callers tolerate empty TS); errors are emitted to stderr.
agent_state_complete() {
  local project_root="$1" session_key="${2:-unknown}" phase="${3:-0}" agent_id="$4"
  if [ -z "$agent_id" ]; then
    echo ""
    return 0
  fi
  local state_file lock_file
  state_file="$(agent_state_file "$project_root")"
  lock_file="$(agent_state_lock_file "$project_root")"
  if [ ! -f "$state_file" ]; then
    echo ""
    return 0
  fi
  AGENT_STATE_FILE="$state_file" AGENT_STATE_LOCK="$lock_file" \
    AS_SESSION_KEY="$session_key" AS_PHASE="$phase" AS_AGENT_ID="$agent_id" \
    python3 - <<'PY'
import fcntl, json, os, sys, tempfile, time

path = os.environ["AGENT_STATE_FILE"]
lock_path = os.environ["AGENT_STATE_LOCK"]
session_key = os.environ.get("AS_SESSION_KEY") or "unknown"
phase = str(os.environ.get("AS_PHASE") or "0")
agent_id = os.environ["AS_AGENT_ID"]


def _write_atomic(state):
    tmp_fd, tmp_path = tempfile.mkstemp(prefix=".active-agent-state.", dir=os.path.dirname(path))
    try:
        with os.fdopen(tmp_fd, "w", encoding="utf-8") as f:
            json.dump(state, f, ensure_ascii=False, indent=2)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp_path, path)
    except Exception:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
        raise


try:
    with open(lock_path, "a+", encoding="utf-8") as lock:
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
        try:
            with open(path, "r", encoding="utf-8") as f:
                state = json.load(f)
        except FileNotFoundError:
            print("")
            sys.exit(0)
        except json.JSONDecodeError:
            sys.stderr.write(
                f"AUTOPILOT_AGENT_STATE_CORRUPT path={path} action=quarantine_on_complete\n"
            )
            try:
                os.replace(path, f"{path}.corrupt-{int(time.time()*1000)}")
            except OSError:
                pass
            print("")
            sys.exit(0)

        dispatch_ts = state.get("dispatch_ts", {}).pop(agent_id, None)
        # Only clear per-session/global/phase entries if they still point to this agent
        sess = state.get("sessions", {})
        if session_key in sess and sess[session_key].get("agent_id") == agent_id:
            sess.pop(session_key, None)
        phases = state.get("phases", {})
        if phases.get(phase) == agent_id:
            phases.pop(phase, None)
        if state.get("global", {}).get("agent_id") == agent_id:
            state["global"] = {}

        _write_atomic(state)
        print(dispatch_ts if dispatch_ts is not None else "")
except OSError as e:
    sys.stderr.write(
        f"AUTOPILOT_AGENT_STATE_WRITE_FAIL path={path} errno={e.errno} msg={e.strerror}\n"
    )
    print("")
except Exception as e:
    sys.stderr.write(
        f"AUTOPILOT_AGENT_STATE_COMPLETE_UNEXPECTED err={type(e).__name__}:{e}\n"
    )
    print("")
PY
}

# Read: get the active agent_id using session > phase > global fallback chain.
# Usage: agent_state_get_agent_id <project_root> [session_key] [phase]
# Output: agent_id on stdout, empty string when nothing matches or on error.
# Errors: stderr token, exit 0 (read path stays non-fatal for hooks).
agent_state_get_agent_id() {
  local project_root="$1" session_key="${2:-}" phase="${3:-}"
  local state_file
  state_file="$(agent_state_file "$project_root")"
  if [ ! -f "$state_file" ]; then
    echo ""
    return 0
  fi
  AGENT_STATE_FILE="$state_file" AS_SESSION_KEY="$session_key" AS_PHASE="$phase" \
    python3 - <<'PY'
import fcntl, json, os, sys

path = os.environ["AGENT_STATE_FILE"]
session_key = os.environ.get("AS_SESSION_KEY") or ""
phase = os.environ.get("AS_PHASE") or ""
try:
    with open(path, "r", encoding="utf-8") as f:
        fcntl.flock(f.fileno(), fcntl.LOCK_SH)
        state = json.load(f)
except FileNotFoundError:
    print("")
    sys.exit(0)
except json.JSONDecodeError:
    sys.stderr.write(f"AUTOPILOT_AGENT_STATE_CORRUPT path={path} action=read_returns_empty\n")
    print("")
    sys.exit(0)
except OSError as e:
    sys.stderr.write(f"AUTOPILOT_AGENT_STATE_READ_FAIL path={path} errno={e.errno}\n")
    print("")
    sys.exit(0)

if session_key:
    sess = state.get("sessions", {}).get(session_key, {})
    if sess.get("agent_id"):
        print(sess["agent_id"])
        sys.exit(0)
if phase:
    ph = state.get("phases", {}).get(str(phase))
    if ph:
        print(ph)
        sys.exit(0)
g = state.get("global", {})
print(g.get("agent_id", ""))
PY
}

# Read: get dispatch_epoch_ms for an agent (used to compute duration on complete).
# Usage: agent_state_get_dispatch_ts <project_root> <agent_id>
# Output: epoch_ms on stdout, empty when missing.
agent_state_get_dispatch_ts() {
  local project_root="$1" agent_id="$2"
  if [ -z "$agent_id" ]; then
    echo ""
    return 0
  fi
  local state_file
  state_file="$(agent_state_file "$project_root")"
  if [ ! -f "$state_file" ]; then
    echo ""
    return 0
  fi
  AGENT_STATE_FILE="$state_file" AS_AGENT_ID="$agent_id" \
    python3 - <<'PY'
import fcntl, json, os, sys

path = os.environ["AGENT_STATE_FILE"]
agent_id = os.environ["AS_AGENT_ID"]
try:
    with open(path, "r", encoding="utf-8") as f:
        fcntl.flock(f.fileno(), fcntl.LOCK_SH)
        state = json.load(f)
except FileNotFoundError:
    print("")
    sys.exit(0)
except json.JSONDecodeError:
    sys.stderr.write(f"AUTOPILOT_AGENT_STATE_CORRUPT path={path} action=read_returns_empty\n")
    print("")
    sys.exit(0)
except OSError as e:
    sys.stderr.write(f"AUTOPILOT_AGENT_STATE_READ_FAIL path={path} errno={e.errno}\n")
    print("")
    sys.exit(0)
print(state.get("dispatch_ts", {}).get(agent_id, ""))
PY
}
