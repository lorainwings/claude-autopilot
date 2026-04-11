#!/usr/bin/env bash
# test_poll_gate_decision.sh — Regression tests for gate override safety
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../runtime/scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"

POLL_SCRIPT="$SCRIPT_DIR/poll-gate-decision.sh"

setup_poll_project() {
  local tmpdir
  local port="${1:-$(python3 - <<'PY'
import socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()
PY
)}"
  tmpdir=$(mktemp -d)
  local project_root="$tmpdir/project"
  local change_dir="$project_root/openspec/changes/test-feature/"

  mkdir -p "${change_dir}context" "$project_root/.claude" "$project_root/logs"
  cat > "$project_root/.claude/autopilot.config.yaml" <<EOF
gui:
  port: $port
  decision_poll_timeout: 30
EOF

  echo "$project_root"
}

get_configured_gui_port() {
  awk '/^[[:space:]]*port:/ {print $2; exit}' "$1/.claude/autopilot.config.yaml"
}

start_mock_gui_server() {
  local port="${1:-9527}"
  local project_root="${2:-}"
  python3 - "$port" "$project_root" <<'PY' >/dev/null 2>&1 &
import http.server, json, socketserver, sys

port = int(sys.argv[1])
project_root = sys.argv[2]
socketserver.TCPServer.allow_reuse_address = True

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/api/health":
            body = json.dumps({"status": "ok"}).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        if self.path == "/api/info":
            body = json.dumps({"projectRoot": project_root}).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        self.send_response(404)
        self.end_headers()

    def log_message(self, fmt, *args):
        pass

with socketserver.TCPServer(("127.0.0.1", port), Handler) as httpd:
    httpd.serve_forever()
PY
  echo $!
}

create_mock_gui_bootstrap() {
  local project_root="$1"
  local port="${2:-9527}"
  local ws_port=$((port + 1))
  local mock_script="$project_root/mock-start-gui-server.sh"
  cat > "$mock_script" <<EOF
#!/usr/bin/env bash
set -eu
project_root="\${@: -1}"
mkdir -p "\$project_root/logs"
printf '%s\n' "\$*" > "\$project_root/logs/mock-gui-bootstrap.args"
echo 'GUI_SERVER_JSON:{"status":"starting","http_url":"http://localhost:${port}","ws_url":"ws://localhost:${ws_port}","health_url":"http://localhost:${port}/api/health","reused_existing":false,"started_new":true,"async":true}'
EOF
  chmod +x "$mock_script"
  echo "$mock_script"
}

echo "--- poll-gate-decision override safety ---"

# 1. full mode Phase 5: override must be rejected and polling must continue
PROJECT_ROOT=$(setup_poll_project)
CHANGE_DIR="$PROJECT_ROOT/openspec/changes/test-feature/"
OUTPUT_FILE="$PROJECT_ROOT/output.json"
GUI_PORT=$(get_configured_gui_port "$PROJECT_ROOT")
GUI_PID=$(start_mock_gui_server "$GUI_PORT" "$PROJECT_ROOT")
PROJECT_ROOT_QUICK="$PROJECT_ROOT" bash "$POLL_SCRIPT" "$CHANGE_DIR" 5 full '{"blocked_step":8,"error_message":"quality floor"}' > "$OUTPUT_FILE" 2>&1 &
PID=$!

sleep 1
REQUEST_JSON=$(cat "${CHANGE_DIR}context/decision-request.json")
assert_contains "full Phase 5 request marks override disallowed" "$REQUEST_JSON" '"override_allowed": false'

cat > "${CHANGE_DIR}context/decision.json" <<'EOF'
{"action":"override","phase":5,"reason":"force it"}
EOF
sleep 1

if kill -0 "$PID" 2>/dev/null; then
  green "  PASS: disallowed override does not terminate polling"
  PASS=$((PASS + 1))
else
  red "  FAIL: polling exited after disallowed override"
  FAIL=$((FAIL + 1))
fi

cat > "${CHANGE_DIR}context/decision.json" <<'EOF'
{"action":"retry","phase":5,"reason":"rerun gate"}
EOF
sleep 1
wait "$PID"
EXIT_CODE=$?
OUTPUT=$(cat "$OUTPUT_FILE")

assert_exit "full Phase 5 falls through to retry after rejecting override" 0 "$EXIT_CODE"
assert_contains "full Phase 5 final action is retry" "$OUTPUT" '"action": "retry"'
kill "$GUI_PID" 2>/dev/null || true
rm -rf "$(dirname "$PROJECT_ROOT")"

