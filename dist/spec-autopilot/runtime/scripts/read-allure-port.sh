#!/usr/bin/env bash
# read-allure-port.sh — 读取 Allure serve port，默认 4040
# 用法: BASE_PORT=$(bash "${CLAUDE_PLUGIN_ROOT}/runtime/scripts/read-allure-port.sh")
set -uo pipefail
CONFIG="${AUTOPILOT_PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}/.claude/autopilot.config.yaml"
python3 -c "
import yaml, sys
try:
    cfg = yaml.safe_load(open(sys.argv[1]))
    print(cfg.get('phases',{}).get('reporting',{}).get('allure',{}).get('serve_port',4040))
except Exception:
    print(4040)
" "$CONFIG" 2>/dev/null || echo 4040