# 2. minimal mode Phase 5: override remains allowed
PROJECT_ROOT=$(setup_poll_project)
CHANGE_DIR="$PROJECT_ROOT/openspec/changes/test-feature/"
OUTPUT_FILE="$PROJECT_ROOT/output.json"
GUI_PORT=$(get_configured_gui_port "$PROJECT_ROOT")
GUI_PID=$(start_mock_gui_server "$GUI_PORT" "$PROJECT_ROOT")
PROJECT_ROOT_QUICK="$PROJECT_ROOT" bash "$POLL_SCRIPT" "$CHANGE_DIR" 5 minimal '{"blocked_step":2,"error_message":"manual approval"}' > "$OUTPUT_FILE" 2>&1 &
PID=$!

sleep 1
REQUEST_JSON=$(cat "${CHANGE_DIR}context/decision-request.json")
assert_contains "minimal Phase 5 request keeps override allowed" "$REQUEST_JSON" '"override_allowed": true'

cat > "${CHANGE_DIR}context/decision.json" <<'EOF'
{"action":"override","phase":5,"reason":"allowed in minimal"}
EOF
wait "$PID"
EXIT_CODE=$?
OUTPUT=$(cat "$OUTPUT_FILE")

assert_exit "minimal Phase 5 accepts override" 0 "$EXIT_CODE"
assert_contains "minimal Phase 5 returns override action" "$OUTPUT" '"action": "override"'
kill "$GUI_PID" 2>/dev/null || true
rm -rf "$(dirname "$PROJECT_ROOT")"

# 3. GUI unavailable → async bootstrap + immediate auto_continue with dashboard URLs
PROJECT_ROOT=$(setup_poll_project)
CHANGE_DIR="$PROJECT_ROOT/openspec/changes/test-feature/"
GUI_PORT=$(get_configured_gui_port "$PROJECT_ROOT")
MOCK_GUI_SCRIPT=$(create_mock_gui_bootstrap "$PROJECT_ROOT" "$GUI_PORT")
OUTPUT=$(PROJECT_ROOT_QUICK="$PROJECT_ROOT" START_GUI_SERVER_SCRIPT="$MOCK_GUI_SCRIPT" bash "$POLL_SCRIPT" "$CHANGE_DIR" 3 full '{"blocked_step":2,"error_message":"test"}' 2>&1)
EXIT_CODE=$?

assert_exit "3a. GUI unavailable returns exit 0" 0 "$EXIT_CODE"
assert_contains "3b. GUI unavailable returns auto_continue action" "$OUTPUT" '"action":"auto_continue"'
assert_contains "3c. GUI unavailable returns bootstrap reason" "$OUTPUT" '"reason":"gui_dashboard_bootstrap"'
assert_contains "3d. GUI unavailable returns elapsed 0" "$OUTPUT" '"elapsed_seconds":0'
assert_contains "3e. GUI unavailable returns dashboard URL" "$OUTPUT" "\"dashboard_url\":\"http://localhost:${GUI_PORT}\""
assert_contains "3f. GUI unavailable returns gui status" "$OUTPUT" '"gui_status":"starting"'
BOOTSTRAP_ARGS=$(cat "$PROJECT_ROOT/logs/mock-gui-bootstrap.args" 2>/dev/null || true)
assert_contains "3g. async bootstrap uses --no-wait" "$BOOTSTRAP_ARGS" '--no-wait'
rm -rf "$(dirname "$PROJECT_ROOT")"

# 4. Legacy config opt-out no longer blocks bootstrap path
PROJECT_ROOT=$(setup_poll_project)
CHANGE_DIR="$PROJECT_ROOT/openspec/changes/test-feature/"
GUI_PORT=$(get_configured_gui_port "$PROJECT_ROOT")
cat > "$PROJECT_ROOT/.claude/autopilot.config.yaml" <<EOF
gui:
  port: $GUI_PORT
  decision_poll_timeout: 2
  auto_continue_on_gui_unavailable: false
EOF

MOCK_GUI_SCRIPT=$(create_mock_gui_bootstrap "$PROJECT_ROOT" "$GUI_PORT")
OUTPUT=$(PROJECT_ROOT_QUICK="$PROJECT_ROOT" START_GUI_SERVER_SCRIPT="$MOCK_GUI_SCRIPT" bash "$POLL_SCRIPT" "$CHANGE_DIR" 3 full '{"blocked_step":2,"error_message":"test"}' 2>&1)
EXIT_CODE=$?

assert_exit "4a. GUI unavailable + legacy opt-out still returns exit 0" 0 "$EXIT_CODE"
assert_contains "4b. GUI unavailable + legacy opt-out still auto_continue" "$OUTPUT" '"action":"auto_continue"'
assert_contains "4c. GUI unavailable + legacy opt-out still returns dashboard URL" "$OUTPUT" "\"dashboard_url\":\"http://localhost:${GUI_PORT}\""
rm -rf "$(dirname "$PROJECT_ROOT")"

echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1
exit 0
